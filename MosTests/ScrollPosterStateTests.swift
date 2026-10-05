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
        sut?.stopKeeper()
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

    // MARK: - Display-link refresh-rate recovery

    func testRateVerification_displayTransitionSurvivesRecreateAndRestartsCleanly() {
        sut.startDisplayTransitionRateVerification()
        let initial = sut.rateVerificationStateForTests
        XCTAssertTrue(initial.isTransition)
        XCTAssertEqual(initial.remainingChecks, 4)
        guard let initialTimer = initial.timer else {
            XCTFail("Display transition should arm a verification timer")
            return
        }
        XCTAssertTrue(initialTimer.isValid)

        // A screen-change rebuild must not replace the transition check sequence.
        sut.scheduleRateVerificationAfterCreate()
        let afterRecreate = sut.rateVerificationStateForTests
        XCTAssertTrue(afterRecreate.isTransition)
        XCTAssertEqual(afterRecreate.remainingChecks, 4)
        XCTAssertTrue(afterRecreate.timer === initialTimer)
        XCTAssertTrue(initialTimer.isValid)

        // A new transition should cancel the old sequence and start a fresh one.
        sut.startDisplayTransitionRateVerification()
        let restarted = sut.rateVerificationStateForTests
        XCTAssertTrue(restarted.isTransition)
        XCTAssertEqual(restarted.remainingChecks, 4)
        XCTAssertFalse(initialTimer.isValid)
        guard let restartedTimer = restarted.timer else {
            XCTFail("Restarted transition should arm a new verification timer")
            return
        }
        XCTAssertFalse(restartedTimer === initialTimer)
        XCTAssertTrue(restartedTimer.isValid)

        sut.stopKeeper()
        let stopped = sut.rateVerificationStateForTests
        XCTAssertFalse(stopped.isTransition)
        XCTAssertEqual(stopped.remainingChecks, 0)
        XCTAssertNil(stopped.timer)
        XCTAssertFalse(restartedTimer.isValid)
    }

    func testRateVerification_displayWakeOrReconnectKeepsCheckingUntilRatesDiverge() {
        // Both APIs can temporarily report 60 Hz while a 120 Hz display returns.
        let transitional = ScrollPoster.rateVerificationDecision(
            linkHz: 60, displayHz: 60, ratio: 0.7, isTransition: true, remainingChecks: 2
        )
        XCTAssertFalse(transitional.rebuild)
        XCTAssertTrue(transitional.continueChecking)

        let settledDisplay = ScrollPoster.rateVerificationDecision(
            linkHz: 60, displayHz: 120, ratio: 0.7, isTransition: true, remainingChecks: 1
        )
        XCTAssertTrue(settledDisplay.rebuild)
        XCTAssertTrue(settledDisplay.continueChecking)
    }

    func testRateVerification_afterWakeStopsWhenChecksAreExhausted() {
        let decision = ScrollPoster.rateVerificationDecision(
            linkHz: 60, displayHz: 60, ratio: 0.7, isTransition: true, remainingChecks: 0
        )
        XCTAssertFalse(decision.rebuild)
        XCTAssertFalse(decision.continueChecking)
    }

    func testRateVerification_normalMatchingRatesStopImmediately() {
        let decision = ScrollPoster.rateVerificationDecision(
            linkHz: 120, displayHz: 120, ratio: 0.7, isTransition: false, remainingChecks: 2
        )
        XCTAssertFalse(decision.rebuild)
        XCTAssertFalse(decision.continueChecking)

        let temporaryNormal = ScrollPoster.rateVerificationDecision(
            linkHz: 60, displayHz: 60, ratio: 0.7, isTransition: false, remainingChecks: 2
        )
        let temporaryTransition = ScrollPoster.rateVerificationDecision(
            linkHz: 60, displayHz: 60, ratio: 0.7, isTransition: true, remainingChecks: 2
        )
        XCTAssertFalse(temporaryNormal.continueChecking)
        XCTAssertTrue(temporaryTransition.continueChecking)
    }

    func testRateVerification_invalidRateRetriesDuringTransitionWindow() {
        let decision = ScrollPoster.rateVerificationDecision(
            linkHz: -1, displayHz: 120, ratio: 0.7, isTransition: true, remainingChecks: 1
        )
        XCTAssertFalse(decision.rebuild)
        XCTAssertTrue(decision.continueChecking)
    }

    func testRateVerification_mismatchOnLastCheckRebuildsWithoutAnotherRetry() {
        let decision = ScrollPoster.rateVerificationDecision(
            linkHz: 60, displayHz: 120, ratio: 0.7, isTransition: true, remainingChecks: 0
        )
        XCTAssertTrue(decision.rebuild)
        XCTAssertFalse(decision.continueChecking)
    }
}
