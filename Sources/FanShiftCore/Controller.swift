import Foundation

/// 每次计算得出的结论：要么交还系统，要么给每个风扇一个目标转速
public enum FanCommand: Equatable {
    case release
    case targets([Double])
}

public enum ControllerEvent: Equatable {
    case cooldownDone   // Cooldown 降到目标温度，已交还系统
    case autoReverted   // Full Blast 到点，已交还系统
}

/// 档位状态机 + 按曲线算转速。纯逻辑：温度读数和当前时间都由外面传进来，不碰硬件。
/// 不是线程安全的，调用方要保证在同一个队列上用。
public final class FanController {
    public struct Tuning {
        /// 每次计算时，平滑温度向新读数靠拢的比例（2 秒算一次时，大约 4 秒跟上）
        public var smoothing = 0.4
        /// 原始温度到这个值就直接全速，不管曲线怎么画
        public var hardCeiling = 95.0
        /// 已经接管时，温度要比 Stop 边界再低这么多才交还，避免在边界上来回切
        public var stopHysteresis = 2.0
        /// 连直线方式下：目标转速变化小于这个值就不动，避免风扇一直微调
        public var rpmDeadband = 50.0
        /// 阶梯方式下：换到另一级转速时用这么多秒匀速过渡（TG Pro 实测约 10 秒）
        public var rampSeconds = 10.0

        public init() {}
    }

    public var tuning = Tuning()
    public private(set) var config: AppConfig
    public private(set) var fans: [FanInfo]
    public private(set) var stepIndex: Int
    /// Full Blast 到点或 Cooldown 完成后为 true：档位没变，但实际已交还系统
    public private(set) var revertedToAuto: Bool
    /// 当前档位参考的温度（原始读数），读不到时为 nil
    public private(set) var lastTemperature: Double?
    /// 最近一次算出的百分比；交还系统时为 nil
    public private(set) var lastPercent: Double?

    private var stepStartedAt: Date
    private var lastCooldownCheck: Date
    private var smoothed: Double?
    private var holding = false
    private var lastTargets: [Double]?
    private var rampFrom: [Double]?
    private var rampTo: [Double]?
    private var rampStart = Date.distantPast

    public init(config: AppConfig, fans: [FanInfo], stepIndex: Int = 0, revertedToAuto: Bool = false, now: Date = Date()) {
        self.config = config
        self.fans = fans
        self.stepIndex = config.cycleSteps.indices.contains(stepIndex) ? stepIndex : 0
        self.revertedToAuto = revertedToAuto
        stepStartedAt = now
        lastCooldownCheck = now
    }

    public var currentStep: CycleStep? {
        config.cycleSteps.indices.contains(stepIndex) ? config.cycleSteps[stepIndex] : nil
    }

    /// 菜单栏上显示的字母：档位名的第一个字；已交还系统时显示 A
    public var letter: String {
        guard let step = currentStep else { return "?" }
        if revertedToAuto { return "A" }
        return String(step.effectiveName.prefix(1)).uppercased()
    }

    public var displayName: String {
        guard let step = currentStep else { return "—" }
        return revertedToAuto ? CycleStepType.auto.displayName : step.effectiveName
    }

    /// 换配置。当前档位还在就留在当前档位，不在了回到第一档。
    public func setConfig(_ newConfig: AppConfig, now: Date) {
        let currentID = currentStep?.id
        config = newConfig
        if let id = currentID, let idx = newConfig.cycleSteps.firstIndex(where: { $0.id == id }) {
            stepIndex = idx
            lastTargets = nil
        } else {
            enter(0, now: now)
        }
    }

    /// 切到下一档（到头回到第一档）。列表为空时返回 nil。
    @discardableResult
    public func cycle(now: Date) -> CycleStep? {
        let count = config.cycleSteps.count
        guard count > 0 else { return nil }
        return select((stepIndex + 1) % count, now: now)
    }

    @discardableResult
    public func select(_ index: Int, now: Date) -> CycleStep? {
        guard config.cycleSteps.indices.contains(index) else { return nil }
        enter(index, now: now)
        return config.cycleSteps[index]
    }

    private func enter(_ index: Int, now: Date) {
        stepIndex = index
        revertedToAuto = false
        stepStartedAt = now
        lastCooldownCheck = now
        smoothed = nil
        holding = false
        lastTargets = nil
        lastPercent = nil
        rampFrom = nil
        rampTo = nil
    }

    /// 算一次。readings 是这一刻所有温度传感器的读数。
    public func tick(readings: [SensorReading], now: Date) -> (command: FanCommand, events: [ControllerEvent]) {
        var events: [ControllerEvent] = []
        let command = compute(readings: readings, now: now, events: &events)
        if command == .release {
            holding = false
            lastTargets = nil
            lastPercent = nil
            rampFrom = nil
            rampTo = nil
        }
        return (command, events)
    }

    private func compute(readings: [SensorReading], now: Date, events: inout [ControllerEvent]) -> FanCommand {
        guard let step = currentStep, !revertedToAuto, step.type != .auto else {
            lastTemperature = SensorMath.value(.cpuMax, from: readings)
            return .release
        }

        switch step.type {
        case .auto:
            return .release

        case .fullBlast:
            lastTemperature = SensorMath.value(.cpuMax, from: readings)
            if step.autoRevertEnabled, now.timeIntervalSince(stepStartedAt) >= Double(step.autoRevertSec) {
                revertedToAuto = true
                events.append(.autoReverted)
                return .release
            }
            return fullSpeed()

        case .cooldown:
            let average = SensorMath.value(.cpuAvg, from: readings)
            lastTemperature = average
            if now.timeIntervalSince(lastCooldownCheck) >= max(step.cooldownPollSec, 1) {
                lastCooldownCheck = now
                if let average, average < step.cooldownTargetTemp {
                    revertedToAuto = true
                    events.append(.cooldownDone)
                    return .release
                }
            }
            return fullSpeed()

        case .temperature:
            guard let raw = SensorMath.value(step.sensor, from: readings) else {
                // 读不到温度就不接管，让系统自己管
                lastTemperature = nil
                smoothed = nil
                return .release
            }
            lastTemperature = raw
            let s = smoothed.map { $0 + tuning.smoothing * (raw - $0) } ?? raw
            smoothed = s
            if raw >= tuning.hardCeiling {
                holding = true
                return fullSpeed()
            }
            let mode = config.curveMode
            var out = evaluateCurve(step.curve, at: s, mode: mode)
            if out == .stop, holding {
                out = evaluateCurve(step.curve, at: s + tuning.stopHysteresis, mode: mode)
            }
            guard case .percent(let p) = out else { return .release }
            holding = true
            lastPercent = p
            let desired = fans.map { $0.rpm(forPercent: p) }
            var targets = desired
            switch mode {
            case .step:
                targets = ramp(toward: desired, now: now)
            case .linear:
                // 变化太小就保持原目标；到 0% 和 100% 两端不受这个限制，保证能落到最低和最高转速
                if p > 0, p < 100, let last = lastTargets, last.count == desired.count,
                   zip(last, desired).allSatisfy({ abs($0 - $1) < tuning.rpmDeadband }) {
                    targets = last
                }
            }
            lastTargets = targets
            return .targets(targets)
        }
    }

    /// 阶梯方式下换级：从当前转速匀速过渡到新的一级。刚接管时没有「当前转速」，直接到位。
    private func ramp(toward desired: [Double], now: Date) -> [Double] {
        guard let current = lastTargets, current.count == desired.count, tuning.rampSeconds > 0 else {
            rampFrom = nil
            rampTo = desired
            return desired
        }
        if rampTo != desired {
            rampFrom = current
            rampTo = desired
            rampStart = now
        }
        guard let from = rampFrom else { return desired }
        let f = min(1, max(0, now.timeIntervalSince(rampStart) / tuning.rampSeconds))
        return zip(from, desired).map { $0 + ($1 - $0) * f }
    }

    private func fullSpeed() -> FanCommand {
        lastPercent = 100
        let targets = fans.map(\.maxRPM)
        lastTargets = targets
        rampFrom = nil
        rampTo = nil
        return .targets(targets)
    }
}
