import FanShiftCore
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    /// 正在编辑、还没保存的配置
    @State private var draft = AppConfig()
    @State private var loaded = false
    @State private var saveStatus: SaveStatus = .idle
    @State private var expandedStepIDs: Set<UUID> = []
    @State private var autostart = Autostart.isEnabled

    enum SaveStatus: Equatable { case idle, saved, error(String) }

    private var dirty: Bool { draft != model.config }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("开机自启") {
                    Toggle("登录时自动启动 \(FanShiftInfo.appName)", isOn: Binding(
                        get: { autostart },
                        set: { v in autostart = v; Autostart.setEnabled(v) }
                    ))
                }

                Section("快捷键") {
                    Toggle("启用全局快捷键", isOn: $draft.hotkeyEnabled)
                    HStack {
                        Text("组合键")
                        HotkeyRecorder(mods: $draft.hotkeyMods, key: $draft.hotkeyKey, keyCode: $draft.hotkeyKeyCode)
                    }
                    .disabled(!draft.hotkeyEnabled)
                    Text("点上方按钮 → 按一下组合键即可绑定（ESC 取消）。修饰键 ⌃⌥⇧⌘ 至少要有一个。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section("循环档位（按 \(KeyCodes.display(mods: draft.hotkeyMods, key: draft.hotkeyKey)) 在档位间循环）") {
                    cycleStepsList
                    addStepMenu
                    Text("点档位左侧 ▶ 三角展开改名 / 调参数。Cooldown 档：全速直到 CPU 平均温度降到目标值后自动交还系统。Full Blast 档：可设 N 分钟后自动交还系统。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section("曲线") {
                    Picker("两个点之间怎么取值", selection: $draft.curveMode) {
                        ForEach(CurveMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    Text("阶梯：温度超过某个点就用那个点的转速，换转速时用大约 10 秒缓缓过渡。连直线：两个点之间按比例变化。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    HStack {
                        Text("最热核心的温度修正")
                        Slider(value: $draft.hotCoreOffset, in: -5...5, step: 0.5)
                        Text(String(format: "%+.1f °C", draft.hotCoreOffset))
                            .frame(width: 70, alignment: .trailing)
                            .font(.system(.body, design: .monospaced))
                    }
                    Text("参考温度选「最热的 CPU 核心」时，先在读数上加这个值再去查曲线。实测 TG Pro 的读数比最热核心低约 2°C，默认 −2 才和原来的曲线手感一致；0 就是原始读数。菜单栏显示的始终是原始读数。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section("菜单栏") {
                    Toggle("显示温度", isOn: $draft.menuBarShowTemp)
                    Toggle("显示转速", isOn: $draft.menuBarShowRPM)
                    Text("菜单栏放不下、图标被刘海挡住时，可以关掉这两项，只留档位字母。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section("提示") {
                    Toggle("启用屏幕中央提示", isOn: $draft.alertEnabled)
                    HStack {
                        Text("Cooldown 结束文字")
                            .frame(width: 130, alignment: .leading)
                        TextField("Cooldown done ✓", text: $draft.alertCooldownDone)
                            .textFieldStyle(.roundedBorder)
                    }
                    .disabled(!draft.alertEnabled)
                    HStack {
                        Text("显示时长")
                            .frame(width: 130, alignment: .leading)
                        Slider(value: $draft.alertDuration, in: 0.3...3.0, step: 0.1)
                        Text("\(String(format: "%.1f", draft.alertDuration)) 秒")
                            .frame(width: 60, alignment: .trailing)
                            .font(.system(.body, design: .monospaced))
                    }
                    .disabled(!draft.alertEnabled)
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                statusBadge
                Spacer()
                if dirty {
                    Text("有未保存的修改")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Button("放弃修改") { draft = model.config }
                }
                Button("保存并生效") { save() }
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(!dirty)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
        .onAppear {
            if !loaded {
                draft = model.config
                loaded = true
            }
        }
    }

    // MARK: 档位列表

    @ViewBuilder
    private var cycleStepsList: some View {
        if draft.cycleSteps.isEmpty {
            Text("（空 — 至少加一档才能使用快捷键）")
                .font(.caption)
                .foregroundColor(.secondary)
        } else {
            VStack(spacing: 6) {
                ForEach(draft.cycleSteps.indices, id: \.self) { idx in
                    cycleStepCard(idx: idx)
                }
            }
        }
    }

    private func cycleStepCard(idx: Int) -> some View {
        let step = draft.cycleSteps[idx]
        let isExpanded = Binding<Bool>(
            get: { expandedStepIDs.contains(step.id) },
            set: { v in
                if v { expandedStepIDs.insert(step.id) } else { expandedStepIDs.remove(step.id) }
            }
        )
        return DisclosureGroup(isExpanded: isExpanded) {
            stepDetails(step: $draft.cycleSteps[idx])
                .padding(.top, 8)
                .padding(.horizontal, 4)
                .padding(.bottom, 4)
        } label: {
            HStack(spacing: 8) {
                Text("\(idx + 1).")
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 22, alignment: .trailing)
                Image(systemName: step.type.icon)
                    .frame(width: 22)
                    .foregroundColor(.accentColor)
                Text(step.effectiveName)
                if !step.name.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text("(\(step.type.displayName))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                rowButtons(idx: idx)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.08)))
    }

    private func rowButtons(idx: Int) -> some View {
        HStack(spacing: 4) {
            Button {
                draft.cycleSteps.swapAt(idx, idx - 1)
            } label: { Image(systemName: "arrow.up") }
                .buttonStyle(.borderless)
                .disabled(idx == 0)
                .help("上移")

            Button {
                draft.cycleSteps.swapAt(idx, idx + 1)
            } label: { Image(systemName: "arrow.down") }
                .buttonStyle(.borderless)
                .disabled(idx == draft.cycleSteps.count - 1)
                .help("下移")

            Button {
                let removed = draft.cycleSteps.remove(at: idx)
                expandedStepIDs.remove(removed.id)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundColor(.orange)
            }
            .buttonStyle(.borderless)
            .help("删除")
        }
    }

    @ViewBuilder
    private func stepDetails(step: Binding<CycleStep>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("名字")
                    .frame(width: 80, alignment: .leading)
                TextField(step.wrappedValue.type.displayName, text: step.name)
                    .textFieldStyle(.roundedBorder)
            }

            switch step.wrappedValue.type {
            case .auto:
                Text("Auto 档不接管风扇，完全交给系统自己控制（空闲时风扇可以停转）")
                    .font(.caption)
                    .foregroundColor(.secondary)
            case .fullBlast:
                Toggle("到点自动交还系统", isOn: step.autoRevertEnabled)
                HStack {
                    Text("倒计时")
                        .frame(width: 80, alignment: .leading)
                    Slider(
                        value: Binding(
                            get: { Double(step.wrappedValue.autoRevertSec) / 60.0 },
                            set: { step.wrappedValue.autoRevertSec = Int($0 * 60) }
                        ),
                        in: 1...60, step: 1
                    )
                    Text("\(step.wrappedValue.autoRevertSec / 60) 分钟")
                        .frame(width: 60, alignment: .trailing)
                        .font(.system(.body, design: .monospaced))
                }
                .disabled(!step.wrappedValue.autoRevertEnabled)
            case .cooldown:
                HStack {
                    Text("目标温度")
                        .frame(width: 80, alignment: .leading)
                    Slider(value: step.cooldownTargetTemp, in: 30...70, step: 1)
                    Text("\(Int(step.wrappedValue.cooldownTargetTemp)) °C")
                        .frame(width: 60, alignment: .trailing)
                        .font(.system(.body, design: .monospaced))
                }
                HStack {
                    Text("检查间隔")
                        .frame(width: 80, alignment: .leading)
                    Slider(value: step.cooldownPollSec, in: 1...30, step: 1)
                    Text("\(Int(step.wrappedValue.cooldownPollSec)) 秒")
                        .frame(width: 60, alignment: .trailing)
                        .font(.system(.body, design: .monospaced))
                }
            case .temperature:
                sensorPicker(step: step)
                temperatureCurveEditor(step: step)
            }
        }
    }

    @ViewBuilder
    private func sensorPicker(step: Binding<CycleStep>) -> some View {
        let current = step.wrappedValue.sensor
        let names = model.snapshot.readings.map(\.name).filter { !SensorMath.isCalibration($0) }
        HStack {
            Text("参考温度")
                .frame(width: 80, alignment: .leading)
            Picker("", selection: step.sensor) {
                Text("最热的 CPU 核心（推荐，等同 TG Pro 的 Highest CPU）").tag(SensorSelection.cpuMax)
                Text("芯片各温度点的平均").tag(SensorSelection.cpuAvg)
                Text("所有传感器里最热的（含硬盘、电池）").tag(SensorSelection.anyMax)
                Divider()
                if case .named(let n) = current, !names.contains(n) {
                    Text("\(n)（现在读不到）").tag(current)
                }
                ForEach(names, id: \.self) { n in
                    Text(n).tag(SensorSelection.named(n))
                }
            }
            .labelsHidden()
            .frame(maxWidth: 380)
            Spacer()
        }
    }

    @ViewBuilder
    private func temperatureCurveEditor(step: Binding<CycleStep>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("曲线（拖拽调点；右键删除）")
                    .font(.subheadline).bold()
                Spacer()
                Button {
                    let last = step.wrappedValue.curve.max { $0.temperatureLimit < $1.temperatureLimit }
                    let newT = min(90.0, (last?.temperatureLimit ?? 40) + 10)
                    let newP = min(100, max(0, last?.percent ?? 30) + 15)
                    var arr = step.wrappedValue.curve
                    arr.append(CurvePoint(temperatureLimit: newT, percent: newP))
                    arr.sort { $0.temperatureLimit < $1.temperatureLimit }
                    step.wrappedValue.curve = arr
                } label: { Image(systemName: "plus.circle") }
                    .buttonStyle(.borderless)
                    .help("加一个点")
                Menu("载入预设") {
                    ForEach(CurveTemplate.allCases) { tmpl in
                        Button(tmpl.displayName) { step.wrappedValue.curve = tmpl.points }
                    }
                }
                .frame(maxWidth: 100)
            }
            FanCurveEditor(curve: step.curve, mode: draft.curveMode, live: liveMarker(for: step.wrappedValue))
                .background(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.3), lineWidth: 1))
            Text("""
                X 轴 20–90°C（5°C 一格） · Y 轴 0–100%（5% 一格）+ 底部 Stop 档（橙色）。
                百分比按风扇转速范围折算（0% = 最低转速，100% = 最高转速）。
                把点拖到 Stop 区表示这一段不接管，交还系统（风扇可以停转）。空心圆圈是当前温度在这条曲线上的位置。
                """)
                .font(.caption2)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// 当前温度落在这条（正在编辑的）曲线上的位置
    private func liveMarker(for step: CycleStep) -> (temperature: Double, percent: Double?)? {
        guard let raw = SensorMath.value(step.sensor, from: model.snapshot.readings) else { return nil }
        let t = raw + (step.sensor == .cpuMax ? draft.hotCoreOffset : 0)
        if case .percent(let p) = evaluateCurve(step.curve, at: t, mode: draft.curveMode) { return (t, p) }
        return (t, nil)
    }

    private var addStepMenu: some View {
        HStack {
            Menu {
                ForEach(CycleStepType.allCases) { t in
                    Button {
                        let new = CycleStep(type: t)
                        draft.cycleSteps.append(new)
                        expandedStepIDs.insert(new.id)
                    } label: {
                        Label(t.displayName, systemImage: t.icon)
                    }
                }
            } label: {
                Label("添加档位", systemImage: "plus")
            }
            .frame(maxWidth: 140)
            Spacer()
            Text("用 ↑↓ 调整顺序")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch saveStatus {
        case .idle:
            EmptyView()
        case .saved:
            Label("已保存并生效", systemImage: "checkmark.circle.fill").foregroundColor(.blue)
        case .error(let msg):
            Label(msg, systemImage: "exclamationmark.triangle.fill").foregroundColor(.orange)
        }
    }

    private func save() {
        do {
            try model.apply(draft)
            saveStatus = .saved
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                if saveStatus == .saved { saveStatus = .idle }
            }
        } catch {
            saveStatus = .error(error.localizedDescription)
        }
    }
}
