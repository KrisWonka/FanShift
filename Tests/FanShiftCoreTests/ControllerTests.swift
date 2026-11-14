import XCTest
@testable import FanShiftCore

final class ControllerTests: XCTestCase {
    private let fans = [
        FanInfo(index: 0, minRPM: 2317, maxRPM: 7826),
        FanInfo(index: 1, minRPM: 2317, maxRPM: 7826),
    ]
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    /// 所有 CPU 传感器都是同一个温度
    private func cpu(_ temp: Double) -> [SensorReading] {
        [SensorReading(name: "PMU tdie1", value: temp), SensorReading(name: "PMU tdie2", value: temp)]
    }

    private func make(_ steps: [CycleStep], index: Int = 0, mode: CurveMode = .linear) -> FanController {
        var cfg = AppConfig()
        cfg.cycleSteps = steps
        cfg.curveMode = mode
        return FanController(config: cfg, fans: fans, stepIndex: index, now: t0)
    }

    private func curveStep(_ raw: [(Double, Int)], name: String = "Curve") -> CycleStep {
        CycleStep(type: .temperature, name: name, curve: raw.map { CurvePoint(temperatureLimit: $0.0, percent: $0.1) })
    }

    func testAutoStepReleases() {
        let c = make([CycleStep(type: .auto, name: "Silence")])
        XCTAssertEqual(c.tick(readings: cpu(80), now: t0).command, .release)
        XCTAssertEqual(c.letter, "S")
        XCTAssertNil(c.lastPercent)
    }

    func testCurveStepProducesTargetsForEveryFan() {
        let c = make([curveStep([(40, 0), (60, 100)])])
        // 50°C 在 40→60 的正中间 → 50% → 2317 + 0.5 × 5509 = 5071.5
        let cmd = c.tick(readings: cpu(50), now: t0).command
        XCTAssertEqual(cmd, .targets([5071.5, 5071.5]))
        XCTAssertEqual(c.lastPercent, 50)
        XCTAssertEqual(c.lastTemperature, 50)
    }

    func testCycleAdvancesAndWraps() {
        let c = make([CycleStep(type: .auto, name: "Silence"), curveStep([(40, 0)], name: "Performance"), curveStep([(40, 0)], name: "Turbo")])
        XCTAssertEqual(c.letter, "S")
        XCTAssertEqual(c.cycle(now: t0)?.effectiveName, "Performance")
        XCTAssertEqual(c.letter, "P")
        XCTAssertEqual(c.cycle(now: t0)?.effectiveName, "Turbo")
        XCTAssertEqual(c.cycle(now: t0)?.effectiveName, "Silence")
        XCTAssertEqual(c.stepIndex, 0)
    }

    func testCycleOnEmptyListDoesNothing() {
        let c = make([])
        XCTAssertNil(c.cycle(now: t0))
        XCTAssertEqual(c.tick(readings: cpu(50), now: t0).command, .release)
        XCTAssertEqual(c.letter, "?")
    }

    func testFullBlastRunsAtMaxAndRevertsOnTime() {
        var step = CycleStep(type: .fullBlast)
        step.autoRevertEnabled = true
        step.autoRevertSec = 60
        let c = make([step])
        XCTAssertEqual(c.tick(readings: cpu(40), now: t0).command, .targets([7826, 7826]))
        XCTAssertEqual(c.tick(readings: cpu(40), now: t0.addingTimeInterval(59)).command, .targets([7826, 7826]))
        let r = c.tick(readings: cpu(40), now: t0.addingTimeInterval(60))
        XCTAssertEqual(r.command, .release)
        XCTAssertEqual(r.events, [.autoReverted])
        XCTAssertEqual(c.letter, "A")
        // 之后一直交还系统，也不会重复发事件
        let later = c.tick(readings: cpu(40), now: t0.addingTimeInterval(120))
        XCTAssertEqual(later.command, .release)
        XCTAssertEqual(later.events, [])
    }

    func testFullBlastWithoutAutoRevertNeverReverts() {
        let c = make([CycleStep(type: .fullBlast)])
        XCTAssertEqual(c.tick(readings: cpu(40), now: t0.addingTimeInterval(100_000)).command, .targets([7826, 7826]))
    }

    func testCooldownFinishesWhenAverageDropsBelowTarget() {
        var step = CycleStep(type: .cooldown)
        step.cooldownTargetTemp = 40
        step.cooldownPollSec = 3
        let c = make([step])
        // 还没到第一次检查的时间：即使已经够凉，也先全速
        XCTAssertEqual(c.tick(readings: cpu(35), now: t0.addingTimeInterval(1)).command, .targets([7826, 7826]))
        // 到检查时间但还热：继续全速
        XCTAssertEqual(c.tick(readings: cpu(45), now: t0.addingTimeInterval(3)).command, .targets([7826, 7826]))
        // 下一次检查时降到目标以下：完成
        let r = c.tick(readings: cpu(39.9), now: t0.addingTimeInterval(6))
        XCTAssertEqual(r.command, .release)
        XCTAssertEqual(r.events, [.cooldownDone])
        XCTAssertTrue(c.revertedToAuto)
    }

    func testCycleAfterRevertGoesToNextStep() {
        var blast = CycleStep(type: .fullBlast)
        blast.autoRevertEnabled = true
        blast.autoRevertSec = 1
        let c = make([blast, curveStep([(40, 0)], name: "Turbo")])
        _ = c.tick(readings: cpu(40), now: t0.addingTimeInterval(2))
        XCTAssertTrue(c.revertedToAuto)
        XCTAssertEqual(c.cycle(now: t0.addingTimeInterval(3))?.effectiveName, "Turbo")
        XCTAssertFalse(c.revertedToAuto)
    }

    func testUnreadableSensorsReleaseInCurveMode() {
        let c = make([curveStep([(40, 0), (60, 100)])])
        XCTAssertEqual(c.tick(readings: cpu(50), now: t0).command, .targets([5071.5, 5071.5]))
        XCTAssertEqual(c.tick(readings: [], now: t0).command, .release)
        XCTAssertNil(c.lastTemperature)
    }

    func testHardCeilingForcesFullSpeed() {
        // 曲线画得很低，但温度到 95°C 必须全速
        let c = make([curveStep([(40, 0), (100, 10)])])
        XCTAssertEqual(c.tick(readings: cpu(95), now: t0).command, .targets([7826, 7826]))
    }

    func testTemperatureIsSmoothed() {
        let c = make([curveStep([(40, 0), (60, 100)])])
        c.tuning.rpmDeadband = 0
        _ = c.tick(readings: cpu(40), now: t0)
        // 读数从 40 跳到 60：平滑后是 40 + 0.4 × 20 = 48 → 40%
        _ = c.tick(readings: cpu(60), now: t0)
        XCTAssertEqual(c.lastPercent ?? -1, 40, accuracy: 1e-9)
        XCTAssertEqual(c.lastTemperature, 60)
    }

    func testSmallChangesAreIgnored() {
        let c = make([curveStep([(40, 0), (60, 100)])])
        c.tuning.smoothing = 1
        let first = c.tick(readings: cpu(50), now: t0).command
        // 50.1°C → 50.5% → 只差约 27 转，小于 50 转的门槛，目标不变
        XCTAssertEqual(c.tick(readings: cpu(50.1), now: t0).command, first)
        // 51°C → 55% → 差约 275 转，跟上
        guard case .targets(let moved) = c.tick(readings: cpu(51), now: t0).command else { return XCTFail("应该给出目标转速") }
        XCTAssertEqual(moved.count, 2)
        XCTAssertEqual(moved[0], 5346.95, accuracy: 0.01)
        XCTAssertEqual(moved[1], 5346.95, accuracy: 0.01)
    }

    func testStopRegionReleasesWithHysteresis() {
        let c = make([curveStep([(30, CurvePoint.stopSentinel), (50, 20), (70, 60)])])
        c.tuning.smoothing = 1
        // 没接管过，49°C 在 Stop 段 → 不接管
        XCTAssertEqual(c.tick(readings: cpu(49), now: t0).command, .release)
        // 升到 50°C → 接管，20%
        XCTAssertEqual(c.tick(readings: cpu(50), now: t0).command, .targets([3418.8, 3418.8]))
        // 回落到 49°C：还在边界以下 2°C 以内，继续接管
        guard case .targets = c.tick(readings: cpu(49), now: t0).command else { return XCTFail("应继续接管") }
        // 落到 47.9°C：超过 2°C，交还
        XCTAssertEqual(c.tick(readings: cpu(47.9), now: t0).command, .release)
    }

    func testStepModeJumpsOnAcquireThenRampsBetweenLevels() {
        // 阶梯方式：40°C 以上 0%（最低转速 2317），60°C 以上 100%（7826）
        let c = make([curveStep([(40, 0), (60, 100)])], mode: .step)
        c.tuning.smoothing = 1
        // 刚接管：直接到这一级，不过渡
        XCTAssertEqual(c.tick(readings: cpu(50), now: t0).command, .targets([2317, 2317]))
        // 温度超过 60°C：这一刻开始过渡，先还在原来的转速
        XCTAssertEqual(c.tick(readings: cpu(61), now: t0.addingTimeInterval(2)).command, .targets([2317, 2317]))
        // 过渡总共 10 秒，过了 5 秒走到一半：2317 + 0.5 × 5509 = 5071.5
        XCTAssertEqual(c.tick(readings: cpu(61), now: t0.addingTimeInterval(7)).command, .targets([5071.5, 5071.5]))
        // 10 秒后到位，之后保持
        XCTAssertEqual(c.tick(readings: cpu(61), now: t0.addingTimeInterval(12)).command, .targets([7826, 7826]))
        XCTAssertEqual(c.tick(readings: cpu(70), now: t0.addingTimeInterval(60)).command, .targets([7826, 7826]))
        XCTAssertEqual(c.lastPercent, 100)
    }

    func testStepModeRampRestartsFromCurrentSpeedWhenLevelChangesMidway() {
        let c = make([curveStep([(40, 0), (60, 100)])], mode: .step)
        c.tuning.smoothing = 1
        _ = c.tick(readings: cpu(50), now: t0)
        _ = c.tick(readings: cpu(61), now: t0.addingTimeInterval(2))
        _ = c.tick(readings: cpu(61), now: t0.addingTimeInterval(7))   // 走到一半：5071.5
        // 温度又掉回 60°C 以下：从 5071.5 往回过渡，这一刻还在 5071.5
        XCTAssertEqual(c.tick(readings: cpu(55), now: t0.addingTimeInterval(8)).command, .targets([5071.5, 5071.5]))
        // 再过 5 秒，回到一半：5071.5 − 0.5 × (5071.5 − 2317) = 3694.25
        XCTAssertEqual(c.tick(readings: cpu(55), now: t0.addingTimeInterval(13)).command, .targets([3694.25, 3694.25]))
    }

    func testSwitchingStepsDoesNotRamp() {
        let c = make([curveStep([(40, 0)], name: "Low"), curveStep([(40, 100)], name: "High")], mode: .step)
        XCTAssertEqual(c.tick(readings: cpu(50), now: t0).command, .targets([2317, 2317]))
        c.cycle(now: t0.addingTimeInterval(1))
        // 换档是用户主动操作，直接到新档位的转速
        XCTAssertEqual(c.tick(readings: cpu(50), now: t0.addingTimeInterval(1)).command, .targets([7826, 7826]))
    }

    func testSetConfigKeepsCurrentStepByID() {
        let a = CycleStep(type: .auto, name: "Silence")
        let b = curveStep([(40, 0)], name: "Performance")
        let c = make([a, b], index: 1)
        var cfg = c.config
        cfg.cycleSteps = [b, a]  // 调换顺序
        c.setConfig(cfg, now: t0)
        XCTAssertEqual(c.currentStep?.id, b.id)
        XCTAssertEqual(c.stepIndex, 0)
        // 当前档位被删掉 → 回到第一档
        cfg.cycleSteps = [a]
        c.setConfig(cfg, now: t0)
        XCTAssertEqual(c.currentStep?.id, a.id)
    }
}
