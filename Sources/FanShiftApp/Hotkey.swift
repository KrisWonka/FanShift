import AppKit
import Carbon.HIToolbox

/// 全局快捷键。用系统自带的 Carbon 热键接口，不需要辅助功能权限。
final class HotkeyManager {
    static let shared = HotkeyManager()

    /// 快捷键按下时调用（主线程）
    var onPress: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerInstalled = false

    private init() {}

    private func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { HotkeyManager.shared.onPress?() }
            return noErr
        }, 1, &spec, nil, nil)
    }

    /// 注册快捷键，返回是否成功。会先取消之前注册的那个。
    @discardableResult
    func register(keyCode: Int, modifiers: UInt32) -> Bool {
        unregister()
        installHandlerIfNeeded()
        let id = EventHotKeyID(signature: OSType(0x464E_5348), id: 1)  // 'FNSH'
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(keyCode), modifiers, id, GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else { return false }
        hotKeyRef = ref
        return true
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
    }
}
