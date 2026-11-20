import XCTest
@testable import FanShiftCore

/// 假风扇：记录每一次写入，可以模拟「接管不上」
private final class FakeFans: FanHardware {
    let fans = [
        FanInfo(index: 0, minRPM: 2317, maxRPM: 7826),
        FanInfo(index: 1, minRPM: 2317, maxRPM: 7826),
    ]
    var modes = [0, 0]
    var targets = [0.0, 0.0]
    var log: [String] = []
    var refuseAcquireOnFan: Int?

    func mode(fan: Int) throws -> Int { modes[fan] }
    func setMode(fan: Int, _ mode: Int) throws {
        log.append("mode\(fan)=\(mode)")
        if mode == FanMode.forced, refuseAcquireOnFan == fan { return }  // 固件没接受
        modes[fan] = mode
    }
    func target(fan: Int) throws -> Double { targets[fan] }
    func setTarget(fan: Int, rpm: Double) throws {
        log.append("target\(fan)=\(Int(rpm))")
        targets[fan] = rpm
    }
    func actual(fan: Int) throws -> Double { targets[fan] }
}

/// 假时钟：sleep 只把时间往前拨
private final class FakeClock {
    var now: Date
    var slept: TimeInterval = 0
    init(_ start: Date) { now = start }
    var timing: GovernorTiming {
        GovernorTiming(now: { self.now }, sleep: { self.now += $0; self.slept += $0 })
    }
}

/// 模拟 M1–M4：系统温控占着风扇（模式 3），直接写模式 1 会被固件拒绝（0x82）；
/// 写了 Ftst = 1 之后，要再过 unlockDelay 秒写模式 1 才会被接受。
private final class FakeLegacyFans: FanHardware {
    let clock: FakeClock
    let fans = [
        FanInfo(index: 0, minRPM: 1200, maxRPM: 6550),
        FanInfo(index: 1, minRPM: 1200, maxRPM: 6550),
    ]
    var modes = [3, 3]
    var targets = [0.0, 0.0]
    var ftst = 0
    var ftstSince: Date?
    /// nil = 永远解不开
    var unlockDelay: TimeInterval? = 3.5
    var log: [String] = []

    init(clock: FakeClock) { self.clock = clock }

    var hasForceTestKey: Bool { true }
    func forceTest() throws -> Int { ftst }
    func setForceTest(_ on: Bool) throws {
        ftst = on ? 1 : 0
        ftstSince = on ? clock.now : nil
        log.append("ftst=\(ftst)")
    }
    func mode(fan: Int) throws -> Int { modes[fan] }
    func setMode(fan: Int, _ mode: Int) throws {
        if mode == FanMode.forced, modes[fan] != FanMode.forced {
            guard let since = ftstSince, let delay = unlockDelay, clock.now.timeIntervalSince(since) >= delay else {
                throw SMCError(op: "写", key: "F\(fan)Md", kr: 0, result: 0x82)
            }
        }
        modes[fan] = mode
        log.append("mode\(fan)=\(mode)")
    }
    func target(fan: Int) throws -> Double { targets[fan] }
    func setTarget(fan: Int, rpm: Double) throws {
        targets[fan] = rpm
        log.append("target\(fan)=\(Int(rpm))")
    }
    func actual(fan: Int) throws -> Double { targets[fan] }
}

final class GovernorTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)
    private var marker: String!
    private var clock: FakeClock!

    /// 所有测试都用假时钟，重试时不真的等
    private func governor(_ hw: FanHardware) -> FanGovernor {
        FanGovernor(hardware: hw, markerPath: marker, timing: clock.timing)
    }

    override func setUp() {
        marker = FileManager.default.temporaryDirectory.appendingPathComponent("fanshift-marker-\(UUID().uuidString)").path
        clock = FakeClock(t0)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(atPath: marker)
    }

    private var markerExists: Bool { FileManager.default.fileExists(atPath: marker) }

    func testAcquiresThenSetsTargets() throws {
        let hw = FakeFans()
        let g = governor(hw)
        try g.setTargets([4500, 4500], lease: 10, now: t0)
        XCTAssertEqual(hw.log, ["mode0=1", "target0=4500", "mode1=1", "target1=4500"])
        XCTAssertTrue(g.holding)
        XCTAssertTrue(markerExists)
    }

    func testRepeatedSameTargetWritesNothing() throws {
        let hw = FakeFans()
        let g = governor(hw)
        try g.setTargets([4500, 4500], lease: 10, now: t0)
        hw.log.removeAll()
        try g.setTargets([4500, 4500], lease: 10, now: t0)
        XCTAssertEqual(hw.log, [])
        try g.setTargets([3000, 4500], lease: 10, now: t0)
        XCTAssertEqual(hw.log, ["target0=3000"])
    }

    func testTargetsAreClampedToFanRange() throws {
        let hw = FakeFans()
        let g = governor(hw)
        try g.setTargets([0, 99999], lease: 10, now: t0)
        XCTAssertEqual(hw.targets, [2317, 7826])
    }

    func testRejectsWrongCountAndNaN() {
        let hw = FakeFans()
        let g = governor(hw)
        XCTAssertThrowsError(try g.setTargets([4500], lease: 10, now: t0))
        XCTAssertThrowsError(try g.setTargets([4500, .nan], lease: 10, now: t0))
        XCTAssertEqual(hw.log, [])
        XCTAssertFalse(g.holding)
        XCTAssertFalse(markerExists)
    }

    func testReacquiresWhenSomethingResetTheMode() throws {
        // 比如睡眠唤醒后系统把模式改回去了
        let hw = FakeFans()
        let g = governor(hw)
        try g.setTargets([4500, 4500], lease: 10, now: t0)
        hw.modes = [3, 3]
        hw.log.removeAll()
        try g.setTargets([4500, 4500], lease: 10, now: t0)
        XCTAssertEqual(hw.log, ["mode0=1", "target0=4500", "mode1=1", "target1=4500"])
    }

    func testReleaseHandsBackAndClearsMarker() throws {
        let hw = FakeFans()
        let g = governor(hw)
        try g.setTargets([4500, 4500], lease: 10, now: t0)
        g.release()
        XCTAssertEqual(hw.modes, [0, 0])
        XCTAssertFalse(g.holding)
        XCTAssertFalse(markerExists)
    }

    func testReleaseWhenNotHoldingLeavesOtherControllersAlone() {
        // 风扇被别的软件接管着（模式 1），我们没接管过 → 不动它
        let hw = FakeFans()
        hw.modes = [1, 1]
        let g = governor(hw)
        g.release()
        XCTAssertEqual(hw.modes, [1, 1])
        XCTAssertEqual(hw.log, [])
    }

    func testLeaseExpiryReleases() throws {
        let hw = FakeFans()
        let g = governor(hw)
        try g.setTargets([4500, 4500], lease: 10, now: t0)
        XCTAssertFalse(g.checkLease(now: t0.addingTimeInterval(9.9)))
        XCTAssertTrue(g.holding)
        XCTAssertTrue(g.checkLease(now: t0.addingTimeInterval(10)))
        XCTAssertEqual(hw.modes, [0, 0])
        XCTAssertFalse(g.holding)
    }

    func testLeaseIsRenewedAndBounded() throws {
        let hw = FakeFans()
        let g = governor(hw)
        try g.setTargets([4500, 4500], lease: 10, now: t0)
        try g.setTargets([4500, 4500], lease: 10, now: t0.addingTimeInterval(8))
        XCTAssertFalse(g.checkLease(now: t0.addingTimeInterval(15)))
        // 要一个小时的租约也只给 30 秒
        try g.setTargets([4500, 4500], lease: 3600, now: t0)
        XCTAssertTrue(g.checkLease(now: t0.addingTimeInterval(30)))
    }

    func testFailedAcquireReleasesEverythingAndThrows() {
        let hw = FakeFans()
        hw.refuseAcquireOnFan = 1
        let g = governor(hw)
        XCTAssertThrowsError(try g.setTargets([4500, 4500], lease: 10, now: t0))
        XCTAssertEqual(hw.modes, [0, 0])  // 已经接管上的风扇 0 也交还了
        XCTAssertFalse(g.holding)
        XCTAssertFalse(markerExists)
    }

    func testReconcileAtStartReleasesWhenMarkerLeftBehind() {
        // 上次接管着风扇时进程被杀：标记文件还在，风扇还停在模式 1
        FileManager.default.createFile(atPath: marker, contents: nil)
        let hw = FakeFans()
        hw.modes = [1, 1]
        let g = governor(hw)
        g.reconcileAtStart()
        XCTAssertEqual(hw.modes, [0, 0])
        XCTAssertFalse(markerExists)
    }

    // MARK: 接管时重试（各代机型）

    func testWakeHoldIsRetriedWithoutFtst() throws {
        // M5 睡眠唤醒后：系统温控占着风扇半秒，期间写模式 1 被拒绝
        final class WakingFans: FanHardware {
            let clock: FakeClock
            let fans = [FanInfo(index: 0, minRPM: 2317, maxRPM: 7826)]
            var mode = 3
            let busyUntil: Date
            var ftstWrites = 0
            init(clock: FakeClock) { self.clock = clock; busyUntil = clock.now.addingTimeInterval(0.45) }
            func mode(fan: Int) throws -> Int { mode }
            func setMode(fan: Int, _ m: Int) throws {
                if m == FanMode.forced, clock.now < busyUntil { throw SMCError(op: "写", key: "F0md", kr: 0, result: 0x82) }
                mode = m
            }
            func target(fan: Int) throws -> Double { 0 }
            func setTarget(fan: Int, rpm: Double) throws {}
            func actual(fan: Int) throws -> Double { 0 }
            func setForceTest(_ on: Bool) throws { ftstWrites += 1 }
        }
        let hw = WakingFans(clock: clock)
        var events: [String] = []
        let g = governor(hw)
        g.onEvent = { events.append($0) }
        try g.setTargets([4500], lease: 10, now: t0)
        XCTAssertEqual(hw.mode, FanMode.forced)
        XCTAssertEqual(hw.ftstWrites, 0)           // 没有 Ftst 键，不碰它
        XCTAssertEqual(clock.slept, 0.5, accuracy: 1e-9)  // 每 0.1 秒一次，第 6 次成功
        XCTAssertEqual(events.count, 1)
    }

    func testGivesUpAfterOneSecondWithoutFtst() {
        let hw = FakeFans()
        hw.refuseAcquireOnFan = 0
        let g = governor(hw)
        XCTAssertThrowsError(try g.setTargets([4500, 4500], lease: 10, now: t0))
        XCTAssertEqual(clock.slept, 1.0, accuracy: 1e-9)
        XCTAssertFalse(g.holding)
    }

    func testOtherWriteErrorsAreNotRetried() {
        // 比如没有 root 权限：不是「系统占着」，重试也没用，马上报错
        final class NoRootFans: FanHardware {
            let fans = [FanInfo(index: 0, minRPM: 2317, maxRPM: 7826)]
            func mode(fan: Int) throws -> Int { 3 }
            func setMode(fan: Int, _ m: Int) throws { throw SMCError(op: "写", key: "F0md", kr: Int32(bitPattern: 0xe000_02c1), result: 0) }
            func target(fan: Int) throws -> Double { 0 }
            func setTarget(fan: Int, rpm: Double) throws {}
            func actual(fan: Int) throws -> Double { 0 }
        }
        let g = governor(NoRootFans())
        XCTAssertThrowsError(try g.setTargets([4500], lease: 10, now: t0)) { error in
            XCTAssertTrue((error as? SMCError)?.isNotPrivileged == true)
        }
        XCTAssertEqual(clock.slept, 0)
    }

    // MARK: M1–M4：用 Ftst 解锁

    func testLegacyUnlocksWithFtstThenAcquires() throws {
        let hw = FakeLegacyFans(clock: clock)
        var events: [String] = []
        let g = governor(hw)
        g.onEvent = { events.append($0) }
        try g.setTargets([4000, 4000], lease: 10, now: t0)
        // Ftst 只写一次；风扇 0 等了约 3.5 秒，风扇 1 直接就接管上了
        XCTAssertEqual(hw.log, ["ftst=1", "mode0=1", "target0=4000", "mode1=1", "target1=4000"])
        XCTAssertEqual(hw.modes, [1, 1])
        XCTAssertEqual(hw.ftst, 1)  // 接管期间保持 1
        XCTAssertTrue(g.holding)
        XCTAssertEqual(clock.slept, 3.5, accuracy: 0.11)
        XCTAssertTrue(events.contains { $0.contains("写 Ftst = 1") })
        XCTAssertTrue(events.contains { $0.contains("解锁后接管") })
    }

    func testLegacyReleaseClearsFtst() throws {
        let hw = FakeLegacyFans(clock: clock)
        let g = governor(hw)
        try g.setTargets([4000, 4000], lease: 10, now: t0)
        g.release()
        XCTAssertEqual(hw.modes, [0, 0])
        XCTAssertEqual(hw.ftst, 0)
        XCTAssertFalse(g.holding)
        XCTAssertFalse(markerExists)
    }

    func testLegacyGivesUpAfterTenSecondsAndClearsFtst() {
        let hw = FakeLegacyFans(clock: clock)
        hw.unlockDelay = nil
        let g = governor(hw)
        XCTAssertThrowsError(try g.setTargets([4000, 4000], lease: 10, now: t0))
        XCTAssertEqual(clock.slept, 10, accuracy: 0.11)
        XCTAssertEqual(hw.ftst, 0)          // 失败了也不能把 Ftst 留在 1
        XCTAssertEqual(hw.modes, [3, 3])    // 本来就是系统的，不去写它
        XCTAssertFalse(g.holding)
        XCTAssertFalse(markerExists)
    }

    func testLeaseDoesNotCountTimeSpentAcquiring() throws {
        let hw = FakeLegacyFans(clock: clock)
        let g = governor(hw)
        try g.setTargets([4000, 4000], lease: 10, now: t0)  // 接管花了约 3.5 秒
        XCTAssertFalse(g.checkLease(now: t0.addingTimeInterval(13)))
        XCTAssertTrue(g.checkLease(now: t0.addingTimeInterval(13.7)))
        XCTAssertEqual(hw.ftst, 0)          // 租约到期的交还也清 Ftst
    }

    func testReconcileClearsStaleFtstWhenNobodyHoldsTheFans() {
        // 上次留下 Ftst = 1，风扇却都在系统手里：系统温控被晾着，要清掉
        let hw = FakeLegacyFans(clock: clock)
        hw.ftst = 1
        let g = governor(hw)
        g.reconcileAtStart()
        XCTAssertEqual(hw.ftst, 0)
        XCTAssertEqual(hw.modes, [3, 3])
    }

    func testReconcileLeavesFtstAloneWhenAnotherAppHoldsTheFans() {
        // 别的软件正接管着（风扇在模式 1），Ftst 是它的
        let hw = FakeLegacyFans(clock: clock)
        hw.ftst = 1
        hw.modes = [1, 1]
        let g = governor(hw)
        g.reconcileAtStart()
        XCTAssertEqual(hw.ftst, 1)
        XCTAssertEqual(hw.modes, [1, 1])
    }

    func testReconcileWithMarkerAlsoClearsFtst() {
        FileManager.default.createFile(atPath: marker, contents: nil)
        let hw = FakeLegacyFans(clock: clock)
        hw.ftst = 1
        hw.modes = [1, 1]
        let g = governor(hw)
        g.reconcileAtStart()
        XCTAssertEqual(hw.modes, [0, 0])
        XCTAssertEqual(hw.ftst, 0)
        XCTAssertFalse(markerExists)
    }

    func testReconcileAtStartWithoutMarkerTouchesNothing() {
        let hw = FakeFans()
        hw.modes = [1, 1]
        let g = governor(hw)
        g.reconcileAtStart()
        XCTAssertEqual(hw.modes, [1, 1])
    }
}
