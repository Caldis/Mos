import XCTest
@testable import Mos_Debug

final class InputProcessorTests: XCTestCase {

    override func setUp() {
        super.setUp()
        Options.shared.buttons.binding = []
        ButtonUtils.shared.invalidateCache()
        MouseInteractionSessionController.shared.setTestingMotionTapHooks()
        MouseInteractionSessionController.shared.clearAllSessions()
        ShortcutExecutor.shared.setTestingMouseEventObserver()
        InputProcessor.shared.clearActiveBindings()
        ScrollCore.shared.dashScroll = false
        ScrollCore.shared.dashAmplification = 1.0
        ScrollCore.shared.toggleScroll = false
        ScrollCore.shared.blockSmooth = false
        ScrollCore.shared.dashKeyHeld = false
        ScrollCore.shared.toggleKeyHeld = false
        ScrollCore.shared.blockKeyHeld = false
    }

    override func tearDown() {
        InputProcessor.shared.clearActiveBindings()
        ScrollCore.shared.dashScroll = false
        ScrollCore.shared.dashAmplification = 1.0
        ScrollCore.shared.toggleScroll = false
        ScrollCore.shared.blockSmooth = false
        ScrollCore.shared.dashKeyHeld = false
        ScrollCore.shared.toggleKeyHeld = false
        ScrollCore.shared.blockKeyHeld = false
        MouseInteractionSessionController.shared.clearAllSessions()
        MouseInteractionSessionController.shared.clearTestingMotionTapHooks()
        ShortcutExecutor.shared.clearTestingMouseEventObserver()
        Options.shared.buttons.binding = []
        ButtonUtils.shared.invalidateCache()
        super.tearDown()
    }

    func testProcess_downEvent_consumedWhenBindingMatches() {
        let trigger = RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil)
        let binding = ButtonBinding(triggerEvent: trigger, systemShortcutName: "custom::56:0", isEnabled: true)
        Options.shared.buttons.binding = [binding]
        ButtonUtils.shared.invalidateCache()

        let event = InputEvent(type: .mouse, code: 3, modifiers: CGEventFlags(rawValue: 0),
                               phase: .down, source: .hidPP, device: nil)
        let result = InputProcessor.shared.process(event)
        XCTAssertEqual(result, .consumed)
    }

    func testProcess_upEvent_consumedViaActiveBindings() {
        let trigger = RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil)
        let binding = ButtonBinding(triggerEvent: trigger, systemShortcutName: "custom::56:0", isEnabled: true)
        Options.shared.buttons.binding = [binding]
        ButtonUtils.shared.invalidateCache()

        let downEvent = InputEvent(type: .mouse, code: 3, modifiers: CGEventFlags(rawValue: 0),
                                   phase: .down, source: .hidPP, device: nil)
        _ = InputProcessor.shared.process(downEvent)

        let upEvent = InputEvent(type: .mouse, code: 3, modifiers: CGEventFlags(rawValue: 0),
                                 phase: .up, source: .hidPP, device: nil)
        let result = InputProcessor.shared.process(upEvent)
        XCTAssertEqual(result, .consumed)
    }

    func testProcess_upEvent_passthroughWithoutPriorDown() {
        let event = InputEvent(type: .mouse, code: 99, modifiers: CGEventFlags(rawValue: 0),
                               phase: .up, source: .hidPP, device: nil)
        let result = InputProcessor.shared.process(event)
        XCTAssertEqual(result, .passthrough)
    }

    func testProcess_upEvent_matchesDespiteModifierChange() {
        let trigger = RecordedEvent(type: .mouse, code: 3, modifiers: UInt(CGEventFlags.maskCommand.rawValue),
                                    displayComponents: ["⌘", "🖱4"], deviceFilter: nil)
        let binding = ButtonBinding(triggerEvent: trigger, systemShortcutName: "custom::56:0", isEnabled: true)
        Options.shared.buttons.binding = [binding]
        ButtonUtils.shared.invalidateCache()

        let downEvent = InputEvent(type: .mouse, code: 3, modifiers: .maskCommand,
                                   phase: .down, source: .hidPP, device: nil)
        _ = InputProcessor.shared.process(downEvent)

        // Up with ⌘ already released (modifiers = 0)
        let upEvent = InputEvent(type: .mouse, code: 3, modifiers: CGEventFlags(rawValue: 0),
                                 phase: .up, source: .hidPP, device: nil)
        let result = InputProcessor.shared.process(upEvent)
        XCTAssertEqual(result, .consumed)
    }

    func testSystemShortcutExecutionModes_mouseActionsStateful_nonMouseTrigger() {
        XCTAssertEqual(SystemShortcut.mouseLeftClick.executionMode, .stateful)
        XCTAssertEqual(SystemShortcut.logiSmartShiftToggle.executionMode, .trigger)
    }

    func testProcess_upEvent_passthroughForTriggerShortcut() {
        let trigger = RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil)
        let binding = ButtonBinding(triggerEvent: trigger, systemShortcutName: "logiSmartShiftToggle", isEnabled: true)
        Options.shared.buttons.binding = [binding]
        ButtonUtils.shared.invalidateCache()

        let downEvent = InputEvent(type: .mouse, code: 3, modifiers: .init(rawValue: 0),
                                   phase: .down, source: .hidPP, device: nil)
        XCTAssertEqual(InputProcessor.shared.process(downEvent), .consumed)

        let upEvent = InputEvent(type: .mouse, code: 3, modifiers: .init(rawValue: 0),
                                 phase: .up, source: .hidPP, device: nil)
        XCTAssertEqual(InputProcessor.shared.process(upEvent), .passthrough)
    }

    func testProcess_upEvent_consumedForStatefulMouseShortcut() {
        let trigger = RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil)
        let binding = ButtonBinding(triggerEvent: trigger, systemShortcutName: "mouseLeftClick", isEnabled: true)
        Options.shared.buttons.binding = [binding]
        ButtonUtils.shared.invalidateCache()

        let downEvent = InputEvent(type: .mouse, code: 3, modifiers: .init(rawValue: 0),
                                   phase: .down, source: .hidPP, device: nil)
        XCTAssertEqual(InputProcessor.shared.process(downEvent), .consumed)

        let upEvent = InputEvent(type: .mouse, code: 3, modifiers: .init(rawValue: 0),
                                 phase: .up, source: .hidPP, device: nil)
        XCTAssertEqual(InputProcessor.shared.process(upEvent), .consumed)
    }

    func testProcess_statefulMouseShortcut_doesNotSetVirtualModifierFlags() {
        let trigger = RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil)
        let binding = ButtonBinding(triggerEvent: trigger, systemShortcutName: "mouseLeftClick", isEnabled: true)
        Options.shared.buttons.binding = [binding]
        ButtonUtils.shared.invalidateCache()

        let downEvent = InputEvent(type: .mouse, code: 3, modifiers: .init(rawValue: 0),
                                   phase: .down, source: .hidPP, device: nil)
        XCTAssertEqual(InputProcessor.shared.process(downEvent), .consumed)
        XCTAssertEqual(InputProcessor.shared.activeModifierFlags, 0)
    }

    func testProcess_statefulMouseShortcut_startsAndStopsMouseInteractionSession() {
        let trigger = RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil)
        let binding = ButtonBinding(triggerEvent: trigger, systemShortcutName: "mouseLeftClick", isEnabled: true)
        Options.shared.buttons.binding = [binding]
        ButtonUtils.shared.invalidateCache()

        let downEvent = InputEvent(type: .mouse, code: 3, modifiers: .init(rawValue: 0),
                                   phase: .down, source: .hidPP, device: nil)
        XCTAssertEqual(InputProcessor.shared.process(downEvent), .consumed)
        XCTAssertTrue(MouseInteractionSessionController.shared.isMotionTapRunning)
        XCTAssertEqual(MouseInteractionSessionController.shared.activeSessionCount, 1)

        let upEvent = InputEvent(type: .mouse, code: 3, modifiers: .init(rawValue: 0),
                                 phase: .up, source: .hidPP, device: nil)
        XCTAssertEqual(InputProcessor.shared.process(upEvent), .consumed)
        XCTAssertFalse(MouseInteractionSessionController.shared.isMotionTapRunning)
        XCTAssertEqual(MouseInteractionSessionController.shared.activeSessionCount, 0)
    }

    func testProcess_virtualModifierShortcut_startsAndStopsMotionTapForMouseInteractionPropagation() {
        let trigger = RecordedEvent(type: .mouse, code: 6, modifiers: 0, displayComponents: ["🖱7"], deviceFilter: nil)
        let binding = ButtonBinding(triggerEvent: trigger, systemShortcutName: "custom::58:0", isEnabled: true)
        Options.shared.buttons.binding = [binding]
        ButtonUtils.shared.invalidateCache()

        let downEvent = InputEvent(type: .mouse, code: 6, modifiers: .init(rawValue: 0),
                                   phase: .down, source: .hidPP, device: nil)
        XCTAssertEqual(InputProcessor.shared.process(downEvent), .consumed)
        XCTAssertTrue(MouseInteractionSessionController.shared.isMotionTapRunning)
        XCTAssertEqual(InputProcessor.shared.activeModifierFlags, CGEventFlags.maskAlternate.rawValue)

        let upEvent = InputEvent(type: .mouse, code: 6, modifiers: .init(rawValue: 0),
                                 phase: .up, source: .hidPP, device: nil)
        XCTAssertEqual(InputProcessor.shared.process(upEvent), .consumed)
        XCTAssertFalse(MouseInteractionSessionController.shared.isMotionTapRunning)
        XCTAssertEqual(InputProcessor.shared.activeModifierFlags, 0)
    }

    func testProcess_predefinedModifierShortcut_usesStatefulModifierFlow() {
        let trigger = RecordedEvent(type: .mouse, code: 6, modifiers: 0, displayComponents: ["🖱7"], deviceFilter: nil)
        let binding = ButtonBinding(triggerEvent: trigger, systemShortcutName: "modifierOption", isEnabled: true)
        Options.shared.buttons.binding = [binding]
        ButtonUtils.shared.invalidateCache()

        let downEvent = InputEvent(type: .mouse, code: 6, modifiers: .init(rawValue: 0),
                                   phase: .down, source: .hidPP, device: nil)
        XCTAssertEqual(InputProcessor.shared.process(downEvent), .consumed)
        XCTAssertTrue(MouseInteractionSessionController.shared.isMotionTapRunning)
        XCTAssertEqual(InputProcessor.shared.activeModifierFlags, CGEventFlags.maskAlternate.rawValue)

        let upEvent = InputEvent(type: .mouse, code: 6, modifiers: .init(rawValue: 0),
                                 phase: .up, source: .hidPP, device: nil)
        XCTAssertEqual(InputProcessor.shared.process(upEvent), .consumed)
        XCTAssertFalse(MouseInteractionSessionController.shared.isMotionTapRunning)
        XCTAssertEqual(InputProcessor.shared.activeModifierFlags, 0)
    }

    func testResolveAction_predefinedModifierShortcut_mapsToCustomModifierKey() {
        guard let action = ShortcutExecutor.shared.resolveAction(named: "modifierShift") else {
            return XCTFail("Expected predefined modifier shortcut to resolve")
        }

        switch action {
        case .customKey(let code, let modifiers):
            XCTAssertEqual(code, KeyCode.shiftL)
            XCTAssertEqual(modifiers, 0)
        default:
            XCTFail("Expected predefined modifier shortcut to reuse custom modifier execution")
        }
    }

    func testResolveAction_escapeShortcut_mapsToSystemShortcut() {
        guard let action = ShortcutExecutor.shared.resolveAction(named: "escapeKey") else {
            return XCTFail("Expected escape shortcut to resolve")
        }

        switch action {
        case .systemShortcut(let identifier):
            XCTAssertEqual(identifier, "escapeKey")
        default:
            XCTFail("Expected escape shortcut to use the system shortcut execution path")
        }
    }

    func testResolveAction_mosScrollActionsAreStateful() {
        for identifier in ["mosScrollDash", "mosScrollToggle", "mosScrollBlock"] {
            guard let action = ShortcutExecutor.shared.resolveAction(named: identifier) else {
                return XCTFail("Expected \(identifier) action to resolve")
            }

            XCTAssertEqual(action.executionMode, .stateful)
        }
    }

    func testProcess_mosScrollDash_downAndUpControlsDashState() {
        let trigger = RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil)
        let binding = ButtonBinding(triggerEvent: trigger, systemShortcutName: "mosScrollDash", isEnabled: true)
        Options.shared.buttons.binding = [binding]
        ButtonUtils.shared.invalidateCache()

        let downEvent = InputEvent(type: .mouse, code: 3, modifiers: .init(rawValue: 0),
                                   phase: .down, source: .hidPP, device: nil)
        XCTAssertEqual(InputProcessor.shared.process(downEvent), .consumed)
        XCTAssertTrue(ScrollCore.shared.dashScroll)
        XCTAssertEqual(ScrollCore.shared.dashAmplification, 5.0)

        let upEvent = InputEvent(type: .mouse, code: 3, modifiers: .init(rawValue: 0),
                                 phase: .up, source: .hidPP, device: nil)
        XCTAssertEqual(InputProcessor.shared.process(upEvent), .consumed)
        XCTAssertFalse(ScrollCore.shared.dashScroll)
        XCTAssertEqual(ScrollCore.shared.dashAmplification, 1.0)
    }

    func testProcess_mosScrollMiddleTapWithoutScroll_replaysOriginalMouseClick() {
        let trigger = RecordedEvent(type: .mouse, code: 2, modifiers: 0, displayComponents: ["🖱M"], deviceFilter: nil)
        let binding = ButtonBinding(triggerEvent: trigger, systemShortcutName: "mosScrollDash", isEnabled: true)
        Options.shared.buttons.binding = [binding]
        ButtonUtils.shared.invalidateCache()

        var observedEvents: [(type: CGEventType, buttonNumber: Int64, userData: Int64)] = []
        ShortcutExecutor.shared.setTestingMouseEventObserver { event in
            observedEvents.append((
                event.type,
                event.getIntegerValueField(.mouseEventButtonNumber),
                event.getIntegerValueField(.eventSourceUserData)
            ))
        }

        XCTAssertEqual(
            InputProcessor.shared.process(InputEvent(type: .mouse, code: 2, modifiers: .init(rawValue: 0), phase: .down, source: .hidPP, device: nil)),
            .consumed
        )
        XCTAssertTrue(ScrollCore.shared.dashScroll)

        XCTAssertEqual(
            InputProcessor.shared.process(InputEvent(type: .mouse, code: 2, modifiers: .init(rawValue: 0), phase: .up, source: .hidPP, device: nil)),
            .consumed
        )

        XCTAssertEqual(observedEvents.map(\.type), [.otherMouseDown, .otherMouseUp])
        XCTAssertEqual(observedEvents.map(\.buttonNumber), [2, 2])
        XCTAssertEqual(observedEvents.map(\.userData), [MosEventMarker.syntheticCustom, MosEventMarker.syntheticCustom])
        XCTAssertFalse(ScrollCore.shared.dashScroll)
    }

    func testProcess_mosScrollMiddleTapWithScrollUse_doesNotReplayOriginalMouseClick() {
        let trigger = RecordedEvent(type: .mouse, code: 2, modifiers: 0, displayComponents: ["🖱M"], deviceFilter: nil)
        let binding = ButtonBinding(triggerEvent: trigger, systemShortcutName: "mosScrollDash", isEnabled: true)
        Options.shared.buttons.binding = [binding]
        ButtonUtils.shared.invalidateCache()

        var observedEvents: [CGEventType] = []
        ShortcutExecutor.shared.setTestingMouseEventObserver { event in
            observedEvents.append(event.type)
        }

        XCTAssertEqual(
            InputProcessor.shared.process(InputEvent(type: .mouse, code: 2, modifiers: .init(rawValue: 0), phase: .down, source: .hidPP, device: nil)),
            .consumed
        )
        InputProcessor.shared.markMosScrollActionSessionsUsedForScroll()

        XCTAssertEqual(
            InputProcessor.shared.process(InputEvent(type: .mouse, code: 2, modifiers: .init(rawValue: 0), phase: .up, source: .hidPP, device: nil)),
            .consumed
        )

        XCTAssertTrue(observedEvents.isEmpty)
        XCTAssertFalse(ScrollCore.shared.dashScroll)
    }

    func testScrollCore_scrollWheelWhileMosScrollHeldSuppressesTapReplay() {
        let trigger = RecordedEvent(type: .mouse, code: 2, modifiers: 0, displayComponents: ["🖱M"], deviceFilter: nil)
        let binding = ButtonBinding(triggerEvent: trigger, systemShortcutName: "mosScrollDash", isEnabled: true)
        Options.shared.buttons.binding = [binding]
        ButtonUtils.shared.invalidateCache()

        var observedEvents: [CGEventType] = []
        ShortcutExecutor.shared.setTestingMouseEventObserver { event in
            observedEvents.append(event.type)
        }

        XCTAssertEqual(
            InputProcessor.shared.process(InputEvent(type: .mouse, code: 2, modifiers: .init(rawValue: 0), phase: .down, source: .hidPP, device: nil)),
            .consumed
        )

        guard let scrollEvent = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: 1, wheel2: 0, wheel3: 0) else {
            return XCTFail("Expected scroll wheel event to be creatable")
        }
        ScrollEvent.isTrackpadCallCount = ScrollEvent.isTrackpadCallSamplingRate - 1
        _ = ScrollCore.shared.scrollEventCallBack(CGEventTapProxy(bitPattern: 1)!, .scrollWheel, scrollEvent, nil)

        XCTAssertEqual(
            InputProcessor.shared.process(InputEvent(type: .mouse, code: 2, modifiers: .init(rawValue: 0), phase: .up, source: .hidPP, device: nil)),
            .consumed
        )

        XCTAssertTrue(observedEvents.isEmpty)
        XCTAssertFalse(ScrollCore.shared.dashScroll)
    }

    func testScrollCore_scrollWheelReleasesCGMosScrollSessionWhenPhysicalButtonIsNoLongerDown() {
        let trigger = RecordedEvent(type: .mouse, code: 2, modifiers: 0, displayComponents: ["🖱M"], deviceFilter: nil)
        let binding = ButtonBinding(triggerEvent: trigger, systemShortcutName: "mosScrollDash", isEnabled: true)
        Options.shared.buttons.binding = [binding]
        ButtonUtils.shared.invalidateCache()

        let downEvent = CGEvent(
            mouseEventSource: nil,
            mouseType: .otherMouseDown,
            mouseCursorPosition: CGPoint(x: 40, y: 40),
            mouseButton: .center
        )!
        downEvent.setIntegerValueField(.mouseEventButtonNumber, value: 2)

        XCTAssertEqual(InputProcessor.shared.process(InputEvent(fromCGEvent: downEvent)), .consumed)
        XCTAssertTrue(ScrollCore.shared.dashScroll)

        guard let scrollEvent = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: 1, wheel2: 0, wheel3: 0) else {
            return XCTFail("Expected scroll wheel event to be creatable")
        }
        ScrollEvent.isTrackpadCallCount = ScrollEvent.isTrackpadCallSamplingRate - 1
        _ = ScrollCore.shared.scrollEventCallBack(CGEventTapProxy(bitPattern: 1)!, .scrollWheel, scrollEvent, nil)

        XCTAssertFalse(ScrollCore.shared.dashScroll)
        XCTAssertEqual(ScrollCore.shared.dashAmplification, 1.0)
    }

    func testProcess_mosScrollCGMouseTapWithPointerMove_doesNotReplayOriginalMouseClick() {
        let trigger = RecordedEvent(type: .mouse, code: 2, modifiers: 0, displayComponents: ["🖱M"], deviceFilter: nil)
        let binding = ButtonBinding(triggerEvent: trigger, systemShortcutName: "mosScrollDash", isEnabled: true)
        Options.shared.buttons.binding = [binding]
        ButtonUtils.shared.invalidateCache()

        var observedEvents: [CGEventType] = []
        ShortcutExecutor.shared.setTestingMouseEventObserver { event in
            observedEvents.append(event.type)
        }

        let downEvent = CGEvent(
            mouseEventSource: nil,
            mouseType: .otherMouseDown,
            mouseCursorPosition: CGPoint(x: 40, y: 40),
            mouseButton: .center
        )!
        downEvent.setIntegerValueField(.mouseEventButtonNumber, value: 2)

        let upEvent = CGEvent(
            mouseEventSource: nil,
            mouseType: .otherMouseUp,
            mouseCursorPosition: CGPoint(x: 70, y: 40),
            mouseButton: .center
        )!
        upEvent.setIntegerValueField(.mouseEventButtonNumber, value: 2)

        XCTAssertEqual(InputProcessor.shared.process(InputEvent(fromCGEvent: downEvent)), .consumed)
        XCTAssertEqual(InputProcessor.shared.process(InputEvent(fromCGEvent: upEvent)), .consumed)

        XCTAssertTrue(observedEvents.isEmpty)
        XCTAssertFalse(ScrollCore.shared.dashScroll)
    }

    func testProcess_logiButtonCanTriggerMosScrollToggle() {
        let trigger = RecordedEvent(
            type: .mouse,
            code: 1007,
            modifiers: 0,
            displayComponents: ["[Logi]", "Forward Button"],
            deviceFilter: nil
        )
        let binding = ButtonBinding(triggerEvent: trigger, systemShortcutName: "mosScrollToggle", isEnabled: true)
        Options.shared.buttons.binding = [binding]
        ButtonUtils.shared.invalidateCache()

        XCTAssertEqual(
            InputProcessor.shared.process(InputEvent(type: .mouse, code: 1007, modifiers: .init(rawValue: 0), phase: .down, source: .hidPP, device: nil)),
            .consumed
        )
        XCTAssertTrue(ScrollCore.shared.toggleScroll)

        XCTAssertEqual(
            InputProcessor.shared.process(InputEvent(type: .mouse, code: 1007, modifiers: .init(rawValue: 0), phase: .up, source: .hidPP, device: nil)),
            .consumed
        )
        XCTAssertFalse(ScrollCore.shared.toggleScroll)
    }

    func testProcess_logiMosScrollForwardTapWithoutScroll_replaysForwardButton() {
        let trigger = RecordedEvent(
            type: .mouse,
            code: 1007,
            modifiers: 0,
            displayComponents: ["[Logi]", "Forward Button"],
            deviceFilter: nil
        )
        let binding = ButtonBinding(triggerEvent: trigger, systemShortcutName: "mosScrollToggle", isEnabled: true)
        Options.shared.buttons.binding = [binding]
        ButtonUtils.shared.invalidateCache()

        var observedEvents: [(type: CGEventType, buttonNumber: Int64)] = []
        ShortcutExecutor.shared.setTestingMouseEventObserver { event in
            observedEvents.append((event.type, event.getIntegerValueField(.mouseEventButtonNumber)))
        }

        XCTAssertEqual(
            InputProcessor.shared.process(InputEvent(type: .mouse, code: 1007, modifiers: .init(rawValue: 0), phase: .down, source: .hidPP, device: nil)),
            .consumed
        )
        XCTAssertEqual(
            InputProcessor.shared.process(InputEvent(type: .mouse, code: 1007, modifiers: .init(rawValue: 0), phase: .up, source: .hidPP, device: nil)),
            .consumed
        )

        XCTAssertEqual(observedEvents.map(\.type), [.otherMouseDown, .otherMouseUp])
        XCTAssertEqual(observedEvents.map(\.buttonNumber), [4, 4])
        XCTAssertFalse(ScrollCore.shared.toggleScroll)
    }

    func testProcess_mosScrollBlock_downAndUpControlsBlockState() {
        let trigger = RecordedEvent(type: .mouse, code: 5, modifiers: 0, displayComponents: ["🖱6"], deviceFilter: nil)
        let binding = ButtonBinding(triggerEvent: trigger, systemShortcutName: "mosScrollBlock", isEnabled: true)
        Options.shared.buttons.binding = [binding]
        ButtonUtils.shared.invalidateCache()

        XCTAssertEqual(
            InputProcessor.shared.process(InputEvent(type: .mouse, code: 5, modifiers: .init(rawValue: 0), phase: .down, source: .hidPP, device: nil)),
            .consumed
        )
        XCTAssertTrue(ScrollCore.shared.blockSmooth)

        XCTAssertEqual(
            InputProcessor.shared.process(InputEvent(type: .mouse, code: 5, modifiers: .init(rawValue: 0), phase: .up, source: .hidPP, device: nil)),
            .consumed
        )
        XCTAssertFalse(ScrollCore.shared.blockSmooth)
    }

    func testProcess_multipleMosScrollDashTriggers_releaseOneKeepsDashActive() {
        let firstTrigger = RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil)
        let secondTrigger = RecordedEvent(type: .mouse, code: 4, modifiers: 0, displayComponents: ["🖱5"], deviceFilter: nil)
        let firstBinding = ButtonBinding(triggerEvent: firstTrigger, systemShortcutName: "mosScrollDash", isEnabled: true)
        let secondBinding = ButtonBinding(triggerEvent: secondTrigger, systemShortcutName: "mosScrollDash", isEnabled: true)
        Options.shared.buttons.binding = [firstBinding, secondBinding]
        ButtonUtils.shared.invalidateCache()

        XCTAssertEqual(
            InputProcessor.shared.process(InputEvent(type: .mouse, code: 3, modifiers: .init(rawValue: 0), phase: .down, source: .hidPP, device: nil)),
            .consumed
        )
        XCTAssertTrue(ScrollCore.shared.dashScroll)

        XCTAssertEqual(
            InputProcessor.shared.process(InputEvent(type: .mouse, code: 4, modifiers: .init(rawValue: 0), phase: .down, source: .hidPP, device: nil)),
            .consumed
        )
        XCTAssertTrue(ScrollCore.shared.dashScroll)

        XCTAssertEqual(
            InputProcessor.shared.process(InputEvent(type: .mouse, code: 3, modifiers: .init(rawValue: 0), phase: .up, source: .hidPP, device: nil)),
            .consumed
        )
        XCTAssertTrue(ScrollCore.shared.dashScroll)

        XCTAssertEqual(
            InputProcessor.shared.process(InputEvent(type: .mouse, code: 4, modifiers: .init(rawValue: 0), phase: .up, source: .hidPP, device: nil)),
            .consumed
        )
        XCTAssertFalse(ScrollCore.shared.dashScroll)
    }

    func testProcess_mosScrollBindingDoesNotLatchWhenLegacyScrollHotkeySeesOnlyDown() {
        struct Case {
            let shortcutName: String
            let configureLegacyHotkey: (ScrollHotkey) -> Void
            let isRoleActive: () -> Bool
        }

        let originalDash = Options.shared.scroll.dash
        let originalToggle = Options.shared.scroll.toggle
        let originalBlock = Options.shared.scroll.block
        defer {
            Options.shared.scroll.dash = originalDash
            Options.shared.scroll.toggle = originalToggle
            Options.shared.scroll.block = originalBlock
        }

        let cases: [Case] = [
            Case(
                shortcutName: "mosScrollDash",
                configureLegacyHotkey: { Options.shared.scroll.dash = $0 },
                isRoleActive: { ScrollCore.shared.dashScroll }
            ),
            Case(
                shortcutName: "mosScrollToggle",
                configureLegacyHotkey: { Options.shared.scroll.toggle = $0 },
                isRoleActive: { ScrollCore.shared.toggleScroll }
            ),
            Case(
                shortcutName: "mosScrollBlock",
                configureLegacyHotkey: { Options.shared.scroll.block = $0 },
                isRoleActive: { ScrollCore.shared.blockSmooth }
            ),
        ]

        for testCase in cases {
            InputProcessor.shared.clearActiveBindings()
            ScrollCore.shared.dashScroll = false
            ScrollCore.shared.dashAmplification = 1.0
            ScrollCore.shared.toggleScroll = false
            ScrollCore.shared.blockSmooth = false
            ScrollCore.shared.dashKeyHeld = false
            ScrollCore.shared.toggleKeyHeld = false
            ScrollCore.shared.blockKeyHeld = false
            Options.shared.scroll.dash = nil
            Options.shared.scroll.toggle = nil
            Options.shared.scroll.block = nil

            let trigger = RecordedEvent(type: .mouse, code: 2, modifiers: 0, displayComponents: ["🖱M"], deviceFilter: nil)
            let binding = ButtonBinding(triggerEvent: trigger, systemShortcutName: testCase.shortcutName, isEnabled: true)
            Options.shared.buttons.binding = [binding]
            ButtonUtils.shared.invalidateCache()
            testCase.configureLegacyHotkey(ScrollHotkey(type: .mouse, code: 2))

            let legacyDownEvent = CGEvent(
                mouseEventSource: nil,
                mouseType: .otherMouseDown,
                mouseCursorPosition: CGPoint(x: 40, y: 40),
                mouseButton: .center
            )!
            legacyDownEvent.setIntegerValueField(.mouseEventButtonNumber, value: 2)
            _ = ScrollCore.shared.hotkeyEventCallBack(CGEventTapProxy(bitPattern: 1)!, .otherMouseDown, legacyDownEvent, nil)

            XCTAssertEqual(
                InputProcessor.shared.process(InputEvent(type: .mouse, code: 2, modifiers: .init(rawValue: 0), phase: .down, source: .hidPP, device: nil)),
                .consumed
            )
            XCTAssertTrue(testCase.isRoleActive(), "\(testCase.shortcutName) should be active while held")

            XCTAssertEqual(
                InputProcessor.shared.process(InputEvent(type: .mouse, code: 2, modifiers: .init(rawValue: 0), phase: .up, source: .hidPP, device: nil)),
                .consumed
            )
            XCTAssertFalse(testCase.isRoleActive(), "\(testCase.shortcutName) should release even if the legacy hotkey tap missed up")
        }
    }

    func testProcess_mouseSessionRemainsActiveAfterVirtualModifierReleasesUntilMouseUp() {
        let modifierTrigger = RecordedEvent(type: .mouse, code: 6, modifiers: 0, displayComponents: ["🖱7"], deviceFilter: nil)
        let mouseTrigger = RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil)
        let modifierBinding = ButtonBinding(triggerEvent: modifierTrigger, systemShortcutName: "custom::58:0", isEnabled: true)
        let mouseBinding = ButtonBinding(triggerEvent: mouseTrigger, systemShortcutName: "mouseLeftClick", isEnabled: true)
        Options.shared.buttons.binding = [modifierBinding, mouseBinding]
        ButtonUtils.shared.invalidateCache()

        XCTAssertEqual(
            InputProcessor.shared.process(InputEvent(type: .mouse, code: 3, modifiers: .init(rawValue: 0), phase: .down, source: .hidPP, device: nil)),
            .consumed
        )
        XCTAssertTrue(MouseInteractionSessionController.shared.isMotionTapRunning)
        XCTAssertEqual(MouseInteractionSessionController.shared.activeSessionCount, 1)

        XCTAssertEqual(
            InputProcessor.shared.process(InputEvent(type: .mouse, code: 6, modifiers: .init(rawValue: 0), phase: .down, source: .hidPP, device: nil)),
            .consumed
        )
        XCTAssertEqual(InputProcessor.shared.activeModifierFlags, CGEventFlags.maskAlternate.rawValue)
        XCTAssertTrue(MouseInteractionSessionController.shared.isMotionTapRunning)

        XCTAssertEqual(
            InputProcessor.shared.process(InputEvent(type: .mouse, code: 6, modifiers: .init(rawValue: 0), phase: .up, source: .hidPP, device: nil)),
            .consumed
        )
        XCTAssertEqual(InputProcessor.shared.activeModifierFlags, 0)
        XCTAssertTrue(MouseInteractionSessionController.shared.isMotionTapRunning)
        XCTAssertEqual(MouseInteractionSessionController.shared.activeSessionCount, 1)

        XCTAssertEqual(
            InputProcessor.shared.process(InputEvent(type: .mouse, code: 3, modifiers: .init(rawValue: 0), phase: .up, source: .hidPP, device: nil)),
            .consumed
        )
        XCTAssertFalse(MouseInteractionSessionController.shared.isMotionTapRunning)
        XCTAssertEqual(MouseInteractionSessionController.shared.activeSessionCount, 0)
    }

    func testProcess_virtualModifierKeepsMotionTapRunningAfterMouseSessionEndsUntilModifierUp() {
        let modifierTrigger = RecordedEvent(type: .mouse, code: 6, modifiers: 0, displayComponents: ["🖱7"], deviceFilter: nil)
        let mouseTrigger = RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil)
        let modifierBinding = ButtonBinding(triggerEvent: modifierTrigger, systemShortcutName: "custom::58:0", isEnabled: true)
        let mouseBinding = ButtonBinding(triggerEvent: mouseTrigger, systemShortcutName: "mouseLeftClick", isEnabled: true)
        Options.shared.buttons.binding = [modifierBinding, mouseBinding]
        ButtonUtils.shared.invalidateCache()

        XCTAssertEqual(
            InputProcessor.shared.process(InputEvent(type: .mouse, code: 6, modifiers: .init(rawValue: 0), phase: .down, source: .hidPP, device: nil)),
            .consumed
        )
        XCTAssertEqual(
            InputProcessor.shared.process(InputEvent(type: .mouse, code: 3, modifiers: .init(rawValue: 0), phase: .down, source: .hidPP, device: nil)),
            .consumed
        )
        XCTAssertTrue(MouseInteractionSessionController.shared.isMotionTapRunning)
        XCTAssertEqual(MouseInteractionSessionController.shared.activeSessionCount, 1)

        XCTAssertEqual(
            InputProcessor.shared.process(InputEvent(type: .mouse, code: 3, modifiers: .init(rawValue: 0), phase: .up, source: .hidPP, device: nil)),
            .consumed
        )
        XCTAssertTrue(MouseInteractionSessionController.shared.isMotionTapRunning)
        XCTAssertEqual(MouseInteractionSessionController.shared.activeSessionCount, 0)
        XCTAssertEqual(InputProcessor.shared.activeModifierFlags, CGEventFlags.maskAlternate.rawValue)

        XCTAssertEqual(
            InputProcessor.shared.process(InputEvent(type: .mouse, code: 6, modifiers: .init(rawValue: 0), phase: .up, source: .hidPP, device: nil)),
            .consumed
        )
        XCTAssertFalse(MouseInteractionSessionController.shared.isMotionTapRunning)
        XCTAssertEqual(InputProcessor.shared.activeModifierFlags, 0)
    }

    func testProcess_multipleVirtualModifiers_applyToMappedMouseEvents() {
        let shiftTrigger = RecordedEvent(type: .mouse, code: 6, modifiers: 0, displayComponents: ["🖱7"], deviceFilter: nil)
        let optionTrigger = RecordedEvent(type: .mouse, code: 7, modifiers: 0, displayComponents: ["🖱8"], deviceFilter: nil)
        let leftTrigger = RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil)

        let shiftBinding = ButtonBinding(triggerEvent: shiftTrigger, systemShortcutName: "custom::56:0", isEnabled: true)
        let optionBinding = ButtonBinding(triggerEvent: optionTrigger, systemShortcutName: "custom::58:0", isEnabled: true)
        let leftBinding = ButtonBinding(triggerEvent: leftTrigger, systemShortcutName: "mouseLeftClick", isEnabled: true)
        Options.shared.buttons.binding = [shiftBinding, optionBinding, leftBinding]
        ButtonUtils.shared.invalidateCache()

        var observedEvents: [(type: CGEventType, flags: CGEventFlags)] = []
        ShortcutExecutor.shared.setTestingMouseEventObserver { event in
            observedEvents.append((event.type, event.flags))
        }

        XCTAssertEqual(
            InputProcessor.shared.process(InputEvent(type: .mouse, code: 6, modifiers: .init(rawValue: 0), phase: .down, source: .hidPP, device: nil)),
            .consumed
        )
        XCTAssertEqual(
            InputProcessor.shared.process(InputEvent(type: .mouse, code: 7, modifiers: .init(rawValue: 0), phase: .down, source: .hidPP, device: nil)),
            .consumed
        )
        XCTAssertEqual(InputProcessor.shared.activeModifierFlags, CGEventFlags.maskShift.rawValue | CGEventFlags.maskAlternate.rawValue)

        XCTAssertEqual(
            InputProcessor.shared.process(InputEvent(type: .mouse, code: 3, modifiers: .init(rawValue: 0), phase: .down, source: .hidPP, device: nil)),
            .consumed
        )
        XCTAssertEqual(
            InputProcessor.shared.process(InputEvent(type: .mouse, code: 3, modifiers: .init(rawValue: 0), phase: .up, source: .hidPP, device: nil)),
            .consumed
        )

        XCTAssertEqual(observedEvents.map(\.type), [.leftMouseDown, .leftMouseUp])
        XCTAssertTrue(observedEvents.allSatisfy { event in
            event.flags.contains(.maskShift) && event.flags.contains(.maskAlternate)
        })
    }

    func testProcess_statefulMouseShortcut_preservesPhysicalModifierFlagsOnSyntheticMouseEvents() {
        let trigger = RecordedEvent(type: .mouse, code: 3, modifiers: UInt(CGEventFlags.maskShift.rawValue), displayComponents: ["⇧", "🖱4"], deviceFilter: nil)
        let binding = ButtonBinding(triggerEvent: trigger, systemShortcutName: "mouseLeftClick", isEnabled: true)
        Options.shared.buttons.binding = [binding]
        ButtonUtils.shared.invalidateCache()

        var observedEvents: [(type: CGEventType, flags: CGEventFlags)] = []
        ShortcutExecutor.shared.setTestingMouseEventObserver { event in
            observedEvents.append((event.type, event.flags))
        }

        let downEvent = InputEvent(type: .mouse, code: 3, modifiers: .maskShift,
                                   phase: .down, source: .hidPP, device: nil)
        XCTAssertEqual(InputProcessor.shared.process(downEvent), .consumed)

        let upEvent = InputEvent(type: .mouse, code: 3, modifiers: .maskShift,
                                 phase: .up, source: .hidPP, device: nil)
        XCTAssertEqual(InputProcessor.shared.process(upEvent), .consumed)

        XCTAssertEqual(observedEvents.map(\.type), [.leftMouseDown, .leftMouseUp])
        XCTAssertTrue(observedEvents.allSatisfy { $0.flags.contains(.maskShift) })
    }

    func testProcess_mouseTriggerWithoutModifiers_matchesWhenAdditionalModifiersHeld() {
        let trigger = RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil)
        let binding = ButtonBinding(triggerEvent: trigger, systemShortcutName: "mouseLeftClick", isEnabled: true)
        Options.shared.buttons.binding = [binding]
        ButtonUtils.shared.invalidateCache()

        var observedTypes: [CGEventType] = []
        ShortcutExecutor.shared.setTestingMouseEventObserver { event in
            observedTypes.append(event.type)
        }

        let downEvent = InputEvent(type: .mouse, code: 3, modifiers: .maskShift,
                                   phase: .down, source: .hidPP, device: nil)
        XCTAssertEqual(InputProcessor.shared.process(downEvent), .consumed)

        let upEvent = InputEvent(type: .mouse, code: 3, modifiers: .maskShift,
                                 phase: .up, source: .hidPP, device: nil)
        XCTAssertEqual(InputProcessor.shared.process(upEvent), .consumed)

        XCTAssertEqual(observedTypes, [.leftMouseDown, .leftMouseUp])
    }

    func testProcess_mouseTriggerPrefersExactModifierBindingOverBaseBinding() {
        let baseTrigger = RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil)
        let exactTrigger = RecordedEvent(type: .mouse, code: 3, modifiers: UInt(CGEventFlags.maskShift.rawValue), displayComponents: ["⇧", "🖱4"], deviceFilter: nil)
        let baseBinding = ButtonBinding(triggerEvent: baseTrigger, systemShortcutName: "mouseLeftClick", isEnabled: true)
        let exactBinding = ButtonBinding(triggerEvent: exactTrigger, systemShortcutName: "mouseRightClick", isEnabled: true)
        Options.shared.buttons.binding = [baseBinding, exactBinding]
        ButtonUtils.shared.invalidateCache()

        var observedTypes: [CGEventType] = []
        ShortcutExecutor.shared.setTestingMouseEventObserver { event in
            observedTypes.append(event.type)
        }

        let downEvent = InputEvent(type: .mouse, code: 3, modifiers: .maskShift,
                                   phase: .down, source: .hidPP, device: nil)
        XCTAssertEqual(InputProcessor.shared.process(downEvent), .consumed)

        let upEvent = InputEvent(type: .mouse, code: 3, modifiers: .maskShift,
                                 phase: .up, source: .hidPP, device: nil)
        XCTAssertEqual(InputProcessor.shared.process(upEvent), .consumed)

        XCTAssertEqual(observedTypes, [.rightMouseDown, .rightMouseUp])
    }

    func testProcess_repeatedDownForSameTrigger_replacesPreviousMouseInteractionSession() {
        let trigger = RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil)
        let binding = ButtonBinding(triggerEvent: trigger, systemShortcutName: "mouseLeftClick", isEnabled: true)
        Options.shared.buttons.binding = [binding]
        ButtonUtils.shared.invalidateCache()

        let downEvent = InputEvent(type: .mouse, code: 3, modifiers: .init(rawValue: 0),
                                   phase: .down, source: .hidPP, device: nil)
        XCTAssertEqual(InputProcessor.shared.process(downEvent), .consumed)
        XCTAssertEqual(MouseInteractionSessionController.shared.activeSessionCount, 1)

        XCTAssertEqual(InputProcessor.shared.process(downEvent), .consumed)
        XCTAssertEqual(MouseInteractionSessionController.shared.activeSessionCount, 1)
    }

    func testClearActiveBindings_clearsVirtualModifierFlags() {
        let trigger = RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil)
        let binding = ButtonBinding(triggerEvent: trigger, systemShortcutName: "custom::56:0", isEnabled: true)
        Options.shared.buttons.binding = [binding]
        ButtonUtils.shared.invalidateCache()

        let downEvent = InputEvent(type: .mouse, code: 3, modifiers: .init(rawValue: 0),
                                   phase: .down, source: .hidPP, device: nil)
        XCTAssertEqual(InputProcessor.shared.process(downEvent), .consumed)
        XCTAssertEqual(InputProcessor.shared.activeModifierFlags, KeyCode.getKeyMask(56).rawValue)

        InputProcessor.shared.clearActiveBindings()
        XCTAssertEqual(InputProcessor.shared.activeModifierFlags, 0)
    }

    func testClearActiveBindings_clearsActiveMouseInteractionSessions() {
        let trigger = RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil)
        let binding = ButtonBinding(triggerEvent: trigger, systemShortcutName: "mouseLeftClick", isEnabled: true)
        Options.shared.buttons.binding = [binding]
        ButtonUtils.shared.invalidateCache()

        let downEvent = InputEvent(type: .mouse, code: 3, modifiers: .init(rawValue: 0),
                                   phase: .down, source: .hidPP, device: nil)
        XCTAssertEqual(InputProcessor.shared.process(downEvent), .consumed)
        XCTAssertEqual(MouseInteractionSessionController.shared.activeSessionCount, 1)

        InputProcessor.shared.clearActiveBindings()
        XCTAssertFalse(MouseInteractionSessionController.shared.isMotionTapRunning)
        XCTAssertEqual(MouseInteractionSessionController.shared.activeSessionCount, 0)
    }

    func testButtonCore_passthroughKeyboardEvent_appliesVirtualModifierFlags() {
        let modifierTrigger = RecordedEvent(type: .mouse, code: 6, modifiers: 0, displayComponents: ["🖱7"], deviceFilter: nil)
        let modifierBinding = ButtonBinding(triggerEvent: modifierTrigger, systemShortcutName: "custom::56:0", isEnabled: true)
        Options.shared.buttons.binding = [modifierBinding]
        ButtonUtils.shared.invalidateCache()

        let modifierDown = InputEvent(type: .mouse, code: 6, modifiers: .init(rawValue: 0),
                                      phase: .down, source: .hidPP, device: nil)
        XCTAssertEqual(InputProcessor.shared.process(modifierDown), .consumed)
        XCTAssertEqual(InputProcessor.shared.activeModifierFlags, CGEventFlags.maskShift.rawValue)

        let event = CGEvent(
            keyboardEventSource: nil,
            virtualKey: 0,
            keyDown: true
        )!

        let proxy = CGEventTapProxy(bitPattern: 1)!
        let output = ButtonCore.shared.buttonEventCallBack(proxy, .keyDown, event, nil)

        XCTAssertNotNil(output)
        XCTAssertTrue(event.flags.contains(.maskShift))
    }

    func testButtonCore_passthroughRealLeftMouseEvent_doesNotApplyVirtualModifierFlags() {
        let modifierTrigger = RecordedEvent(type: .mouse, code: 6, modifiers: 0, displayComponents: ["🖱7"], deviceFilter: nil)
        let modifierBinding = ButtonBinding(triggerEvent: modifierTrigger, systemShortcutName: "custom::56:0", isEnabled: true)
        Options.shared.buttons.binding = [modifierBinding]
        ButtonUtils.shared.invalidateCache()

        let modifierDown = InputEvent(type: .mouse, code: 6, modifiers: .init(rawValue: 0),
                                      phase: .down, source: .hidPP, device: nil)
        XCTAssertEqual(InputProcessor.shared.process(modifierDown), .consumed)
        XCTAssertEqual(InputProcessor.shared.activeModifierFlags, CGEventFlags.maskShift.rawValue)

        let event = CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseDown,
            mouseCursorPosition: CGPoint(x: 16, y: 24),
            mouseButton: .left
        )!

        let proxy = CGEventTapProxy(bitPattern: 1)!
        let output = ButtonCore.shared.primaryMouseObservationCallBack(proxy, .leftMouseDown, event, nil)

        XCTAssertNotNil(output)
        XCTAssertFalse(event.flags.contains(.maskShift))
    }

    func testCGEventExtensions_otherMouseDraggedIsRecognizedForDiagnostics() {
        let event = CGEvent(
            mouseEventSource: nil,
            mouseType: .otherMouseDragged,
            mouseCursorPosition: CGPoint(x: 120, y: 80),
            mouseButton: .center
        )!
        event.setIntegerValueField(.mouseEventButtonNumber, value: 3)

        XCTAssertFalse(event.isMouseEvent)
        XCTAssertTrue(event.isMouseDragEvent)
        XCTAssertTrue(event.isMouseInteractionEvent)
        XCTAssertEqual(event.mouseCode, 3)
        XCTAssertEqual(event.eventTypeName, "otherMouseDragged")
    }

    func testCGEventExtensions_mouseMovedIsRecognizedForDiagnostics() {
        let event = CGEvent(
            mouseEventSource: nil,
            mouseType: .mouseMoved,
            mouseCursorPosition: CGPoint(x: 12, y: 34),
            mouseButton: .left
        )!

        XCTAssertFalse(event.isMouseEvent)
        XCTAssertFalse(event.isMouseDragEvent)
        XCTAssertTrue(event.isMouseMoveEvent)
        XCTAssertTrue(event.isMouseInteractionEvent)
        XCTAssertEqual(event.eventTypeName, "mouseMoved")
    }

    func testInputEventFromCGEvent_otherMouseDraggedPreservesMouseCode() {
        let event = CGEvent(
            mouseEventSource: nil,
            mouseType: .otherMouseDragged,
            mouseCursorPosition: CGPoint(x: 90, y: 45),
            mouseButton: .center
        )!
        event.setIntegerValueField(.mouseEventButtonNumber, value: 3)

        let inputEvent = InputEvent(fromCGEvent: event)
        XCTAssertEqual(inputEvent.type, .mouse)
        XCTAssertEqual(inputEvent.code, 3)
    }

    func testMonitorLogStore_previewShowsNewestLinesWithoutDroppingExportHistory() {
        let store = MonitorLogStore(previewLineLimit: 2)

        store.append("first", to: .buttonEvent)
        store.append("second", to: .buttonEvent)
        store.append("third", to: .buttonEvent)

        XCTAssertEqual(store.previewText(for: .buttonEvent), "third\nsecond")
        XCTAssertEqual(store.exportText(for: .buttonEvent), "first\nsecond\nthird")
    }

    func testMonitorLogStore_clearChannelRemovesPreviewAndHistory() {
        let store = MonitorLogStore(previewLineLimit: 3)

        store.append("one", to: .buttonEvent)
        store.append("two", to: .buttonEvent)
        store.clear(.buttonEvent)

        XCTAssertEqual(store.previewText(for: .buttonEvent), "")
        XCTAssertEqual(store.exportText(for: .buttonEvent), "")
    }

    func testMonitorButtonEventLogLine_includesMouseModifierFlags() {
        let controller = MonitorViewController()

        let event = CGEvent(
            mouseEventSource: nil,
            mouseType: .mouseMoved,
            mouseCursorPosition: CGPoint(x: 32, y: 48),
            mouseButton: .left
        )!
        event.flags = [.maskShift, .maskCommand]
        event.setIntegerValueField(.mouseEventDeltaX, value: 4)
        event.setIntegerValueField(.mouseEventDeltaY, value: -2)
        event.setIntegerValueField(.eventSourceUserData, value: 42)

        let rendered = controller.buttonEventLogLine(for: event)
        XCTAssertTrue(rendered.contains("mods:[⇧ ⌘]"))
        XCTAssertTrue(rendered.contains("flags:0x"))
        XCTAssertTrue(rendered.contains("userData: 42"))
    }

    func testMonitorButtonEventLogLine_includesFlagsChangedPhaseAndModifierFlags() {
        let controller = MonitorViewController()

        let event = CGEvent(source: nil)!
        event.type = .flagsChanged
        event.setIntegerValueField(.keyboardEventKeycode, value: Int64(KeyCode.optionL))
        event.flags = [.maskAlternate, .maskShift]

        let rendered = controller.buttonEventLogLine(for: event)
        XCTAssertTrue(rendered.contains("flagsChanged"))
        XCTAssertTrue(rendered.contains("phase: down"))
        XCTAssertTrue(rendered.contains("mods:[⇧ ⌥]"))
        XCTAssertTrue(rendered.contains("flags:0x"))
    }

    func testMonitorButtonEventLogLine_includesKeyDownModifiersAndKeyName() {
        let controller = MonitorViewController()

        let event = CGEvent(
            keyboardEventSource: nil,
            virtualKey: 0,
            keyDown: true
        )!
        event.flags = [.maskCommand, .maskShift]

        let rendered = controller.buttonEventLogLine(for: event)
        XCTAssertTrue(rendered.contains("keyDown"))
        XCTAssertTrue(rendered.contains("key:"))
        XCTAssertTrue(rendered.contains("keyCode: 0"))
        XCTAssertTrue(rendered.contains("mods:[⇧ ⌘]"))
        XCTAssertTrue(rendered.contains("flags:0x"))
    }

    func testButtonUtilsIndex_returnsOnlyMatchingTypeAndCodeCandidates() {
        let matchingTrigger = RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil)
        let matchingWithDifferentModifiers = RecordedEvent(type: .mouse, code: 3, modifiers: UInt(CGEventFlags.maskCommand.rawValue), displayComponents: ["⌘", "🖱4"], deviceFilter: nil)
        let wrongTypeTrigger = RecordedEvent(type: .keyboard, code: 3, modifiers: 0, displayComponents: ["F"], deviceFilter: nil)
        let wrongCodeTrigger = RecordedEvent(type: .mouse, code: 4, modifiers: 0, displayComponents: ["🖱5"], deviceFilter: nil)

        let matchingBinding = ButtonBinding(triggerEvent: matchingTrigger, systemShortcutName: "mouseLeftClick", isEnabled: true)
        let matchingWithDifferentModifiersBinding = ButtonBinding(triggerEvent: matchingWithDifferentModifiers, systemShortcutName: "custom::56:0", isEnabled: true)
        let wrongTypeBinding = ButtonBinding(triggerEvent: wrongTypeTrigger, systemShortcutName: "mouseRightClick", isEnabled: true)
        let wrongCodeBinding = ButtonBinding(triggerEvent: wrongCodeTrigger, systemShortcutName: "mouseMiddleClick", isEnabled: true)

        Options.shared.buttons.binding = [
            matchingBinding,
            matchingWithDifferentModifiersBinding,
            wrongTypeBinding,
            wrongCodeBinding,
        ]
        ButtonUtils.shared.invalidateCache()

        let candidates = ButtonUtils.shared.getButtonBindings(for: .mouse, code: 3)

        XCTAssertEqual(
            Set(candidates.map(\.id)),
            Set([matchingBinding.id, matchingWithDifferentModifiersBinding.id])
        )
    }

    func testButtonCore_dispatchEventMask_excludesPrimaryMouseButtons() {
        let core = ButtonCore.shared

        func contains(_ type: CGEventType, in mask: CGEventMask) -> Bool {
            let typeMask = CGEventMask(1 << type.rawValue)
            return mask & typeMask != 0
        }

        XCTAssertFalse(contains(.leftMouseDown, in: core.dispatchEventMask))
        XCTAssertFalse(contains(.leftMouseUp, in: core.dispatchEventMask))
        XCTAssertFalse(contains(.rightMouseDown, in: core.dispatchEventMask))
        XCTAssertFalse(contains(.rightMouseUp, in: core.dispatchEventMask))
        XCTAssertTrue(contains(.otherMouseDown, in: core.dispatchEventMask))
        XCTAssertTrue(contains(.otherMouseUp, in: core.dispatchEventMask))
        XCTAssertTrue(contains(.keyDown, in: core.dispatchEventMask))
        XCTAssertTrue(contains(.keyUp, in: core.dispatchEventMask))
    }

    func testButtonCore_primaryObservationMask_includesPrimaryMouseButtons() {
        let core = ButtonCore.shared

        func contains(_ type: CGEventType, in mask: CGEventMask) -> Bool {
            let typeMask = CGEventMask(1 << type.rawValue)
            return mask & typeMask != 0
        }

        XCTAssertTrue(contains(.leftMouseDown, in: core.primaryObservationEventMask))
        XCTAssertTrue(contains(.leftMouseUp, in: core.primaryObservationEventMask))
        XCTAssertTrue(contains(.rightMouseDown, in: core.primaryObservationEventMask))
        XCTAssertTrue(contains(.rightMouseUp, in: core.primaryObservationEventMask))
        XCTAssertFalse(contains(.otherMouseDown, in: core.primaryObservationEventMask))
        XCTAssertFalse(contains(.otherMouseUp, in: core.primaryObservationEventMask))
        XCTAssertFalse(contains(.keyDown, in: core.primaryObservationEventMask))
        XCTAssertFalse(contains(.keyUp, in: core.primaryObservationEventMask))
    }
}
