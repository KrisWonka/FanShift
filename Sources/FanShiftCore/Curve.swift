import Foundation

public enum CurveOutput: Equatable {
    case stop             // 这个温度不接管，交还系统
    case percent(Double)  // 0–100，按风扇转速范围折算
}

/// 按温度在曲线上取值。
///
/// 阶梯（.step）：
/// - 温度超过某个点，就用那个点的值，直到超过下一个点；
/// - 没超过任何点 = 没有规则 = 交还系统。
///
/// 连直线（.linear）：
/// - 相邻两点之间按比例过渡；
/// - 低于第一个点按第一个点算，高于最后一个点按最后一个点算；
/// - Stop 点管到下一个点为止；普通点后面跟 Stop 点时保持普通点的值，不往 Stop 方向过渡。
///
/// 两种方式下，Stop 点（percent < 0）都表示交还系统；没有点 = 交还系统。
public func evaluateCurve(_ points: [CurvePoint], at temperature: Double, mode: CurveMode) -> CurveOutput {
    let sorted = points.sorted { $0.temperatureLimit < $1.temperatureLimit }
    guard let first = sorted.first, let last = sorted.last else { return .stop }

    func value(_ p: CurvePoint) -> CurveOutput {
        p.isStop ? .stop : .percent(Double(min(p.percent, 100)))
    }

    switch mode {
    case .step:
        guard let active = sorted.last(where: { temperature > $0.temperatureLimit }) else { return .stop }
        return value(active)

    case .linear:
        if temperature <= first.temperatureLimit { return value(first) }
        if temperature >= last.temperatureLimit { return value(last) }
        for (a, b) in zip(sorted, sorted.dropFirst()) where temperature < b.temperatureLimit {
            if a.isStop { return .stop }
            if b.isStop { return value(a) }
            let span = b.temperatureLimit - a.temperatureLimit
            guard span > 0 else { return value(b) }
            let f = (temperature - a.temperatureLimit) / span
            return .percent(Double(a.percent) + f * Double(b.percent - a.percent))
        }
        return value(last)
    }
}
