import Foundation

/// App 和 root 后台程序之间的接口（XPC，Mach 服务名是 FanShiftInfo.daemonLabel）。
/// 后台程序只暴露这三件事，不提供任意写 SMC 的能力。
@objc public protocol FanHelperXPC {
    /// 返回一段 JSON，内容见 HelperInfo
    func info(reply: @escaping (String) -> Void)

    /// 接管风扇并设目标转速，每个风扇一个值。leaseSeconds 秒内没有再次调用，风扇自动交还系统。
    /// 成功时 reply(nil)，失败时 reply(原因)。
    func setTargets(_ rpms: [Double], leaseSeconds: Double, reply: @escaping (String?) -> Void)

    /// 把风扇交还系统。成功时 reply(nil)。
    func releaseFans(reply: @escaping (String?) -> Void)
}

public struct HelperInfo: Codable, Equatable {
    public var version: String
    public var fans: [FanInfo]
    public var holding: Bool
    /// 后台程序启动时没能认出风扇的原因；正常时为 nil
    public var problem: String?

    public init(version: String, fans: [FanInfo], holding: Bool, problem: String? = nil) {
        self.version = version
        self.fans = fans
        self.holding = holding
        self.problem = problem
    }

    public var json: String {
        (try? JSONEncoder().encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }

    public static func parse(_ json: String) -> HelperInfo? {
        try? JSONDecoder().decode(HelperInfo.self, from: Data(json.utf8))
    }
}
