//
//  ScrollFilterTests.swift
//  MosTests
//
//  ScrollFilter 曲线滤波测试 (Task 6)
//

import XCTest
@testable import Mos_Debug

final class ScrollFilterTests: XCTestCase {

    var sut: ScrollFilter!

    override func setUp() {
        super.setUp()
        sut = ScrollFilter()
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    // MARK: - 初始状态

    func testInitialValue_isZero() {
        let val = sut.value()
        XCTAssertEqual(val.y, 0.0, accuracy: 1e-10)
        XCTAssertEqual(val.x, 0.0, accuracy: 1e-10)
    }

    // MARK: - reset

    func testReset_clearsToZero() {
        _ = sut.fill(with: (y: 10.0, x: 5.0))
        sut.reset()
        let val = sut.value()
        XCTAssertEqual(val.y, 0.0, accuracy: 1e-10)
        XCTAssertEqual(val.x, 0.0, accuracy: 1e-10)
        // reset 后应与全新实例行为一致: 首次 fill 输出 0
        XCTAssertEqual(sut.fill(with: (y: 10.0, x: 0.0)).y, 0.0, accuracy: 1e-10)
    }

    // MARK: - fill: 首次填充

    func testFill_firstCall_smoothsFromZero() {
        // 平滑递推: output(n) = s(n-1), s(n) = s(n-1) + 0.23*(input - s(n-1)), s(0) = 0
        // 首次 fill(10): 输出 s(0) = 0, s(1) = 2.3
        let result = sut.fill(with: (y: 10.0, x: 0.0))
        XCTAssertEqual(result.y, 0.0, accuracy: 1e-10, "first fill Y should return the pre-smoothing state (0)")
        XCTAssertEqual(result.x, 0.0, accuracy: 1e-10)
    }

    // MARK: - fill: 连续填充产生平滑效果

    func testFill_secondCall_advancesToNextSmoothedValue() {
        // 第一次 fill(10): s(1) = 0 + 0.23*10 = 2.3
        _ = sut.fill(with: (y: 10.0, x: 0.0))

        // 第二次 fill(10): 输出 s(1) = 2.3
        let result2 = sut.fill(with: (y: 10.0, x: 0.0))
        XCTAssertEqual(result2.y, 2.3, accuracy: 1e-10, "second fill should return smoothed value from previous step")
    }

    func testFill_convergesToTarget_afterMultipleCalls() {
        // 反复填充相同值, 应该逐渐逼近目标
        let target = 10.0
        var lastY = 0.0
        for _ in 0..<20 {
            let result = sut.fill(with: (y: target, x: 0.0))
            XCTAssertGreaterThanOrEqual(result.y, lastY, "value should be monotonically non-decreasing toward target")
            lastY = result.y
        }
        // 经过足够多次迭代后应该接近目标
        XCTAssertEqual(lastY, target, accuracy: 0.1, "after many fills, should converge close to target")
    }

    // MARK: - fill: X 轴独立

    func testFill_xAxisIndependent() {
        _ = sut.fill(with: (y: 0.0, x: 20.0))
        let val = sut.value()
        XCTAssertEqual(val.y, 0.0, accuracy: 1e-10)
        XCTAssertEqual(val.x, 0.0, accuracy: 1e-10, "first fill x should also be smoothed from zero")

        _ = sut.fill(with: (y: 0.0, x: 20.0))
        let val2 = sut.value()
        XCTAssertEqual(val2.y, 0.0, accuracy: 1e-10, "Y axis should remain at zero")
        XCTAssertGreaterThan(val2.x, 0.0, "X axis should start advancing")
    }

    // MARK: - fill: 负值

    func testFill_negativeValues() {
        _ = sut.fill(with: (y: -10.0, x: -5.0))
        _ = sut.fill(with: (y: -10.0, x: -5.0))
        let val = sut.value()
        XCTAssertLessThan(val.y, 0.0, "negative fill should produce negative smoothed values")
        XCTAssertLessThan(val.x, 0.0, "negative fill should produce negative smoothed values")
    }

    // MARK: - fill: 方向突变

    func testFill_directionChange_smoothsTransition() {
        // 先正向填充几次
        for _ in 0..<5 {
            _ = sut.fill(with: (y: 10.0, x: 0.0))
        }
        let beforeChange = sut.value().y

        // 然后反向填充
        // polish 的 value() 返回 curveWindow[0], 即上一轮 curveWindow[1]
        // 因此第一次反向 fill 的返回值仍然反映前一轮的惯性 (会继续上升)
        _ = sut.fill(with: (y: -10.0, x: 0.0))
        let oneStepAfter = sut.value().y

        // 再填充一次反向值, 此时 curveWindow[0] 才会开始体现反向趋势
        _ = sut.fill(with: (y: -10.0, x: 0.0))
        let twoStepsAfter = sut.value().y

        // 由于平滑, 方向变化不会立即完全反转
        XCTAssertGreaterThan(beforeChange, 0.0)
        // 第二次反向 fill 后, 值应该比第一次反向 fill 后更小 (开始向负方向移动)
        XCTAssertLessThan(twoStepsAfter, oneStepAfter, "direction change should start moving value toward new target after smoothing delay")
    }

    // MARK: - 平滑递推序列验证 (等价性规格: 与旧版 5 元素曲线窗口的可观察输出一致)

    func testFill_outputSequence_matchesSmoothingRecurrence() {
        // output(n) = s(n-1); s(n) = s(n-1) + 0.23*(10 - s(n-1))
        // 序列: 0, 2.3, 2.3+0.23*7.7=4.071, ...
        XCTAssertEqual(sut.fill(with: (y: 10.0, x: 10.0)).y, 0.0, accuracy: 1e-10)
        XCTAssertEqual(sut.fill(with: (y: 10.0, x: 10.0)).y, 2.3, accuracy: 1e-10)
        let third = sut.fill(with: (y: 10.0, x: 10.0))
        XCTAssertEqual(third.y, 4.071, accuracy: 1e-10)
        XCTAssertEqual(third.x, 4.071, accuracy: 1e-10, "两轴递推应一致")
    }

    // MARK: - value 与 fill 返回值一致

    func testFill_returnValue_matchesValue() {
        let fillResult = sut.fill(with: (y: 7.0, x: 3.0))
        let valueResult = sut.value()
        XCTAssertEqual(fillResult.y, valueResult.y, accuracy: 1e-10)
        XCTAssertEqual(fillResult.x, valueResult.x, accuracy: 1e-10)
    }
}
