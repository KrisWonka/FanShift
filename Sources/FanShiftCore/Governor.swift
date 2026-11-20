import Foundation

public struct GovernorError: Error, CustomStringConvertible {
    public let description: String
}

/// 接管风扇时要等待和重试，时间来源做成可替换的，测试里不用真等
public struct GovernorTiming {
    public var now: () -> Date
    public var sleep: (TimeInterval) -> Void

    public init(now: @escaping () -> Date, sleep: @escaping (TimeInterval) -> Void) {
        self.now = now
        self.sleep = sleep
    }

    public static let real = GovernorTiming(now: Date.init, sleep: Thread.sleep(forTimeInterval:))
}

/// 跑在 root 后台程序里，是唯一往风扇里写东西的地方。只做三件事：
/// 接管并设目标转速、交还系统、租约到期自动交还。
/// 不是线程安全的，调用方要保证在同一个队列上用。
///
/// 接管的过程（各代机型通用）：写模式 1，读回来确认。系统温控（thermalmonitord）占着风扇时固件不接受，
/// 这时：
/// - M5（没有 Ftst 键）：每 0.1 秒重试，最多 1 秒。睡眠唤醒后系统会占住风扇几秒，App 每 2 秒还会再来。
/// - M1–M4（有 Ftst 键）：先写 Ftst = 1 让系统温控放手，再每 0.1 秒重试，最多 10 秒（别的项目实测要 3–6 秒）。
///   Ftst 在接管期间一直保持 1，交还时清回 0。Ftst 停在 1 而没人接管时，系统温控也不管风扇，
///   所以交还、租约到期、启动时发现残留，都要把它清掉。
public final class FanGovernor {
    public static let minLease: TimeInterval = 3
    public static let maxLease: TimeInterval = 30
    /// 没有 Ftst 键时，一次接管最多重试多久
    public static let directAcquireTimeout: TimeInterval = 1
    /// 写了 Ftst = 1 之后，最多等多久
    public static let unlockAcquireTimeout: TimeInterval = 10
    public static let acquireRetryInterval: TimeInterval = 0.1

    public let fans: [FanInfo]
    /// 我们是否正接管着风扇
    public private(set) var holding = false
    /// 接管、解锁、交还时的说明，后台程序把它写进日志
    public var onEvent: ((String) -> Void)?

    private let hardware: FanHardware
    private let markerPath: String?
    private let timing: GovernorTiming
    private var leaseDeadline: Date?
    private var lastWritten: [Double?]

    public init(hardware: FanHardware, markerPath: String?, timing: GovernorTiming = .real) {
        self.hardware = hardware
        self.markerPath = markerPath
        self.timing = timing
        fans = hardware.fans
        lastWritten = Array(repeating: nil, count: hardware.fans.count)
    }

    /// 启动时调用。
    /// - 标记文件还在：上次接管着风扇时进程没正常退出，先把风扇交还系统。
    /// - Ftst 停在 1、却没有风扇处在模式 1：没人在接管，系统温控却被晾着，清掉。
    ///   有风扇在模式 1 说明别的软件正接管着，Ftst 是它的，不动。
    public func reconcileAtStart() {
        if let markerPath, FileManager.default.fileExists(atPath: markerPath) {
            release(force: true)
            return
        }
        guard hardware.hasForceTestKey, (try? hardware.forceTest()) == 1 else { return }
        let anyForced = fans.contains { (try? hardware.mode(fan: $0.index)) == FanMode.forced }
        if !anyForced {
            try? hardware.setForceTest(false)
            onEvent?("Ftst was left at 1 with no fan taken over; reset it to 0")
        }
    }

    /// 接管风扇并设目标转速。rpms 每个风扇一个值，会被限制在该风扇的转速范围内。
    /// 之后 lease 秒内没有再次调用，风扇会自动交还系统。
    public func setTargets(_ rpms: [Double], lease: TimeInterval, now: Date) throws {
        guard rpms.count == fans.count else {
            throw GovernorError(description: "expected \(fans.count) target speeds, got \(rpms.count)")
        }
        guard rpms.allSatisfy(\.isFinite) else {
            throw GovernorError(description: "target speed is not a finite number")
        }
        let started = timing.now()
        do {
            if !holding {
                // 先落标记再动硬件：中途崩了，下次启动也知道要交还
                if let markerPath { FileManager.default.createFile(atPath: markerPath, contents: nil) }
                holding = true
            }
            for (i, fan) in fans.enumerated() {
                let rpm = fan.clamp(rpms[i])
                if try hardware.mode(fan: fan.index) != FanMode.forced {
                    try acquire(fan)
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
        // 接管花掉的时间（M1–M4 可能几秒）不算在租约里
        let spent = max(0, timing.now().timeIntervalSince(started))
        leaseDeadline = now.addingTimeInterval(min(max(lease, Self.minLease), Self.maxLease) + spent)
    }

    /// 让一个风扇进入模式 1，进不去就抛错
    private func acquire(_ fan: FanInfo) throws {
        let started = timing.now()
        var unlocked = false
        var attempts = 0
        while true {
            attempts += 1
            do {
                try hardware.setMode(fan: fan.index, FanMode.forced)
            } catch let error as SMCError where error.result == 0x82 {
                // 固件没接受：系统温控占着风扇，下面读回来看、按机型重试
            }
            let mode = try hardware.mode(fan: fan.index)
            let elapsed = timing.now().timeIntervalSince(started)
            if mode == FanMode.forced {
                if unlocked {
                    onEvent?("fan \(fan.index) taken over after Ftst unlock in \(String(format: "%.1f", elapsed)) s")
                } else if attempts > 1 {
                    onEvent?("fan \(fan.index) taken over after retrying for \(String(format: "%.1f", elapsed)) s")
                }
                return
            }
            if hardware.hasForceTestKey, !unlocked {
                if try hardware.forceTest() != 1 {
                    try hardware.setForceTest(true)
                    onEvent?("fan \(fan.index) is held by the system (mode \(mode)); writing Ftst = 1 to unlock")
                }
                unlocked = true
            }
            let timeout = hardware.hasForceTestKey ? Self.unlockAcquireTimeout : Self.directAcquireTimeout
            if elapsed >= timeout {
                throw GovernorError(description: "could not take over fan \(fan.index): still in mode \(mode) after retrying for \(String(format: "%.1f", elapsed)) s")
            }
            timing.sleep(Self.acquireRetryInterval)
        }
    }

    /// 把风扇交还系统。默认只在我们接管着的时候才动，免得把别的软件的接管也解除掉。
    public func release(force: Bool = false) {
        guard holding || force else { return }
        for fan in fans where (try? hardware.mode(fan: fan.index)) == FanMode.forced {
            try? hardware.setMode(fan: fan.index, FanMode.auto)
        }
        if hardware.hasForceTestKey, (try? hardware.forceTest()) == 1 {
            try? hardware.setForceTest(false)
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
