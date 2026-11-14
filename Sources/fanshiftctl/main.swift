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
    case FanMode.auto: return "0 系统自动"
    case FanMode.forced: return "1 被软件接管"
    case FanMode.system: return "3 系统温控"
    default: return "\(m)"
    }
}

func printStatus() {
    do {
        let hw = try SMCFans()
        print("风扇 \(hw.fans.count) 个，模式键 F{n}\(hw.modeSuffix)\(hw.needsUnlock ? "（这代机型接管前要先解锁，暂不支持）" : "")")
        for fan in hw.fans {
            let mode = (try? hw.mode(fan: fan.index)) ?? -1
            print("  风扇\(fan.index)：实际 \(fmt(try? hw.actual(fan: fan.index), 0))  目标 \(fmt(try? hw.target(fan: fan.index), 0))  范围 \(fmt(fan.minRPM, 0))–\(fmt(fan.maxRPM, 0))  模式 \(modeName(mode))")
        }
    } catch {
        print("风扇读取失败：\(error)")
    }
    let readings = TemperatureSensors().readAll()
    print("温度传感器 \(readings.count) 个")
    print("  最热的 CPU 核心 \(fmt(SensorMath.value(.cpuMax, from: readings)))°C")
    print("  芯片各温度点的平均 \(fmt(SensorMath.value(.cpuAvg, from: readings)))°C")
    print("  所有传感器里最热的 \(fmt(SensorMath.value(.anyMax, from: readings)))°C")
}

func printSensors() {
    for r in TemperatureSensors().readAll() {
        var tag = ""
        if SensorMath.isCalibration(r.name) { tag = "（校准读数，不参与计算）" } else if SensorMath.isCore(r.name) { tag = "核心" } else if SensorMath.isDie(r.name) { tag = "芯片" }
        print("\(r.name.padding(toLength: 22, withPad: " ", startingAt: 0)) \(String(format: "%6.2f", r.value))  \(tag)")
    }
}

/// 只算不写：按配置里某个档位的曲线算出目标转速，和风扇此刻实际的目标转速并排打印。
/// 用来在切换前对比新程序和现在的控制软件差多少。输出是 CSV。
func shadow(stepName: String?, seconds: Int) {
    let (config, source) = AppConfig.load()
    guard let hw = try? SMCFans() else { fail("读不到风扇") }
    let steps = config.cycleSteps.filter { $0.type == .temperature }
    guard let step = stepName.flatMap({ n in steps.first { $0.effectiveName.lowercased() == n.lowercased() } }) ?? steps.first else {
        fail("配置里没有温度曲线档位")
    }
    var cfg = config
    cfg.cycleSteps = [step]
    let controller = FanController(config: cfg, fans: hw.fans)
    let sensors = TemperatureSensors()
    FileHandle.standardError.write(Data("档位 \(step.effectiveName)，配置来源 \(source)，采样 \(seconds) 秒\n".utf8))
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
    guard let hw = try? SMCFans() else { fail("读不到风扇") }
    let keys = SMC.allKeys().filter { $0.hasPrefix("T") && SMC.info($0)?.type == "flt " }
    let sensors = TemperatureSensors()
    FileHandle.standardError.write(Data("SMC 温度类的键 \(keys.count) 个，采样 \(seconds) 秒\n".utf8))
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
        print("连不上后台程序：\(error.localizedDescription)")
        done.signal()
    }) as? FanHelperXPC else { fail("接口不对") }

    switch args.first ?? "info" {
    case "info":
        proxy.info { json in print(json); done.signal() }
    case "release":
        proxy.releaseFans { err in print(err ?? "已交还系统"); done.signal() }
    case "set":
        guard args.count >= 2, let rpm = Double(args[1]) else { fail("用法：fanshiftctl helper set <转速> [保持秒数]") }
        let hold = args.count >= 3 ? (Double(args[2]) ?? 10) : 10
        let fanCount = (try? SMCFans().fans.count) ?? 2
        let until = Date().addingTimeInterval(hold)
        // 每 2 秒续一次租约，保持指定的秒数后交还
        while Date() < until {
            let sent = DispatchSemaphore(value: 0)
            proxy.setTargets(Array(repeating: rpm, count: fanCount), leaseSeconds: 6) { err in
                if let err { print("设置失败：\(err)") }
                sent.signal()
            }
            _ = sent.wait(timeout: .now() + 3)
            printStatus()
            Thread.sleep(forTimeInterval: 2)
        }
        proxy.releaseFans { err in print(err ?? "已交还系统"); done.signal() }
    default:
        fail("用法：fanshiftctl helper [info | release | set <转速> [保持秒数]]")
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
    用法：
      fanshiftctl status                   风扇和温度的当前状态
      fanshiftctl sensors                  列出所有温度传感器
      fanshiftctl shadow [档位名] [秒数]   只算不写，和风扇实际目标转速并排对比（CSV）
      fanshiftctl helper info              后台程序的信息
      fanshiftctl helper release           让后台程序把风扇交还系统
      fanshiftctl helper set <转速> [秒]   让后台程序把风扇设到指定转速，保持若干秒后交还
    """)
}
