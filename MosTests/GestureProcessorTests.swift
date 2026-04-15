//
//  GestureProcessorTests.swift
//  MosTests
//  GestureProcessor 状态机单元测试
//  Created by Claude on 2026/4/15.
//  Copyright © 2026 Caldis. All rights reserved.
//

import XCTest
@testable import Mos_Debug

final class GestureProcessorTests: XCTestCase {

    // MARK: - Helpers

    /// 创建用于测试的 GestureBinding (默认中键触发)
    private func makeGestureBinding(
        code: UInt16 = 2,               // 中键 button code = 2
        upAction: String? = "missionControl",
        downAction: String? = "appExpose",
        leftAction: String? = "moveSpaceLeft",
        rightAction: String? = "moveSpaceRight",
        threshold: Double = 30.0
    ) -> GestureBinding {
        let trigger = RecordedEvent(
            type: .mouse,
            code: code,
            modifiers: 0,
            displayComponents: ["🖱3"],
            deviceFilter: nil
        )
        return GestureBinding(
            triggerEvent: trigger,
            upAction: upAction,
            downAction: downAction,
            leftAction: leftAction,
            rightAction: rightAction,
            threshold: threshold
        )
    }

    /// 创建 mouse InputEvent
    private func makeMouseEvent(code: UInt16, phase: InputPhase) -> InputEvent {
        return InputEvent(
            type: .mouse,
            code: code,
            modifiers: CGEventFlags(rawValue: 0),
            phase: phase,
            source: .hidPP,
            device: nil
        )
    }

    /// 创建最小化 CGEvent (用于 handleButtonEvent 的 cgEvent 参数)
    private func makeCGMouseEvent(type: CGEventType = .otherMouseDown) -> CGEvent {
        return CGEvent(source: CGEventSource(stateID: .hidSystemState))!
    }

    override func setUp() {
        super.setUp()
        Options.shared.gestures.binding = []
        GestureProcessor.shared.invalidateCache()
        GestureProcessor.shared.clearState()
        MouseInteractionSessionController.shared.setTestingMotionTapHooks()
    }

    override func tearDown() {
        GestureProcessor.shared.clearState()
        Options.shared.gestures.binding = []
        GestureProcessor.shared.invalidateCache()
        MouseInteractionSessionController.shared.clearTestingMotionTapHooks()
        super.tearDown()
    }

    // MARK: - Direction Resolution Tests

    func testResolveDirection_upwardMovement() {
        let direction = GestureProcessor.shared.resolveDirection(dx: 0, dy: -50, threshold: 30)
        XCTAssertEqual(direction, .up, "Negative deltaY (mouse up) should resolve to .up")
    }

    func testResolveDirection_downwardMovement() {
        let direction = GestureProcessor.shared.resolveDirection(dx: 0, dy: 50, threshold: 30)
        XCTAssertEqual(direction, .down, "Positive deltaY (mouse down) should resolve to .down")
    }

    func testResolveDirection_leftMovement() {
        let direction = GestureProcessor.shared.resolveDirection(dx: -50, dy: 0, threshold: 30)
        XCTAssertEqual(direction, .left, "Negative deltaX should resolve to .left")
    }

    func testResolveDirection_rightMovement() {
        let direction = GestureProcessor.shared.resolveDirection(dx: 50, dy: 0, threshold: 30)
        XCTAssertEqual(direction, .right, "Positive deltaX should resolve to .right")
    }

    func testResolveDirection_belowThreshold_returnsNil() {
        let direction = GestureProcessor.shared.resolveDirection(dx: 0, dy: -10, threshold: 30)
        XCTAssertNil(direction, "Delta below threshold should not resolve to any direction")
    }

    func testResolveDirection_exactlyAtThreshold_resolves() {
        let direction = GestureProcessor.shared.resolveDirection(dx: 0, dy: -30, threshold: 30)
        XCTAssertEqual(direction, .up, "Delta exactly at threshold should resolve")
    }

    func testResolveDirection_diagonal45degrees_returnsNil() {
        // Equal x and y movement — no dominant axis, diagonal ratio not met
        let direction = GestureProcessor.shared.resolveDirection(dx: 50, dy: -50, threshold: 30)
        XCTAssertNil(direction, "45-degree diagonal movement should not trigger any direction")
    }

    func testResolveDirection_slightlyOffDiagonal_returnsNil() {
        // dx=40, dy=-30: ratio = 40/30 = 1.33 < 1.5 — not dominant enough
        let direction = GestureProcessor.shared.resolveDirection(dx: 40, dy: -30, threshold: 30)
        XCTAssertNil(direction, "Diagonal movement with insufficient ratio should not trigger")
    }

    func testResolveDirection_dominantAxis_passesRatio() {
        // dx=60, dy=-10: ratio = 60/10 = 6.0 >= 1.5 — clearly horizontal
        let direction = GestureProcessor.shared.resolveDirection(dx: 60, dy: -10, threshold: 30)
        XCTAssertEqual(direction, .right, "Clearly dominant horizontal movement should resolve to .right")
    }

    func testResolveDirection_pureVertical_noXComponent() {
        // dx=0, dy=-50: zero division handled by guard
        let direction = GestureProcessor.shared.resolveDirection(dx: 0, dy: -50, threshold: 30)
        XCTAssertEqual(direction, .up)
    }

    // MARK: - State Machine Tests

    func testHandleButtonEvent_idle_noMatch_passthrough() {
        // No gesture bindings registered → passthrough
        let event = makeMouseEvent(code: 2, phase: .down)
        let cgEvent = makeCGMouseEvent()
        let result = GestureProcessor.shared.handleButtonEvent(event, cgEvent: cgEvent)
        XCTAssertEqual(result, .passthrough)
    }

    func testHandleButtonEvent_idle_match_consumed() {
        let binding = makeGestureBinding(code: 2)
        Options.shared.gestures.binding = [binding]
        GestureProcessor.shared.invalidateCache()

        let event = makeMouseEvent(code: 2, phase: .down)
        let cgEvent = makeCGMouseEvent()
        let result = GestureProcessor.shared.handleButtonEvent(event, cgEvent: cgEvent)
        XCTAssertEqual(result, .consumed, "Matching button down should be consumed (gesture pending)")
    }

    func testHandleButtonEvent_pending_triggerReleased_consumed() {
        let binding = makeGestureBinding(code: 2)
        Options.shared.gestures.binding = [binding]
        GestureProcessor.shared.invalidateCache()

        // Down → pending
        let downEvent = makeMouseEvent(code: 2, phase: .down)
        _ = GestureProcessor.shared.handleButtonEvent(downEvent, cgEvent: makeCGMouseEvent())

        // Up of trigger → consumed (click replay)
        let upEvent = makeMouseEvent(code: 2, phase: .up)
        let result = GestureProcessor.shared.handleButtonEvent(upEvent, cgEvent: makeCGMouseEvent())
        XCTAssertEqual(result, .consumed, "Releasing trigger without reaching threshold should be consumed")
    }

    func testHandleButtonEvent_pending_nonTriggerReleased_passthrough() {
        let binding = makeGestureBinding(code: 2)
        Options.shared.gestures.binding = [binding]
        GestureProcessor.shared.invalidateCache()

        // Middle button down → pending
        let downEvent = makeMouseEvent(code: 2, phase: .down)
        _ = GestureProcessor.shared.handleButtonEvent(downEvent, cgEvent: makeCGMouseEvent())

        // Release a DIFFERENT button → passthrough (not the trigger)
        let otherUpEvent = makeMouseEvent(code: 3, phase: .up)
        let result = GestureProcessor.shared.handleButtonEvent(otherUpEvent, cgEvent: makeCGMouseEvent())
        XCTAssertEqual(result, .passthrough)
    }

    func testHandleButtonEvent_afterGestureActive_triggerReleased_consumed() {
        let binding = makeGestureBinding(code: 2, threshold: 10.0)
        Options.shared.gestures.binding = [binding]
        GestureProcessor.shared.invalidateCache()

        // Trigger down → pending
        let downEvent = makeMouseEvent(code: 2, phase: .down)
        _ = GestureProcessor.shared.handleButtonEvent(downEvent, cgEvent: makeCGMouseEvent())

        // Simulate motion that crosses threshold (directly call handleMotionEvent)
        let motionEvent = makeCGMotionEvent(deltaX: 0, deltaY: -50)
        GestureProcessor.shared.handleMotionEvent(motionEvent)

        // Trigger up → consumed (gesture was already fired, just cleanup)
        let upEvent = makeMouseEvent(code: 2, phase: .up)
        let result = GestureProcessor.shared.handleButtonEvent(upEvent, cgEvent: makeCGMouseEvent())
        XCTAssertEqual(result, .consumed)
    }

    // MARK: - GestureBinding Matching Tests

    func testGestureBinding_matchingPriority_higherModifierCountWins() {
        // Two bindings: one with modifier, one without — higher modifier count should match
        let noMod = RecordedEvent(type: .mouse, code: 2, modifiers: 0, displayComponents: ["🖱3"], deviceFilter: nil)
        let withMod = RecordedEvent(type: .mouse, code: 2, modifiers: UInt(CGEventFlags.maskCommand.rawValue), displayComponents: ["⌘", "🖱3"], deviceFilter: nil)

        let bindingNoMod = GestureBinding(triggerEvent: noMod, upAction: "missionControl")
        let bindingWithMod = GestureBinding(triggerEvent: withMod, upAction: "appExpose")

        Options.shared.gestures.binding = [bindingNoMod, bindingWithMod]
        GestureProcessor.shared.invalidateCache()

        // Event with Command held → should match bindingWithMod (higher priority)
        let event = InputEvent(
            type: .mouse, code: 2,
            modifiers: .maskCommand,
            phase: .down, source: .hidPP, device: nil
        )
        let result = GestureProcessor.shared.handleButtonEvent(event, cgEvent: makeCGMouseEvent())
        XCTAssertEqual(result, .consumed)
    }

    // MARK: - Direction to Action Mapping Tests

    func testGestureBinding_actionForDirection() {
        let binding = makeGestureBinding(
            upAction: "missionControl",
            downAction: "appExpose",
            leftAction: "moveSpaceLeft",
            rightAction: "moveSpaceRight"
        )
        XCTAssertEqual(binding.action(for: .up), "missionControl")
        XCTAssertEqual(binding.action(for: .down), "appExpose")
        XCTAssertEqual(binding.action(for: .left), "moveSpaceLeft")
        XCTAssertEqual(binding.action(for: .right), "moveSpaceRight")
    }

    func testGestureBinding_withAction_returnsUpdatedCopy() {
        let binding = makeGestureBinding(upAction: nil)
        let updated = binding.withAction("missionControl", for: .up)
        XCTAssertEqual(updated.action(for: .up), "missionControl")
        XCTAssertNil(binding.action(for: .up), "Original should be unchanged")
    }

    func testGestureBinding_hasAnyAction_trueWhenAtLeastOneActionSet() {
        let binding = GestureBinding(
            triggerEvent: RecordedEvent(type: .mouse, code: 2, modifiers: 0, displayComponents: ["🖱3"], deviceFilter: nil),
            upAction: "missionControl"
        )
        XCTAssertTrue(binding.hasAnyAction)
    }

    func testGestureBinding_hasAnyAction_falseWhenNoActions() {
        let binding = GestureBinding(
            triggerEvent: RecordedEvent(type: .mouse, code: 2, modifiers: 0, displayComponents: ["🖱3"], deviceFilter: nil)
        )
        XCTAssertFalse(binding.hasAnyAction)
    }

    // MARK: - Motion Tap State Tests

    func testMotionTap_startsWhenGestureBegins() {
        let binding = makeGestureBinding(code: 2)
        Options.shared.gestures.binding = [binding]
        GestureProcessor.shared.invalidateCache()

        let startExpectation = expectation(description: "Motion tap should start")
        MouseInteractionSessionController.shared.setTestingMotionTapHooks(
            start: { startExpectation.fulfill() },
            stop: {}
        )

        let event = makeMouseEvent(code: 2, phase: .down)
        _ = GestureProcessor.shared.handleButtonEvent(event, cgEvent: makeCGMouseEvent())

        waitForExpectations(timeout: 1.0)
    }

    func testMotionTap_stopsWhenGestureCancelled() {
        let binding = makeGestureBinding(code: 2)
        Options.shared.gestures.binding = [binding]
        GestureProcessor.shared.invalidateCache()

        var stopCalled = false
        MouseInteractionSessionController.shared.setTestingMotionTapHooks(
            start: {},
            stop: { stopCalled = true }
        )

        // Start gesture
        let downEvent = makeMouseEvent(code: 2, phase: .down)
        _ = GestureProcessor.shared.handleButtonEvent(downEvent, cgEvent: makeCGMouseEvent())

        // Cancel gesture (trigger released without crossing threshold)
        let upEvent = makeMouseEvent(code: 2, phase: .up)
        _ = GestureProcessor.shared.handleButtonEvent(upEvent, cgEvent: makeCGMouseEvent())

        XCTAssertTrue(stopCalled, "Motion tap should stop when gesture is cancelled")
    }

    // MARK: - Codable Tests

    func testGestureBinding_codable_roundTrip() throws {
        let binding = makeGestureBinding()
        let data = try JSONEncoder().encode(binding)
        let decoded = try JSONDecoder().decode(GestureBinding.self, from: data)

        XCTAssertEqual(binding.id, decoded.id)
        XCTAssertEqual(binding.upAction, decoded.upAction)
        XCTAssertEqual(binding.downAction, decoded.downAction)
        XCTAssertEqual(binding.leftAction, decoded.leftAction)
        XCTAssertEqual(binding.rightAction, decoded.rightAction)
        XCTAssertEqual(binding.threshold, decoded.threshold)
        XCTAssertEqual(binding.isEnabled, decoded.isEnabled)
    }

    // MARK: - Private Helpers

    /// Create a minimal CGEvent with deltaX/deltaY field set
    private func makeCGMotionEvent(deltaX: Int64, deltaY: Int64) -> CGEvent {
        let event = CGEvent(source: CGEventSource(stateID: .hidSystemState))!
        event.type = .mouseMoved
        event.setIntegerValueField(.mouseEventDeltaX, value: deltaX)
        event.setIntegerValueField(.mouseEventDeltaY, value: deltaY)
        return event
    }
}
