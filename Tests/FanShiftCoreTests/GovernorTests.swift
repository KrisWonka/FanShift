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

final class GovernorTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)
    private var marker: String!

    override func setUp() {
        marker = FileManager.default.temporaryDirectory.appendingPathComponent("fanshift-marker-\(UUID().uuidString)").path
    }

    override func tearDown() {
        try? FileManager.default.removeItem(atPath: marker)
    }

    private var markerExists: Bool { FileManager.default.fileExists(atPath: marker) }

    func testAcquiresThenSetsTargets() throws {
        let hw = FakeFans()
        let g = FanGovernor(hardware: hw, markerPath: marker)
        try g.setTargets([4500, 4500], lease: 10, now: t0)
        XCTAssertEqual(hw.log, ["mode0=1", "target0=4500", "mode1=1", "target1=4500"])
        XCTAssertTrue(g.holding)
        XCTAssertTrue(markerExists)
    }

    func testRepeatedSameTargetWritesNothing() throws {
        let hw = FakeFans()
        let g = FanGovernor(hardware: hw, markerPath: marker)
        try g.setTargets([4500, 4500], lease: 10, now: t0)
        hw.log.removeAll()
        try g.setTargets([4500, 4500], lease: 10, now: t0)
        XCTAssertEqual(hw.log, [])
        try g.setTargets([3000, 4500], lease: 10, now: t0)
        XCTAssertEqual(hw.log, ["target0=3000"])
    }

    func testTargetsAreClampedToFanRange() throws {
        let hw = FakeFans()
        let g = FanGovernor(hardware: hw, markerPath: marker)
        try g.setTargets([0, 99999], lease: 10, now: t0)
        XCTAssertEqual(hw.targets, [2317, 7826])
    }

    func testRejectsWrongCountAndNaN() {
        let hw = FakeFans()
        let g = FanGovernor(hardware: hw, markerPath: marker)
        XCTAssertThrowsError(try g.setTargets([4500], lease: 10, now: t0))
        XCTAssertThrowsError(try g.setTargets([4500, .nan], lease: 10, now: t0))
        XCTAssertEqual(hw.log, [])
        XCTAssertFalse(g.holding)
        XCTAssertFalse(markerExists)
    }

    func testReacquiresWhenSomethingResetTheMode() throws {
        // 比如睡眠唤醒后系统把模式改回去了
        let hw = FakeFans()
        let g = FanGovernor(hardware: hw, markerPath: marker)
        try g.setTargets([4500, 4500], lease: 10, now: t0)
        hw.modes = [3, 3]
        hw.log.removeAll()
        try g.setTargets([4500, 4500], lease: 10, now: t0)
        XCTAssertEqual(hw.log, ["mode0=1", "target0=4500", "mode1=1", "target1=4500"])
    }

    func testReleaseHandsBackAndClearsMarker() throws {
        let hw = FakeFans()
        let g = FanGovernor(hardware: hw, markerPath: marker)
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
        let g = FanGovernor(hardware: hw, markerPath: marker)
        g.release()
        XCTAssertEqual(hw.modes, [1, 1])
        XCTAssertEqual(hw.log, [])
    }

    func testLeaseExpiryReleases() throws {
        let hw = FakeFans()
        let g = FanGovernor(hardware: hw, markerPath: marker)
        try g.setTargets([4500, 4500], lease: 10, now: t0)
        XCTAssertFalse(g.checkLease(now: t0.addingTimeInterval(9.9)))
        XCTAssertTrue(g.holding)
        XCTAssertTrue(g.checkLease(now: t0.addingTimeInterval(10)))
        XCTAssertEqual(hw.modes, [0, 0])
        XCTAssertFalse(g.holding)
    }

    func testLeaseIsRenewedAndBounded() throws {
        let hw = FakeFans()
        let g = FanGovernor(hardware: hw, markerPath: marker)
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
        let g = FanGovernor(hardware: hw, markerPath: marker)
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
        let g = FanGovernor(hardware: hw, markerPath: marker)
        g.reconcileAtStart()
        XCTAssertEqual(hw.modes, [0, 0])
        XCTAssertFalse(markerExists)
    }

    func testReconcileAtStartWithoutMarkerTouchesNothing() {
        let hw = FakeFans()
        hw.modes = [1, 1]
        let g = FanGovernor(hardware: hw, markerPath: marker)
        g.reconcileAtStart()
        XCTAssertEqual(hw.modes, [1, 1])
    }
}
