import XCTest
@testable import FanShiftCore

final class MenuBarTests: XCTestCase {
    private func layout(
        _ config: AppConfig,
        letter: String = "P",
        warning: Bool = false,
        temperature: Double? = 52.4,
        second: Double? = 47.6,
        rpm: Double? = 5330.2
    ) -> MenuBarLayout {
        MenuBar.layout(letter: letter, warning: warning, temperature: temperature, secondTemperature: second, rpm: rpm, config: config)
    }

    func testDefaultIsOneLineWithLetterInFront() {
        // 默认：字母、温度、转速挤在一项里排一行，和加这个功能之前一样
        let l = layout(AppConfig())
        XCTAssertNil(l.letterItem)
        XCTAssertEqual(l.leading, "P")
        XCTAssertEqual(l.lines, [[MenuBarSegment("52°"), MenuBarSegment("5330")]])
        XCTAssertFalse(l.stacked)
        XCTAssertFalse(l.readoutHidden)
    }

    func testWarningGoesWithTheLetter() {
        XCTAssertEqual(layout(AppConfig(), warning: true).leading, "⚠︎ P")
        var config = AppConfig()
        config.menuBarSeparateLetter = true
        XCTAssertEqual(layout(config, warning: true).letterItem, "⚠︎ P")
    }

    func testStackedPutsRPMAboveTemperatures() {
        var config = AppConfig()
        config.menuBarStyle = .stackedRPMAbove
        config.menuBarSecondSensor = .cpuAvg
        let l = layout(config)
        // 上面一行转速，下面一行两个温度，都带单位
        XCTAssertEqual(l.lines, [
            [MenuBarSegment("5330 RPM")],
            [MenuBarSegment("52°C"), MenuBarSegment("48°C")],
        ])
        XCTAssertTrue(l.stacked)
        XCTAssertEqual(l.leading, "P")
    }

    func testStackedBelowSwapsTheLines() {
        var config = AppConfig()
        config.menuBarStyle = .stackedRPMBelow
        let l = layout(config)
        XCTAssertEqual(l.lines, [[MenuBarSegment("52°C")], [MenuBarSegment("5330 RPM")]])
    }

    func testSecondTemperatureOnlyWhenChosen() {
        // 配置里没选第二个温度：就算传了值也不显示
        XCTAssertEqual(layout(AppConfig()).lines.first?.count, 2)
        var config = AppConfig()
        config.menuBarSecondSensor = .anyMax
        XCTAssertEqual(layout(config).lines, [[MenuBarSegment("52°"), MenuBarSegment("48°"), MenuBarSegment("5330")]])
        // 选了但这一刻读不到：只显示第一个
        XCTAssertEqual(layout(config, second: nil).lines, [[MenuBarSegment("52°"), MenuBarSegment("5330")]])
    }

    func testSeparateLetterLeavesReadoutWithoutIt() {
        var config = AppConfig()
        config.menuBarSeparateLetter = true
        let l = layout(config)
        XCTAssertEqual(l.letterItem, "P")
        XCTAssertNil(l.leading)
        XCTAssertEqual(l.lines, [[MenuBarSegment("52°"), MenuBarSegment("5330")]])
        XCTAssertFalse(l.readoutHidden)
    }

    func testReadoutHiddenWhenLetterIsSeparateAndNothingElseIsShown() {
        var config = AppConfig()
        config.menuBarSeparateLetter = true
        config.menuBarShowTemp = false
        config.menuBarShowRPM = false
        XCTAssertTrue(layout(config).readoutHidden)
        // 字母没分离时，读数那一项至少还有字母
        config.menuBarSeparateLetter = false
        let l = layout(config)
        XCTAssertFalse(l.readoutHidden)
        XCTAssertEqual(l.leading, "P")
        XCTAssertTrue(l.lines.isEmpty)
    }

    func testSeparateReadoutKeepsItsPlaceBeforeDataArrives() {
        // 刚启动、温度和转速都还没读到：读数那一项不能消失，先显示占位符
        var config = AppConfig()
        config.menuBarSeparateLetter = true
        let l = layout(config, temperature: nil, second: nil, rpm: nil)
        XCTAssertFalse(l.readoutHidden)
        XCTAssertEqual(l.lines, [[MenuBarSegment("…")]])
        XCTAssertEqual(l.letterItem, "P")
        // 字母没分离时，读数那一项本来就有字母，不需要占位符
        config.menuBarSeparateLetter = false
        XCTAssertTrue(layout(config, temperature: nil, second: nil, rpm: nil).lines.isEmpty)
    }

    func testStackedStyleWithOnlyOneLineIsNotStacked() {
        var config = AppConfig()
        config.menuBarStyle = .stackedRPMAbove
        config.menuBarShowTemp = false
        let l = layout(config)
        XCTAssertEqual(l.lines, [[MenuBarSegment("5330 RPM")]])
        XCTAssertFalse(l.stacked)
        // 风扇读不到转速（比如没有风扇的机器）：只剩温度一行
        config.menuBarShowTemp = true
        XCTAssertEqual(layout(config, rpm: nil).lines, [[MenuBarSegment("52°C")]])
    }

    func testHeatLevels() {
        XCTAssertEqual(MenuBar.heat(99, colored: false), .normal)
        XCTAssertEqual(MenuBar.heat(84.9, colored: true), .normal)
        XCTAssertEqual(MenuBar.heat(85, colored: true), .warm)
        XCTAssertEqual(MenuBar.heat(94.9, colored: true), .warm)
        XCTAssertEqual(MenuBar.heat(95, colored: true), .hot)

        var config = AppConfig()
        config.menuBarColorTemps = true
        config.menuBarSecondSensor = .cpuAvg
        let l = layout(config, temperature: 96, second: 86, rpm: 7826)
        XCTAssertEqual(l.lines, [[
            MenuBarSegment("96°", heat: .hot),
            MenuBarSegment("86°", heat: .warm),
            MenuBarSegment("7826"),
        ]])
    }

    func testNewFieldsSurviveSaveAndLoad() throws {
        var config = AppConfig()
        config.menuBarStyle = .stackedRPMAbove
        config.menuBarSeparateLetter = true
        config.menuBarSecondSensor = .named("NAND CH0 temp")
        config.menuBarColorTemps = true
        let data = try JSONEncoder().encode(config)
        XCTAssertEqual(try AppConfig.decode(data), config)
    }

    func testOldConfigWithoutNewFieldsKeepsOldLook() throws {
        let cfg = try AppConfig.decode(Data(#"{"menuBarShowRPM": false}"#.utf8))
        XCTAssertEqual(cfg.menuBarStyle, .inline)
        XCTAssertFalse(cfg.menuBarSeparateLetter)
        XCTAssertNil(cfg.menuBarSecondSensor)
        XCTAssertFalse(cfg.menuBarColorTemps)
        XCTAssertFalse(cfg.menuBarShowRPM)
    }

    func testUnknownStyleNameFallsBackInsteadOfBreakingTheWholeConfig() throws {
        let cfg = try AppConfig.decode(Data(#"{"menuBarStyle": "vertical3D", "hotkeyKey": "5"}"#.utf8))
        XCTAssertEqual(cfg.menuBarStyle, .inline)
        XCTAssertEqual(cfg.hotkeyKey, "5")
    }
}
