import Foundation

public struct GovernorError: Error, CustomStringConvertible {
    public let description: String
}

/// 跑在 root 后台程序里，是唯一往风扇里写东西的地方。只做三件事：
/// 接管并设目标转速、交还系统、租约到期自动交还。
/// 不是线程安全的，调用方要保证在同一个队列上用。
public final class FanGovernor {
    public static let minLease: TimeInterval = 3
    public static let maxLease: TimeInterval = 30

    public let fans: [FanInfo]
    /// 我们是否正接管着风扇
    public private(set) var holding = false

    private let hardware: FanHardware
    private let markerPath: String?
    private var leaseDeadline: Date?
    private var lastWritten: [Double?]

    public init(hardware: FanHardware, markerPath: String?) {
        self.hardware = hardware
        self.markerPath = markerPath
        fans = hardware.fans
        lastWritten = Array(repeating: nil, count: hardware.fans.count)
    }

    /// 启动时调用。标记文件还在，说明上次接管着风扇时进程没正常退出，先把风扇交还系统。
    public func reconcileAtStart() {
        guard let markerPath, FileManager.default.fileExists(atPath: markerPath) else { return }
        release(force: true)
    }

    /// 接管风扇并设目标转速。rpms 每个风扇一个值，会被限制在该风扇的转速范围内。
    /// 之后 lease 秒内没有再次调用，风扇会自动交还系统。
    public func setTargets(_ rpms: [Double], lease: TimeInterval, now: Date) throws {
        guard rpms.count == fans.count else {
            throw GovernorError(description: "目标转速要 \(fans.count) 个，收到 \(rpms.count) 个")
        }
        guard rpms.allSatisfy(\.isFinite) else {
            throw GovernorError(description: "目标转速不是有效数字")
        }
        do {
            if !holding {
                // 先落标记再动硬件：中途崩了，下次启动也知道要交还
                if let markerPath { FileManager.default.createFile(atPath: markerPath, contents: nil) }
                holding = true
            }
            for (i, fan) in fans.enumerated() {
                let rpm = fan.clamp(rpms[i])
                if try hardware.mode(fan: fan.index) != FanMode.forced {
                    try hardware.setMode(fan: fan.index, FanMode.forced)
                    guard try hardware.mode(fan: fan.index) == FanMode.forced else {
                        throw GovernorError(description: "风扇 \(fan.index) 接管失败：写入后模式没有变成 1")
                    }
                    lastWritten[i] = nil
                }
                if lastWritten[i].map({ abs($0 - rpm) >= 1 }) ?? true {
                    try hardware.setTarget(fan: fan.index, rpm: rpm)
                    lastWritten[i] = rpm
                }
            }
        } catch {
            release(force: true)
            throw error
        }
        leaseDeadline = now.addingTimeInterval(min(max(lease, Self.minLease), Self.maxLease))
    }

    /// 把风扇交还系统。默认只在我们接管着的时候才动，免得把别的软件的接管也解除掉。
    public func release(force: Bool = false) {
        guard holding || force else { return }
        for fan in fans where (try? hardware.mode(fan: fan.index)) == FanMode.forced {
            try? hardware.setMode(fan: fan.index, FanMode.auto)
        }
        holding = false
        leaseDeadline = nil
        lastWritten = Array(repeating: nil, count: fans.count)
        if let markerPath { try? FileManager.default.removeItem(atPath: markerPath) }
    }

    /// 定时调用。租约过期就交还，返回 true 表示这次交还了。
    @discardableResult
    public func checkLease(now: Date) -> Bool {
        guard holding, let deadline = leaseDeadline, now >= deadline else { return false }
        release()
        return true
    }
}
