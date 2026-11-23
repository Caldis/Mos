import CoreGraphics

enum MonitorChannel: Int {
    case scroll
    case buttons
}

enum MonitorAxis: Int {
    case vertical
    case horizontal
}

struct MonitorDelta {
    let x: Double
    let y: Double

    subscript(_ axis: MonitorAxis) -> Double { axis == .vertical ? y : x }
}

enum ScrollMonitorStage {
    case captured
    case frame
    case postedToProcess
    case postedToHID
}

struct MonitorEvent {
    enum Payload {
        case scroll(ScrollSample)
        case button(ButtonSnapshot, tap: CGEventTapLocation)
    }

    let id: UInt64
    let time: CFTimeInterval
    let payload: Payload

    var channel: MonitorChannel {
        if case .button = payload { return .buttons }
        return .scroll
    }

    struct ScrollSample {
        let stage: ScrollMonitorStage
        let delta: MonitorDelta
        var fields: ScrollSnapshot?
        var tap: CGEventTapLocation?
        var postingPID: pid_t?
    }

    /// A value snapshot taken at the tap or sender. CGEvent stays on the
    /// calling thread because the scroll core can mutate it in place.
    struct QuartzSnapshot {
        let type: CGEventType
        let typeName: String
        let timestamp: CGEventTimestamp
        let flags: UInt64
        let sourcePID: Int64
        let targetPID: Int64
        let userData: Int64

        init(_ event: CGEvent) {
            type = event.type
            typeName = event.eventTypeName
            timestamp = event.timestamp
            flags = event.flags.rawValue
            sourcePID = event.getIntegerValueField(.eventSourceUnixProcessID)
            targetPID = event.getIntegerValueField(.eventTargetUnixProcessID)
            userData = event.getIntegerValueField(.eventSourceUserData)
        }
    }

    struct ScrollSnapshot {
        private static let invertedField = CGEventField(rawValue: 137)!
        private static let momentumOptionsField = CGEventField(rawValue: 173)!

        let quartz: QuartzSnapshot
        let lineX: Int64
        let lineY: Int64
        let fixed: MonitorDelta
        let accelerated: MonitorDelta
        let raw: MonitorDelta
        let phase: Int64
        let momentum: Int64
        let continuous: Int64
        let count: Int64
        let sender: Int64
        let inverted: Int64
        let momentumOptions: Int64

        init(_ event: CGEvent) {
            quartz = QuartzSnapshot(event)
            lineX = event.getIntegerValueField(.scrollWheelEventDeltaAxis2)
            lineY = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
            fixed = MonitorDelta(
                x: event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2),
                y: event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
            )
            accelerated = MonitorDelta(
                x: event.getDoubleValueField(TrackpadEventField.acceleratedX),
                y: event.getDoubleValueField(TrackpadEventField.acceleratedY)
            )
            raw = MonitorDelta(
                x: event.getDoubleValueField(TrackpadEventField.rawX),
                y: event.getDoubleValueField(TrackpadEventField.rawY)
            )
            phase = event.getIntegerValueField(.scrollWheelEventScrollPhase)
            momentum = event.getIntegerValueField(.scrollWheelEventMomentumPhase)
            continuous = event.getIntegerValueField(.scrollWheelEventIsContinuous)
            count = event.getIntegerValueField(.scrollWheelEventScrollCount)
            sender = event.getIntegerValueField(TrackpadEventField.sender)
            inverted = event.getIntegerValueField(Self.invertedField)
            momentumOptions = event.getIntegerValueField(Self.momentumOptionsField)
        }
    }

    struct ButtonSnapshot {
        enum Input {
            case key(UInt16)
            case mouse(number: UInt16, eventNumber: Int64, clickCount: Int64, deltaX: Int64, deltaY: Int64)
        }

        let quartz: QuartzSnapshot
        let input: Input
        let isDown: Bool

        init?(_ event: CGEvent) {
            if event.isKeyboardEvent || event.type == .flagsChanged {
                input = .key(event.keyCode)
            } else if event.isMouseButtonEvent {
                input = .mouse(
                    number: event.mouseCode,
                    eventNumber: event.getIntegerValueField(.mouseEventNumber),
                    clickCount: event.getIntegerValueField(.mouseEventClickState),
                    deltaX: event.getIntegerValueField(.mouseEventDeltaX),
                    deltaY: event.getIntegerValueField(.mouseEventDeltaY)
                )
            } else {
                return nil
            }
            quartz = QuartzSnapshot(event)
            isDown = event.isKeyDown
        }
    }
}
