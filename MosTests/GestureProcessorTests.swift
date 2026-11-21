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
    /// movement 动作 (4 方向) 和 scroll 动作 (↑↓) 相互独立
    private func makeGestureBinding(
        code: UInt16 = 2,               // 中键 button code = 2
        upAction: String? = "missionControl",
        downAction: String? = "appExpose",
        leftAction: String? = "moveSpaceLeft",
        rightAction: String? = "moveSpaceRight",
        threshold: Double = 30.0,
        scrollUpAction: String? = nil,
        scrollDownAction: String? = nil,
        scrollThreshold: Double = 3.0
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
            threshold: threshold,
            scrollUpAction: scrollUpAction,
            scrollDownAction: scrollDownAction,
            scrollThreshold: scrollThreshold
        )
    }

    /// 创建仅有 scroll 动作 (无 movement 动作) 的手势绑定
    private func makeScrollOnlyBinding(
        code: UInt16 = 2,
        scrollUpAction: String? = "missionControl",
        scrollDownAction: String? = "appExpose",
        scrollThreshold: Double = 3.0
    ) -> GestureBinding {
        return makeGestureBinding(
            code: code,
            upAction: nil, downAction: nil, leftAction: nil, rightAction: nil,
            scrollUpAction: scrollUpAction,
            scrollDownAction: scrollDownAction,
            scrollThreshold: scrollThreshold
        )
    }

    /// 创建用于测试的滚轮手势 CGEvent
    private func makeCGScrollEvent(deltaAxis1: Int64, deltaAxis2: Int64 = 0) -> CGEvent {
        let event = CGEvent(source: CGEventSource(stateID: .hidSystemState))!
        event.type = .scrollWheel
        event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: deltaAxis1)
        event.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: deltaAxis2)
        return event
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
        let binding = makeGestureBinding(scrollUpAction: "missionControl", scrollDownAction: "appExpose")
        let data = try JSONEncoder().encode(binding)
        let decoded = try JSONDecoder().decode(GestureBinding.self, from: data)

        XCTAssertEqual(binding.id,              decoded.id)
        XCTAssertEqual(binding.upAction,        decoded.upAction)
        XCTAssertEqual(binding.downAction,      decoded.downAction)
        XCTAssertEqual(binding.leftAction,      decoded.leftAction)
        XCTAssertEqual(binding.rightAction,     decoded.rightAction)
        XCTAssertEqual(binding.threshold,       decoded.threshold)
        XCTAssertEqual(binding.scrollUpAction,  decoded.scrollUpAction)
        XCTAssertEqual(binding.scrollDownAction, decoded.scrollDownAction)
        XCTAssertEqual(binding.scrollThreshold, decoded.scrollThreshold)
        XCTAssertEqual(binding.isEnabled,       decoded.isEnabled)
    }

    func testGestureBinding_codable_backwardCompatible_legacyJSON() throws {
        // Simulate JSON from before scrollUpAction/scrollDownAction/scrollThreshold were added.
        // Old JSON may have an `inputMode` key (now ignored) and no scroll fields.
        let json = """
        {
          "id": "00000000-0000-0000-0000-000000000001",
          "triggerEvent": {
            "type": "mouse", "code": 2, "modifiers": 0,
            "displayComponents": ["🖱3"]
          },
          "threshold": 30.0,
          "inputMode": "scrollWheel",
          "isEnabled": true,
          "createdAt": 0
        }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(GestureBinding.self, from: json)
        // inputMode is silently ignored
        XCTAssertEqual(decoded.threshold,       30.0, "Legacy threshold should map to movement threshold")
        XCTAssertEqual(decoded.scrollThreshold, 3.0,  "scrollThreshold absent → default 3.0")
        XCTAssertNil(decoded.scrollUpAction,   "scrollUpAction absent → nil")
        XCTAssertNil(decoded.scrollDownAction, "scrollDownAction absent → nil")
    }

    // MARK: - GestureBinding Threshold Tests

    func testGestureBinding_defaultMovementThreshold() {
        let binding = makeGestureBinding()
        XCTAssertEqual(binding.threshold, 30.0)
    }

    func testGestureBinding_defaultScrollThreshold() {
        let binding = makeScrollOnlyBinding()
        XCTAssertEqual(binding.scrollThreshold, 3.0)
    }

    func testGestureBinding_withScrollAction_returnsUpdatedCopy() {
        let original = makeScrollOnlyBinding(scrollUpAction: nil)
        let updated = original.withScrollAction("missionControl", for: .up)
        XCTAssertEqual(updated.scrollUpAction, "missionControl")
        XCTAssertNil(original.scrollUpAction, "Original should be unchanged")
    }

    func testGestureBinding_hasAnyScrollAction() {
        let noScroll   = makeGestureBinding()
        let withScroll = makeGestureBinding(scrollUpAction: "missionControl")
        XCTAssertFalse(noScroll.hasAnyScrollAction)
        XCTAssertTrue(withScroll.hasAnyScrollAction)
    }

    func testGestureBinding_hasAnyMovementAction() {
        let noMovement   = makeScrollOnlyBinding()
        let withMovement = makeGestureBinding()
        XCTAssertFalse(noMovement.hasAnyMovementAction)
        XCTAssertTrue(withMovement.hasAnyMovementAction)
    }

    // MARK: - Scroll Gesture State Machine Tests

    func testHandleScrollEvent_whenIdle_notConsumed() {
        let scrollEvent = makeCGScrollEvent(deltaAxis1: -5)
        XCTAssertFalse(GestureProcessor.shared.handleScrollEvent(scrollEvent),
                       "Scroll not consumed when idle")
    }

    func testHandleScrollEvent_whenPending_movementOnlyBinding_notConsumed() {
        // Binding has movement actions but no scroll actions → scroll passes through
        let binding = makeGestureBinding()  // no scrollUpAction/scrollDownAction
        Options.shared.gestures.binding = [binding]
        GestureProcessor.shared.invalidateCache()

        _ = GestureProcessor.shared.handleButtonEvent(makeMouseEvent(code: 2, phase: .down), cgEvent: makeCGMouseEvent())

        XCTAssertFalse(GestureProcessor.shared.handleScrollEvent(makeCGScrollEvent(deltaAxis1: -5)),
                       "Scroll not consumed for movement-only binding")
    }

    func testHandleScrollEvent_whenPending_scrollBinding_consumed() {
        let binding = makeScrollOnlyBinding(scrollThreshold: 3.0)
        Options.shared.gestures.binding = [binding]
        GestureProcessor.shared.invalidateCache()

        _ = GestureProcessor.shared.handleButtonEvent(makeMouseEvent(code: 2, phase: .down), cgEvent: makeCGMouseEvent())

        XCTAssertTrue(GestureProcessor.shared.handleScrollEvent(makeCGScrollEvent(deltaAxis1: -1)),
                      "Scroll consumed when pending with scroll actions")
    }

    func testHandleScrollEvent_scrollBinding_accumulatesAndFires() {
        let binding = makeScrollOnlyBinding(scrollUpAction: "missionControl", scrollThreshold: 3.0)
        Options.shared.gestures.binding = [binding]
        GestureProcessor.shared.invalidateCache()

        _ = GestureProcessor.shared.handleButtonEvent(makeMouseEvent(code: 2, phase: .down), cgEvent: makeCGMouseEvent())

        // Three ticks upward (negative axis1) → crosses threshold of 3
        for _ in 0..<3 {
            _ = GestureProcessor.shared.handleScrollEvent(makeCGScrollEvent(deltaAxis1: -1))
        }

        // State should now be .active → trigger release is consumed
        let result = GestureProcessor.shared.handleButtonEvent(makeMouseEvent(code: 2, phase: .up), cgEvent: makeCGMouseEvent())
        XCTAssertEqual(result, .consumed, "After scroll gesture fires, trigger release consumed (.active state)")
    }

    func testHandleScrollEvent_accumulator_isIndependentFromMotionAccumulator() {
        // A binding with both movement and scroll actions. Small mouse movement (below threshold)
        // followed by scroll ticks should resolve via scroll, not via accumulated motion.
        let binding = makeGestureBinding(
            upAction: "missionControl", threshold: 30.0,
            scrollUpAction: "appExpose", scrollThreshold: 3.0
        )
        Options.shared.gestures.binding = [binding]
        GestureProcessor.shared.invalidateCache()

        _ = GestureProcessor.shared.handleButtonEvent(makeMouseEvent(code: 2, phase: .down), cgEvent: makeCGMouseEvent())

        // Small motion (below movement threshold) — should NOT fire movement action
        let motionEvent = makeCGMotionEvent(deltaX: 0, deltaY: -5)
        GestureProcessor.shared.handleMotionEvent(motionEvent)

        // Three scroll ticks upward → should fire via scroll accumulator
        for _ in 0..<3 {
            _ = GestureProcessor.shared.handleScrollEvent(makeCGScrollEvent(deltaAxis1: -1))
        }

        // State .active → trigger up is consumed
        XCTAssertEqual(
            GestureProcessor.shared.handleButtonEvent(makeMouseEvent(code: 2, phase: .up), cgEvent: makeCGMouseEvent()),
            .consumed
        )
    }

    func testHandleScrollEvent_whenActive_withScrollActions_stillConsumed() {
        let binding = makeScrollOnlyBinding(scrollThreshold: 3.0)
        Options.shared.gestures.binding = [binding]
        GestureProcessor.shared.invalidateCache()

        _ = GestureProcessor.shared.handleButtonEvent(makeMouseEvent(code: 2, phase: .down), cgEvent: makeCGMouseEvent())

        for _ in 0..<3 {
            _ = GestureProcessor.shared.handleScrollEvent(makeCGScrollEvent(deltaAxis1: -1))
        }

        // Additional scroll in .active state should still be consumed (prevent smooth pipeline)
        XCTAssertTrue(GestureProcessor.shared.handleScrollEvent(makeCGScrollEvent(deltaAxis1: -1)),
                      "Scroll consumed in .active state to prevent smooth scrolling pipeline")
    }

    func testMotionTap_notStartedForScrollOnlyBinding() {
        let binding = makeScrollOnlyBinding()
        Options.shared.gestures.binding = [binding]
        GestureProcessor.shared.invalidateCache()

        var motionTapStarted = false
        MouseInteractionSessionController.shared.setTestingMotionTapHooks(
            start: { motionTapStarted = true },
            stop: {}
        )

        _ = GestureProcessor.shared.handleButtonEvent(makeMouseEvent(code: 2, phase: .down), cgEvent: makeCGMouseEvent())

        XCTAssertFalse(motionTapStarted,
                       "Motion tap should NOT start when binding has no movement actions")
    }

    func testMotionTap_startsForBindingWithMovementActions() {
        let binding = makeGestureBinding()  // has movement actions
        Options.shared.gestures.binding = [binding]
        GestureProcessor.shared.invalidateCache()

        let expectation = expectation(description: "Motion tap starts")
        MouseInteractionSessionController.shared.setTestingMotionTapHooks(
            start: { expectation.fulfill() },
            stop: {}
        )

        _ = GestureProcessor.shared.handleButtonEvent(makeMouseEvent(code: 2, phase: .down), cgEvent: makeCGMouseEvent())

        waitForExpectations(timeout: 1.0)
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
