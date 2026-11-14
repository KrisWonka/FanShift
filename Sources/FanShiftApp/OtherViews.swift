import FanShiftCore
import SwiftUI

struct ContentView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        TabView(selection: $model.selectedTab) {
            SettingsView()
                .tabItem { Label("Settings", systemImage: "slider.horizontal.3") }
                .tag(0)
            SensorsView()
                .tabItem { Label("Sensors", systemImage: "thermometer.medium") }
                .tag(1)
            StatusView()
                .tabItem { Label("Status", systemImage: "fan") }
                .tag(2)
            AboutView()
                .tabItem { Label("About", systemImage: "info.circle") }
                .tag(3)
        }
        .frame(minWidth: 720, minHeight: 600)
        .padding(.top, 4)
    }
}

/// 温度的冷热用「蓝 → 橙」表示，不用红绿（色弱友好）
func heatColor(_ v: Double) -> Color {
    switch v {
    case ..<40: return Color(red: 0.0, green: 0.45, blue: 0.70)     // 蓝
    case 40..<60: return Color(red: 0.34, green: 0.71, blue: 0.91)  // 天蓝
    case 60..<80: return Color(red: 0.90, green: 0.62, blue: 0.0)   // 橙
    default: return Color(red: 0.84, green: 0.37, blue: 0.0)        // 朱红
    }
}

// MARK: 传感器

struct SensorsView: View {
    @EnvironmentObject var model: AppModel
    @State private var sortByValue = true
    @State private var filter = ""

    private var displayed: [SensorReading] {
        let all = model.snapshot.readings
        let filtered = filter.isEmpty ? all : all.filter { $0.name.localizedCaseInsensitiveContains(filter) }
        guard sortByValue else { return filtered.sorted { $0.name < $1.name } }
        // 校准读数不是真实温度，按温度排序时放到最后
        return filtered.sorted { a, b in
            let ca = SensorMath.isCalibration(a.name), cb = SensorMath.isCalibration(b.name)
            return ca == cb ? a.value > b.value : !ca
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("温度传感器实时监控")
                .font(.title2).bold()
            HStack {
                TextField("过滤名字（如 核心、tdie、NAND）", text: $filter)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 280)
                Toggle("按温度排序", isOn: $sortByValue)
                Spacer()
                Text("共 \(model.snapshot.readings.count) 个，每 2 秒刷新")
                    .font(.caption).foregroundColor(.secondary)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(displayed, id: \.name) { r in
                        row(r)
                    }
                }
                .padding(.vertical, 4)
            }
            .background(Color.gray.opacity(0.06))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Text("「核心」是各 CPU 核心的温度，曲线默认参考其中最热的一个；「芯片」是芯片上的温度点，Cooldown 参考它们的平均。每个档位参考哪个温度，在 Settings → 展开档位 →「参考温度」里选。")
                .font(.caption2).foregroundColor(.secondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func row(_ r: SensorReading) -> some View {
        let calibration = SensorMath.isCalibration(r.name)
        return HStack(spacing: 8) {
            Text(r.name)
                .font(.system(.body, design: .monospaced))
                .frame(width: 200, alignment: .leading)
            Text(calibration ? "校准值" : (SensorMath.isCore(r.name) ? "核心" : (SensorMath.isDie(r.name) ? "芯片" : "")))
                .font(.caption2)
                .foregroundColor(.secondary)
                .frame(width: 44, alignment: .leading)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3).fill(Color.gray.opacity(0.15))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(calibration ? Color.gray : heatColor(r.value))
                        .frame(width: g.size.width * CGFloat(min(max(r.value / 100.0, 0), 1)))
                }
            }
            .frame(height: 8)
            Text(String(format: "%.1f °C", r.value))
                .font(.system(.body, design: .monospaced))
                .foregroundColor(calibration ? .secondary : heatColor(r.value))
                .frame(width: 80, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
    }
}

// MARK: 状态

struct StatusView: View {
    @EnvironmentObject var model: AppModel
    @State private var message: String?

    var body: some View {
        let s = model.snapshot
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("当前状态").font(.title2).bold()

                statusRow(
                    label: "后台程序（负责把转速写进风扇）",
                    ok: model.helperState.isReady,
                    detail: model.dryRun ? "演练模式：只打印指令，不碰风扇" : model.helperState.summary
                )
                HStack {
                    Button(model.helperState == .notInstalled ? "安装后台程序…" : "重新安装后台程序…") {
                        message = model.installHelper().map { "安装没成功：\($0)" } ?? "已安装"
                    }
                    Button("卸载后台程序…") {
                        message = model.uninstallHelper().map { "卸载没成功：\($0)" } ?? "已卸载，风扇完全交给系统"
                    }
                    .disabled(model.helperState == .notInstalled)
                    if let message {
                        Text(message).font(.caption).foregroundColor(.secondary)
                    }
                }
                .disabled(model.dryRun)
                .padding(.leading, 34)

                statusRow(
                    label: "当前档位：\(s.stepName)",
                    ok: true,
                    detail: stepDetail(s)
                )

                ForEach(s.fans, id: \.index) { fan in
                    statusRow(
                        label: "风扇 \(fan.index + 1)：\(Int(fan.actual.rounded())) RPM",
                        ok: true,
                        detail: "目标 \(Int(fan.target.rounded())) · 范围 \(Int(fan.minRPM))–\(Int(fan.maxRPM)) · \(modeText(fan.mode))"
                    )
                }
                if s.fans.isEmpty {
                    statusRow(label: "风扇", ok: false, detail: "读不到风扇信息")
                }

                if model.menuBarObstructed {
                    statusRow(
                        label: "菜单栏项被刘海挡住了",
                        ok: false,
                        detail: "右边的菜单栏图标太多，\(FanShiftInfo.appName) 的那一项被排到了刘海底下。可以在 Settings →「菜单栏」里关掉温度或转速显示，或者减少其他菜单栏图标。快捷键不受影响。"
                    )
                }
                if s.tgProRunning {
                    statusRow(
                        label: "TG Pro 正在运行",
                        ok: false,
                        detail: "两个软件同时控制风扇会互相覆盖。用 \(FanShiftInfo.appName) 控制时请退出 TG Pro。"
                    )
                }
                if let error = model.lastError {
                    statusRow(label: "最近一次出错", ok: false, detail: error)
                }

                Divider()
                Text("配置文件：\(AppPaths.config.path)")
                    .font(.caption).foregroundColor(.secondary).textSelection(.enabled)
                if model.configSource == .migratedFromLegacy {
                    Text("这份配置是第一次启动时从旧版（~/.hammerspoon/tgpro-hotkey-config.json）搬过来的，旧文件没有动。")
                        .font(.caption).foregroundColor(.secondary)
                }
            }
            .padding(40)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private func stepDetail(_ s: Snapshot) -> String {
        let temp = s.temperature.map { String(format: "参考温度 %.1f°C", $0) } ?? "读不到温度"
        if let p = s.percent {
            return "\(temp) · 目标 \(Int(p.rounded()))%" + (s.controlling ? "" : "（没有生效：后台程序不可用）")
        }
        return "\(temp) · 风扇已交还系统"
    }

    private func modeText(_ mode: Int) -> String {
        switch mode {
        case FanMode.forced: return "由软件接管"
        case FanMode.auto, FanMode.system: return "系统控制"
        default: return "模式 \(mode)"
        }
    }

    private func statusRow(label: String, ok: Bool, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // 对勾 / 感叹号形状不同，颜色用蓝 / 橙，不靠红绿区分
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundColor(ok ? .blue : .orange)
                .font(.title3)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.headline)
                Text(detail).font(.caption).foregroundColor(.secondary)
            }
            Spacer()
        }
    }
}

// MARK: 关于

struct AboutView: View {
    private var version: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "开发版"
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 128, height: 128)
            Text(FanShiftInfo.appName)
                .font(.largeTitle).bold()
            Text("版本 \(version)")
                .font(.caption).foregroundColor(.secondary)
            Text("一个快捷键循环切换风扇档位，每个档位一条自己画的温度曲线")
                .foregroundColor(.secondary)
            if let url = URL(string: FanShiftInfo.repoURL) {
                Link(FanShiftInfo.repoURL.replacingOccurrences(of: "https://", with: ""), destination: url)
            }
            Spacer()
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
