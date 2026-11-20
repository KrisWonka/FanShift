import AppKit
import Carbon.HIToolbox
import FanShiftCore
import SwiftUI

/// 点一下进入录制，再按一次组合键就绑定（Esc 取消）。同时记下按键码，注册快捷键时直接用。
struct HotkeyRecorder: View {
    @Binding var mods: [String]
    @Binding var key: String
    @Binding var keyCode: Int?
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 4) {
                if recording {
                    Text(L.hotkeyRecording.s)
                        .foregroundColor(.secondary)
                        .italic()
                } else {
                    Text(key.isEmpty ? L.notSet.s : KeyCodes.display(mods: mods, key: key))
                        .font(.system(.body, design: .monospaced))
                }
                Spacer()
                Image(systemName: recording ? "circle.fill" : "pencil")
                    .foregroundColor(recording ? .orange : .secondary)
                    .font(.caption)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(recording ? Color.accentColor : Color.gray.opacity(0.4), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onDisappear { stopRecording() }
    }

    private func toggle() {
        if recording { stopRecording() } else { startRecording() }
    }

    private func startRecording() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            handle(event)
            return nil
        }
    }

    private func stopRecording() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private func handle(_ event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) { return stopRecording() }

        var newMods: [String] = []
        let flags = event.modifierFlags
        if flags.contains(.control) { newMods.append("ctrl") }
        if flags.contains(.option) { newMods.append("alt") }
        if flags.contains(.shift) { newMods.append("shift") }
        if flags.contains(.command) { newMods.append("cmd") }
        guard !newMods.isEmpty, let name = keyName(for: event) else { return }

        mods = newMods
        key = name
        keyCode = Int(event.keyCode)
        stopRecording()
    }

    private func keyName(for event: NSEvent) -> String? {
        let special: [Int: String] = [
            kVK_F1: "f1", kVK_F2: "f2", kVK_F3: "f3", kVK_F4: "f4", kVK_F5: "f5", kVK_F6: "f6",
            kVK_F7: "f7", kVK_F8: "f8", kVK_F9: "f9", kVK_F10: "f10", kVK_F11: "f11", kVK_F12: "f12",
            kVK_Space: "space", kVK_Return: "return", kVK_Tab: "tab",
            kVK_Delete: "delete", kVK_ForwardDelete: "forwarddelete",
            kVK_LeftArrow: "left", kVK_RightArrow: "right", kVK_UpArrow: "up", kVK_DownArrow: "down",
        ]
        if let s = special[Int(event.keyCode)] { return s }
        if let chars = event.charactersIgnoringModifiers, !chars.isEmpty { return chars.lowercased() }
        return nil
    }
}
