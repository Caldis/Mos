//
//  ScrollPosterStateTests.swift
//  MosTests
//
//  ScrollPoster.shift 方法测试 (Task 10)
//

import XCTest
@testable import Mos_Debug

final class ScrollPosterStateTests: XCTestCase {

    var sut: ScrollPoster!

    override func setUp() {
        super.setUp()
        sut = ScrollPoster()
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    // MARK: - shift: shifting = false (默认)

    func testShift_whenNotShifting_passThrough() {
        // 默认 shifting = false
        let input = (y: 5.0, x: 3.0)
        let result = sut.shift(with: input)
        XCTAssertEqual(result.y, 5.0, accuracy: 1e-10)
        XCTAssertEqual(result.x, 3.0, accuracy: 1e-10)
    }

    func testShift_whenNotShifting_zeroValues() {
        let input = (y: 0.0, x: 0.0)
        let result = sut.shift(with: input)
        XCTAssertEqual(result.y, 0.0, accuracy: 1e-10)
        XCTAssertEqual(result.x, 0.0, accuracy: 1e-10)
    }

    func testShift_whenNotShifting_negativeValues() {
        let input = (y: -10.0, x: -7.0)
        let result = sut.shift(with: input)
        XCTAssertEqual(result.y, -10.0, accuracy: 1e-10)
        XCTAssertEqual(result.x, -7.0, accuracy: 1e-10)
    }

    // MARK: - shift: shifting = true, Y有值X无值 -> 交换到X

    func testShift_whenShifting_yHasValue_xIsZero_swapsToX() {
        sut.updateShifting(enable: true)
        let input = (y: 10.0, x: 0.0)
        let result = sut.shift(with: input)
        XCTAssertEqual(result.y, 0.0, accuracy: 1e-10, "Y should become X's original value (0)")
        XCTAssertEqual(result.x, 10.0, accuracy: 1e-10, "X should receive Y's original value")
    }

    func testShift_whenShifting_negativeY_xIsZero_swapsToX() {
        sut.updateShifting(enable: true)
        let input = (y: -8.0, x: 0.0)
        let result = sut.shift(with: input)
        XCTAssertEqual(result.y, 0.0, accuracy: 1e-10)
        XCTAssertEqual(result.x, -8.0, accuracy: 1e-10)
    }

    // MARK: - shift: shifting = true, X已有值 (如 MX Master 横向) -> 直接传递

    func testShift_whenShifting_bothAxesHaveValues_passThrough() {
        sut.updateShifting(enable: true)
        let input = (y: 5.0, x: 3.0)
        let result = sut.shift(with: input)
        // 当 y != 0 且 x != 0 时, 不交换 (某些鼠标已经显式转换方向)
        XCTAssertEqual(result.y, 5.0, accuracy: 1e-10)
        XCTAssertEqual(result.x, 3.0, accuracy: 1e-10)
    }

    func testShift_whenShifting_onlyXHasValue_passThrough() {
        sut.updateShifting(enable: true)
        let input = (y: 0.0, x: 7.0)
        let result = sut.shift(with: input)
        // y == 0, 不符合 y != 0 && x == 0 条件, 直接传递
        XCTAssertEqual(result.y, 0.0, accuracy: 1e-10)
        XCTAssertEqual(result.x, 7.0, accuracy: 1e-10)
    }

    func testShift_whenShifting_bothZero_passThrough() {
        sut.updateShifting(enable: true)
        let input = (y: 0.0, x: 0.0)
        let result = sut.shift(with: input)
        XCTAssertEqual(result.y, 0.0, accuracy: 1e-10)
        XCTAssertEqual(result.x, 0.0, accuracy: 1e-10)
    }

    // MARK: - updateShifting: 切换

    func testUpdateShifting_togglesShiftBehavior() {
        // 初始: 不 shift
        let input = (y: 10.0, x: 0.0)
        var result = sut.shift(with: input)
        XCTAssertEqual(result.y, 10.0, accuracy: 1e-10)

        // 启用 shift
        sut.updateShifting(enable: true)
        result = sut.shift(with: input)
        XCTAssertEqual(result.y, 0.0, accuracy: 1e-10)
        XCTAssertEqual(result.x, 10.0, accuracy: 1e-10)

        // 禁用 shift
        sut.updateShifting(enable: false)
        result = sut.shift(with: input)
        XCTAssertEqual(result.y, 10.0, accuracy: 1e-10)
        XCTAssertEqual(result.x, 0.0, accuracy: 1e-10)
    }

    // MARK: - 边界值

    func testShift_whenShifting_verySmallY_swapsToX() {
        sut.updateShifting(enable: true)
        let input = (y: 0.001, x: 0.0)
        let result = sut.shift(with: input)
        XCTAssertEqual(result.y, 0.0, accuracy: 1e-10)
        XCTAssertEqual(result.x, 0.001, accuracy: 1e-10)
    }

    func testShift_whenShifting_largeValues() {
        sut.updateShifting(enable: true)
        let input = (y: 10000.0, x: 0.0)
        let result = sut.shift(with: input)
        XCTAssertEqual(result.y, 0.0, accuracy: 1e-10)
        XCTAssertEqual(result.x, 10000.0, accuracy: 1e-10)
    }

    @MainActor
    func testNormalizedDisplayClockSelectsOnSessionStartAndCachesTheLayout() throws {
        let saved = Options.shared.scrollNormalizeTiming
        defer { Options.shared.scrollNormalizeTiming = saved }
        Options.shared.scrollNormalizeTiming = false

        let left = ScrollDisplayLayout.Display(id: 1, hz: 120)
        let right = ScrollDisplayLayout.Display(id: 2, hz: 60)
        let leftBounds = CGRect(x: 0, y: 0, width: 500, height: 300)
        let rightBounds = CGRect(x: 500, y: -50, width: 400, height: 350)
        var screens: [ScrollDisplayLayout.Screen] = [
            .init(display: left, bounds: leftBounds), .init(display: right, bounds: rightBounds),
        ]
        let display = TestFrameClock(.displayLink)
        let leftPoint = CGPoint(x: 12, y: 40)
        let rightPoint = CGPoint(x: 501, y: -10)
        var reads = 0
        let poster = ScrollPoster(makeDisplayClock: { display }, displayLayout: {
            reads += 1
            return ScrollDisplayLayout(screens: screens)
        })
        defer { poster.stop() }

        try input(to: poster, at: leftPoint)
        Options.shared.scrollNormalizeTiming = true
        try input(to: poster, at: rightPoint)
        XCTAssertFalse(poster.configSnapshotForTests.normalizesTiming)
        XCTAssertEqual(reads, 0)

        poster.stop()
        try input(to: poster, at: leftPoint)
        XCTAssertEqual(poster.frameClockKindForTests, .displayLink)
        XCTAssertEqual(poster.selectedDisplayForTests, left)
        try input(to: poster, at: rightPoint)
        XCTAssertEqual(poster.selectedDisplayForTests, left)

        poster.stop()
        try input(to: poster, at: CGPoint(x: 45, y: 10))
        XCTAssertEqual(poster.selectedDisplayForTests, left)
        XCTAssertEqual(reads, 1)

        poster.stop()
        try input(to: poster, at: rightPoint)
        XCTAssertEqual(poster.selectedDisplayForTests, right)
        XCTAssertEqual(reads, 1)

        let refreshed = ScrollDisplayLayout.Display(id: 2, hz: 90)
        screens[1] = .init(display: refreshed, bounds: rightBounds)
        poster.invalidateDisplayLayout()
        try input(to: poster, at: rightPoint)
        XCTAssertEqual(reads, 1)
        poster.stop()
        try input(to: poster, at: rightPoint)
        XCTAssertEqual(poster.selectedDisplayForTests, refreshed)
        XCTAssertEqual(reads, 2)

        poster.stop()
        Options.shared.scrollNormalizeTiming = false
        try input(to: poster, at: leftPoint)
        XCTAssertFalse(poster.configSnapshotForTests.normalizesTiming)
        XCTAssertEqual(reads, 2)
    }

    func testDisplayLayoutResolvesNegativeOriginsAndSharedEdges() {
        let main = ScrollDisplayLayout.Display(id: 1, hz: 120)
        let alternate = ScrollDisplayLayout.Display(id: 2, hz: 30)
        var layout = ScrollDisplayLayout(screens: [
            .init(display: main, bounds: CGRect(x: 0, y: 0, width: 500, height: 400)),
            .init(display: alternate, bounds: CGRect(x: -400, y: -100, width: 400, height: 500)),
        ])
        XCTAssertEqual(layout.display(at: CGPoint(x: -10, y: -40)), alternate)
        XCTAssertEqual(layout.display(at: CGPoint(x: -1, y: 40)), alternate)
        XCTAssertEqual(layout.display(at: CGPoint(x: 0, y: 40)), main)
        XCTAssertEqual(layout.display(at: CGPoint(x: 900, y: 0)), main)
    }

    @MainActor
    func testExplicitClockSelectionIsIndependentOfNormalization() throws {
        let saved = Options.shared.scrollNormalizeTiming
        defer { Options.shared.scrollNormalizeTiming = saved }
        let location = CGPoint(x: 50, y: 90)

        for kind in [ScrollFrameClockKind.displayLink, .fixedRate, .screen] {
            let display = TestFrameClock(.displayLink)
            let timer = TestFrameClock(.fixedRate)
            let screen = TestFrameClock(.screen)
            let selected = ScrollDisplayLayout.Display(id: 5, hz: 90)
            let poster = ScrollPoster(clockOverride: kind, makeDisplayClock: { display }, makeFixedClock: { timer },
                                      makeScreenClock: { displayID, _ in
                XCTAssertEqual(displayID, selected.id)
                return screen
            }, displayLayout: {
                ScrollDisplayLayout(screens: [.init(display: selected, bounds: CGRect(x: 0, y: 0, width: 500, height: 500))])
            })
            defer { poster.stop() }

            for normalize in [false, true] {
                Options.shared.scrollNormalizeTiming = normalize
                try input(to: poster, at: location)
                XCTAssertEqual(poster.frameClockKindForTests, kind)
                XCTAssertEqual(poster.configSnapshotForTests.normalizesTiming, normalize)
                poster.stop()
            }
        }
    }

    @MainActor
    func testUnavailableScreenClockFallsBackToTheTimerForTheRun() throws {
        let saved = Options.shared.scrollNormalizeTiming
        defer { Options.shared.scrollNormalizeTiming = saved }
        Options.shared.scrollNormalizeTiming = false

        let display = TestFrameClock(.displayLink, isAvailable: false)
        let timer = TestFrameClock(.fixedRate)
        var screenAttempts = 0
        let poster = ScrollPoster(clockOverride: .screen, makeDisplayClock: { display }, makeFixedClock: { timer },
                                  makeScreenClock: { _, _ in
            screenAttempts += 1
            return nil
        })
        defer { poster.stop() }

        XCTAssertTrue(poster.isAvailable)
        for _ in 0..<2 {
            try input(to: poster, at: .zero)
            XCTAssertEqual(poster.frameClockKindForTests, .fixedRate)
            XCTAssertFalse(poster.configSnapshotForTests.normalizesTiming)
            XCTAssertTrue(timer.isRunning)
            poster.stop()
        }
        XCTAssertEqual(screenAttempts, 1)
    }

    @MainActor
    func testScreenClockTimeoutKeepsTheCapturedNormalizationOnFallback() throws {
        let saved = Options.shared.scrollNormalizeTiming
        defer { Options.shared.scrollNormalizeTiming = saved }
        Options.shared.scrollNormalizeTiming = true

        let display = TestFrameClock(.displayLink)
        let timer = TestFrameClock(.fixedRate)
        let screen = TestFrameClock(.screen)
        var timeout: (() -> Void)?
        let poster = ScrollPoster(clockOverride: .screen, makeDisplayClock: { display }, makeFixedClock: { timer },
                                  makeScreenClock: { _, onTimeout in
            timeout = onTimeout
            return screen
        })
        defer { poster.stop() }

        try input(to: poster, at: .zero)
        XCTAssertEqual(poster.frameClockKindForTests, .screen)
        Options.shared.scrollNormalizeTiming = false
        try XCTUnwrap(timeout)()
        XCTAssertEqual(poster.frameClockKindForTests, .fixedRate)
        XCTAssertTrue(poster.configSnapshotForTests.normalizesTiming)
        XCTAssertTrue(timer.isRunning)
        XCTAssertFalse(screen.isRunning)
    }

    func testClockLaunchOverrideUsesTheLastExplicitValue() {
        let app = "Mos Debug"
        let flag = "--mos-scroll-clock"
        XCTAssertNil(ScrollFrameClockKind.launchOverride(in: [app]))
        XCTAssertNil(ScrollFrameClockKind.launchOverride(in: [app, flag]))
        XCTAssertNil(ScrollFrameClockKind.launchOverride(in: [app, flag, "unknown"]))
        XCTAssertEqual(ScrollFrameClockKind.launchOverride(in: [app, flag, "cvdisplaylink"]), .displayLink)
        XCTAssertEqual(ScrollFrameClockKind.launchOverride(in: [app, flag, "timer"]), .fixedRate)
        XCTAssertEqual(ScrollFrameClockKind.launchOverride(in: [app, flag, "timer", flag, "nsscreen"]), .screen)
    }

    @MainActor
    func testFixedClockCanStartWithoutAnAvailableDisplayLink() throws {
        let settings = Options.shared.scrollNormalizeTiming
        defer { Options.shared.scrollNormalizeTiming = settings }
        Options.shared.scrollNormalizeTiming = false

        let display = TestFrameClock(.displayLink, isAvailable: false)
        let fixed = TestFrameClock(.fixedRate)
        let poster = ScrollPoster(clockOverride: .fixedRate, makeDisplayClock: { display }, makeFixedClock: { fixed })
        defer { poster.stop() }

        XCTAssertTrue(poster.isAvailable)
        try input(to: poster, at: .zero)
        XCTAssertTrue(fixed.isRunning)
        XCTAssertNil(poster.selectedDisplayForTests)
    }

    @MainActor
    func testFixedClockRestartsWithThe60HzReferenceInterval() {
        let clock = FixedRateFrameClock()
        for _ in 0..<2 {
            XCTAssertTrue(clock.rebuild())
            XCTAssertFalse(clock.isRunning)

            let firstFrame = expectation(description: "First frame of this clock run")
            var firstInterval: CFTimeInterval?
            clock.onTick = { tick in
                guard firstInterval == nil else { return }
                firstInterval = tick.interval
                firstFrame.fulfill()
            }

            XCTAssertTrue(clock.start())
            wait(for: [firstFrame], timeout: 2)
            clock.stop()
            XCTAssertFalse(clock.isRunning)
            XCTAssertEqual(firstInterval ?? 0, 1.0 / 60, accuracy: 1e-10)
        }
    }

    private func input(to poster: ScrollPoster, at location: CGPoint) throws {
        let event = try XCTUnwrap(CGEvent(
            scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: 8, wheel2: 0, wheel3: 0
        ))
        event.location = location
        poster.update(event: event, duration: 0.1, y: 8, x: 0, speed: 1,
                      route: .adapter(TestScrollSink()), targetPID: ProcessInfo.processInfo.processIdentifier).tryStart()
    }

    private final class TestFrameClock: ScrollFrameClock {
        let kind: ScrollFrameClockKind
        var onTick: ((FrameTick) -> Void)?
        let isAvailable: Bool
        private(set) var isRunning = false

        init(_ kind: ScrollFrameClockKind, isAvailable: Bool = true) {
            self.kind = kind
            self.isAvailable = isAvailable
        }

        func prepare() {}
        func start() -> Bool {
            isRunning = true
            return true
        }
        func stop() { isRunning = false }
        func rebuild() -> Bool { start() }
        func startMonitoring() {}
        func stopMonitoring() {}
    }

    private final class TestScrollSink: ScrollOutputSink {
        func frame(y: Double, x: Double, at location: CGPoint) {}
        func end(at location: CGPoint) {}
    }
}
