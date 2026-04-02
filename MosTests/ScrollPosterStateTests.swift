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

    // MARK: - resolveAxisInput

    func testResolveAxisInput_sameDirection_accumulatesBuffer() {
        var current = 10.0
        var buffer = 50.0
        var delta = 12.0
        var reverseCandidate = ScrollReverseCandidateState()

        let decision = sut.resolveAxisInput(
            input: 8.0,
            speed: 2.0,
            amplification: 1.0,
            deadZone: 1.0,
            current: &current,
            buffer: &buffer,
            delta: &delta,
            reverseCandidate: &reverseCandidate
        )

        XCTAssertEqual(decision, .acceptedContinuation)
        XCTAssertEqual(current, 10.0, accuracy: 1e-10)
        XCTAssertEqual(buffer, 66.0, accuracy: 1e-10)
        XCTAssertEqual(delta, 8.0, accuracy: 1e-10)
        XCTAssertEqual(reverseCandidate, ScrollReverseCandidateState())
    }

    func testResolveAxisInput_firstOppositePulseWhileActive_isIgnored() {
        var current = 40.0
        var buffer = 100.0
        var delta = 12.0
        var reverseCandidate = ScrollReverseCandidateState()

        let decision = sut.resolveAxisInput(
            input: -8.0,
            speed: 2.0,
            amplification: 1.0,
            deadZone: 1.0,
            current: &current,
            buffer: &buffer,
            delta: &delta,
            reverseCandidate: &reverseCandidate
        )

        XCTAssertEqual(decision, .ignoredOppositePulse)
        XCTAssertEqual(current, 40.0, accuracy: 1e-10)
        XCTAssertEqual(buffer, 100.0, accuracy: 1e-10)
        XCTAssertEqual(delta, 12.0, accuracy: 1e-10)
        XCTAssertEqual(reverseCandidate.sign, -1.0, accuracy: 1e-10)
        XCTAssertEqual(reverseCandidate.count, 1)
    }

    func testResolveAxisInput_secondOppositePulseWhileActive_acceptsReversal() {
        var current = 40.0
        var buffer = 100.0
        var delta = 12.0
        var reverseCandidate = ScrollReverseCandidateState(sign: -1.0, count: 1)

        let decision = sut.resolveAxisInput(
            input: -8.0,
            speed: 2.0,
            amplification: 1.0,
            deadZone: 1.0,
            current: &current,
            buffer: &buffer,
            delta: &delta,
            reverseCandidate: &reverseCandidate
        )

        XCTAssertEqual(decision, .acceptedReversal)
        XCTAssertEqual(current, 0.0, accuracy: 1e-10)
        XCTAssertEqual(buffer, -16.0, accuracy: 1e-10)
        XCTAssertEqual(delta, -8.0, accuracy: 1e-10)
        XCTAssertEqual(reverseCandidate, ScrollReverseCandidateState())
    }

    func testResolveAxisInput_oppositePulseWithoutResidual_acceptsImmediately() {
        var current = 0.0
        var buffer = 0.0
        var delta = 12.0
        var reverseCandidate = ScrollReverseCandidateState()

        let decision = sut.resolveAxisInput(
            input: -8.0,
            speed: 2.0,
            amplification: 1.0,
            deadZone: 1.0,
            current: &current,
            buffer: &buffer,
            delta: &delta,
            reverseCandidate: &reverseCandidate
        )

        XCTAssertEqual(decision, .acceptedReversal)
        XCTAssertEqual(current, 0.0, accuracy: 1e-10)
        XCTAssertEqual(buffer, -16.0, accuracy: 1e-10)
        XCTAssertEqual(delta, -8.0, accuracy: 1e-10)
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
}
