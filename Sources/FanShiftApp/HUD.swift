import AppKit

/// 屏幕中央的提示框：黑底白字圆角，显示一会儿自动淡出。连续触发时只留最新的一个。
final class HUD {
    static let shared = HUD()

    private var panel: NSPanel?
    private var box: NSView?
    private var label: NSTextField?
    private var generation = 0

    private init() {}

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.level = .statusBar
        p.ignoresMouseEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        p.isReleasedWhenClosed = false

        let box = NSView()
        box.wantsLayer = true
        box.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.75).cgColor
        box.layer?.borderColor = NSColor.white.cgColor
        box.layer?.borderWidth = 2

        let label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: 27)
        label.textColor = .white
        label.alignment = .center
        box.addSubview(label)

        p.contentView = box
        self.box = box
        self.label = label
        panel = p
        return p
    }

    func show(_ text: String, duration: TimeInterval) {
        let panel = ensurePanel()
        guard let box, let label, let screen = NSScreen.main ?? NSScreen.screens.first else { return }

        label.stringValue = text
        label.sizeToFit()
        let padX: CGFloat = 30, padY: CGFloat = 18
        let size = NSSize(width: label.frame.width + padX * 2, height: label.frame.height + padY * 2)
        let origin = NSPoint(x: screen.frame.midX - size.width / 2, y: screen.frame.midY - size.height / 2)
        panel.setFrame(NSRect(origin: origin, size: size), display: false)
        box.frame = NSRect(origin: .zero, size: size)
        box.layer?.cornerRadius = min(27, size.height / 2)
        label.frame.origin = NSPoint(x: padX, y: padY)

        generation += 1
        let mine = generation
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        HUD.debugLog("show #\(mine) \"\(text)\" 屏幕 \(screen.frame) 窗口 \(panel.frame) 共 \(NSScreen.screens.count) 块屏")

        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            guard let self, self.generation == mine else { return }
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.15
                panel.animator().alphaValue = 0
            }
        }
        // 收起窗口不依赖淡出动画的完成回调：显示器休眠或锁屏时动画不会执行，回调也就不会来
        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.25) { [weak self] in
            HUD.debugLog("hide 定时器 #\(mine) 触发，当前 #\(self?.generation ?? -1)")
            guard let self, self.generation == mine else { return }
            panel.orderOut(nil)
            HUD.debugLog("orderOut 之后 isVisible=\(panel.isVisible)")
        }
    }

    /// 立刻收起（要弹别的窗口时用，免得挡住）
    func hide() {
        generation += 1
        panel?.orderOut(nil)
    }

    static func debugLog(_ line: String) {
        guard ProcessInfo.processInfo.environment["FANSHIFT_DEBUG"] == "1" else { return }
        FileHandle.standardError.write(Data("[hud \(Date().timeIntervalSince1970.truncatingRemainder(dividingBy: 1000))] \(line)\n".utf8))
    }

    /// 当前是否正显示着（测试用）
    var isVisible: Bool { panel?.isVisible ?? false }

    /// 提示框的内容视图（测试时用来渲染成图片）
    var contentViewForSnapshot: NSView? { box }
}
