import Foundation

/// 全项目共用的名字和路径。改名字只需要改这里和 scripts/ 里的打包脚本。
public enum FanShiftInfo {
    public static let appName = "FanShift"
    public static let bundleID = "com.kriswonka.fanshift"
    public static let daemonLabel = "com.kriswonka.fanshift.daemon"
    public static let autostartLabel = "com.kriswonka.fanshift.autostart"
    public static let repoURL = "https://github.com/KrisWonka/FanShift"

    /// 后台程序的接口版本。App 和后台程序各编进一份，对不上就提示重装后台程序。
    public static let helperVersion = "1"

    public static let daemonBinaryPath = "/Library/PrivilegedHelperTools/\(daemonLabel)"
    public static let daemonPlistPath = "/Library/LaunchDaemons/\(daemonLabel).plist"
    /// 后台程序接管风扇期间存在的标记文件。/var/run 重启后会清空。
    public static let daemonMarkerPath = "/var/run/\(daemonLabel).holding"
    public static let appInstallPath = "/Applications/\(appName).app"
}

public enum AppPaths {
    /// 配置和状态所在的文件夹。设了环境变量 FANSHIFT_HOME 就用它（开发、测试时用）。
    public static var home: URL {
        if let override = ProcessInfo.processInfo.environment["FANSHIFT_HOME"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent(FanShiftInfo.appName, isDirectory: true)
    }

    public static var config: URL { home.appendingPathComponent("config.json") }
    public static var state: URL { home.appendingPathComponent("state.json") }

    /// 旧版（tgpro-hotkey-mac）的配置文件，第一次启动时从这里搬过来
    public static var legacyConfig: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".hammerspoon/tgpro-hotkey-config.json")
    }
}
