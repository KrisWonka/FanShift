import FanShiftCore
import SwiftUI

struct ContentView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        TabView(selection: $model.selectedTab) {
            SettingsView()
                .tabItem { Label(L.tabSettings.s, systemImage: "slider.horizontal.3") }
                .tag(0)
            SensorsView()
                .tabItem { Label(L.tabSensors.s, systemImage: "thermometer.medium") }
                .tag(1)
            StatusView()
                .tabItem { Label(L.tabStatus.s, systemImage: "fan") }
                .tag(2)
            AboutView()
                .tabItem { Label(L.tabAbout.s, systemImage: "info.circle") }
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
        // 原名和界面上显示的（翻译过的）名字，哪个对得上都算
        let filtered = filter.isEmpty ? all : all.filter {
            $0.name.localizedCaseInsensitiveContains(filter)
                || L.sensorName($0.name).localizedCaseInsensitiveContains(filter)
        }
        guard sortByValue else { return filtered.sorted { L.sensorName($0.name) < L.sensorName($1.name) } }
        // 校准读数不是真实温度，按温度排序时放到最后
        return filtered.sorted { a, b in
            let ca = SensorMath.isCalibration(a.name), cb = SensorMath.isCalibration(b.name)
            return ca == cb ? a.value > b.value : !ca
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L.sensorsTitle.s)
                .font(.title2).bold()
            HStack {
                TextField(L.filterPlaceholder.s, text: $filter)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 280)
                Toggle(L.sortByTemp.s, isOn: $sortByValue)
                Spacer()
                Text(L.sensorCount(model.snapshot.readings.count).s)
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
            Text(L.sensorsHelp.s)
                .font(.caption2).foregroundColor(.secondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func row(_ r: SensorReading) -> some View {
        let calibration = SensorMath.isCalibration(r.name)
        return HStack(spacing: 8) {
            Text(L.sensorName(r.name))
                .font(.system(.body, design: .monospaced))
                .frame(width: 200, alignment: .leading)
            Text(calibration ? L.kindCalibration.s : (SensorMath.isCore(r.name) ? L.kindCore.s : (SensorMath.isDie(r.name) ? L.kindDie.s : "")))
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
                Text(L.statusTitle.s).font(.title2).bold()

                statusRow(
                    label: L.helperRow.s,
                    ok: model.helperState.isReady,
                    detail: model.dryRun ? L.dryRun.s : model.helperState.summary
                )
                HStack {
                    Button(model.helperState == .notInstalled ? L.installHelper.s : L.reinstallHelper.s) {
                        switch model.installHelperResult() {
                        case nil: message = L.installed.s
                        case .cancelled?: message = L.cancelled.s  // 在密码框点了取消，不算失败
                        case .failed(let reason)?: message = L.installFailedMessage(reason).s
                        }
                    }
                    Button(L.uninstallHelper.s) {
                        message = model.uninstallHelper().map { L.uninstallFailedMessage($0).s } ?? L.uninstalled.s
                    }
                    .disabled(model.helperState == .notInstalled)
                    if let message {
                        Text(message).font(.caption).foregroundColor(.secondary)
                    }
                }
                .disabled(model.dryRun)
                .padding(.leading, 34)

                statusRow(
                    label: L.currentProfile(s.stepName).s,
                    ok: true,
                    detail: stepDetail(s)
                )

                ForEach(s.fans, id: \.index) { fan in
                    statusRow(
                        label: L.fanRow(fan.index + 1, Int(fan.actual.rounded())).s,
                        ok: true,
                        detail: L.fanDetail(
                            target: Int(fan.target.rounded()),
                            min: Int(fan.minRPM),
                            max: Int(fan.maxRPM),
                            mode: modeText(fan.mode)
                        ).s
                    )
                }
                if s.fans.isEmpty {
                    statusRow(label: L.fans.s, ok: false, detail: L.noFanInfo.s)
                }

                if model.menuBarObstructed {
                    statusRow(
                        label: L.hiddenTitle(FanShiftInfo.appName).s,
                        ok: false,
                        detail: L.hiddenDetail.s
                    )
                }
                if s.otherController {
                    statusRow(
                        label: L.otherControllerTitle.s,
                        ok: false,
                        detail: L.otherControllerDetail(FanShiftInfo.appName).s
                    )
                }
                if let error = model.lastError {
                    statusRow(label: L.lastError.s, ok: false, detail: error)
                }

                Divider()
                Text(L.configFile(AppPaths.config.path).s)
                    .font(.caption).foregroundColor(.secondary).textSelection(.enabled)
                if !model.menuBarDiagnostics.isEmpty {
                    Text(L.menuBarItems(model.menuBarDiagnostics).s)
                        .font(.caption).foregroundColor(.secondary).textSelection(.enabled)
                }
                if model.configSource == .migratedFromLegacy {
                    Text(L.migrated.s)
                        .font(.caption).foregroundColor(.secondary)
                }
            }
            .padding(40)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private func stepDetail(_ s: Snapshot) -> String {
        let temp = s.temperature.map { L.following(String(format: "%.1f", $0)).s } ?? L.noTemp.s
        if let p = s.percent {
            return "\(temp) · \(L.targetPercent(Int(p.rounded())).s)" + (s.controlling ? "" : L.notApplied.s)
        }
        return "\(temp) · \(L.fansReleased.s)"
    }

    private func modeText(_ mode: Int) -> String {
        switch mode {
        case FanMode.forced: return L.modeForced.s
        case FanMode.auto, FanMode.system: return L.modeSystem.s
        default: return L.modeOther(mode).s
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
    // 不直接用 model，但要观察它：切换语言时这一页才会跟着刷新
    @EnvironmentObject var model: AppModel

    private var version: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? L.devBuild.s
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 128, height: 128)
            Text(FanShiftInfo.appName)
                .font(.largeTitle).bold()
            Text(L.version(version).s)
                .font(.caption).foregroundColor(.secondary)
            Text(L.tagline.s)
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
