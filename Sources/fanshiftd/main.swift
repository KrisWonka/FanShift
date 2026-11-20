// fanshiftd：root 后台程序，由 launchd 启动。整个项目里只有它往风扇里写东西。
// 对外只有三个操作（见 FanHelperXPC）：查信息、接管并设目标转速、交还系统。
// 任何「没人管」的情况都把风扇交还系统：租约到期、App 断开、收到退出信号、上次没正常退出。
import FanShiftCore
import Foundation

func log(_ message: String) {
    let stamp = ISO8601DateFormatter().string(from: Date())
    FileHandle.standardError.write(Data("[\(stamp)] \(message)\n".utf8))
}

/// 当前登录图形界面的用户
func consoleUID() -> uid_t? {
    var st = stat()
    return stat("/dev/console", &st) == 0 ? st.st_uid : nil
}

final class HelperService: NSObject, NSXPCListenerDelegate, FanHelperXPC {
    /// governor 和下面的状态都只在这个队列上碰
    let queue = DispatchQueue(label: "com.kriswonka.fanshift.daemon.governor")
    private var governor: FanGovernor?
    private var problem: String?
    private var clients: Set<ObjectIdentifier> = []
    private var leaseTimer: DispatchSourceTimer?

    override init() {
        super.init()
        var modeKey = ""
        do {
            let hardware = try SMCFans()
            modeKey = "mode key F{n}\(hardware.modeSuffix), " + (hardware.hasForceTestKey ? "has Ftst (may need unlocking)" : "no Ftst")
            let g = FanGovernor(hardware: hardware, markerPath: FanShiftInfo.daemonMarkerPath)
            g.onEvent = { log($0) }
            governor = g
        } catch {
            problem = "\(error)"
        }
        queue.sync { governor?.reconcileAtStart() }

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler { [weak self] in
            if self?.governor?.checkLease(now: Date()) == true { log("lease expired, fans handed back to the system") }
        }
        timer.resume()
        leaseTimer = timer

        if let governor {
            let ranges = governor.fans.map { "\(Int($0.minRPM))–\(Int($0.maxRPM))" }.joined(separator: "，")
            log("started: interface \(FanShiftInfo.helperVersion), \(governor.fans.count) fans (\(ranges) rpm), \(modeKey)")
        } else {
            log("started, but cannot control the fans: \(problem ?? "unknown reason")")
        }
    }

    // MARK: 连接

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        let uid = connection.effectiveUserIdentifier
        guard uid == 0 || uid == consoleUID() else {
            log("refused a connection from uid \(uid): only the logged-in user is accepted")
            return false
        }
        let id = ObjectIdentifier(connection)
        connection.exportedInterface = NSXPCInterface(with: FanHelperXPC.self)
        connection.exportedObject = self
        connection.invalidationHandler = { [weak self] in self?.clientGone(id) }
        queue.async { self.clients.insert(id) }
        connection.resume()
        return true
    }

    private func clientGone(_ id: ObjectIdentifier) {
        queue.async {
            self.clients.remove(id)
            if self.clients.isEmpty, self.governor?.holding == true {
                self.governor?.release()
                log("app disconnected, fans handed back to the system")
            }
        }
    }

    /// 退出前调用
    func releaseNow(reason: String) {
        queue.sync {
            if governor?.holding == true {
                governor?.release()
                log("\(reason), fans handed back to the system")
            }
        }
    }

    // MARK: FanHelperXPC

    func info(reply: @escaping (String) -> Void) {
        queue.async {
            let info = HelperInfo(
                version: FanShiftInfo.helperVersion,
                fans: self.governor?.fans ?? [],
                holding: self.governor?.holding ?? false,
                problem: self.problem
            )
            reply(info.json)
        }
    }

    func setTargets(_ rpms: [Double], leaseSeconds: Double, reply: @escaping (String?) -> Void) {
        queue.async {
            guard let governor = self.governor else {
                reply(self.problem ?? "the helper did not find any fans")
                return
            }
            do {
                let wasHolding = governor.holding
                try governor.setTargets(rpms, lease: leaseSeconds, now: Date())
                if !wasHolding { log("took over the fans, targets \(rpms.map { Int($0) })") }
                reply(nil)
            } catch {
                log("setting target speeds failed: \(error)")
                reply("\(error)")
            }
        }
    }

    func releaseFans(reply: @escaping (String?) -> Void) {
        queue.async {
            if self.governor?.holding == true {
                self.governor?.release()
                log("fans handed back to the system at the app's request")
            }
            reply(nil)
        }
    }
}

guard geteuid() == 0 else {
    log("fanshiftd must run as root, started by launchd")
    exit(1)
}

let service = HelperService()

// 收到退出信号：先交还风扇再走
var signalSources: [DispatchSourceSignal] = []
for sig in [SIGTERM, SIGINT, SIGHUP] {
    signal(sig, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
    source.setEventHandler {
        service.releaseNow(reason: "received a quit signal")
        exit(0)
    }
    source.resume()
    signalSources.append(source)
}

let listener = NSXPCListener(machServiceName: FanShiftInfo.daemonLabel)
listener.delegate = service
listener.resume()
dispatchMain()
