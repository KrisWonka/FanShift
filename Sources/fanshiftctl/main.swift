// fanshiftctl：命令行诊断工具。只读硬件，不改任何东西（helper 子命令除外，它走后台程序）。
import FanShiftCore
import Foundation

setvbuf(stdout, nil, _IOLBF, 0)

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("✗ \(message)\n".utf8))
    exit(1)
}

func fmt(_ v: Double?, _ digits: Int = 1) -> String {
    v.map { String(format: "%.\(digits)f", $0) } ?? "—"
}

func modeName(_ m: Int) -> String {
    switch m {
    case FanMode.auto: return "0 auto"
    case FanMode.forced: return "1 forced"
    case FanMode.system: return "3 system"
    default: return "\(m)"
    }
}

func printStatus() {
    do {
        let hw = try SMCFans()
        print("\(hw.fans.count) fans, mode key F{n}\(hw.modeSuffix)\(hw.hasForceTestKey ? ", has Ftst (M1–M4: may need unlocking before takeover)" : "")")
        for fan in hw.fans {
            let mode = (try? hw.mode(fan: fan.index)) ?? -1
            print("  fan \(fan.index): actual \(fmt(try? hw.actual(fan: fan.index), 0))  target \(fmt(try? hw.target(fan: fan.index), 0))  range \(fmt(fan.minRPM, 0))–\(fmt(fan.maxRPM, 0))  mode \(modeName(mode))")
        }
    } catch {
        print("could not read fans: \(error)")
    }
    let readings = TemperatureSensors().readAll()
    print("\(readings.count) temperature sensors")
    print("  hottest CPU core \(fmt(SensorMath.value(.cpuMax, from: readings)))°C")
    print("  chip average     \(fmt(SensorMath.value(.cpuAvg, from: readings)))°C")
    print("  hottest sensor   \(fmt(SensorMath.value(.anyMax, from: readings)))°C")
}

func printSensors() {
    for r in TemperatureSensors().readAll() {
        var tag = ""
        if SensorMath.isCalibration(r.name) { tag = "(calibration constant, not used)" } else if SensorMath.isCore(r.name) { tag = "core" } else if SensorMath.isDie(r.name) { tag = "die" }
        print("\(r.name.padding(toLength: 22, withPad: " ", startingAt: 0)) \(String(format: "%6.2f", r.value))  \(tag)")
    }
}

/// 只算不写：按配置里某个档位的曲线算出目标转速，和风扇此刻实际的目标转速并排打印。
/// 用来在切换前对比新程序和现在的控制软件差多少。输出是 CSV。
func shadow(stepName: String?, seconds: Int) {
    let (config, source) = AppConfig.load()
    guard let hw = try? SMCFans() else { fail("could not read fans") }
    let steps = config.cycleSteps.filter { $0.type == .temperature }
    guard let step = stepName.flatMap({ n in steps.first { $0.effectiveName.lowercased() == n.lowercased() } }) ?? steps.first else {
        fail("no Temperature profile in the configuration")
    }
    var cfg = config
    cfg.cycleSteps = [step]
    let controller = FanController(config: cfg, fans: hw.fans)
    let sensors = TemperatureSensors()
    FileHandle.standardError.write(Data("profile \(step.effectiveName), config from \(source), sampling for \(seconds) s\n".utf8))
    print("t,cpuMax,cpuAvg,anyMax,ours_percent,ours_rpm,actual_target,actual_percent,actual_rpm")
    let start = Date()
    while Date().timeIntervalSince(start) < Double(seconds) {
        let readings = sensors.readAll()
        let (command, _) = controller.tick(readings: readings, now: Date())
        var ours = 0.0
        if case .targets(let t) = command { ours = t.first ?? 0 }
        let actualTarget = (try? hw.target(fan: 0)) ?? 0
        let fan = hw.fans[0]
        let actualPercent = (actualTarget - fan.minRPM) / (fan.maxRPM - fan.minRPM) * 100
        print([
            fmt(Date().timeIntervalSince(start), 0),
            fmt(SensorMath.value(.cpuMax, from: readings)),
            fmt(SensorMath.value(.cpuAvg, from: readings)),
            fmt(SensorMath.value(.anyMax, from: readings)),
            fmt(controller.lastPercent),
            fmt(ours, 0),
            fmt(actualTarget, 0),
            fmt(actualPercent),
            fmt(try? hw.actual(fan: 0), 0),
        ].joined(separator: ","))
        Thread.sleep(forTimeInterval: 2)
    }
}

/// 标定用：把 SMC 里所有温度类的键和风扇当前目标转速一起记下来（CSV）
func calib(seconds: Int) {
    guard let hw = try? SMCFans() else { fail("could not read fans") }
    let keys = SMC.allKeys().filter { $0.hasPrefix("T") && SMC.info($0)?.type == "flt " }
    let sensors = TemperatureSensors()
    FileHandle.standardError.write(Data("\(keys.count) SMC temperature keys, sampling for \(seconds) s\n".utf8))
    print((["t", "target", "hidMax"] + keys).joined(separator: ","))
    let start = Date()
    while Date().timeIntervalSince(start) < Double(seconds) {
        let hid = SensorMath.value(.cpuMax, from: sensors.readAll())
        var row = [fmt(Date().timeIntervalSince(start), 0), fmt(try? hw.target(fan: 0), 0), fmt(hid)]
        for k in keys { row.append(fmt(try? SMC.readDouble(k))) }
        print(row.joined(separator: ","))
        Thread.sleep(forTimeInterval: 2)
    }
}

/// 和后台程序说话（需要后台程序已安装）
func helper(_ args: [String]) {
    let connection = NSXPCConnection(machServiceName: FanShiftInfo.daemonLabel, options: .privileged)
    connection.remoteObjectInterface = NSXPCInterface(with: FanHelperXPC.self)
    connection.resume()
    let done = DispatchSemaphore(value: 0)
    guard let proxy = connection.remoteObjectProxyWithErrorHandler({ error in
        print("cannot reach the helper: \(error.localizedDescription)")
        done.signal()
    }) as? FanHelperXPC else { fail("unexpected helper interface") }

    switch args.first ?? "info" {
    case "info":
        proxy.info { json in print(json); done.signal() }
    case "release":
        proxy.releaseFans { err in print(err ?? "fans handed back to the system"); done.signal() }
    case "set":
        guard args.count >= 2, let rpm = Double(args[1]) else { fail("usage: fanshiftctl helper set <rpm> [seconds]") }
        let hold = args.count >= 3 ? (Double(args[2]) ?? 10) : 10
        let fanCount = (try? SMCFans().fans.count) ?? 2
        let until = Date().addingTimeInterval(hold)
        // 每 2 秒续一次租约，保持指定的秒数后交还
        while Date() < until {
            let sent = DispatchSemaphore(value: 0)
            proxy.setTargets(Array(repeating: rpm, count: fanCount), leaseSeconds: 6) { err in
                if let err { print("failed: \(err)") }
                sent.signal()
            }
            _ = sent.wait(timeout: .now() + 3)
            printStatus()
            Thread.sleep(forTimeInterval: 2)
        }
        proxy.releaseFans { err in print(err ?? "fans handed back to the system"); done.signal() }
    default:
        fail("usage: fanshiftctl helper [info | release | set <rpm> [seconds]]")
    }
    _ = done.wait(timeout: .now() + 5)
}

let args = Array(CommandLine.arguments.dropFirst())
switch args.first ?? "status" {
case "status":
    printStatus()
case "sensors":
    printSensors()
case "shadow":
    // fanshiftctl shadow [档位名] [秒数]
    let name = args.count >= 2 && Int(args[1]) == nil ? args[1] : nil
    let secs = args.dropFirst().compactMap { Int($0) }.first ?? 60
    shadow(stepName: name, seconds: secs)
case "calib":
    calib(seconds: args.dropFirst().compactMap { Int($0) }.first ?? 60)
case "helper":
    helper(Array(args.dropFirst()))
default:
    print("""
    usage:
      fanshiftctl status                       fans and temperatures right now
      fanshiftctl sensors                      list every temperature sensor
      fanshiftctl shadow [profile] [seconds]   compute targets without writing them, next to the real fan targets (CSV)
      fanshiftctl helper info                  what the helper reports
      fanshiftctl helper release               ask the helper to hand the fans back to the system
      fanshiftctl helper set <rpm> [seconds]   ask the helper to hold the fans at a speed, then hand them back
    """)
}
