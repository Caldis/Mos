import Foundation
import CoreGraphics

extension MonitorChannel {
    var title: String {
        switch self {
        case .scroll: return NSLocalizedString("monitor-scroll-log", comment: "Scroll view")
        case .buttons: return NSLocalizedString("monitor-button-log", comment: "Buttons view")
        }
    }

    var exportName: String {
        self == .scroll ? "monitor-scroll-events.log" : "monitor-button-events.log"
    }
}

struct MonitorField {
    let title: String
    let value: String

    init(_ title: String, _ value: String) {
        self.title = title
        self.value = value
    }
}

enum MonitorPresentation {
    struct Detail {
        let source: MonitorField?
        let fields: [MonitorField]
    }

    private static let missing = "—"

    static func displacement(_ value: Double) -> String {
        guard value.isFinite else { return missing }
        return String(format: value.rounded(.towardZero) == value ? "%.0f" : "%.2f", value)
    }

    static func columns(_ event: MonitorEvent, origin: CFTimeInterval) -> [String] {
        let time = String(format: "%.3f s", max(0, event.time - origin))
        switch event.payload {
        case .scroll(let sample):
            return [
                time, stageName(sample.stage), source(of: sample)?.value ?? missing,
                displacement(sample.delta.x), displacement(sample.delta.y)
            ]
        case let .button(snapshot, tap):
            return [time, buttonInput(snapshot), tapName(tap)]
        }
    }

    static func detail(_ event: MonitorEvent) -> Detail {
        switch event.payload {
        case .scroll(let sample):
            return Detail(source: source(of: sample), fields: scrollFields(sample))
        case let .button(snapshot, tap):
            return Detail(source: tapField(tap), fields: buttonFields(snapshot))
        }
    }

    static func rawText(_ fields: [MonitorField]) -> String {
        fields.map { "\($0.title)\t\($0.value)" }.joined(separator: "\n")
    }

    static func export(_ event: MonitorEvent, origin: CFTimeInterval) -> String {
        [
            columns(event, origin: origin).joined(separator: "\t"),
            rawText(detail(event).fields),
        ].joined(separator: "\n")
    }

    private static func stageName(_ stage: ScrollMonitorStage) -> String {
        switch stage {
        case .captured: return NSLocalizedString("monitor-captured-stage", comment: "Captured event stage")
        case .frame: return NSLocalizedString("monitor-frame-stage", comment: "Computed frame stage")
        case .postedToProcess, .postedToHID: return NSLocalizedString("monitor-posted-stage", comment: "Posted event stage")
        }
    }

    private static func source(of sample: MonitorEvent.ScrollSample) -> MonitorField? {
        if let tap = sample.tap { return tapField(tap) }
        // Posting hooks observe a call to the output API, not an input tap.
        let title = NSLocalizedString("monitor-output", comment: "Scroll output")
        switch sample.stage {
        case .postedToProcess: return MonitorField(title, "postToPid")
        case .postedToHID: return MonitorField(title, "postToHID")
        case .captured, .frame: return nil
        }
    }

    private static func tapField(_ tap: CGEventTapLocation) -> MonitorField {
        MonitorField(NSLocalizedString("monitor-tap", comment: "Event tap"), tapName(tap))
    }

    private static func tapName(_ tap: CGEventTapLocation) -> String {
        switch tap {
        case .cghidEventTap: return "HID Tap"
        case .cgSessionEventTap: return "Session Tap"
        case .cgAnnotatedSessionEventTap: return "Annotated Session Tap"
        @unknown default: return missing
        }
    }

    private static func buttonName(_ number: UInt16) -> String {
        String.localizedStringWithFormat(
            NSLocalizedString("monitor-button-number", comment: "One-based physical mouse button number"), Int64(number) + 1
        )
    }

    private static func keyName(_ code: UInt16) -> String {
        KeyCode.keyMap[code] ?? String(code)
    }

    private static func buttonInput(_ snapshot: MonitorEvent.ButtonSnapshot) -> String {
        let name: String
        switch snapshot.input {
        case .key(let code): name = keyName(code)
        case .mouse(let number, _, _, _, _): name = buttonName(number)
        }
        let phase = snapshot.isDown
            ? NSLocalizedString("monitor-button-down", comment: "Button down")
            : NSLocalizedString("monitor-button-up", comment: "Button up")
        return "\(name) · \(phase)"
    }

    private static func flags(_ value: UInt64) -> String {
        let hex = "0x" + String(value, radix: 16, uppercase: true)
        let known: [(CGEventFlags, String)] = [
            (.maskAlphaShift, "⇪"), (.maskShift, "⇧"), (.maskControl, "⌃"),
            (.maskAlternate, "⌥"), (.maskCommand, "⌘"), (.maskSecondaryFn, "Fn"),
        ]
        let symbols = known.compactMap { value & $0.0.rawValue != 0 ? $0.1 : nil }.joined()
        return raw(hex, decoded: symbols)
    }

    private static func raw<T>(_ value: T, decoded: String = "") -> String {
        decoded.isEmpty ? String(describing: value) : "\(value) · \(decoded)"
    }

    private static func field<T>(_ field: CGEventField, _ name: String, _ value: T, decoded: String = "") -> MonitorField {
        MonitorField("\(field.rawValue) \(name)", raw(value, decoded: decoded))
    }

    private static func quartzFields(_ snapshot: MonitorEvent.QuartzSnapshot) -> [MonitorField] {
        [
            MonitorField("Event type", raw(snapshot.type.rawValue, decoded: snapshot.typeName)),
            MonitorField("Timestamp (ns)", String(snapshot.timestamp)),
            MonitorField("Flags", flags(snapshot.flags)),
            field(.eventSourceUnixProcessID, "Source PID", snapshot.sourcePID),
            field(.eventTargetUnixProcessID, "Event target PID", snapshot.targetPID),
            field(.eventSourceUserData, "User data", snapshot.userData),
        ]
    }

    private static func scrollFields(_ sample: MonitorEvent.ScrollSample) -> [MonitorField] {
        guard let fields = sample.fields else {
            return [MonitorField("ΔX (pt)", raw(sample.delta.x)), MonitorField("ΔY (pt)", raw(sample.delta.y))]
        }
        var result: [MonitorField] = [
            field(.scrollWheelEventPointDeltaAxis1, "Point Y", sample.delta.y),
            field(.scrollWheelEventPointDeltaAxis2, "Point X", sample.delta.x),
            field(.scrollWheelEventScrollPhase, "Scroll phase", fields.phase,
                  decoded: [0: "None", 1: "Began", 2: "Changed", 4: "Ended", 8: "Cancelled", 128: "MayBegin"][fields.phase] ?? ""),
            field(.scrollWheelEventMomentumPhase, "Momentum", fields.momentum,
                  decoded: [0: "None", 1: "Begin", 2: "Continue", 3: "End"][fields.momentum] ?? ""),
        ]
        // The explicit postToPid argument can differ from CGEvent's own target field.
        if let pid = sample.postingPID {
            result.append(MonitorField("postToPid target PID", String(pid)))
        }
        result.append(contentsOf: [
            field(.scrollWheelEventDeltaAxis1, "Line Y", fields.lineY),
            field(.scrollWheelEventDeltaAxis2, "Line X", fields.lineX),
            field(.scrollWheelEventFixedPtDeltaAxis1, "Fixed Y", fields.fixed.y),
            field(.scrollWheelEventFixedPtDeltaAxis2, "Fixed X", fields.fixed.x),
            field(TrackpadEventField.acceleratedY, "Accelerated Y", fields.accelerated.y),
            field(TrackpadEventField.acceleratedX, "Accelerated X", fields.accelerated.x),
            field(TrackpadEventField.rawY, "Raw Y", fields.raw.y),
            field(TrackpadEventField.rawX, "Raw X", fields.raw.x),
            field(TrackpadEventField.sender, "Sender", fields.sender),
            field(.scrollWheelEventIsContinuous, "Continuous", fields.continuous),
            field(.scrollWheelEventScrollCount, "Scroll count", fields.count),
            MonitorField("137 Inverted", raw(fields.inverted)),
            MonitorField("173 Momentum options", raw(fields.momentumOptions)),
        ])
        return result + quartzFields(fields.quartz)
    }

    private static func buttonFields(_ snapshot: MonitorEvent.ButtonSnapshot) -> [MonitorField] {
        var fields = quartzFields(snapshot.quartz)
        switch snapshot.input {
        case .key(let code):
            fields.insert(field(.keyboardEventKeycode, "KeyCode", code, decoded: keyName(code)), at: 1)
        case .mouse(let number, let eventNumber, let clickCount, let deltaX, let deltaY):
            fields.insert(field(.mouseEventButtonNumber, "Button number", number, decoded: buttonName(number)), at: 1)
            fields.append(contentsOf: [
                field(.mouseEventNumber, "Mouse event number", eventNumber),
                field(.mouseEventClickState, "Click count", clickCount),
                field(.mouseEventDeltaX, "Mouse ΔX", deltaX),
                field(.mouseEventDeltaY, "Mouse ΔY", deltaY),
            ])
        }
        return fields
    }
}
