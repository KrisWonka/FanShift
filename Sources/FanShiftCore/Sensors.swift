import Foundation
import IOKit

// 温度传感器走 IOHIDEventSystemClient（IOKit 的私有接口，Stats、Macs Fan Control 等监控软件用的是同一套）。
@_silgen_name("IOHIDEventSystemClientCreate")
private func _IOHIDEventSystemClientCreate(_ allocator: CFAllocator?) -> Unmanaged<CFTypeRef>?

@_silgen_name("IOHIDEventSystemClientSetMatching")
private func _IOHIDEventSystemClientSetMatching(_ client: CFTypeRef, _ matching: CFDictionary) -> Int32

@_silgen_name("IOHIDEventSystemClientCopyServices")
private func _IOHIDEventSystemClientCopyServices(_ client: CFTypeRef) -> CFArray?

@_silgen_name("IOHIDServiceClientCopyProperty")
private func _IOHIDServiceClientCopyProperty(_ service: CFTypeRef, _ key: CFString) -> CFTypeRef?

@_silgen_name("IOHIDServiceClientCopyEvent")
private func _IOHIDServiceClientCopyEvent(_ service: CFTypeRef, _ type: Int64, _ options: Int64, _ flags: Int64) -> Unmanaged<CFTypeRef>?

@_silgen_name("IOHIDEventGetFloatValue")
private func _IOHIDEventGetFloatValue(_ event: CFTypeRef, _ field: Int32) -> Double

private let kHIDPageAppleVendor: Int32 = 0xff00
private let kHIDUsageTemperatureSensor: Int32 = 0x0005
private let kIOHIDEventTypeTemperature: Int64 = 15
private let kIOHIDEventFieldTemperatureLevel: Int32 = Int32(kIOHIDEventTypeTemperature) << 16

public struct SensorReading: Equatable {
    public let name: String
    public let value: Double

    public init(name: String, value: Double) {
        self.name = name
        self.value = value
    }
}

/// 读本机所有温度传感器。同一个对象可以反复读，但要在同一个队列上用。
///
/// 读数来自两处：
/// - IOHID 的温度传感器（芯片上的温度点、硬盘、电池）；
/// - SMC 里的 CPU 核心温度（键名 Tp** 是性能核心，Te** 是能效核心）。核心温度比芯片上的温度点
///   更靠近发热源，负载下要高出几度。TG Pro 的「Highest CPU」跟的就是这一组（实测吻合度 99%）。
public final class TemperatureSensors {
    private let client: CFTypeRef?
    private var coreKeys: [String]?

    public init() {
        if let c = _IOHIDEventSystemClientCreate(kCFAllocatorDefault)?.takeRetainedValue() {
            let matching: [String: Any] = [
                "PrimaryUsagePage": kHIDPageAppleVendor,
                "PrimaryUsage": kHIDUsageTemperatureSensor,
            ]
            _ = _IOHIDEventSystemClientSetMatching(c, matching as CFDictionary)
            client = c
        } else {
            client = nil
        }
    }

    /// 所有读数，按名字排序。读不到时返回空数组。
    public func readAll() -> [SensorReading] {
        (readHID() + readCores()).sorted { $0.name < $1.name }
    }

    /// IOHID 的温度传感器。同名的会重复出现，合并取平均。
    private func readHID() -> [SensorReading] {
        guard let client, let services = _IOHIDEventSystemClientCopyServices(client) as? [CFTypeRef] else { return [] }
        var groups: [String: [Double]] = [:]
        for svc in services {
            guard let name = _IOHIDServiceClientCopyProperty(svc, "Product" as CFString) as? String,
                  let event = _IOHIDServiceClientCopyEvent(svc, kIOHIDEventTypeTemperature, 0, 0)?.takeRetainedValue()
            else { continue }
            let v = _IOHIDEventGetFloatValue(event, kIOHIDEventFieldTemperatureLevel)
            if v.isFinite, v > 0, v < 150 { groups[name, default: []].append(v) }
        }
        return groups.map { SensorReading(name: $0.key, value: $0.value.reduce(0, +) / Double($0.value.count)) }
    }

    /// SMC 里的 CPU 核心温度。键名第一次读的时候找一遍（要枚举几千个键，约 0.1 秒），之后只读这几个。
    private func readCores() -> [SensorReading] {
        if coreKeys == nil {
            coreKeys = SMC.allKeys()
                .filter { ($0.hasPrefix("Tp") || $0.hasPrefix("Te")) && SMC.info($0)?.type == "flt " }
                .sorted()
        }
        return (coreKeys ?? []).compactMap { key in
            guard let v = try? SMC.readDouble(key), v.isFinite, v > 10, v < 130 else { return nil }
            return SensorReading(name: SensorMath.coreName(key), value: v)
        }
    }
}

/// 一个档位的曲线参考哪个温度
public enum SensorSelection: Hashable, Codable {
    case cpuMax          // 最热的 CPU 核心（默认；等同 TG Pro 的 Highest CPU）
    case cpuAvg          // 芯片上各温度点的平均（Cooldown 用的就是它）
    case anyMax          // 所有传感器里最热的（含硬盘、电池）
    case named(String)   // 指定某一个传感器

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = SensorSelection(raw: raw)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(raw)
    }

    public init(raw: String) {
        switch raw {
        case "cpuMax": self = .cpuMax
        case "cpuAvg": self = .cpuAvg
        case "anyMax": self = .anyMax
        default:
            guard raw.hasPrefix("name:") else { self = .cpuMax; return }
            self = .named(SensorMath.migratedName(String(raw.dropFirst(5))))
        }
    }

    public var raw: String {
        switch self {
        case .cpuMax: return "cpuMax"
        case .cpuAvg: return "cpuAvg"
        case .anyMax: return "anyMax"
        case .named(let n): return "name:\(n)"
        }
    }

    /// 英文名，命令行工具和日志用；界面上的名字在 App 里按语言翻译
    public var displayName: String {
        switch self {
        case .cpuMax: return "Hottest CPU core"
        case .cpuAvg: return "Chip average"
        case .anyMax: return "Hottest sensor"
        case .named(let n): return n
        }
    }
}

public enum SensorMath {
    /// 校准用的参考读数，是个基本不变的常数，不能当温度用
    public static func isCalibration(_ name: String) -> Bool {
        name.lowercased().contains("tcal")
    }

    /// 核心温度读数的名字 = 这个前缀 + SMC 键名。名字会存进配置（参考温度选了某个具体传感器时），
    /// 所以不能跟着界面语言变；界面上显示时再翻译。
    private static let corePrefix = "CPU core "
    /// 2026-11 之前的前缀，旧配置里可能存着
    private static let legacyCorePrefix = "CPU 核心 "

    public static func coreName(_ smcKey: String) -> String {
        corePrefix + smcKey
    }

    /// 核心温度读数对应的 SMC 键名（比如 "Tp00"）；不是核心温度就返回 nil
    public static func coreKey(_ name: String) -> String? {
        name.hasPrefix(corePrefix) ? String(name.dropFirst(corePrefix.count)) : nil
    }

    /// 旧配置里的传感器名换成现在的写法
    public static func migratedName(_ name: String) -> String {
        name.hasPrefix(legacyCorePrefix) ? corePrefix + name.dropFirst(legacyCorePrefix.count) : name
    }

    /// CPU 核心温度（来自 SMC）
    public static func isCore(_ name: String) -> Bool {
        name.hasPrefix(corePrefix)
    }

    /// 芯片上的温度点（来自 IOHID）。M5 上叫 "PMU tdie1…14"；其他机型常见 pACC / eACC / SOC die。
    public static func isDie(_ name: String) -> Bool {
        let n = name.lowercased()
        if isCalibration(n) || isCore(name) { return false }
        return n.contains("tdie") || n.contains("pacc") || n.contains("eacc") || n.contains("soc") || n.contains("cpu")
    }

    public static func isCPU(_ name: String) -> Bool {
        isCore(name) || isDie(name)
    }

    /// 按选择算出一个温度。没有可用读数时返回 nil。
    ///
    /// - cpuMax：最热的 CPU 核心；读不到核心温度的机器退回到芯片温度点里最热的。
    /// - cpuAvg：芯片上各温度点的平均（旧版 Cooldown 用的就是这个口径）；没有就退回到核心温度的平均。
    public static func value(_ selection: SensorSelection, from readings: [SensorReading]) -> Double? {
        let usable = readings.filter { !isCalibration($0.name) }
        let cores = usable.filter { isCore($0.name) }.map(\.value)
        let dies = usable.filter { isDie($0.name) }.map(\.value)
        func average(_ xs: [Double]) -> Double? {
            xs.isEmpty ? nil : xs.reduce(0, +) / Double(xs.count)
        }
        switch selection {
        case .cpuMax:
            return cores.max() ?? dies.max()
        case .cpuAvg:
            return average(dies) ?? average(cores)
        case .anyMax:
            return usable.map(\.value).max()
        case .named(let name):
            return readings.first { $0.name == name }?.value
        }
    }
}
