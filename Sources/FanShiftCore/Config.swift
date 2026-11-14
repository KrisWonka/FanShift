import Foundation

public enum CycleStepType: String, Codable, CaseIterable, Identifiable {
    case auto
    case fullBlast
    case cooldown
    case temperature

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .auto: return "Auto"
        case .fullBlast: return "Full Blast"
        case .cooldown: return "Cooldown"
        case .temperature: return "Temperature"
        }
    }

    public var icon: String {
        switch self {
        case .auto: return "leaf.fill"
        case .fullBlast: return "wind"
        case .cooldown: return "snowflake"
        case .temperature: return "thermometer.medium"
        }
    }
}

/// 曲线上两个点之间怎么取值
public enum CurveMode: String, Codable, CaseIterable, Identifiable {
    /// 阶梯：温度超过某个点，就用那个点的转速，直到超过下一个点（TG Pro 的做法）
    case step
    /// 连直线：两个点之间按比例过渡
    case linear

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .step: return "阶梯（和 TG Pro 一样）"
        case .linear: return "连直线（更平滑，同一条曲线下转速会更高）"
        }
    }
}

public struct CurvePoint: Codable, Identifiable, Equatable {
    /// 拖到 0% 以下的点记成这个值，表示 Stop
    public static let stopSentinel = -10

    public var id = UUID()
    public var temperatureLimit: Double  // °C
    public var percent: Int              // 0–100；小于 0 表示 Stop（这一段交还系统，风扇可以停转）

    enum CodingKeys: String, CodingKey {
        case temperatureLimit, percent
    }

    public init(temperatureLimit: Double, percent: Int) {
        self.temperatureLimit = temperatureLimit
        self.percent = percent
    }

    public var isStop: Bool { percent < 0 }

    public static func == (a: CurvePoint, b: CurvePoint) -> Bool {
        a.temperatureLimit == b.temperatureLimit && a.percent == b.percent
    }
}

public enum CurveTemplate: String, CaseIterable, Identifiable {
    case silence, performance, turbo, empty

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .silence: return "Silence"
        case .performance: return "Performance"
        case .turbo: return "Turbo"
        case .empty: return "Empty"
        }
    }

    public var points: [CurvePoint] {
        let raw: [(Double, Int)]
        switch self {
        case .silence:
            raw = [(30, 0), (40, 0), (50, 20), (60, 35), (70, 50), (80, 70), (90, 100)]
        case .performance:
            raw = [(30, 0), (35, 10), (45, 25), (50, 55), (60, 75), (70, 80), (80, 90), (90, 100)]
        case .turbo:
            raw = [(20, 0), (30, 0), (35, 10), (40, 50), (50, 75), (60, 95), (70, 100), (80, 100), (90, 100)]
        case .empty:
            raw = []
        }
        return raw.map { CurvePoint(temperatureLimit: $0.0, percent: $0.1) }
    }
}

public struct CycleStep: Codable, Identifiable, Equatable {
    public var id = UUID()
    public var type: CycleStepType
    public var name: String = ""

    // Cooldown 专属
    public var cooldownTargetTemp: Double = 40
    public var cooldownPollSec: Double = 3

    // Full Blast 专属
    public var autoRevertEnabled: Bool = false
    public var autoRevertSec: Int = 600

    // Temperature 专属
    public var curve: [CurvePoint] = []
    public var sensor: SensorSelection = .cpuMax

    public init(type: CycleStepType, name: String = "", curve: [CurvePoint] = []) {
        self.type = type
        self.name = name
        self.curve = curve
    }

    public var effectiveName: String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? type.displayName : trimmed
    }

    enum CodingKeys: String, CodingKey {
        case id, type, name, cooldownTargetTemp, cooldownPollSec, autoRevertEnabled, autoRevertSec, curve, sensor
        case configSensor  // 旧版字段，只读不写
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        type = try c.decode(CycleStepType.self, forKey: .type)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        cooldownTargetTemp = try c.decodeIfPresent(Double.self, forKey: .cooldownTargetTemp) ?? 40
        cooldownPollSec = try c.decodeIfPresent(Double.self, forKey: .cooldownPollSec) ?? 3
        autoRevertEnabled = try c.decodeIfPresent(Bool.self, forKey: .autoRevertEnabled) ?? false
        autoRevertSec = try c.decodeIfPresent(Int.self, forKey: .autoRevertSec) ?? 600
        curve = try c.decodeIfPresent([CurvePoint].self, forKey: .curve) ?? []
        if let s = try c.decodeIfPresent(SensorSelection.self, forKey: .sensor) {
            sensor = s
        } else if let legacy = try c.decodeIfPresent(Int.self, forKey: .configSensor) {
            // 旧版存的是 TG Pro 的传感器编号：0 = Any Sensor，4 = Highest CPU
            sensor = legacy == 0 ? .anyMax : .cpuMax
        } else {
            sensor = .cpuMax
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(type, forKey: .type)
        try c.encode(name, forKey: .name)
        try c.encode(cooldownTargetTemp, forKey: .cooldownTargetTemp)
        try c.encode(cooldownPollSec, forKey: .cooldownPollSec)
        try c.encode(autoRevertEnabled, forKey: .autoRevertEnabled)
        try c.encode(autoRevertSec, forKey: .autoRevertSec)
        try c.encode(curve, forKey: .curve)
        try c.encode(sensor, forKey: .sensor)
    }
}

public struct AppConfig: Codable, Equatable {
    public var hotkeyEnabled: Bool = true
    public var hotkeyMods: [String] = ["ctrl", "alt", "cmd"]
    public var hotkeyKey: String = "8"
    /// 录制快捷键时记下的按键码。没有（比如从旧配置搬来的）就按 hotkeyKey 查表。
    public var hotkeyKeyCode: Int? = nil

    public var alertEnabled: Bool = true
    public var alertDuration: Double = 1.2
    public var alertCooldownDone: String = "Cooldown done ✓"

    public var menuBarShowTemp: Bool = true
    public var menuBarShowRPM: Bool = true

    public var curveMode: CurveMode = .step
    /// 参考温度选「最热的 CPU 核心」时，在读数上加的修正值（°C）。
    /// 实测 TG Pro 的 Highest CPU 比最热核心的读数低约 2°C（四次标定 216 行数据，减 2°C 后 100% 吻合），
    /// 默认减 2°C，同一条曲线才和原来手感一致。设成 0 就是原始读数。
    public var hotCoreOffset: Double = -2.0

    public var cycleSteps: [CycleStep] = [
        CycleStep(type: .auto, name: "Silence"),
        CycleStep(type: .temperature, name: "Performance", curve: CurveTemplate.performance.points),
        CycleStep(type: .temperature, name: "Turbo", curve: CurveTemplate.turbo.points),
    ]

    public init() {}

    enum CodingKeys: String, CodingKey {
        case hotkeyEnabled, hotkeyMods, hotkeyKey, hotkeyKeyCode
        case alertEnabled, alertDuration, alertCooldownDone
        case menuBarShowTemp, menuBarShowRPM, curveMode, hotCoreOffset, cycleSteps
    }

    public init(from decoder: Decoder) throws {
        let d = AppConfig()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hotkeyEnabled = try c.decodeIfPresent(Bool.self, forKey: .hotkeyEnabled) ?? d.hotkeyEnabled
        hotkeyMods = try c.decodeIfPresent([String].self, forKey: .hotkeyMods) ?? d.hotkeyMods
        hotkeyKey = try c.decodeIfPresent(String.self, forKey: .hotkeyKey) ?? d.hotkeyKey
        hotkeyKeyCode = try c.decodeIfPresent(Int.self, forKey: .hotkeyKeyCode)
        alertEnabled = try c.decodeIfPresent(Bool.self, forKey: .alertEnabled) ?? d.alertEnabled
        alertDuration = try c.decodeIfPresent(Double.self, forKey: .alertDuration) ?? d.alertDuration
        alertCooldownDone = try c.decodeIfPresent(String.self, forKey: .alertCooldownDone) ?? d.alertCooldownDone
        menuBarShowTemp = try c.decodeIfPresent(Bool.self, forKey: .menuBarShowTemp) ?? d.menuBarShowTemp
        menuBarShowRPM = try c.decodeIfPresent(Bool.self, forKey: .menuBarShowRPM) ?? d.menuBarShowRPM
        curveMode = try c.decodeIfPresent(CurveMode.self, forKey: .curveMode) ?? d.curveMode
        hotCoreOffset = try c.decodeIfPresent(Double.self, forKey: .hotCoreOffset) ?? d.hotCoreOffset
        cycleSteps = try c.decodeIfPresent([CycleStep].self, forKey: .cycleSteps) ?? d.cycleSteps
    }

    /// 快捷键实际用的按键码
    public var resolvedHotkeyKeyCode: Int? {
        hotkeyKeyCode ?? KeyCodes.keyCode(for: hotkeyKey)
    }

    public enum Source: Equatable {
        case saved               // 读到了自己的配置文件
        case migratedFromLegacy  // 从旧版（Hammerspoon 目录）搬过来的
        case defaults            // 什么都没有，用默认值
    }

    public static func decode(_ data: Data) throws -> AppConfig {
        try JSONDecoder().decode(AppConfig.self, from: data)
    }

    /// 读配置。自己的配置不存在时，先找旧版配置搬过来；都没有就用默认值。
    public static func load(from url: URL = AppPaths.config, legacy: URL = AppPaths.legacyConfig) -> (config: AppConfig, source: Source) {
        if let data = try? Data(contentsOf: url), let cfg = try? decode(data) {
            return (cfg, .saved)
        }
        if let data = try? Data(contentsOf: legacy), let cfg = try? decode(data) {
            try? cfg.save(to: url)
            return (cfg, .migratedFromLegacy)
        }
        return (AppConfig(), .defaults)
    }

    public func save(to url: URL = AppPaths.config) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}

/// 重启后要恢复的运行状态
public struct RuntimeState: Codable, Equatable {
    public var activeStepID: UUID?
    public var revertedToAuto: Bool = false

    public init(activeStepID: UUID? = nil, revertedToAuto: Bool = false) {
        self.activeStepID = activeStepID
        self.revertedToAuto = revertedToAuto
    }

    public static func load(from url: URL = AppPaths.state) -> RuntimeState {
        guard let data = try? Data(contentsOf: url),
              let s = try? JSONDecoder().decode(RuntimeState.self, from: data) else { return RuntimeState() }
        return s
    }

    public func save(to url: URL = AppPaths.state) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(self) { try? data.write(to: url, options: .atomic) }
    }
}
