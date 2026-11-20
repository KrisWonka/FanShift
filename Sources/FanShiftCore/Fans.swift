import Foundation

public struct FanInfo: Codable, Equatable {
    public var index: Int
    public var minRPM: Double
    public var maxRPM: Double

    public init(index: Int, minRPM: Double, maxRPM: Double) {
        self.index = index
        self.minRPM = minRPM
        self.maxRPM = maxRPM
    }

    /// 百分比按风扇转速范围折算：0% = 最低转速，100% = 最高转速
    public func rpm(forPercent percent: Double) -> Double {
        let p = min(max(percent, 0), 100)
        return minRPM + (maxRPM - minRPM) * p / 100
    }

    public func clamp(_ rpm: Double) -> Double {
        min(max(rpm, minRPM), maxRPM)
    }
}

/// 风扇模式键的取值
public enum FanMode {
    public static let auto = 0     // 交还系统
    public static let forced = 1   // 由软件接管，按目标转速转
    public static let system = 3   // 系统温控进程（thermalmonitord）在管
}

/// 风扇硬件接口。真机实现是 SMCFans，测试里用假的。
public protocol FanHardware {
    var fans: [FanInfo] { get }
    func mode(fan: Int) throws -> Int
    /// 固件不接受时抛 SMCError，result = 0x82（系统温控占着风扇时就是这样）
    func setMode(fan: Int, _ mode: Int) throws
    func target(fan: Int) throws -> Double
    func setTarget(fan: Int, rpm: Double) throws
    func actual(fan: Int) throws -> Double

    /// 有没有 Ftst 键（M1–M4 有，M5 没有）。有的话，系统温控占着风扇时要先写 Ftst = 1 才接管得了。
    var hasForceTestKey: Bool { get }
    func forceTest() throws -> Int
    func setForceTest(_ on: Bool) throws
}

/// 没有 Ftst 键的机型（M5）用这组默认实现
public extension FanHardware {
    var hasForceTestKey: Bool { false }
    func forceTest() throws -> Int { 0 }
    func setForceTest(_ on: Bool) throws {}
}

public struct FanSetupError: Error, CustomStringConvertible {
    public let description: String
}

/// 通过 AppleSMC 读写风扇。
/// 每个风扇 n 的键：F{n}Ac 实际转速、F{n}Tg 目标转速、F{n}Mn / F{n}Mx 转速范围、模式键；
/// M1–M4 另有一个全机共用的 Ftst 键，接管前用来让系统温控放手。
public final class SMCFans: FanHardware {
    public let fans: [FanInfo]
    /// 模式键后缀：M5 是小写 "md"，M1–M4 是大写 "Md"
    public let modeSuffix: String
    /// 有 Ftst 键（M1–M4）：系统温控占着风扇时，要先写 Ftst = 1 才接管得了
    public let hasForceTestKey: Bool

    public init() throws {
        guard let count = try? SMC.readDouble("FNum"), count >= 1 else {
            throw FanSetupError(description: "this Mac has no fans, or the fan count cannot be read")
        }
        var list: [FanInfo] = []
        for n in 0..<Int(count) {
            let mn = try SMC.readDouble("F\(n)Mn")
            let mx = try SMC.readDouble("F\(n)Mx")
            guard mn > 0, mx > mn else {
                throw FanSetupError(description: "fan \(n) reports an invalid speed range: \(mn) to \(mx)")
            }
            list.append(FanInfo(index: n, minRPM: mn, maxRPM: mx))
        }
        fans = list
        if SMC.info("F0md") != nil {
            modeSuffix = "md"
        } else if SMC.info("F0Md") != nil {
            modeSuffix = "Md"
        } else {
            throw FanSetupError(description: "no fan mode key found (F0md / F0Md)")
        }
        hasForceTestKey = SMC.info("Ftst") != nil
    }

    public func mode(fan: Int) throws -> Int {
        Int(try SMC.readDouble("F\(fan)\(modeSuffix)"))
    }

    public func setMode(fan: Int, _ mode: Int) throws {
        try SMC.writeUInt8("F\(fan)\(modeSuffix)", UInt8(mode))
    }

    public func target(fan: Int) throws -> Double {
        try SMC.readDouble("F\(fan)Tg")
    }

    /// 有的机型写目标转速时固件回一个结果码（chill 在 M4 Pro 上见过 0x87），但稍后照样生效。
    /// 所以回了结果码时再看半秒：读回来的值变成写进去的值，就算成功。
    public func setTarget(fan: Int, rpm: Double) throws {
        let wanted = Double(Float(rpm))
        do {
            try SMC.writeFloat("F\(fan)Tg", Float(rpm))
        } catch let error as SMCError where error.kr == 0 && error.result != 0 && error.result != 0x84 {
            let deadline = Date().addingTimeInterval(0.5)
            while Date() < deadline {
                if let now = try? target(fan: fan), abs(now - wanted) < 1 { return }
                Thread.sleep(forTimeInterval: 0.02)
            }
            throw error
        }
    }

    public func actual(fan: Int) throws -> Double {
        try SMC.readDouble("F\(fan)Ac")
    }

    public func forceTest() throws -> Int {
        hasForceTestKey ? Int(try SMC.readDouble("Ftst")) : 0
    }

    public func setForceTest(_ on: Bool) throws {
        guard hasForceTestKey else { return }
        try SMC.writeUInt8("Ftst", on ? 1 : 0)
    }
}
