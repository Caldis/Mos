//
//  ScrollEventTests.swift
//  MosTests
//
//  ScrollEvent 事件解析优先级/reverse/normalize/clear 测试 (Task 8)
//

import XCTest
@testable import Mos_Debug

final class ScrollEventTests: XCTestCase {

    // MARK: - 辅助: 创建 CGEvent

    /// 创建滚动事件并设置指定轴的值
    private func makeScrollEvent(
        deltaAxis1: Int64 = 0, ptDeltaAxis1: Double = 0.0, fixPtDeltaAxis1: Double = 0.0,
        deltaAxis2: Int64 = 0, ptDeltaAxis2: Double = 0.0, fixPtDeltaAxis2: Double = 0.0
    ) -> CGEvent? {
        guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: 0, wheel2: 0, wheel3: 0) else {
            return nil
        }
        event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: deltaAxis1)
        event.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: ptDeltaAxis1)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: fixPtDeltaAxis1)
        event.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: deltaAxis2)
        event.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: ptDeltaAxis2)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: fixPtDeltaAxis2)
        return event
    }

    // MARK: - 远程控制应用识别

    func testRemoteControlApplicationDetectsToDeskExecutableKeyword() {
        XCTAssertTrue(ScrollUtils.shared.isKnownRemoteControlApplication(
            executablePath: "/Applications/ToDesk.app/Contents/MacOS/ToDesk",
            bundleIdentifier: nil
        ))
    }

    func testRemoteControlApplicationDetectsToDeskBundleIdentifierKeyword() {
        XCTAssertTrue(ScrollUtils.shared.isKnownRemoteControlApplication(
            executablePath: nil,
            bundleIdentifier: "com.youqu.todesk"
        ))
    }

    func testRemoteControlApplicationRequiresRawPassthroughForToDesk() {
        XCTAssertTrue(ScrollUtils.shared.needsRawScrollPassthrough(
            executablePath: "/Library/Application Support/ToDesk/ToDesk_Service",
            bundleIdentifier: nil
        ))
    }

    func testRemoteControlApplicationDoesNotRequireRawPassthroughForOtherRemoteApps() {
        XCTAssertTrue(ScrollUtils.shared.isKnownRemoteControlApplication(
            executablePath: nil,
            bundleIdentifier: "com.teamviewer.TeamViewer"
        ))
        XCTAssertFalse(ScrollUtils.shared.needsRawScrollPassthrough(
            executablePath: nil,
            bundleIdentifier: "com.teamviewer.TeamViewer"
        ))
    }

    // MARK: - initEvent: 优先级 (scrollPt > scrollFixPt > scrollFix)

    func testInitEvent_prefersPtOverFixPt() throws {
        // CGEvent scrollWheelEventPointDelta 字段会截断小数部分, 10.5 实际存储为 10.0
        let cgEvent = try XCTUnwrap(makeScrollEvent(deltaAxis1: 3, ptDeltaAxis1: 10.0, fixPtDeltaAxis1: 5.0))
        let scrollEvent = ScrollEvent(with: cgEvent)

        XCTAssertEqual(scrollEvent.Y.usableValue, 10.0, "scrollPt should take priority")
        XCTAssertFalse(scrollEvent.Y.fixed, "scrollPt-based data should not be marked as fixed")
        XCTAssertTrue(scrollEvent.Y.valid)
    }

    func testInitEvent_prefersFixPtOverFix() throws {
        let cgEvent = try XCTUnwrap(makeScrollEvent(deltaAxis1: 3, ptDeltaAxis1: 0.0, fixPtDeltaAxis1: 5.0))
        let scrollEvent = ScrollEvent(with: cgEvent)

        XCTAssertEqual(scrollEvent.Y.usableValue, 5.0, "scrollFixPt should be used when scrollPt is 0")
        XCTAssertTrue(scrollEvent.Y.fixed, "scrollFixPt-based data should be marked as fixed")
        XCTAssertTrue(scrollEvent.Y.valid)
    }

    func testInitEvent_fallsBackToFix() throws {
        let cgEvent = try XCTUnwrap(makeScrollEvent(deltaAxis1: 3, ptDeltaAxis1: 0.0, fixPtDeltaAxis1: 0.0))
        let scrollEvent = ScrollEvent(with: cgEvent)

        XCTAssertEqual(scrollEvent.Y.usableValue, 3.0, "scrollFix should be used as fallback")
        XCTAssertTrue(scrollEvent.Y.fixed, "scrollFix-based data should be marked as fixed")
        XCTAssertTrue(scrollEvent.Y.valid)
    }

    func testInitEvent_allZero_notValid() throws {
        let cgEvent = try XCTUnwrap(makeScrollEvent())
        let scrollEvent = ScrollEvent(with: cgEvent)

        XCTAssertFalse(scrollEvent.Y.valid, "all-zero data should not be valid")
        XCTAssertEqual(scrollEvent.Y.usableValue, 0.0)
    }

    // MARK: - initEvent: X 轴

    func testInitEvent_xAxis_prefersPt() throws {
        let cgEvent = try XCTUnwrap(makeScrollEvent(deltaAxis2: 2, ptDeltaAxis2: 7.0, fixPtDeltaAxis2: 3.0))
        let scrollEvent = ScrollEvent(with: cgEvent)

        XCTAssertEqual(scrollEvent.X.usableValue, 7.0, "X axis scrollPt should take priority")
        XCTAssertFalse(scrollEvent.X.fixed)
        XCTAssertTrue(scrollEvent.X.valid)
    }

    func testInitEvent_xAxis_fallbackToFix() throws {
        let cgEvent = try XCTUnwrap(makeScrollEvent(deltaAxis2: -4))
        let scrollEvent = ScrollEvent(with: cgEvent)

        XCTAssertEqual(scrollEvent.X.usableValue, -4.0)
        XCTAssertTrue(scrollEvent.X.fixed)
        XCTAssertTrue(scrollEvent.X.valid)
    }

    // MARK: - reverse (Y 轴)

    func testReverseY_negatesAllYFields() throws {
        let cgEvent = try XCTUnwrap(makeScrollEvent(deltaAxis1: 5, ptDeltaAxis1: 10.0, fixPtDeltaAxis1: 7.5))
        let scrollEvent = ScrollEvent(with: cgEvent)

        ScrollEvent.reverseY(scrollEvent)

        // usableValue 应该取反
        XCTAssertEqual(scrollEvent.Y.usableValue, -10.0, accuracy: 1e-10)

        // CGEvent 字段也应该取反
        let newDelta = scrollEvent.event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
        XCTAssertEqual(newDelta, -5)

        let newPt = scrollEvent.event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)
        XCTAssertEqual(newPt, -10.0, accuracy: 1e-10)

        let newFixPt = scrollEvent.event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
        XCTAssertEqual(newFixPt, -7.5, accuracy: 1e-10)
    }

    func testReverseY_doubleReverse_restoresOriginal() throws {
        let cgEvent = try XCTUnwrap(makeScrollEvent(deltaAxis1: 3, ptDeltaAxis1: 6.0, fixPtDeltaAxis1: 4.5))
        let scrollEvent = ScrollEvent(with: cgEvent)

        ScrollEvent.reverseY(scrollEvent)
        ScrollEvent.reverseY(scrollEvent)

        XCTAssertEqual(scrollEvent.Y.usableValue, 6.0, accuracy: 1e-10, "double reverse should restore original")
    }

    // MARK: - reverse (X 轴)

    func testReverseX_negatesAllXFields() throws {
        let cgEvent = try XCTUnwrap(makeScrollEvent(deltaAxis2: 3, ptDeltaAxis2: 8.0, fixPtDeltaAxis2: 4.0))
        let scrollEvent = ScrollEvent(with: cgEvent)

        ScrollEvent.reverseX(scrollEvent)

        XCTAssertEqual(scrollEvent.X.usableValue, -8.0, accuracy: 1e-10)

        let newDelta = scrollEvent.event.getIntegerValueField(.scrollWheelEventDeltaAxis2)
        XCTAssertEqual(newDelta, -3)
    }

    // MARK: - normalize (Y 轴)

    func testNormalizeY_positiveBelowThreshold_clampsUp() throws {
        // CGEvent scrollWheelEventPointDelta 截断小数, 使用 fixPtDelta 来传递小数值
        let cgEvent = try XCTUnwrap(makeScrollEvent(fixPtDeltaAxis1: 0.5))
        let scrollEvent = ScrollEvent(with: cgEvent)

        let threshold = 2.0
        ScrollEvent.normalizeY(scrollEvent, threshold)

        XCTAssertEqual(scrollEvent.Y.usableValue, threshold, accuracy: 1e-10,
            "positive value below threshold should be clamped up to threshold")
    }

    func testNormalizeY_negativeBelowThreshold_clampsDown() throws {
        let cgEvent = try XCTUnwrap(makeScrollEvent(ptDeltaAxis1: -0.5))
        let scrollEvent = ScrollEvent(with: cgEvent)

        let threshold = 2.0
        ScrollEvent.normalizeY(scrollEvent, threshold)

        XCTAssertEqual(scrollEvent.Y.usableValue, -threshold, accuracy: 1e-10,
            "negative value below threshold should be clamped to -threshold")
    }

    func testNormalizeY_aboveThreshold_unchanged() throws {
        let cgEvent = try XCTUnwrap(makeScrollEvent(ptDeltaAxis1: 5.0))
        let scrollEvent = ScrollEvent(with: cgEvent)

        let threshold = 2.0
        ScrollEvent.normalizeY(scrollEvent, threshold)

        XCTAssertEqual(scrollEvent.Y.usableValue, 5.0, accuracy: 1e-10,
            "value above threshold should remain unchanged")
    }

    // MARK: - normalize (X 轴)

    func testNormalizeX_positiveBelowThreshold_clampsUp() throws {
        // CGEvent scrollWheelEventPointDelta 截断小数, 使用 fixPtDelta 来传递小数值
        let cgEvent = try XCTUnwrap(makeScrollEvent(fixPtDeltaAxis2: 0.3))
        let scrollEvent = ScrollEvent(with: cgEvent)

        let threshold = 1.0
        ScrollEvent.normalizeX(scrollEvent, threshold)

        XCTAssertEqual(scrollEvent.X.usableValue, threshold, accuracy: 1e-10)
    }

    // MARK: - clear (Y 轴)

    func testClearY_zerosAllYFields() throws {
        let cgEvent = try XCTUnwrap(makeScrollEvent(deltaAxis1: 5, ptDeltaAxis1: 10.0, fixPtDeltaAxis1: 7.5))
        let scrollEvent = ScrollEvent(with: cgEvent)

        ScrollEvent.clearY(scrollEvent)

        XCTAssertEqual(scrollEvent.Y.scrollFix, 0)
        XCTAssertEqual(scrollEvent.Y.scrollPt, 0.0, accuracy: 1e-10)
        XCTAssertEqual(scrollEvent.Y.scrollFixPt, 0.0, accuracy: 1e-10)
        XCTAssertEqual(scrollEvent.Y.usableValue, 0.0, accuracy: 1e-10)

        // CGEvent 字段也应该被清零
        XCTAssertEqual(scrollEvent.event.getIntegerValueField(.scrollWheelEventDeltaAxis1), 0)
        XCTAssertEqual(scrollEvent.event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1), 0.0, accuracy: 1e-10)
        XCTAssertEqual(scrollEvent.event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1), 0.0, accuracy: 1e-10)
    }

    func testClearY_doesNotAffectXAxis() throws {
        let cgEvent = try XCTUnwrap(makeScrollEvent(deltaAxis1: 5, ptDeltaAxis1: 10.0, deltaAxis2: 3, ptDeltaAxis2: 6.0))
        let scrollEvent = ScrollEvent(with: cgEvent)

        ScrollEvent.clearY(scrollEvent)

        // X 轴不受影响
        XCTAssertEqual(scrollEvent.X.usableValue, 6.0, accuracy: 1e-10, "clearY should not affect X axis")
    }

    // MARK: - clear (X 轴)

    func testClearX_zerosAllXFields() throws {
        let cgEvent = try XCTUnwrap(makeScrollEvent(deltaAxis2: 3, ptDeltaAxis2: 6.0, fixPtDeltaAxis2: 4.0))
        let scrollEvent = ScrollEvent(with: cgEvent)

        ScrollEvent.clearX(scrollEvent)

        XCTAssertEqual(scrollEvent.X.scrollFix, 0)
        XCTAssertEqual(scrollEvent.X.scrollPt, 0.0, accuracy: 1e-10)
        XCTAssertEqual(scrollEvent.X.scrollFixPt, 0.0, accuracy: 1e-10)
        XCTAssertEqual(scrollEvent.X.usableValue, 0.0, accuracy: 1e-10)
    }

    func testClearX_doesNotAffectYAxis() throws {
        let cgEvent = try XCTUnwrap(makeScrollEvent(deltaAxis1: 5, ptDeltaAxis1: 10.0, deltaAxis2: 3, ptDeltaAxis2: 6.0))
        let scrollEvent = ScrollEvent(with: cgEvent)

        ScrollEvent.clearX(scrollEvent)

        XCTAssertEqual(scrollEvent.Y.usableValue, 10.0, accuracy: 1e-10, "clearX should not affect Y axis")
    }

    // MARK: - 负值 scrollFix

    func testInitEvent_negativeDeltaFix() throws {
        let cgEvent = try XCTUnwrap(makeScrollEvent(deltaAxis1: -7))
        let scrollEvent = ScrollEvent(with: cgEvent)

        XCTAssertEqual(scrollEvent.Y.usableValue, -7.0)
        XCTAssertTrue(scrollEvent.Y.fixed)
        XCTAssertTrue(scrollEvent.Y.valid)
    }

    // MARK: - axisData 结构体默认值

    func testAxisData_defaults() {
        let data = axisData()
        XCTAssertEqual(data.scrollFix, 0)
        XCTAssertEqual(data.scrollPt, 0.0)
        XCTAssertEqual(data.scrollFixPt, 0.0)
        XCTAssertFalse(data.fixed)
        XCTAssertFalse(data.valid)
        XCTAssertEqual(data.usableValue, 0.0)
    }
}
