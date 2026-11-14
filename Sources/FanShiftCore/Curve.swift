import Foundation

public enum CurveOutput: Equatable {
    case stop             // 这个温度不接管，交还系统
    case percent(Double)  // 0–100，按风扇转速范围折算
}

/// 按温度在曲线上取值。规则和编辑器里画的折线一致：
/// - 相邻两点之间连直线；
/// - 低于第一个点按第一个点算，高于最后一个点按最后一个点算；
/// - Stop 点（percent < 0）管到下一个点为止：这一段整段交还系统；
/// - 普通点后面跟 Stop 点时，这一段保持普通点的值，不往 Stop 方向插值；
/// - 没有点 = 没有规则 = 交还系统。
public func evaluateCurve(_ points: [CurvePoint], at temperature: Double) -> CurveOutput {
    let sorted = points.sorted { $0.temperatureLimit < $1.temperatureLimit }
    guard let first = sorted.first, let last = sorted.last else { return .stop }

    func value(_ p: CurvePoint) -> CurveOutput {
        p.isStop ? .stop : .percent(Double(min(p.percent, 100)))
    }

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
