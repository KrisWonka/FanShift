import FanShiftCore
import Foundation

/// 开机自启：在 ~/Library/LaunchAgents/ 里放一个 LaunchAgent，登录时后台打开 FanShift。
/// 纯用户域，不需要密码。
enum Autostart {
    static var plistPath: String {
        NSString(string: "~/Library/LaunchAgents/\(FanShiftInfo.autostartLabel).plist").expandingTildeInPath
    }

    static var isEnabled: Bool {
        FileManager.default.fileExists(atPath: plistPath)
    }

    static func setEnabled(_ enabled: Bool) {
        if enabled { enable() } else { disable() }
    }

    private static func enable() {
        let dir = (plistPath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key><string>\(FanShiftInfo.autostartLabel)</string>
            <key>RunAtLoad</key><true/>
            <key>ProgramArguments</key>
            <array>
                <string>/usr/bin/open</string>
                <string>-g</string>
                <string>\(FanShiftInfo.appInstallPath)</string>
            </array>
        </dict>
        </plist>
        """
        try? plist.write(toFile: plistPath, atomically: true, encoding: .utf8)
    }

    private static func disable() {
        launchctl(["bootout", "gui/\(getuid())/\(FanShiftInfo.autostartLabel)"])
        try? FileManager.default.removeItem(atPath: plistPath)
    }

    @discardableResult
    private static func launchctl(_ args: [String]) -> Int32 {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = args
        task.standardOutput = Pipe()
        task.standardError = Pipe()
        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus
        } catch {
            return -1
        }
    }
}
