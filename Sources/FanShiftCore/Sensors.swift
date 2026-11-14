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

/// 读本机所有温度传感器。同一个对象可以反复读。
public final class TemperatureSensors {
    private let client: CFTypeRef?

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

    /// 同名传感器会重复出现，合并取平均；结果按名字排序。读不到时返回空数组。
    public func readAll() -> [SensorReading] {
        guard let client, let services = _IOHIDEventSystemClientCopyServices(client) as? [CFTypeRef] else { return [] }
        var groups: [String: [Double]] = [:]
        for svc in services {
            guard let name = _IOHIDServiceClientCopyProperty(svc, "Product" as CFString) as? String,
                  let event = _IOHIDServiceClientCopyEvent(svc, kIOHIDEventTypeTemperature, 0, 0)?.takeRetainedValue()
            else { continue }
            let v = _IOHIDEventGetFloatValue(event, kIOHIDEventFieldTemperatureLevel)
            if v.isFinite, v > 0, v < 150 { groups[name, default: []].append(v) }
        }
        return groups
            .map { SensorReading(name: $0.key, value: $0.value.reduce(0, +) / Double($0.value.count)) }
            .sorted { $0.name < $1.name }
    }
}

/// 一个档位的曲线参考哪个温度
public enum SensorSelection: Equatable, Codable {
    case cpuMax          // 最热的 CPU 传感器（默认）
    case cpuAvg          // CPU 传感器平均
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
            self = raw.hasPrefix("name:") ? .named(String(raw.dropFirst(5))) : .cpuMax
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

    public var displayName: String {
        switch self {
        case .cpuMax: return "最热的 CPU 传感器"
        case .cpuAvg: return "CPU 平均"
        case .anyMax: return "所有传感器里最热的"
        case .named(let n): return n
        }
    }
}

public enum SensorMath {
    /// 校准用的参考读数，是个基本不变的常数，不能当温度用
    public static func isCalibration(_ name: String) -> Bool {
        name.lowercased().contains("tcal")
    }

    /// CPU 芯片上的温度点。M5 上叫 "PMU tdie1…14"；其他机型常见 pACC / eACC / SOC die。
    public static func isCPU(_ name: String) -> Bool {
        let n = name.lowercased()
        if isCalibration(n) { return false }
        return n.contains("tdie") || n.contains("pacc") || n.contains("eacc") || n.contains("soc") || n.contains("cpu")
    }

    /// 按选择算出一个温度。没有可用读数时返回 nil。
    public static func value(_ selection: SensorSelection, from readings: [SensorReading]) -> Double? {
        let usable = readings.filter { !isCalibration($0.name) }
        switch selection {
        case .cpuMax:
            return usable.filter { isCPU($0.name) }.map(\.value).max()
        case .cpuAvg:
            let cpu = usable.filter { isCPU($0.name) }.map(\.value)
            return cpu.isEmpty ? nil : cpu.reduce(0, +) / Double(cpu.count)
        case .anyMax:
            return usable.map(\.value).max()
        case .named(let name):
            return readings.first { $0.name == name }?.value
        }
    }
}
