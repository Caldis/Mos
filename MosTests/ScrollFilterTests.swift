//
//  ScrollFilterTests.swift
//  MosTests
//
//  ScrollFilter 曲线滤波测试 (Task 6)
//

import CoreGraphics
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
        _ = sut.fill(with: (y: 10.0, x: 5.0), timing: FrameTiming(interval: 1.0 / 120, enabled: true))
        sut.reset()
        let val = sut.value()
        XCTAssertEqual(val.y, 0.0, accuracy: 1e-10)
        XCTAssertEqual(val.x, 0.0, accuracy: 1e-10)
        let firstFrame = sut.fill(with: (y: 10.0, x: 5.0))
        XCTAssertEqual(firstFrame.y, 0.0, accuracy: 1e-10)
        XCTAssertEqual(firstFrame.x, 0.0, accuracy: 1e-10)
    }

    // MARK: - fill: 首次填充

    func testFill_firstCall_smoothsFromZero() {
        let result = sut.fill(with: (y: 10.0, x: 0.0))
        XCTAssertEqual(result.y, 0.0, accuracy: 1e-10)
        XCTAssertEqual(result.x, 0.0, accuracy: 1e-10)
    }

    // MARK: - fill: 连续填充产生平滑效果

    func testFill_secondCall_advancesToNextSmoothedValue() {
        _ = sut.fill(with: (y: 10.0, x: 0.0))
        let result2 = sut.fill(with: (y: 10.0, x: 0.0))
        XCTAssertEqual(result2.y, 2.3, accuracy: 1e-10)
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

        // The first reversed frame still emits the value scheduled by the previous frame.
        _ = sut.fill(with: (y: -10.0, x: 0.0))
        let oneStepAfter = sut.value().y

        _ = sut.fill(with: (y: -10.0, x: 0.0))
        let twoStepsAfter = sut.value().y

        // 由于平滑, 方向变化不会立即完全反转
        XCTAssertGreaterThan(beforeChange, 0.0)
        // 第二次反向 fill 后, 值应该比第一次反向 fill 后更小 (开始向负方向移动)
        XCTAssertLessThan(twoStepsAfter, oneStepAfter, "direction change should start moving value toward new target after smoothing delay")
    }

    // MARK: - value 与 fill 返回值一致

    func testFill_returnValue_matchesValue() {
        let fillResult = sut.fill(with: (y: 7.0, x: 3.0))
        let valueResult = sut.value()
        XCTAssertEqual(fillResult.y, valueResult.y, accuracy: 1e-10)
        XCTAssertEqual(fillResult.x, valueResult.x, accuracy: 1e-10)
    }

    func testNormalizationUsesExactLegacyCoefficientsAt60Hz() {
        let timing = FrameTiming(interval: 1.0 / 60, enabled: true)
        let legacy = FrameTiming(interval: 1.0 / 144, enabled: false)
        XCTAssertEqual(timing.scale, 1)
        XCTAssertEqual(legacy.scale, 1)
        for coefficient in [0.0, 0.09, 0.23, 0.5, 0.77, 1.0] {
            XCTAssertEqual(timing.fraction(coefficient).bitPattern, coefficient.bitPattern)
            XCTAssertEqual(legacy.fraction(coefficient).bitPattern, coefficient.bitPattern)
        }
    }

    func testNormalizedDecayDependsOnElapsedTime() {
        for rate in [60, 120, 144] {
            let timing = FrameTiming(interval: 1.0 / Double(rate), enabled: true)
            let coefficient = timing.fraction(0.1)
            let remainder = (0..<rate).reduce(100.0) { value, _ in value * (1 - coefficient) }
            XCTAssertEqual(remainder, 100 * pow(0.9, 60), accuracy: 1e-12)
        }
    }

    func testNormalizedFilterConvergesOverTheSameTimeAt120Hz() {
        func replay(hz: Double) -> (distance: Double, timeToNinetyPercent: Double) {
            let filter = ScrollFilter()
            let interval = 1 / hz
            let timing = FrameTiming(interval: interval, enabled: true)
            let fraction = timing.fraction(0.1)
            var remaining = 100.0
            var distance = 0.0
            var timeToNinetyPercent: Double?
            for tick in 1...Int(3 * hz) {
                let delta = remaining * fraction
                remaining -= delta
                distance += filter.fill(with: (y: delta, x: 0), timing: timing).y
                if timeToNinetyPercent == nil && distance >= 90 {
                    timeToNinetyPercent = Double(tick) * interval
                }
            }
            return (distance, timeToNinetyPercent ?? .infinity)
        }

        let sixty = replay(hz: 60)
        let oneTwenty = replay(hz: 120)
        XCTAssertEqual(sixty.distance, 100, accuracy: 0.001)
        XCTAssertEqual(oneTwenty.distance, sixty.distance, accuracy: 0.001)
        XCTAssertEqual(oneTwenty.timeToNinetyPercent, sixty.timeToNinetyPercent, accuracy: 1 / 60)
    }

    func testNormalizedWindowCarriesVelocityAcrossRefreshRates() {
        _ = sut.fill(with: (y: 10, x: -10))
        let timing = FrameTiming(interval: 1.0 / 120, enabled: true)
        let result = sut.fill(with: (y: 5, x: -5), timing: timing)
        XCTAssertEqual(result.y, 1.15, accuracy: 1e-12)
        XCTAssertEqual(result.x, -1.15, accuracy: 1e-12)
    }

    func testNormalizationLimitsLongFramesAndIgnoresInvalidIntervals() {
        XCTAssertEqual(FrameTiming(interval: 8, enabled: true).scale, 6)
        XCTAssertEqual(FrameTiming(interval: 1.0 / 1000, enabled: true).scale, 0.125)
        for invalid in [0.0, -1.0, Double.infinity, Double.nan] {
            XCTAssertEqual(FrameTiming(interval: invalid, enabled: true).scale, 1)
        }
    }

    func testQuartzPointAccumulatorCarriesEachAxisForTheSameTarget() {
        var accumulator = ScrollPointAccumulator()
        let first = accumulator.quantize((0.75, -0.5), for: 1)
        XCTAssertEqual(first.y, 0)
        XCTAssertEqual(first.x, 0)

        let second = accumulator.quantize((0.75, -0.75), for: 1)
        XCTAssertEqual(second.y, 1)
        XCTAssertEqual(second.x, -1)

        let otherTarget = accumulator.quantize((0.75, -0.75), for: 2)
        XCTAssertEqual(otherTarget.y, 0)
        XCTAssertEqual(otherTarget.x, 0)
    }

    func testNormalizedQuartzPointDistanceAcrossRefreshRates() throws {
        let event = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
                                         wheel1: 0, wheel2: 0, wheel3: 0))
        for refreshRate in [60.0, 120.0, 144.0] {
            let timing = FrameTiming(interval: 1 / refreshRate, enabled: true)
            let transition = timing.fraction(0.1)
            let filter = ScrollFilter()
            var accumulator = ScrollPointAccumulator()
            var current = 0.0
            var distance = (y: 0.0, x: 0.0)
            for _ in 0..<Int(3 * refreshRate) {
                let step = Interpolator.lerp(src: current, dest: 100, trans: transition)
                current += step
                let frame = filter.fill(with: (step, -step), timing: timing)
                if frame.y > timing.scale {
                    let points = accumulator.quantize(frame, for: 1)
                    event.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: points.y)
                    event.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: points.x)
                    distance.y += event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)
                    distance.x += event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2)
                }
            }
            XCTAssertEqual(distance.y, 90, "Y at \(refreshRate) Hz")
            XCTAssertEqual(distance.x, -90, "X at \(refreshRate) Hz")
        }
    }
}
