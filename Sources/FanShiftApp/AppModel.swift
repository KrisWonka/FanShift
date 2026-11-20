import AppKit
import Combine
import FanShiftCore

struct FanReadout: Equatable {
    var index: Int
    var actual: Double
    var target: Double
    var mode: Int
    var minRPM: Double
    var maxRPM: Double
}

/// 给界面看的一份当前状态，每次计算后更新
struct Snapshot: Equatable {
    var letter = "…"
    var stepName = ""
    var stepIndex = 0
    var revertedToAuto = false
    var temperature: Double?
    var percent: Double?
    /// 这一刻是不是我们在给风扇目标转速
    var controlling = false
    var fans: [FanReadout] = []
    var readings: [SensorReading] = []
    var tgProRunning = false

    var averageRPM: Double? {
        fans.isEmpty ? nil : fans.map(\.actual).reduce(0, +) / Double(fans.count)
    }
}

/// App 的中枢：每 2 秒读一次温度，交给 FanController 算出指令，再发给后台程序。
final class AppModel: ObservableObject {
    static let shared = AppModel()
    static let tickInterval: TimeInterval = 2
    static let lease: TimeInterval = 10

    /// 界面语言跟着配置走。用 willSet 而不是 didSet：订阅 $config 的地方在赋值之前就会收到新值，
    /// 这时界面语言必须已经换好，不然重画出来的还是旧语言。
    @Published private(set) var config: AppConfig {
        willSet { Lang.current = newValue.language }
    }
    @Published private(set) var snapshot = Snapshot()
    @Published private(set) var helperState: HelperState = .unknown
    @Published private(set) var lastError: String?
    @Published var selectedTab = 0
    /// 菜单栏项是不是被刘海挡住了（由菜单栏那边检测后写进来）
    @Published var menuBarObstructed = false
    /// 菜单栏项的实际位置（Status 页底部显示，排查「看不到菜单栏项」时用）
    @Published var menuBarDiagnostics = ""

    let configSource: AppConfig.Source
    let dryRun: Bool

    /// 屏幕中央提示（在主线程调用）
    var onAlert: ((String) -> Void)?
    /// 配置生效后调用（在主线程），用来重新注册快捷键
    var onConfigApplied: (() -> Void)?

    // 以下只在 queue 上碰
    private let queue = DispatchQueue(label: "com.kriswonka.fanshift.control")
    private var controller: FanController
    private let sensors = TemperatureSensors()
    private let hardware: SMCFans?
    private let channel: HelperChannel
    private var timer: DispatchSourceTimer?
    private var engaged = false
    private var helperReady = false
    private var suspended = false
    private var lastHelperCheck = Date.distantPast
    private var activity: NSObjectProtocol?

    private init() {
        let env = ProcessInfo.processInfo.environment
        dryRun = env["FANSHIFT_DRYRUN"] == "1"
        channel = dryRun ? DryRunChannel() : XPCHelperChannel()

        let loaded = AppConfig.load()
        // init 里赋值不会触发 willSet，这里手动设一次
        Lang.current = loaded.config.language
        config = loaded.config
        configSource = loaded.source

        hardware = try? SMCFans()
        let state = RuntimeState.load()
        let index = state.activeStepID.flatMap { id in loaded.config.cycleSteps.firstIndex { $0.id == id } } ?? 0
        controller = FanController(
            config: loaded.config,
            fans: hardware?.fans ?? [],
            stepIndex: index,
            revertedToAuto: state.activeStepID == nil ? false : state.revertedToAuto
        )
    }

    // MARK: 生命周期

    func start() {
        // 没有窗口的菜单栏 App 会被系统「打盹」降频，定时器可能被拖慢好几秒甚至更久，
        // 而后台程序 10 秒收不到指令就会把风扇交还系统。所以明确声明这是不能降频的活动（不阻止电脑睡眠）。
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep],
            reason: "Controlling the fans from temperature curves; needs to run every 2 seconds"
        )
        refreshHelper()
        let t = DispatchSource.makeTimerSource(flags: .strict, queue: queue)
        t.schedule(deadline: .now(), repeating: Self.tickInterval, leeway: .milliseconds(100))
        t.setEventHandler { [weak self] in self?.tick() }
        t.resume()
        timer = t
    }

    /// 退出前：把风扇交还系统，最多等一秒半
    func shutdown() {
        let done = DispatchSemaphore(value: 0)
        queue.async {
            self.timer?.cancel()
            self.suspended = true
            guard self.engaged else {
                done.signal()
                return
            }
            self.engaged = false
            self.channel.release { _ in done.signal() }
        }
        _ = done.wait(timeout: .now() + 1.5)
    }

    /// 睡眠前交还风扇；唤醒后恢复
    func setSuspended(_ value: Bool) {
        queue.async {
            self.suspended = value
            if value, self.engaged {
                self.engaged = false
                self.channel.release { _ in }
            }
            if !value { self.tick() }
        }
    }

    // MARK: 档位

    func cycle() {
        queue.async {
            guard let step = self.controller.cycle(now: Date()) else {
                self.alert(L.noProfilesAlert)
                return
            }
            self.persist()
            self.alert(step.effectiveName)
            self.tick()
        }
    }

    func select(index: Int) {
        queue.async {
            guard let step = self.controller.select(index, now: Date()) else { return }
            self.persist()
            self.alert(step.effectiveName)
            self.tick()
        }
    }

    /// 启动时弹一下当前档位
    func announceCurrent() {
        queue.async {
            guard self.controller.currentStep != nil else { return }
            self.alert(self.controller.displayName)
        }
    }

    /// 保存并立即生效（在主线程调用）
    func apply(_ newConfig: AppConfig) throws {
        try newConfig.save()
        config = newConfig
        queue.async {
            self.controller.setConfig(newConfig, now: Date())
            self.persist()
            self.tick()
        }
        onConfigApplied?()
    }

    // MARK: 后台程序

    func refreshHelper() {
        if dryRun { return setHelper(.ready) }
        guard HelperInstaller.isInstalled else { return setHelper(.notInstalled) }
        channel.info { [weak self] info, error in
            guard let self else { return }
            if let info {
                if info.version != FanShiftInfo.helperVersion {
                    self.setHelper(.outdated(info.version))
                } else if let problem = info.problem {
                    self.setHelper(.problem(problem))
                } else {
                    self.setHelper(.ready)
                }
            } else {
                self.setHelper(.problem(error ?? L.cannotReachHelperShort.s))
            }
        }
    }

    /// 弹密码框安装后台程序（在主线程调用，会一直等到用户输完密码）。成功返回 nil，否则返回给界面看的原因。
    func installHelper() -> String? {
        installHelperResult()?.message
    }

    /// 同上，但能分辨出「用户点了取消」
    func installHelperResult() -> HelperInstallError? {
        let error = HelperInstaller.install()
        // 刚装好的服务要一点时间才能连上
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self.refreshHelper() }
        return error
    }

    func uninstallHelper() -> String? {
        queue.sync { engaged = false }
        let error = HelperInstaller.uninstall()
        refreshHelper()
        return error?.message
    }

    private func setHelper(_ state: HelperState) {
        queue.async {
            self.helperReady = state.isReady
            if state.isReady { self.tick() }
        }
        DispatchQueue.main.async {
            if self.helperState != state { self.helperState = state }
            if state.isReady, self.lastError != nil { self.lastError = nil }
        }
    }

    /// 后台程序还不可用时，每 10 秒重新确认一次。刚装好还没连上、被系统重启、或者是在别处装的，都能自己接上。
    private func recheckHelperIfNeeded() {
        guard !dryRun, !helperReady, Date().timeIntervalSince(lastHelperCheck) > 10 else { return }
        lastHelperCheck = Date()
        refreshHelper()
    }

    // MARK: 以下都在 queue 上执行

    private func alert(_ text: String) {
        DispatchQueue.main.async { self.onAlert?(text) }
    }

    /// 界面文字到了主线程再取当前语言的版本
    private func alert(_ text: Tr) {
        DispatchQueue.main.async { self.onAlert?(text.s) }
    }

    private func persist() {
        RuntimeState(activeStepID: controller.currentStep?.id, revertedToAuto: controller.revertedToAuto).save()
    }

    private func tick() {
        recheckHelperIfNeeded()
        let readings = sensors.readAll()
        let (computed, events) = controller.tick(readings: readings, now: Date())
        for event in events {
            switch event {
            case .cooldownDone: alert(controller.config.alertCooldownDone)
            case .autoReverted: alert("\(CycleStepType.auto.displayName) ⏱")
            }
            persist()
        }
        let command = suspended ? FanCommand.release : computed
        send(command)
        publish(readings: readings, command: command)
    }

    private func send(_ command: FanCommand) {
        switch command {
        case .release:
            guard engaged else { return }
            engaged = false
            channel.release { [weak self] in self?.report($0) }
        case .targets(let rpms):
            guard helperReady else { return }
            engaged = true
            channel.setTargets(rpms, lease: Self.lease) { [weak self] in self?.report($0) }
        }
    }

    private func report(_ error: String?) {
        DispatchQueue.main.async {
            if self.lastError != error { self.lastError = error }
        }
        guard error != nil else { return }
        // 出错了就重新确认一下后台程序的状态，但别查得太勤
        queue.async {
            guard Date().timeIntervalSince(self.lastHelperCheck) > 10 else { return }
            self.lastHelperCheck = Date()
            self.refreshHelper()
        }
    }

    private func publish(readings: [SensorReading], command: FanCommand) {
        var snap = Snapshot()
        snap.letter = controller.letter
        snap.stepName = controller.displayName
        snap.stepIndex = controller.stepIndex
        snap.revertedToAuto = controller.revertedToAuto
        snap.temperature = controller.lastTemperature
        snap.percent = controller.lastPercent
        snap.readings = readings
        snap.tgProRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: "com.tunabellysoftware.tgpro").isEmpty
        if case .targets = command { snap.controlling = helperReady }
        if let hardware {
            snap.fans = hardware.fans.map { fan in
                FanReadout(
                    index: fan.index,
                    actual: (try? hardware.actual(fan: fan.index)) ?? 0,
                    target: (try? hardware.target(fan: fan.index)) ?? 0,
                    mode: (try? hardware.mode(fan: fan.index)) ?? -1,
                    minRPM: fan.minRPM,
                    maxRPM: fan.maxRPM
                )
            }
        }
        DispatchQueue.main.async {
            if self.snapshot != snap { self.snapshot = snap }
        }
    }
}
