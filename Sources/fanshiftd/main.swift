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
        do {
            let hardware = try SMCFans()
            if hardware.needsUnlock {
                problem = "这代机型（M1–M4）接管风扇前要先解锁，目前还不支持"
            } else {
                governor = FanGovernor(hardware: hardware, markerPath: FanShiftInfo.daemonMarkerPath)
            }
        } catch {
            problem = "\(error)"
        }
        queue.sync { governor?.reconcileAtStart() }

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler { [weak self] in
            if self?.governor?.checkLease(now: Date()) == true { log("租约到期，风扇已交还系统") }
        }
        timer.resume()
        leaseTimer = timer

        if let governor {
            let ranges = governor.fans.map { "\(Int($0.minRPM))–\(Int($0.maxRPM))" }.joined(separator: "，")
            log("启动：接口版本 \(FanShiftInfo.helperVersion)，风扇 \(governor.fans.count) 个（\(ranges)）")
        } else {
            log("启动，但不能控制风扇：\(problem ?? "原因不明")")
        }
    }

    // MARK: 连接

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        let uid = connection.effectiveUserIdentifier
        guard uid == 0 || uid == consoleUID() else {
            log("拒绝了 uid \(uid) 的连接：只接受当前登录用户")
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
                log("App 已断开，风扇已交还系统")
            }
        }
    }

    /// 退出前调用
    func releaseNow(reason: String) {
        queue.sync {
            if governor?.holding == true {
                governor?.release()
                log("\(reason)，风扇已交还系统")
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
                reply(self.problem ?? "后台程序没有认出风扇")
                return
            }
            do {
                let wasHolding = governor.holding
                try governor.setTargets(rpms, lease: leaseSeconds, now: Date())
                if !wasHolding { log("已接管风扇，目标 \(rpms.map { Int($0) })") }
                reply(nil)
            } catch {
                log("设置目标转速失败：\(error)")
                reply("\(error)")
            }
        }
    }

    func releaseFans(reply: @escaping (String?) -> Void) {
        queue.async {
            if self.governor?.holding == true {
                self.governor?.release()
                log("按 App 的要求，风扇已交还系统")
            }
            reply(nil)
        }
    }
}

guard geteuid() == 0 else {
    log("fanshiftd 必须以 root 身份由 launchd 启动")
    exit(1)
}

let service = HelperService()

// 收到退出信号：先交还风扇再走
var signalSources: [DispatchSourceSignal] = []
for sig in [SIGTERM, SIGINT, SIGHUP] {
    signal(sig, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
    source.setEventHandler {
        service.releaseNow(reason: "收到退出信号")
        exit(0)
    }
    source.resume()
    signalSources.append(source)
}

let listener = NSXPCListener(machServiceName: FanShiftInfo.daemonLabel)
listener.delegate = service
listener.resume()
dispatchMain()
