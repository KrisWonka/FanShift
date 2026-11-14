import AppKit
import FanShiftCore

/// 后台程序的状态（给界面看）
enum HelperState: Equatable {
    case unknown
    case notInstalled
    case ready
    case outdated(String)  // 装着的是另一个接口版本
    case problem(String)

    var isReady: Bool { self == .ready }

    var summary: String {
        switch self {
        case .unknown: return "检查中…"
        case .notInstalled: return "还没安装"
        case .ready: return "运行正常"
        case .outdated(let v): return "版本不对（装的是 \(v)，需要 \(FanShiftInfo.helperVersion)），请重装"
        case .problem(let p): return p
        }
    }
}

/// 保证回调只被调用一次（XPC 的应答回调和出错回调可能各来一次）
final class Once<T> {
    private let lock = NSLock()
    private var done = false
    private let body: (T) -> Void

    init(_ body: @escaping (T) -> Void) { self.body = body }

    func call(_ value: T) {
        lock.lock()
        let already = done
        done = true
        lock.unlock()
        if !already { body(value) }
    }
}

/// App 往后台程序发指令的通道。真的走 XPC；开发时可以换成只打印不执行的。
protocol HelperChannel: AnyObject {
    func info(completion: @escaping (HelperInfo?, String?) -> Void)
    func setTargets(_ rpms: [Double], lease: Double, completion: @escaping (String?) -> Void)
    func release(completion: @escaping (String?) -> Void)
}

final class XPCHelperChannel: HelperChannel {
    private let lock = NSLock()
    private var connection: NSXPCConnection?

    private func currentConnection() -> NSXPCConnection {
        lock.lock()
        defer { lock.unlock() }
        if let connection { return connection }
        let c = NSXPCConnection(machServiceName: FanShiftInfo.daemonLabel, options: .privileged)
        c.remoteObjectInterface = NSXPCInterface(with: FanHelperXPC.self)
        c.invalidationHandler = { [weak self, weak c] in
            guard let self else { return }
            self.lock.lock()
            if self.connection === c { self.connection = nil }
            self.lock.unlock()
        }
        c.resume()
        connection = c
        return c
    }

    private func proxy(_ onError: @escaping (String) -> Void) -> FanHelperXPC? {
        let p = currentConnection().remoteObjectProxyWithErrorHandler { error in
            onError("连不上后台程序：\(error.localizedDescription)")
        }
        return p as? FanHelperXPC
    }

    func info(completion: @escaping (HelperInfo?, String?) -> Void) {
        let once = Once<(HelperInfo?, String?)> { completion($0.0, $0.1) }
        guard let p = proxy({ once.call((nil, $0)) }) else { return once.call((nil, "接口不对")) }
        p.info { json in
            if let info = HelperInfo.parse(json) { once.call((info, nil)) } else { once.call((nil, "后台程序的应答看不懂")) }
        }
        // 后台程序没反应时不能一直等
        DispatchQueue.global().asyncAfter(deadline: .now() + 3) { once.call((nil, "后台程序没有应答")) }
    }

    func setTargets(_ rpms: [Double], lease: Double, completion: @escaping (String?) -> Void) {
        let once = Once(completion)
        guard let p = proxy({ once.call($0) }) else { return once.call("接口不对") }
        p.setTargets(rpms, leaseSeconds: lease) { once.call($0) }
    }

    func release(completion: @escaping (String?) -> Void) {
        let once = Once(completion)
        guard let p = proxy({ once.call($0) }) else { return once.call("接口不对") }
        p.releaseFans { once.call($0) }
    }
}

/// 开发用：只把指令打印出来，不碰风扇（环境变量 FANSHIFT_DRYRUN=1）
final class DryRunChannel: HelperChannel {
    private let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    private func say(_ line: String) {
        FileHandle.standardError.write(Data("[dry-run \(formatter.string(from: Date()))] \(line)\n".utf8))
    }

    func info(completion: @escaping (HelperInfo?, String?) -> Void) {
        completion(HelperInfo(version: FanShiftInfo.helperVersion, fans: [], holding: false), nil)
    }

    func setTargets(_ rpms: [Double], lease: Double, completion: @escaping (String?) -> Void) {
        say("目标转速 \(rpms.map { Int($0) })")
        completion(nil)
    }

    func release(completion: @escaping (String?) -> Void) {
        say("交还系统")
        completion(nil)
    }
}

/// 安装 / 卸载 root 后台程序。会弹系统密码框。
enum HelperInstaller {
    static var bundledDaemon: String? { Bundle.main.path(forResource: "fanshiftd", ofType: nil) }
    static var bundledPlist: String? { Bundle.main.path(forResource: FanShiftInfo.daemonLabel, ofType: "plist") }

    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: FanShiftInfo.daemonPlistPath)
            && FileManager.default.fileExists(atPath: FanShiftInfo.daemonBinaryPath)
    }

    private static func quote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// 以管理员身份跑一段 shell。成功返回 nil，否则返回原因。必须在主线程调用。
    private static func runAsAdmin(_ shell: String, prompt: String) -> String? {
        func escape(_ s: String) -> String {
            s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        }
        let source = "do shell script \"\(escape(shell))\" with prompt \"\(escape(prompt))\" with administrator privileges"
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        guard let error else { return nil }
        if (error[NSAppleScript.errorNumber] as? Int) == -128 { return "已取消" }
        return (error[NSAppleScript.errorMessage] as? String) ?? "执行失败"
    }

    static func install() -> String? {
        guard let daemon = bundledDaemon, let plist = bundledPlist else {
            return "App 里没有带后台程序，请用 scripts/build-app.sh 打包后的 App 来安装"
        }
        let label = FanShiftInfo.daemonLabel
        let shell = [
            "/bin/launchctl bootout system/\(label) 2>/dev/null && /bin/sleep 1",
            "/bin/mkdir -p /Library/PrivilegedHelperTools"
                + " && /usr/bin/install -o root -g wheel -m 755 \(quote(daemon)) \(quote(FanShiftInfo.daemonBinaryPath))"
                + " && /usr/bin/install -o root -g wheel -m 644 \(quote(plist)) \(quote(FanShiftInfo.daemonPlistPath))"
                + " && /bin/launchctl bootstrap system \(quote(FanShiftInfo.daemonPlistPath))",
        ].joined(separator: "; ")
        return runAsAdmin(shell, prompt: "FanShift 要安装控制风扇用的后台程序。")
    }

    static func uninstall() -> String? {
        let label = FanShiftInfo.daemonLabel
        let shell = [
            "/bin/launchctl bootout system/\(label) 2>/dev/null",
            "/bin/rm -f \(quote(FanShiftInfo.daemonBinaryPath)) \(quote(FanShiftInfo.daemonPlistPath)) \(quote(FanShiftInfo.daemonMarkerPath))",
        ].joined(separator: "; ")
        return runAsAdmin(shell, prompt: "FanShift 要卸载控制风扇用的后台程序。")
    }
}
