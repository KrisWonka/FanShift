// FanShift：菜单栏 App。快捷键切档、按曲线算转速、把目标转速交给 root 后台程序去写。
import AppKit
import FanShiftCore
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let model = AppModel.shared
    private var statusItem: StatusItemController?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMainMenu()
        statusItem = StatusItemController(model: model) { [weak self] in self?.showSettings() }

        model.onAlert = { [weak self] text in
            guard let self, self.model.config.alertEnabled else { return }
            HUD.shared.show(text, duration: self.model.config.alertDuration)
        }
        model.onConfigApplied = { [weak self] in self?.registerHotkey() }
        HotkeyManager.shared.onPress = { [weak self] in self?.model.cycle() }
        registerHotkey()

        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.model.setSuspended(true)
        }
        workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.model.setSuspended(false)
        }

        model.start()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.model.announceCurrent() }
        // 这个弹窗不能从 DispatchQueue.main 的块里弹：弹窗不关，那个块就不结束，主队列被它一直占着，
        // 屏幕提示收不起来、界面也不刷新。Timer 的回调不占主队列，没有这个问题。
        Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in
            self?.offerHelperInstallIfNeeded()
        }
        installDebugHooks()
    }

    // MARK: 开发 / 测试用的钩子（只有设了对应的环境变量才启用）

    private var debugSignal: DispatchSourceSignal?
    private var debugDump: DispatchSourceSignal?
    private var debugToggle: DispatchSourceSignal?

    private func installDebugHooks() {
        let env = ProcessInfo.processInfo.environment
        // FANSHIFT_DEBUG=1：收到 SIGUSR1 就切下一档（相当于按一次快捷键），屏幕锁着也能测
        if env["FANSHIFT_DEBUG"] == "1" {
            signal(SIGUSR1, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
            source.setEventHandler { [weak self] in self?.model.cycle() }
            source.resume()
            debugSignal = source

            // SIGUSR2：把本进程的窗口清单打到 stderr
            signal(SIGUSR2, SIG_IGN)
            let dump = DispatchSource.makeSignalSource(signal: SIGUSR2, queue: .main)
            dump.setEventHandler {
                for w in NSApp.windows {
                    let line = "[win] #\(w.windowNumber) \(type(of: w)) 层级 \(w.level.rawValue) 可见 \(w.isVisible) 位置 \(w.frame)\n"
                    FileHandle.standardError.write(Data(line.utf8))
                }
            }
            dump.resume()
            debugDump = dump

            // SIGHUP：切换「档位字母单独一个图标」并立即生效（测菜单栏项的创建 / 移除，不用点设置窗口）
            signal(SIGHUP, SIG_IGN)
            let toggle = DispatchSource.makeSignalSource(signal: SIGHUP, queue: .main)
            toggle.setEventHandler { [weak self] in
                guard let self else { return }
                var config = self.model.config
                config.menuBarSeparateLetter.toggle()
                try? self.model.apply(config)
            }
            toggle.resume()
            debugToggle = toggle
        }
        // FANSHIFT_SNAPSHOT_DIR=<目录>：启动几秒后把设置窗口的每一页、屏幕提示渲染成 PNG 存进去
        if let dir = env["FANSHIFT_SNAPSHOT_DIR"], !dir.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { self.writeSnapshots(to: URL(fileURLWithPath: dir)) }
        }
    }

    private func snapshot(_ view: NSView, to url: URL) {
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        // 视图本身不画窗口底色，这里补上，不然深色模式下白字落在透明底上看不见
        let image = NSImage(size: view.bounds.size)
        image.lockFocus()
        let dark = view.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        (dark ? NSColor(white: 0.12, alpha: 1) : NSColor(white: 0.93, alpha: 1)).setFill()
        NSRect(origin: .zero, size: view.bounds.size).fill()
        rep.draw(in: NSRect(origin: .zero, size: view.bounds.size))
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation, let out = NSBitmapImageRep(data: tiff) else { return }
        try? out.representation(using: .png, properties: [:])?.write(to: url)
    }

    private func writeSnapshots(to dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        showSettings()
        let names = ["settings", "sensors", "status", "about"]
        func step(_ i: Int) {
            guard i < names.count else {
                HUD.shared.show("Performance", duration: 1)
                if let hud = HUD.shared.contentViewForSnapshot { self.snapshot(hud, to: dir.appendingPathComponent("hud.png")) }
                let layout = StatusItemController.layout(self.model.snapshot, self.model.config, self.model.helperState)
                let text = StatusItemController.debugText(layout) + "\n" + self.model.menuBarDiagnostics
                try? Data("\(text)\n".utf8).write(to: dir.appendingPathComponent("menubar-title.txt"))
                self.statusItem?.writeDebugSnapshots(to: dir)
                try? Data("done\n".utf8).write(to: dir.appendingPathComponent("done.txt"))
                return
            }
            self.model.selectedTab = i
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                if let view = self.settingsWindow?.contentView {
                    self.snapshot(view, to: dir.appendingPathComponent("\(names[i]).png"))
                }
                step(i + 1)
            }
        }
        step(0)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.shutdown()
    }

    private func registerHotkey() {
        let config = model.config
        guard config.hotkeyEnabled, !config.hotkeyMods.isEmpty, let code = config.resolvedHotkeyKeyCode else {
            HotkeyManager.shared.unregister()
            return
        }
        if !HotkeyManager.shared.register(keyCode: code, modifiers: KeyCodes.carbonModifiers(config.hotkeyMods)) {
            HUD.shared.show("快捷键注册失败", duration: 2)
        }
    }

    /// 后台程序没装或版本不对时，问一次要不要现在装
    private func offerHelperInstallIfNeeded() {
        guard !model.dryRun else { return }
        switch model.helperState {
        case .notInstalled, .outdated:
            break
        default:
            return
        }
        // 启动时的档位提示也在屏幕正中，会盖住弹窗的按钮，先收掉
        HUD.shared.hide()
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "安装控制风扇用的后台程序"
        alert.informativeText = "\(FanShiftInfo.appName) 要靠一个以 root 身份运行的小程序来调风扇转速，装的时候需要输一次密码。不装的话只能显示温度和转速，不能控制风扇。"
        alert.addButton(withTitle: "现在安装")
        alert.addButton(withTitle: "以后再说")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        if let error = model.installHelper(), error != "已取消" {
            let failed = NSAlert()
            failed.messageText = "安装失败"
            failed.informativeText = error
            failed.runModal()
        }
    }

    // MARK: 设置窗口

    func showSettings() {
        if settingsWindow == nil {
            let hosting = NSHostingController(rootView: ContentView().environmentObject(model))
            let window = NSWindow(contentViewController: hosting)
            window.title = FanShiftInfo.appName
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 760, height: 680))
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    /// 没有 Dock 图标的 App 也需要主菜单，否则输入框里 ⌘C / ⌘V / ⌘Q 不起作用
    private func buildMainMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "退出 \(FanShiftInfo.appName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "编辑")
        edit.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "窗口")
        windowMenu.addItem(withTitle: "关闭", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowItem.submenu = windowMenu
        main.addItem(windowItem)

        NSApp.mainMenu = main
    }
}

// 已经有一个在运行就把它叫到前面，自己退出（没打包、直接跑二进制时没有 bundle id，跳过这个检查）
if let bundleID = Bundle.main.bundleIdentifier {
    let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
    if let other = others.first {
        other.activate()
        exit(0)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
