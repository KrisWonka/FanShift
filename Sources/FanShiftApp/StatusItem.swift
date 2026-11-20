import AppKit
import Combine
import FanShiftCore

/// 菜单栏：一项读数（档位字母 + 温度 + 转速），字母也可以分出去单独一项。
/// 带字母的那一项左键切下一档、右键出菜单；字母分出去之后，读数那一项点了就出菜单。
///
/// 两项都是用到才创建、不用就移除，不靠「隐藏」：隐藏或移除一项时，系统会把它记住的位置删掉，
/// 再出现就被排到最左边（图标多的机器上正好落在刘海底下）。所以位置由我们自己另存一份，每次创建前写回去。
final class StatusItemController: NSObject, NSMenuDelegate {
    private enum Role: String {
        case readout, letter
        var displayName: String { rawValue }

        /// 给系统认的名字。系统按「程序名 + 这个名字」记每个菜单栏项的位置，而且它自己那份记录优先于我们预置的值。
        /// 不用系统默认的 Item-0、Item-1：那两个名字下的记录一旦坏了（图标怎么预置都被藏起来），没有办法清掉，
        /// 只能换名字。以后再遇到同样的情况，把这里的后缀改一下就行。
        var autosaveName: String { self == .readout ? "FanShiftReadout-1" : "FanShiftLetter-1" }
    }

    private var readout: NSStatusItem?
    private var letter: NSStatusItem?
    private let model: AppModel
    private let openSettings: () -> Void
    private var cancellables = Set<AnyCancellable>()

    init(model: AppModel, openSettings: @escaping () -> Void) {
        self.model = model
        self.openSettings = openSettings
        super.init()
        Publishers.CombineLatest3(model.$snapshot, model.$config, model.$helperState)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] snapshot, config, helper in self?.render(snapshot, config, helper) }
            .store(in: &cancellables)
    }

    // MARK: 位置

    /// 系统记菜单栏项位置用的键。值越大越靠左；只在创建那一刻读，之后用户按住 ⌘ 拖动时系统会改写它。
    private static func systemPositionKey(_ autosaveName: String) -> String {
        "NSStatusItem Preferred Position \(autosaveName)"
    }

    /// 我们自己另存的那一份
    private static func savedPositionKey(_ role: Role) -> String {
        "MenuBarPosition.\(role.rawValue)"
    }

    private func item(_ role: Role) -> NSStatusItem? {
        role == .readout ? readout : letter
    }

    /// 这一项该放在哪。存过就用存的；没存过：读数沿用系统里已有的位置，再不行放在 TG Pro 图标原来的位置；
    /// 字母紧挨在读数左边。
    private func position(for role: Role) -> Double {
        let defaults = UserDefaults.standard
        if let saved = defaults.object(forKey: Self.savedPositionKey(role)) as? Double { return saved }
        let value: Double
        switch role {
        case .readout:
            let existing = defaults.double(forKey: Self.systemPositionKey("Item-0"))
            let tgPro = UserDefaults(suiteName: "com.tunabellysoftware.tgpro")?
                .double(forKey: Self.systemPositionKey("Item-0")) ?? 0
            value = existing > 0 ? existing : (tgPro > 0 ? tgPro : 300)
        case .letter:
            value = position(for: .readout) + 1
        }
        defaults.set(value, forKey: Self.savedPositionKey(role))
        return value
    }

    /// 把系统里现在的位置（用户可能拖动过）抄进我们自己那一份
    private func rememberPositions() {
        let defaults = UserDefaults.standard
        for role in [Role.readout, .letter] {
            guard item(role) != nil,
                  let current = defaults.object(forKey: Self.systemPositionKey(role.autosaveName)) as? Double else { continue }
            if defaults.object(forKey: Self.savedPositionKey(role)) as? Double != current {
                defaults.set(current, forKey: Self.savedPositionKey(role))
            }
        }
    }

    private func create(_ role: Role) -> NSStatusItem {
        // 位置要在创建之前写好：系统只在创建的那一刻读它
        UserDefaults.standard.set(position(for: role), forKey: Self.systemPositionKey(role.autosaveName))
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = role.autosaveName
        if let button = item.button {
            button.target = self
            button.action = #selector(clicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.font = Self.titleFont
        }
        return item
    }

    private func remove(_ role: Role) {
        guard let existing = item(role) else { return }
        // 移除时系统会删掉它的位置，先抄一份
        rememberPositions()
        NSStatusBar.system.removeStatusItem(existing)
        if role == .readout { readout = nil } else { letter = nil }
    }

    /// 这一项现在是不是看不见：菜单栏放不下时，系统会把排在最左边的项藏起来（有刘海的屏幕上是藏到刘海底下）。
    /// 系统不会主动通知，只能自己查。
    private func isHiddenBySystem(_ item: NSStatusItem?) -> Bool {
        guard let window = item?.button?.window else { return false }
        if let rightOfNotch = window.screen?.auxiliaryTopRightArea, window.frame.minX < rightOfNotch.minX - 1 { return true }
        return !window.occlusionState.contains(.visible)
    }

    /// 排查用的技术信息（Status 页底部和调试日志里显示），不翻译
    private func diagnostics() -> String {
        func describe(_ role: Role) -> String {
            guard let item = item(role) else { return "\(role.displayName): none" }
            guard let window = item.button?.window else { return "\(role.displayName): no window" }
            let f = window.frame
            let system = UserDefaults.standard.object(forKey: Self.systemPositionKey(role.autosaveName)).map { "\($0)" } ?? "none"
            let saved = UserDefaults.standard.object(forKey: Self.savedPositionKey(role)).map { "\($0)" } ?? "none"
            return "\(role.displayName): x \(Int(f.minX))–\(Int(f.maxX)), \(window.occlusionState.contains(.visible) ? "visible" : "hidden"), "
                + "position \(system), saved \(saved)"
        }
        let screen = readout?.button?.window?.screen ?? letter?.button?.window?.screen ?? NSScreen.main
        let notchRight = screen?.auxiliaryTopRightArea.map { String(Int($0.minX)) } ?? "none"
        return [
            describe(.readout),
            describe(.letter),
            "screen width \(Int(screen?.frame.width ?? 0)), right of notch from x \(notchRight)",
        ].joined(separator: "; ")
    }

    // MARK: 显示

    private static let titleFont = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
    /// 两行叠起来时用的小字
    private static let stackedFont = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium)
    private static let stackedLineHeight: CGFloat = 10.5

    static func layout(_ s: Snapshot, _ config: AppConfig, _ helper: HelperState) -> MenuBarLayout {
        // 当前档位想控制风扇，但后台程序不可用：加个警告标记
        let wantsControl = s.percent != nil
        let warning = wantsControl && !helper.isReady && helper != .unknown
        let second = config.menuBarSecondSensor.flatMap { SensorMath.value($0, from: s.readings) }
        return MenuBar.layout(
            letter: s.letter,
            warning: warning,
            temperature: s.temperature,
            secondTemperature: second,
            rpm: s.averageRPM,
            config: config
        )
    }

    /// 菜单栏内容的文字版（调试和截图时用）
    static func debugText(_ layout: MenuBarLayout) -> String {
        let lines = layout.lines.map { $0.map(\.text).joined(separator: " ") }.joined(separator: " / ")
        return "letter item: \(layout.letterItem ?? "none") | readout item: \([layout.leading, lines.isEmpty ? nil : lines].compactMap { $0 }.joined(separator: " "))"
    }

    private static func isDark(_ view: NSView?) -> Bool {
        let match = (view?.effectiveAppearance ?? NSApp.effectiveAppearance)
            .bestMatch(from: [.aqua, .darkAqua, .vibrantLight, .vibrantDark])
        return match == .darkAqua || match == .vibrantDark
    }

    private static func color(_ heat: HeatLevel, dark: Bool) -> NSColor {
        switch heat {
        case .normal: return dark ? .white : .black
        case .warm: return .systemOrange
        case .hot: return .systemRed
        }
    }

    private static func attributed(_ segments: [MenuBarSegment], font: NSFont, dark: Bool) -> NSAttributedString {
        let out = NSMutableAttributedString()
        for (i, segment) in segments.enumerated() {
            if i > 0 { out.append(NSAttributedString(string: " ", attributes: [.font: font])) }
            out.append(NSAttributedString(string: segment.text, attributes: [
                .font: font,
                .foregroundColor: color(segment.heat, dark: dark),
            ]))
        }
        return out
    }

    /// 两行小字画成一张图。没有变色的字时做成模板图，深浅由系统跟着菜单栏自动处理。
    static func stackedImage(_ lines: [[MenuBarSegment]], dark: Bool) -> NSImage {
        let colored = lines.joined().contains { $0.heat != .normal }
        // 模板图只看透明度，统一用黑色画
        let strings = lines.map { attributed($0, font: stackedFont, dark: colored ? dark : false) }
        let width = ceil(strings.map { $0.size().width }.max() ?? 0) + 2
        let lineHeight = stackedLineHeight
        let image = NSImage(size: NSSize(width: width, height: 22), flipped: false) { rect in
            // 几行作为一个整体垂直居中，每行水平居中
            let total = lineHeight * CGFloat(strings.count)
            var top = (rect.height + total) / 2
            for string in strings {
                let size = string.size()
                string.draw(at: NSPoint(x: (rect.width - size.width) / 2, y: top - lineHeight + (lineHeight - size.height) / 2))
                top -= lineHeight
            }
            return true
        }
        image.isTemplate = !colored
        return image
    }

    private func render(_ s: Snapshot, _ config: AppConfig, _ helper: HelperState) {
        let layout = Self.layout(s, config, helper)
        // 每次重画都按当前语言重新生成（改语言会改配置，配置一变这里就会重画）
        let hotkey = config.hotkeyEnabled ? KeyCodes.display(mods: config.hotkeyMods, key: config.hotkeyKey) : nil
        let cycleTip = L.tipCycle(s.stepName, hotkey: hotkey).s

        // 读数那一项（先创建它，字母排在它后面创建）
        if layout.readoutHidden {
            remove(.readout)
        } else {
            if readout == nil { readout = create(.readout) }
            if let button = readout?.button {
                let dark = Self.isDark(button)
                if layout.stacked {
                    let image = Self.stackedImage(layout.lines, dark: dark)
                    button.title = layout.leading ?? ""
                    button.image = image
                    button.imagePosition = layout.leading == nil ? .imageOnly : .imageTrailing
                } else {
                    button.image = nil
                    button.imagePosition = .noImage
                    let segments = layout.lines.first ?? []
                    if segments.contains(where: { $0.heat != .normal }) {
                        // 有变色的字：整行都要自己指定颜色
                        let title = NSMutableAttributedString()
                        if let leading = layout.leading {
                            title.append(Self.attributed([MenuBarSegment(leading)], font: Self.titleFont, dark: dark))
                            title.append(NSAttributedString(string: " ", attributes: [.font: Self.titleFont]))
                        }
                        title.append(Self.attributed(segments, font: Self.titleFont, dark: dark))
                        button.attributedTitle = title
                    } else {
                        // 没有变色的字：用普通标题，深浅由系统处理
                        button.title = ([layout.leading].compactMap { $0 } + segments.map(\.text)).joined(separator: " ")
                    }
                }
                button.toolTip = layout.leading == nil ? L.tipMenu(s.stepName).s : cycleTip
            }
        }

        // 字母那一项
        if let text = layout.letterItem {
            if letter == nil { letter = create(.letter) }
            letter?.button?.title = text
            letter?.button?.toolTip = cycleTip
        } else {
            remove(.letter)
        }

        // 内容变了宽度会变，等布局完成再量位置
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self else { return }
            self.rememberPositions()
            let hidden = self.isHiddenBySystem(self.readout) || self.isHiddenBySystem(self.letter)
            if self.model.menuBarObstructed != hidden { self.model.menuBarObstructed = hidden }
            let diagnostics = self.diagnostics()
            if self.model.menuBarDiagnostics != diagnostics {
                self.model.menuBarDiagnostics = diagnostics
                HUD.debugLog("menu bar \(diagnostics)")
            }
        }
    }

    /// 调试用：把菜单栏项现在的样子存成图片（深色底和浅色底各一张），再存一张变色时的样例
    func writeDebugSnapshots(to dir: URL) {
        func save(_ image: NSImage, _ name: String) {
            guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return }
            try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent(name))
        }
        func onBackdrop(dark: Bool, size: NSSize, draw: @escaping (NSRect) -> Void) -> NSImage {
            NSImage(size: size, flipped: false) { rect in
                (dark ? NSColor(white: 0.15, alpha: 1) : NSColor(white: 0.9, alpha: 1)).setFill()
                rect.fill()
                draw(rect)
                return true
            }
        }
        // 现在真实的两项
        for (name, item) in [("readout", readout), ("letter", letter)] {
            guard let button = item?.button, let rep = button.bitmapImageRepForCachingDisplay(in: button.bounds) else { continue }
            button.cacheDisplay(in: button.bounds, to: rep)
            let dark = Self.isDark(button)
            save(onBackdrop(dark: dark, size: button.bounds.size) { rect in rep.draw(in: rect) }, "menubar-\(name).png")
        }
        // 样例：两行、带橙色和红色
        let sample: [[MenuBarSegment]] = [
            [MenuBarSegment("7826 RPM")],
            [MenuBarSegment("96°C", heat: .hot), MenuBarSegment("86°C", heat: .warm), MenuBarSegment("52°C")],
        ]
        for dark in [true, false] {
            let image = Self.stackedImage(sample, dark: dark)
            save(onBackdrop(dark: dark, size: NSSize(width: image.size.width + 16, height: 24)) { rect in
                image.draw(in: NSRect(x: 8, y: 1, width: image.size.width, height: image.size.height))
            }, "menubar-sample-\(dark ? "dark" : "light").png")
        }
    }

    // MARK: 点击和菜单

    @objc private func clicked(_ sender: NSStatusBarButton) {
        let onLetter = letter != nil && sender === letter?.button
        guard let item = onLetter ? letter : readout else { return }
        let event = NSApp.currentEvent
        let secondary = event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true
        // 字母分出去之后，读数那一项不管左键右键都出菜单
        let carriesLetter = onLetter || letter == nil
        if secondary || !carriesLetter {
            showMenu(on: item)
        } else {
            model.cycle()
        }
    }

    private func showMenu(on item: NSStatusItem) {
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
            let warn = NSMenuItem(title: L.helperInMenu(model.helperState.summary).s, action: nil, keyEquivalent: "")
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

        let settings = NSMenuItem(title: L.settingsMenu.s, action: #selector(settingsClicked), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        let quit = NSMenuItem(title: L.quit(FanShiftInfo.appName).s, action: #selector(quitClicked), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        // 临时挂上菜单再触发一次点击，菜单关闭后摘掉，这样左键仍然归我们自己处理
        item.menu = menu
        item.button?.performClick(nil)
    }

    func menuDidClose(_ menu: NSMenu) {
        readout?.menu = nil
        letter?.menu = nil
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
