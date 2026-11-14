import FanShiftCore
import SwiftUI

/// 可拖拽的风扇曲线：横轴 20–90°C（5°C 一格），纵轴 0–100%（5% 一格），底部是 Stop 档。
/// 拖点调整，自动吸附到格子上；右键删除。连线的画法跟随「曲线取值方式」：阶梯或直线。
/// 0% = 风扇最低转速；Stop = 这一段不接管，交还系统（风扇可以停转）。
struct FanCurveEditor: View {
    @Binding var curve: [CurvePoint]
    var mode: CurveMode
    /// 当前温度和算出的百分比，画一个小标记；nil 就不画
    var live: (temperature: Double, percent: Double?)?

    private let tempLow: Double = 20
    private let tempHigh: Double = 90
    private let tempStep: Double = 5
    private let percentLow: Double = 0
    private let percentHigh: Double = 100
    private let percentStep: Double = 5
    /// Stop 档画在 0% 下面一格
    private let stopBand = Double(CurvePoint.stopSentinel)

    private let leftPad: CGFloat = 38
    private let rightPad: CGFloat = 12
    private let topPad: CGFloat = 12
    private let bottomPad: CGFloat = 28

    var body: some View {
        GeometryReader { geo in
            let plot = CGRect(
                x: leftPad,
                y: topPad,
                width: max(0, geo.size.width - leftPad - rightPad),
                height: max(0, geo.size.height - topPad - bottomPad)
            )
            ZStack {
                Rectangle()
                    .fill(Color.gray.opacity(0.06))
                    .frame(width: plot.width, height: plot.height)
                    .position(x: plot.midX, y: plot.midY)
                gridLines(in: plot)
                axisLabels(in: plot)
                curveLine(in: plot)
                liveMarker(in: plot)
                pointHandles(in: plot)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .frame(height: 260)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private func gridLines(in plot: CGRect) -> some View {
        Path { path in
            for t in stride(from: tempLow, through: tempHigh, by: tempStep) {
                path.move(to: CGPoint(x: xPos(t, in: plot), y: plot.minY))
                path.addLine(to: CGPoint(x: xPos(t, in: plot), y: plot.maxY))
            }
            for p in stride(from: percentLow, through: percentHigh, by: percentStep) {
                path.move(to: CGPoint(x: plot.minX, y: yPos(p, in: plot)))
                path.addLine(to: CGPoint(x: plot.maxX, y: yPos(p, in: plot)))
            }
        }
        .stroke(Color.gray.opacity(0.15), lineWidth: 0.5)
        Path { path in
            for t in stride(from: tempLow, through: tempHigh, by: 10) {
                path.move(to: CGPoint(x: xPos(t, in: plot), y: plot.minY))
                path.addLine(to: CGPoint(x: xPos(t, in: plot), y: plot.maxY))
            }
            for p in [0.0, 25, 50, 75, 100] {
                path.move(to: CGPoint(x: plot.minX, y: yPos(p, in: plot)))
                path.addLine(to: CGPoint(x: plot.maxX, y: yPos(p, in: plot)))
            }
        }
        .stroke(Color.gray.opacity(0.35), lineWidth: 0.6)
    }

    @ViewBuilder
    private func axisLabels(in plot: CGRect) -> some View {
        ForEach(Array(stride(from: tempLow, through: tempHigh, by: tempStep)), id: \.self) { t in
            Text("\(Int(t))")
                .font(.system(size: 9))
                .foregroundColor(.secondary)
                .position(x: xPos(t, in: plot), y: plot.maxY + 10)
        }
        ForEach([0, 25, 50, 75, 100], id: \.self) { p in
            Text("\(p)%")
                .font(.caption2)
                .foregroundColor(.secondary)
                .position(x: leftPad - 18, y: yPos(Double(p), in: plot))
        }
        Text("Stop")
            .font(.caption2.bold())
            .foregroundColor(.orange)
            .position(x: leftPad - 18, y: yPos(stopBand, in: plot))
        Path { path in
            path.move(to: CGPoint(x: plot.minX, y: yPos(0, in: plot)))
            path.addLine(to: CGPoint(x: plot.maxX, y: yPos(0, in: plot)))
        }
        .stroke(Color.orange.opacity(0.4), lineWidth: 1)
    }

    private func curveLine(in plot: CGRect) -> some View {
        let points = curve.sorted { $0.temperatureLimit < $1.temperatureLimit }
        return Path { path in
            guard let first = points.first, let last = points.last else { return }
            func at(_ p: CurvePoint) -> CGPoint {
                CGPoint(x: xPos(p.temperatureLimit, in: plot), y: yPos(Double(p.percent), in: plot))
            }
            switch mode {
            case .linear:
                // 第一个点以左、最后一个点以右都按端点的值水平延伸
                path.move(to: CGPoint(x: plot.minX, y: at(first).y))
                path.addLine(to: at(first))
                for p in points.dropFirst() { path.addLine(to: at(p)) }
                path.addLine(to: CGPoint(x: plot.maxX, y: at(last).y))
            case .step:
                // 第一个点以左没有规则（交还系统），画在 Stop 档上；之后每个点的值保持到下一个点
                let stopY = yPos(stopBand, in: plot)
                path.move(to: CGPoint(x: plot.minX, y: stopY))
                path.addLine(to: CGPoint(x: at(first).x, y: stopY))
                path.addLine(to: at(first))
                for (a, b) in zip(points, points.dropFirst()) {
                    path.addLine(to: CGPoint(x: at(b).x, y: at(a).y))
                    path.addLine(to: at(b))
                }
                path.addLine(to: CGPoint(x: plot.maxX, y: at(last).y))
            }
        }
        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, lineJoin: .round))
    }

    @ViewBuilder
    private func liveMarker(in plot: CGRect) -> some View {
        if let live, live.temperature >= tempLow, live.temperature <= tempHigh {
            let x = xPos(live.temperature, in: plot)
            Path { path in
                path.move(to: CGPoint(x: x, y: plot.minY))
                path.addLine(to: CGPoint(x: x, y: plot.maxY))
            }
            .stroke(Color.primary.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            Circle()
                .stroke(Color.primary, lineWidth: 2)
                .frame(width: 9, height: 9)
                .position(x: x, y: yPos(live.percent ?? stopBand, in: plot))
        }
    }

    @ViewBuilder
    private func pointHandles(in plot: CGRect) -> some View {
        ForEach(curve.indices, id: \.self) { i in
            let cp = curve[i]
            let pos = CGPoint(x: xPos(cp.temperatureLimit, in: plot), y: yPos(Double(cp.percent), in: plot))
            Circle()
                .fill(cp.isStop ? Color.orange : Color.accentColor)
                .frame(width: 14, height: 14)
                .overlay(Circle().stroke(Color.white, lineWidth: 2))
                .position(pos)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { v in
                            curve[i].temperatureLimit = snapTemp(temp(at: v.location.x, in: plot))
                            curve[i].percent = Int(snapPercent(percent(at: v.location.y, in: plot)))
                        }
                        .onEnded { _ in
                            curve.sort { $0.temperatureLimit < $1.temperatureLimit }
                        }
                )
                .contextMenu {
                    Button(role: .destructive) {
                        if curve.count > 1 { curve.remove(at: i) }
                    } label: {
                        Label("删除这个点", systemImage: "trash")
                    }
                }
                .overlay(
                    Text(cp.isStop ? "\(Int(cp.temperatureLimit))° Stop" : "\(Int(cp.temperatureLimit))° \(cp.percent)%")
                        .font(.caption2.monospaced())
                        .foregroundColor(cp.isStop ? .orange : .primary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 3))
                        .offset(x: 0, y: -18)
                        .position(pos)
                        .allowsHitTesting(false)
                )
        }
    }

    // MARK: 坐标换算

    private func xPos(_ t: Double, in plot: CGRect) -> CGFloat {
        let f = (t - tempLow) / (tempHigh - tempLow)
        return plot.minX + plot.width * CGFloat(min(max(f, 0), 1))
    }

    private func yPos(_ p: Double, in plot: CGRect) -> CGFloat {
        let clamped = max(stopBand, min(percentHigh, p))
        let f = (clamped - stopBand) / (percentHigh - stopBand)
        return plot.maxY - plot.height * CGFloat(f)
    }

    private func temp(at x: CGFloat, in plot: CGRect) -> Double {
        tempLow + Double((x - plot.minX) / max(plot.width, 1)) * (tempHigh - tempLow)
    }

    private func percent(at y: CGFloat, in plot: CGRect) -> Double {
        stopBand + Double((plot.maxY - y) / max(plot.height, 1)) * (percentHigh - stopBand)
    }

    private func snapTemp(_ t: Double) -> Double {
        min(tempHigh, max(tempLow, (t / tempStep).rounded() * tempStep))
    }

    /// 拖到 0% 以下任意位置都吸到 Stop 档
    private func snapPercent(_ p: Double) -> Double {
        if p < 0 { return stopBand }
        return min(percentHigh, max(percentLow, (p / percentStep).rounded() * percentStep))
    }
}
