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
                Section(L.sectionLanguage.s) {
                    languagePicker
                }

                Section(L.sectionStartup.s) {
                    Toggle(L.launchAtLogin(FanShiftInfo.appName).s, isOn: Binding(
                        get: { autostart },
                        set: { v in autostart = v; Autostart.setEnabled(v) }
                    ))
                }

                Section(L.sectionHotkey.s) {
                    Toggle(L.hotkeyEnabled.s, isOn: $draft.hotkeyEnabled)
                    HStack {
                        Text(L.hotkeyCombo.s)
                        HotkeyRecorder(mods: $draft.hotkeyMods, key: $draft.hotkeyKey, keyCode: $draft.hotkeyKeyCode)
                    }
                    .disabled(!draft.hotkeyEnabled)
                    Text(L.hotkeyHelp.s)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section(L.sectionProfiles(KeyCodes.display(mods: draft.hotkeyMods, key: draft.hotkeyKey)).s) {
                    cycleStepsList
                    addStepMenu
                    Text(L.profilesHelp.s)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section(L.sectionCurves.s) {
                    Picker(L.curveModePicker.s, selection: $draft.curveMode) {
                        ForEach(CurveMode.allCases) { mode in
                            Text(L.curveMode(mode).s).tag(mode)
                        }
                    }
                    Text(L.curveModeHelp.s)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    HStack {
                        Text(L.hotCoreOffset.s)
                        Slider(value: $draft.hotCoreOffset, in: -5...5, step: 0.5)
                        Text(String(format: "%+.1f °C", draft.hotCoreOffset))
                            .frame(width: 70, alignment: .trailing)
                            .font(.system(.body, design: .monospaced))
                    }
                    Text(L.hotCoreOffsetHelp.s)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section(L.sectionMenuBar.s) {
                    Picker(L.menuBarStyle.s, selection: $draft.menuBarStyle) {
                        ForEach(MenuBarStyle.allCases) { style in
                            Text(L.menuBarStyle(style).s).tag(style)
                        }
                    }
                    Toggle(L.separateLetter.s, isOn: $draft.menuBarSeparateLetter)
                    Toggle(L.showTemp.s, isOn: $draft.menuBarShowTemp)
                    Toggle(L.showRPM.s, isOn: $draft.menuBarShowRPM)
                    menuBarSecondSensorPicker
                        .disabled(!draft.menuBarShowTemp)
                    Toggle(
                        L.colorTemps(warm: Int(MenuBar.warmThreshold), hot: Int(MenuBar.hotThreshold)).s,
                        isOn: $draft.menuBarColorTemps
                    )
                    .disabled(!draft.menuBarShowTemp)
                    Text(L.menuBarHelp.s)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section(L.sectionAlert.s) {
                    Toggle(L.alertEnabled.s, isOn: $draft.alertEnabled)
                    HStack {
                        Text(L.cooldownText.s)
                            .frame(minWidth: 130, alignment: .leading)
                            .fixedSize(horizontal: true, vertical: false)
                        // 占位文字用默认的提示文字；标题留空，理由同档位的「名字」输入框
                        TextField("", text: $draft.alertCooldownDone, prompt: Text(AppConfig().alertCooldownDone))
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                    }
                    .disabled(!draft.alertEnabled)
                    HStack {
                        Text(L.alertDuration.s)
                            .frame(minWidth: 130, alignment: .leading)
                            .fixedSize(horizontal: true, vertical: false)
                        Slider(value: $draft.alertDuration, in: 0.3...3.0, step: 0.1)
                        Text(L.seconds(String(format: "%.1f", draft.alertDuration)).s)
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
                    Text(L.unsavedChanges.s)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Button(L.discard.s) { draft = model.config }
                }
                Button(L.saveAndApply.s) { save() }
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
                // 调试时默认把带曲线的档位展开，方便截图检查曲线编辑器
                if ProcessInfo.processInfo.environment["FANSHIFT_DEBUG"] == "1" {
                    expandedStepIDs = Set(draft.cycleSteps.filter { $0.type == .temperature }.map(\.id))
                }
            }
        }
    }

    // MARK: 语言

    /// 改了马上生效，不等「保存并生效」：只把语言这一项写进当前生效的配置，
    /// 同时同步到草稿，这样不会冒出「有未保存的修改」，草稿里别的没保存的改动也还在。
    private var languagePicker: some View {
        Picker(selection: Binding(
            get: { model.config.language },
            set: { lang in
                var c = model.config
                c.language = lang
                do {
                    try model.apply(c)
                    draft.language = lang
                } catch {
                    saveStatus = .error(error.localizedDescription)
                }
            }
        )) {
            ForEach(AppLanguage.allCases) { lang in
                Text(lang.nativeName).tag(lang)
            }
        } label: {
            Label(L.language.s, systemImage: "globe")
        }
    }

    // MARK: 菜单栏

    @ViewBuilder
    private var menuBarSecondSensorPicker: some View {
        let current = draft.menuBarSecondSensor
        let names = model.snapshot.readings.map(\.name).filter { !SensorMath.isCalibration($0) }
        Picker(L.secondTemp.s, selection: $draft.menuBarSecondSensor) {
            Text(L.none.s).tag(SensorSelection?.none)
            Divider()
            Text(L.sensorHottestCore.s).tag(SensorSelection?.some(.cpuMax))
            Text(L.sensorChipAverage.s).tag(SensorSelection?.some(.cpuAvg))
            Text(L.sensorHottestAny.s).tag(SensorSelection?.some(.anyMax))
            Divider()
            if case .named(let n)? = current, !names.contains(n) {
                Text(L.unavailable(L.sensorName(n)).s).tag(current)
            }
            ForEach(names, id: \.self) { n in
                Text(L.sensorName(n)).tag(SensorSelection?.some(.named(n)))
            }
        }
    }

    // MARK: 档位列表

    @ViewBuilder
    private var cycleStepsList: some View {
        if draft.cycleSteps.isEmpty {
            Text(L.noProfiles.s)
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
                .help(L.moveUp.s)

            Button {
                draft.cycleSteps.swapAt(idx, idx + 1)
            } label: { Image(systemName: "arrow.down") }
                .buttonStyle(.borderless)
                .disabled(idx == draft.cycleSteps.count - 1)
                .help(L.moveDown.s)

            Button {
                let removed = draft.cycleSteps.remove(at: idx)
                expandedStepIDs.remove(removed.id)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundColor(.orange)
            }
            .buttonStyle(.borderless)
            .help(L.delete.s)
        }
    }

    @ViewBuilder
    private func stepDetails(step: Binding<CycleStep>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L.name.s)
                    .frame(minWidth: 80, alignment: .leading)
                    .fixedSize(horizontal: true, vertical: false)
                // 标题留空、类型名放进占位文字：不然表单会把标题当成输入框左边的标签再画一遍
                TextField("", text: step.name, prompt: Text(step.wrappedValue.type.displayName))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
            }

            switch step.wrappedValue.type {
            case .auto:
                Text(L.autoHelp.s)
                    .font(.caption)
                    .foregroundColor(.secondary)
            case .fullBlast:
                Toggle(L.autoRevert.s, isOn: step.autoRevertEnabled)
                HStack {
                    Text(L.timer.s)
                        .frame(minWidth: 80, alignment: .leading)
                        .fixedSize(horizontal: true, vertical: false)
                    Slider(
                        value: Binding(
                            get: { Double(step.wrappedValue.autoRevertSec) / 60.0 },
                            set: { step.wrappedValue.autoRevertSec = Int($0 * 60) }
                        ),
                        in: 1...60, step: 1
                    )
                    Text(L.minutes(step.wrappedValue.autoRevertSec / 60).s)
                        .frame(width: 60, alignment: .trailing)
                        .font(.system(.body, design: .monospaced))
                }
                .disabled(!step.wrappedValue.autoRevertEnabled)
            case .cooldown:
                HStack {
                    Text(L.targetTemp.s)
                        .frame(minWidth: 80, alignment: .leading)
                        .fixedSize(horizontal: true, vertical: false)
                    Slider(value: step.cooldownTargetTemp, in: 30...70, step: 1)
                    Text("\(Int(step.wrappedValue.cooldownTargetTemp)) °C")
                        .frame(width: 60, alignment: .trailing)
                        .font(.system(.body, design: .monospaced))
                }
                HStack {
                    Text(L.checkEvery.s)
                        .frame(minWidth: 80, alignment: .leading)
                        .fixedSize(horizontal: true, vertical: false)
                    Slider(value: step.cooldownPollSec, in: 1...30, step: 1)
                    Text(L.seconds("\(Int(step.wrappedValue.cooldownPollSec))").s)
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
            Text(L.follows.s)
                .frame(minWidth: 80, alignment: .leading)
                .fixedSize(horizontal: true, vertical: false)
            Picker("", selection: step.sensor) {
                Text(L.sensorHottestCoreRecommended.s).tag(SensorSelection.cpuMax)
                Text(L.sensorChipAverage.s).tag(SensorSelection.cpuAvg)
                Text(L.sensorHottestAny.s).tag(SensorSelection.anyMax)
                Divider()
                if case .named(let n) = current, !names.contains(n) {
                    Text(L.unavailable(L.sensorName(n)).s).tag(current)
                }
                ForEach(names, id: \.self) { n in
                    Text(L.sensorName(n)).tag(SensorSelection.named(n))
                }
            }
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func temperatureCurveEditor(step: Binding<CycleStep>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(L.curveTitle.s)
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
                    .help(L.addPoint.s)
                Menu(L.loadPreset.s) {
                    ForEach(CurveTemplate.allCases) { tmpl in
                        Button(tmpl.displayName) { step.wrappedValue.curve = tmpl.points }
                    }
                }
                .fixedSize()
            }
            FanCurveEditor(curve: step.curve, mode: draft.curveMode, live: liveMarker(for: step.wrappedValue))
                .background(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.3), lineWidth: 1))
            Text(L.curveHelp.s)
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
                Label(L.addProfile.s, systemImage: "plus")
            }
            .fixedSize()
            Spacer()
            Text(L.reorderHint.s)
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
            Label(L.saved.s, systemImage: "checkmark.circle.fill").foregroundColor(.blue)
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
