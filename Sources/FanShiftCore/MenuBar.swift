import Foundation

/// 菜单栏读数怎么排
public enum MenuBarStyle: String, Codable, CaseIterable, Identifiable {
    /// 一行：P 52° 5330
    case inline
    /// 两行小字，转速在上、温度在下（TG Pro 的「Fan RPM Above」）
    case stackedRPMAbove
    /// 两行小字，温度在上、转速在下（TG Pro 的「Fan RPM Below」）
    case stackedRPMBelow

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .inline: return "一行（P 52° 5330）"
        case .stackedRPMAbove: return "两行，转速在上（仿 TG Pro）"
        case .stackedRPMBelow: return "两行，转速在下"
        }
    }

    public var isStacked: Bool { self != .inline }
}

/// 温度的冷热档，决定菜单栏里那段文字用什么颜色
public enum HeatLevel: Equatable {
    case normal, warm, hot
}

/// 菜单栏读数里的一段文字
public struct MenuBarSegment: Equatable {
    public var text: String
    public var heat: HeatLevel

    public init(_ text: String, heat: HeatLevel = .normal) {
        self.text = text
        self.heat = heat
    }
}

/// 菜单栏上该显示什么。最多两项：档位字母（可选单独一项）和读数。
public struct MenuBarLayout: Equatable {
    /// 档位字母单独那一项的文字；nil 表示字母没有分离出来
    public var letterItem: String?
    /// 读数那一项开头的档位字母；字母分离出去之后是 nil
    public var leading: String?
    /// 读数：没有、一行或两行，每行若干段
    public var lines: [[MenuBarSegment]]
    /// 两行时用小字叠起来画；一行时就是普通的菜单栏文字
    public var stacked: Bool
    /// 读数那一项整个不用显示（字母分离出去了，温度和转速又都关了）。
    /// 只由配置决定，不看这一刻有没有读到数据：菜单栏项时有时无的话，系统会把它记住的位置丢掉。
    public var readoutHidden: Bool
}

public enum MenuBar {
    /// 开了「温度高时变色」之后：到这个温度变橙色
    public static let warmThreshold = 85.0
    /// 到这个温度变红色（和过热保护全速的门槛是同一个数）
    public static let hotThreshold = 95.0

    public static func heat(_ temperature: Double, colored: Bool) -> HeatLevel {
        guard colored else { return .normal }
        if temperature >= hotThreshold { return .hot }
        if temperature >= warmThreshold { return .warm }
        return .normal
    }

    /// - Parameters:
    ///   - letter: 档位字母
    ///   - warning: 当前档位想控制风扇但后台程序不可用，在字母前加警告标记
    ///   - temperature: 当前档位参考的温度
    ///   - secondTemperature: 第二个温度（配置里没选就传 nil）
    ///   - rpm: 风扇平均转速
    public static func layout(
        letter: String,
        warning: Bool,
        temperature: Double?,
        secondTemperature: Double?,
        rpm: Double?,
        config: AppConfig
    ) -> MenuBarLayout {
        let stackedStyle = config.menuBarStyle.isStacked
        let letterText = (warning ? "⚠︎ " : "") + letter

        var temps: [MenuBarSegment] = []
        if config.menuBarShowTemp {
            let shown = [temperature, config.menuBarSecondSensor == nil ? nil : secondTemperature]
            for t in shown.compactMap({ $0 }) {
                let number = "\(Int(t.rounded()))"
                temps.append(MenuBarSegment(
                    stackedStyle ? "\(number)°C" : "\(number)°",
                    heat: heat(t, colored: config.menuBarColorTemps)
                ))
            }
        }
        var rpmLine: [MenuBarSegment] = []
        if config.menuBarShowRPM, let rpm {
            let number = "\(Int(rpm.rounded()))"
            rpmLine = [MenuBarSegment(stackedStyle ? "\(number) RPM" : number)]
        }

        var lines: [[MenuBarSegment]]
        switch config.menuBarStyle {
        case .inline:
            let all = temps + rpmLine
            lines = all.isEmpty ? [] : [all]
        case .stackedRPMAbove:
            lines = [rpmLine, temps].filter { !$0.isEmpty }
        case .stackedRPMBelow:
            lines = [temps, rpmLine].filter { !$0.isEmpty }
        }

        let separate = config.menuBarSeparateLetter
        let hidden = separate && !config.menuBarShowTemp && !config.menuBarShowRPM
        // 该显示读数、但数据还没读到（刚启动）：先占个位
        if separate, !hidden, lines.isEmpty { lines = [[MenuBarSegment("…")]] }

        return MenuBarLayout(
            letterItem: separate ? letterText : nil,
            leading: separate ? nil : letterText,
            lines: lines,
            stacked: lines.count > 1,
            readoutHidden: hidden
        )
    }
}
