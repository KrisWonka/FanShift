import XCTest
@testable import FanShiftCore

final class CurveTests: XCTestCase {
    private func pts(_ raw: [(Double, Int)]) -> [CurvePoint] {
        raw.map { CurvePoint(temperatureLimit: $0.0, percent: $0.1) }
    }

    func testInterpolatesBetweenPoints() {
        // Performance 曲线：45°C → 25%，50°C → 55%。47.5°C 在正中间 → 40%
        let out = evaluateCurve(CurveTemplate.performance.points, at: 47.5, mode: .linear)
        guard case .percent(let p) = out else { return XCTFail("应该是百分比") }
        XCTAssertEqual(p, 40, accuracy: 1e-9)
    }

    func testExactlyOnAPoint() {
        XCTAssertEqual(evaluateCurve(CurveTemplate.performance.points, at: 50, mode: .linear), .percent(55))
    }

    func testBelowFirstAndAboveLast() {
        let curve = CurveTemplate.performance.points
        XCTAssertEqual(evaluateCurve(curve, at: 10, mode: .linear), .percent(0))
        XCTAssertEqual(evaluateCurve(curve, at: 99, mode: .linear), .percent(100))
    }

    func testUnsortedInputIsSorted() {
        let curve = pts([(60, 80), (40, 20)])
        XCTAssertEqual(evaluateCurve(curve, at: 50, mode: .linear), .percent(50))
    }

    func testEmptyCurveMeansStop() {
        XCTAssertEqual(evaluateCurve([], at: 50, mode: .linear), .stop)
    }

    func testStopPointCoversUntilNextPoint() {
        let curve = pts([(30, CurvePoint.stopSentinel), (50, 20), (60, 40)])
        XCTAssertEqual(evaluateCurve(curve, at: 25, mode: .linear), .stop)
        XCTAssertEqual(evaluateCurve(curve, at: 40, mode: .linear), .stop)
        XCTAssertEqual(evaluateCurve(curve, at: 50, mode: .linear), .percent(20))
        XCTAssertEqual(evaluateCurve(curve, at: 55, mode: .linear), .percent(30))
    }

    func testNormalPointFollowedByStopHoldsItsValue() {
        let curve = pts([(40, 20), (50, CurvePoint.stopSentinel)])
        XCTAssertEqual(evaluateCurve(curve, at: 45, mode: .linear), .percent(20))
        XCTAssertEqual(evaluateCurve(curve, at: 60, mode: .linear), .stop)
    }

    func testDuplicateTemperaturesDoNotDivideByZero() {
        let curve = pts([(40, 20), (40, 60), (50, 80)])
        XCTAssertEqual(evaluateCurve(curve, at: 45, mode: .linear), .percent(70))
    }

    func testStepModeHoldsEachPointUntilTheNext() {
        // 阶梯：温度「超过」某个点才用它的值。Performance 曲线：45°C → 25%，50°C → 55%
        let curve = CurveTemplate.performance.points
        XCTAssertEqual(evaluateCurve(curve, at: 47.5, mode: .step), .percent(25))
        XCTAssertEqual(evaluateCurve(curve, at: 50, mode: .step), .percent(25))    // 正好 50 还不算超过
        XCTAssertEqual(evaluateCurve(curve, at: 50.1, mode: .step), .percent(55))
        XCTAssertEqual(evaluateCurve(curve, at: 99, mode: .step), .percent(100))
    }

    func testStepModeBelowFirstPointMeansNoRule() {
        let curve = CurveTemplate.performance.points  // 第一个点在 30°C
        XCTAssertEqual(evaluateCurve(curve, at: 30, mode: .step), .stop)
        XCTAssertEqual(evaluateCurve(curve, at: 30.1, mode: .step), .percent(0))
        XCTAssertEqual(evaluateCurve([], at: 50, mode: .step), .stop)
    }

    func testStepModeStopPoint() {
        let curve = pts([(30, CurvePoint.stopSentinel), (50, 20), (60, 40)])
        XCTAssertEqual(evaluateCurve(curve, at: 45, mode: .step), .stop)
        XCTAssertEqual(evaluateCurve(curve, at: 55, mode: .step), .percent(20))
        XCTAssertEqual(evaluateCurve(curve, at: 65, mode: .step), .percent(40))
    }

    func testPercentToRPMUsesFanRange() {
        // 这台 M5 Pro 的风扇：2317 ~ 7826。55% → 2317 + 0.55 × 5509 = 5346.95
        let fan = FanInfo(index: 0, minRPM: 2317, maxRPM: 7826)
        XCTAssertEqual(fan.rpm(forPercent: 55), 5346.95, accuracy: 0.01)
        XCTAssertEqual(fan.rpm(forPercent: 0), 2317)
        XCTAssertEqual(fan.rpm(forPercent: 100), 7826)
        XCTAssertEqual(fan.rpm(forPercent: 150), 7826)
        XCTAssertEqual(fan.clamp(100), 2317)
        XCTAssertEqual(fan.clamp(9999), 7826)
    }
}

final class ConfigTests: XCTestCase {
    /// 旧版（tgpro-hotkey-mac）配置文件的样子，字段取自用户实际在用的那份
    private let legacyJSON = """
    {
      "alertCooldownDone" : "Cooldown done ✓",
      "alertDuration" : 1.2,
      "alertEnabled" : true,
      "cycleSteps" : [
        { "autoRevertEnabled" : false, "autoRevertSec" : 600, "configFan" : 0, "configSensor" : 0,
          "cooldownPollSec" : 3, "cooldownTargetTemp" : 40, "curve" : [],
          "id" : "0587BFAD-4ACC-4ADC-9336-EF130490AF80", "name" : "Silence", "type" : "auto" },
        { "autoRevertEnabled" : false, "autoRevertSec" : 600, "configFan" : 0, "configSensor" : 4,
          "cooldownPollSec" : 3, "cooldownTargetTemp" : 40,
          "curve" : [ { "percent" : 0, "temperatureLimit" : 30 }, { "percent" : 55, "temperatureLimit" : 50 } ],
          "id" : "2F7B63A2-67CB-4679-955B-D56D68472E8B", "name" : "Performance", "type" : "temperature" }
      ],
      "hotkeyEnabled" : true,
      "hotkeyKey" : "8",
      "hotkeyMods" : [ "ctrl", "alt", "cmd" ]
    }
    """

    func testDecodesLegacyConfig() throws {
        let cfg = try AppConfig.decode(Data(legacyJSON.utf8))
        XCTAssertEqual(cfg.cycleSteps.count, 2)
        XCTAssertEqual(cfg.cycleSteps[0].type, .auto)
        XCTAssertEqual(cfg.cycleSteps[0].effectiveName, "Silence")
        XCTAssertEqual(cfg.cycleSteps[0].id.uuidString, "0587BFAD-4ACC-4ADC-9336-EF130490AF80")
        XCTAssertEqual(cfg.cycleSteps[1].curve.count, 2)
        XCTAssertEqual(cfg.cycleSteps[1].curve[1], CurvePoint(temperatureLimit: 50, percent: 55))
        XCTAssertEqual(cfg.hotkeyMods, ["ctrl", "alt", "cmd"])
        // 旧版没有的字段取默认值
        XCTAssertTrue(cfg.menuBarShowTemp)
        XCTAssertTrue(cfg.menuBarShowRPM)
    }

    func testLegacySensorIndexIsMapped() throws {
        let cfg = try AppConfig.decode(Data(legacyJSON.utf8))
        XCTAssertEqual(cfg.cycleSteps[0].sensor, .anyMax)  // 0 = Any Sensor
        XCTAssertEqual(cfg.cycleSteps[1].sensor, .cpuMax)  // 4 = Highest CPU
    }

    func testHotkeyKeyCodeFallsBackToTable() throws {
        let cfg = try AppConfig.decode(Data(legacyJSON.utf8))
        XCTAssertNil(cfg.hotkeyKeyCode)
        XCTAssertEqual(cfg.resolvedHotkeyKeyCode, 28)  // 数字键 8
    }

    func testRoundTripKeepsEverything() throws {
        var cfg = AppConfig()
        cfg.cycleSteps[1].sensor = .named("PMU tdie1")
        cfg.hotkeyKeyCode = 100
        cfg.menuBarShowRPM = false
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("fanshift-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("config.json")
        try cfg.save(to: url)
        let (loaded, source) = AppConfig.load(from: url, legacy: dir.appendingPathComponent("none.json"))
        XCTAssertEqual(source, .saved)
        XCTAssertEqual(loaded, cfg)
    }

    func testLoadMigratesLegacyWhenOwnConfigMissing() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("fanshift-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let legacy = dir.appendingPathComponent("legacy.json")
        try Data(legacyJSON.utf8).write(to: legacy)
        let own = dir.appendingPathComponent("new/config.json")

        let (cfg, source) = AppConfig.load(from: own, legacy: legacy)
        XCTAssertEqual(source, .migratedFromLegacy)
        XCTAssertEqual(cfg.cycleSteps.count, 2)
        // 搬过来之后自己的配置文件已经写好，下次直接读它
        XCTAssertEqual(AppConfig.load(from: own, legacy: legacy).source, .saved)
        // 旧文件原样不动
        XCTAssertEqual(try Data(contentsOf: legacy), Data(legacyJSON.utf8))
    }

    func testDefaultsWhenNothingExists() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("fanshift-test-\(UUID().uuidString)")
        let (cfg, source) = AppConfig.load(from: dir.appendingPathComponent("a.json"), legacy: dir.appendingPathComponent("b.json"))
        XCTAssertEqual(source, .defaults)
        XCTAssertEqual(cfg.cycleSteps.map(\.effectiveName), ["Silence", "Performance", "Turbo"])
    }

    func testKeyCodes() {
        XCTAssertEqual(KeyCodes.keyCode(for: "8"), 28)
        XCTAssertEqual(KeyCodes.keyCode(for: "F5"), 96)
        XCTAssertEqual(KeyCodes.keyCode(for: "space"), 49)
        XCTAssertNil(KeyCodes.keyCode(for: "不存在"))
        // ⌃⌥⌘ = control(4096) + option(2048) + command(256)
        XCTAssertEqual(KeyCodes.carbonModifiers(["ctrl", "alt", "cmd"]), 6400)
        XCTAssertEqual(KeyCodes.display(mods: ["ctrl", "alt", "cmd"], key: "8"), "⌃⌥⌘8")
    }

    func testSensorMath() {
        let readings = [
            SensorReading(name: "PMU tcal", value: 51.8),      // 校准常数，任何算法都不该用它
            SensorReading(name: "PMU tdie1", value: 50),
            SensorReading(name: "PMU tdie2", value: 44),
            SensorReading(name: "NAND CH0 temp", value: 36),
            SensorReading(name: "gas gauge battery", value: 32),
        ]
        // 读不到核心温度的机器：cpuMax 退回到芯片温度点里最热的
        XCTAssertEqual(SensorMath.value(.cpuMax, from: readings), 50)
        XCTAssertEqual(SensorMath.value(.cpuAvg, from: readings), 47)
        XCTAssertEqual(SensorMath.value(.anyMax, from: readings), 50)
        XCTAssertEqual(SensorMath.value(.named("NAND CH0 temp"), from: readings), 36)
        XCTAssertNil(SensorMath.value(.named("没有这个"), from: readings))
        XCTAssertNil(SensorMath.value(.cpuMax, from: []))
    }

    func testCoreTemperaturesDriveCpuMaxButNotCpuAvg() {
        let readings = [
            SensorReading(name: "PMU tdie1", value: 50),
            SensorReading(name: "PMU tdie2", value: 44),
            SensorReading(name: SensorMath.coreName("Tp00"), value: 58),
            SensorReading(name: SensorMath.coreName("Tp04"), value: 53),
        ]
        // 曲线参考的温度 = 最热的 CPU 核心（等同 TG Pro 的 Highest CPU）
        XCTAssertEqual(SensorMath.value(.cpuMax, from: readings), 58)
        // Cooldown 参考的温度仍是芯片温度点的平均（和旧版一致）
        XCTAssertEqual(SensorMath.value(.cpuAvg, from: readings), 47)
        XCTAssertEqual(SensorMath.value(.anyMax, from: readings), 58)
        XCTAssertTrue(SensorMath.isCore(SensorMath.coreName("Tp00")))
        XCTAssertFalse(SensorMath.isDie(SensorMath.coreName("Tp00")))
        XCTAssertTrue(SensorMath.isDie("PMU tdie1"))
        XCTAssertFalse(SensorMath.isDie("PMU tcal"))
    }
}
