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
    func setMode(fan: Int, _ mode: Int) throws
    func target(fan: Int) throws -> Double
    func setTarget(fan: Int, rpm: Double) throws
    func actual(fan: Int) throws -> Double
}

public struct FanSetupError: Error, CustomStringConvertible {
    public let description: String
}

/// 通过 AppleSMC 读写风扇。
/// 每个风扇 n 的键：F{n}Ac 实际转速、F{n}Tg 目标转速、F{n}Mn / F{n}Mx 转速范围、模式键。
public final class SMCFans: FanHardware {
    public let fans: [FanInfo]
    /// 模式键后缀：M5 是小写 "md"，M1–M4 是大写 "Md"
    public let modeSuffix: String
    /// 有 Ftst 键说明是 M1–M4：接管前要先解锁，目前还没实现
    public let needsUnlock: Bool

    public init() throws {
        guard let count = try? SMC.readDouble("FNum"), count >= 1 else {
            throw FanSetupError(description: "这台 Mac 没有风扇，或者读不到风扇数量")
        }
        var list: [FanInfo] = []
        for n in 0..<Int(count) {
            let mn = try SMC.readDouble("F\(n)Mn")
            let mx = try SMC.readDouble("F\(n)Mx")
            guard mn > 0, mx > mn else {
                throw FanSetupError(description: "风扇 \(n) 的转速范围不正常：\(mn) ~ \(mx)")
            }
            list.append(FanInfo(index: n, minRPM: mn, maxRPM: mx))
        }
        fans = list
        if SMC.info("F0md") != nil {
            modeSuffix = "md"
        } else if SMC.info("F0Md") != nil {
            modeSuffix = "Md"
        } else {
            throw FanSetupError(description: "找不到风扇模式键 F0md / F0Md")
        }
        needsUnlock = SMC.info("Ftst") != nil
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

    public func setTarget(fan: Int, rpm: Double) throws {
        try SMC.writeFloat("F\(fan)Tg", Float(rpm))
    }

    public func actual(fan: Int) throws -> Double {
        try SMC.readDouble("F\(fan)Ac")
    }
}
