import AppKit
import Combine
import FanShiftCore

/// 菜单栏项：显示「档位字母 温度 转速」，左键切下一档，右键出菜单。
final class StatusItemController: NSObject, NSMenuDelegate {
    private let item: NSStatusItem
    private let model: AppModel
    private let openSettings: () -> Void
    private var cancellables = Set<AnyCancellable>()

    init(model: AppModel, openSettings: @escaping () -> Void) {
        self.model = model
        self.openSettings = openSettings
        // 位置要在创建菜单栏项之前预置好：系统只在创建的那一刻读它
        Self.seedPositionIfNeeded()
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        if let button = item.button {
            button.target = self
            button.action = #selector(clicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        }
        Publishers.CombineLatest3(model.$snapshot, model.$config, model.$helperState)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] snapshot, config, helper in self?.render(snapshot, config, helper) }
            .store(in: &cancellables)
    }

    /// 系统记菜单栏项位置用的键。没有另起名字的菜单栏项，系统按创建顺序叫 Item-0、Item-1…，我们只有一个。
    private static let positionKey = "NSStatusItem Preferred Position Item-0"

    /// 系统把新出现的菜单栏项放在最左边，图标多的话第一次运行就正好落在刘海底下，看不见也拖不动。
    /// 所以还没有记忆位置时先预置一个：TG Pro 的图标原来在哪就放哪，没有就放在离屏幕右边 300 点的地方。
    /// 这个值是离屏幕右边缘的距离，用户拖动之后系统会覆盖它。
    private static func seedPositionIfNeeded() {
        let key = positionKey
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: key) == nil else { return }
        let tgPro = UserDefaults(suiteName: "com.tunabellysoftware.tgpro")?
            .double(forKey: "NSStatusItem Preferred Position Item-0") ?? 0
        defaults.set(tgPro > 0 ? tgPro : 300, forKey: key)
    }

    static func title(_ s: Snapshot, _ config: AppConfig, _ helper: HelperState) -> String {
        var parts: [String] = []
        // 当前档位想控制风扇，但后台程序不可用：加个警告标记
        let wantsControl = s.percent != nil
        if wantsControl, !helper.isReady, helper != .unknown { parts.append("⚠︎") }
        parts.append(s.letter)
        if config.menuBarShowTemp, let t = s.temperature { parts.append("\(Int(t.rounded()))°") }
        if config.menuBarShowRPM, let rpm = s.averageRPM { parts.append("\(Int(rpm.rounded()))") }
        return parts.joined(separator: " ")
    }

    /// 有刘海的屏幕上，右边图标太多时菜单栏项会被排到刘海底下：它还在，但看不见也点不到。
    /// 系统不会报告这种遮挡，只能拿菜单栏项的位置和「刘海右侧可用区域」比。
    private func isObstructedByNotch() -> Bool {
        guard let window = item.button?.window, let screen = window.screen,
              let rightOfNotch = screen.auxiliaryTopRightArea else { return false }
        return window.frame.minX < rightOfNotch.minX - 1
    }

    private func diagnostics() -> String {
        guard let button = item.button, let window = button.window else { return "没有窗口" }
        let f = window.frame
        let screen = window.screen
        let notchRight = screen?.auxiliaryTopRightArea.map { String(Int($0.minX)) } ?? "无"
        let saved = UserDefaults.standard.object(forKey: Self.positionKey)
        return "x \(Int(f.minX))–\(Int(f.maxX))，y \(Int(f.minY))，屏幕「\(screen?.localizedName ?? "无")」宽 \(Int(screen?.frame.width ?? 0))，"
            + "刘海右侧从 x \(notchRight) 起，系统报告\(window.occlusionState.contains(.visible) ? "可见" : "不可见")，"
            + "记忆位置 \(saved.map { "\($0)" } ?? "无")，窗口类型 \(type(of: window))"
    }

    private func render(_ s: Snapshot, _ config: AppConfig, _ helper: HelperState) {
        // 标题变了宽度会变，等布局完成再量位置
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self else { return }
            let obstructed = self.isObstructedByNotch()
            if self.model.menuBarObstructed != obstructed { self.model.menuBarObstructed = obstructed }
            let diagnostics = self.diagnostics()
            if self.model.menuBarDiagnostics != diagnostics { self.model.menuBarDiagnostics = diagnostics }
        }
        item.button?.title = Self.title(s, config, helper)
        let hotkey = config.hotkeyEnabled ? "（同 \(KeyCodes.display(mods: config.hotkeyMods, key: config.hotkeyKey))）" : ""
        item.button?.toolTip = "\(s.stepName)。点击切下一档\(hotkey)，右键打开菜单"
    }

    @objc private func clicked(_ sender: Any?) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showMenu()
        } else {
            model.cycle()
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        menu.delegate = self
        let s = model.snapshot

        var header = s.stepName
        if let t = s.temperature { header += " · \(Int(t.rounded()))°C" }
        if let rpm = s.averageRPM { header += " · \(Int(rpm.rounded())) RPM" }
        let headerItem = NSMenuItem(title: header, action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        menu.addItem(headerItem)
        if !model.helperState.isReady, model.helperState != .unknown {
            let warn = NSMenuItem(title: "后台程序：\(model.helperState.summary)", action: nil, keyEquivalent: "")
            warn.isEnabled = false
            menu.addItem(warn)
        }
        menu.addItem(.separator())

        for (i, step) in model.config.cycleSteps.enumerated() {
            let mi = NSMenuItem(title: step.effectiveName, action: #selector(selectStep(_:)), keyEquivalent: "")
            mi.target = self
            mi.tag = i
            mi.state = (i == s.stepIndex && !s.revertedToAuto) ? .on : .off
            menu.addItem(mi)
        }
        menu.addItem(.separator())

        let settings = NSMenuItem(title: "设置…", action: #selector(settingsClicked), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        let quit = NSMenuItem(title: "退出 \(FanShiftInfo.appName)", action: #selector(quitClicked), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        // 临时挂上菜单再触发一次点击，菜单关闭后摘掉，这样左键仍然是「切下一档」
        item.menu = menu
        item.button?.performClick(nil)
    }

    func menuDidClose(_ menu: NSMenu) {
        item.menu = nil
    }

    @objc private func selectStep(_ sender: NSMenuItem) {
        model.select(index: sender.tag)
    }

    @objc private func settingsClicked() {
        openSettings()
    }

    @objc private func quitClicked() {
        NSApp.terminate(nil)
    }
}
