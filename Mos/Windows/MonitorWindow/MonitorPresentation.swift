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
    let enumID: UInt32?
    let title: String
    let value: String

    init(_ title: String, _ value: String, enumID: UInt32? = nil) {
        self.enumID = enumID
        self.title = title
        self.value = value
    }
}

enum MonitorPresentation {
    struct Detail {
        let source: MonitorField?
        let fields: [MonitorField]
    }

    struct Column {
        let id: String
        let title: String
        let enumID: UInt32?
        let width: CGFloat
        let minimum: CGFloat
        let numeric: Bool
        let visibleByDefault: Bool
        let value: (MonitorEvent, CFTimeInterval) -> String?

        init(
            _ id: String, _ title: String, enumID: UInt32? = nil, width: CGFloat = 132,
            minimum: CGFloat = 72, numeric: Bool = false, visibleByDefault: Bool = false,
            value: @escaping (MonitorEvent, CFTimeInterval) -> String?
        ) {
            self.id = id
            self.title = title
            self.enumID = enumID
            self.width = width
            self.minimum = minimum
            self.numeric = numeric
            self.visibleByDefault = visibleByDefault
            self.value = value
        }
    }

    static let missing = "—"
    private static let captureTapTitle = NSLocalizedString("monitor-capture-tap", comment: "Tap where the event was captured")
    private static let postTapTitle = NSLocalizedString("monitor-post-tap", comment: "Tap where Mos posted an event")

    static func displacement(_ value: Double) -> String {
        guard value.isFinite else { return missing }
        return String(format: value.rounded(.towardZero) == value ? "%.0f" : "%.2f", value)
    }

    static func columns(_ event: MonitorEvent, origin: CFTimeInterval, forExport: Bool = false) -> [String] {
        let time = eventTime(event, origin)
        switch event.payload {
        case .scroll(let sample):
            let delta = [
                displacement(sample.delta.x), displacement(sample.delta.y)
            ]
            let tap = sample.tap.map(tapName) ?? missing
            if forExport { return [time, stageName(sample.stage), tap] + delta }
            if sample.stage == .captured { return [time, tap] + delta }
            return [time] + delta
        case let .button(snapshot, tap):
            return [time, buttonInput(snapshot), tapName(tap)]
        }
    }

    static func columnDefinitions(for channel: MonitorChannel) -> [Column] {
        switch channel {
        case .scroll: return scrollColumns + scrollFields + quartzFields
        case .buttons: return buttonColumns + buttonFields
        }
    }

    static func detail(_ event: MonitorEvent) -> Detail {
        let source = event.captureTap.map { MonitorField(captureTapTitle, tapName($0)) }
            ?? event.postTap.map { MonitorField(postTapTitle, tapName($0)) }
        if let sample = event.scroll, sample.fields == nil {
            return Detail(source: source, fields: [
                MonitorField("ΔX (pt)", raw(sample.delta.x)),
                MonitorField("ΔY (pt)", raw(sample.delta.y)),
            ])
        }
        let columns = event.channel == .scroll ? scrollFields + quartzFields : buttonFields
        return Detail(source: source, fields: columns.compactMap { column in
            column.value(event, 0).map { MonitorField(column.title, $0, enumID: column.enumID) }
        })
    }

    static func rawText(_ fields: [MonitorField]) -> String {
        fields.map { field in
            [field.enumID.map(String.init) ?? "", field.title, field.value].joined(separator: "\t")
        }.joined(separator: "\n")
    }

    static func export(_ event: MonitorEvent, origin: CFTimeInterval) -> String {
        [
            columns(event, origin: origin, forExport: true).joined(separator: "\t"),
            rawText(detail(event).fields),
        ].joined(separator: "\n")
    }

    static func stageName(_ stage: ScrollMonitorStage) -> String {
        switch stage {
        case .captured: return NSLocalizedString("monitor-captured", comment: "Raw scroll input at the tap")
        case .frame: return NSLocalizedString("monitor-frame-stage", comment: "Computed frame stage")
        case .posted: return NSLocalizedString("monitor-posted-stage", comment: "Posted event stage")
        }
    }

    private static func eventTime(_ event: MonitorEvent, _ origin: CFTimeInterval) -> String {
        String(format: "%.3f s", max(0, event.time - origin))
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

    private static func field<T>(
        _ field: CGEventField, _ name: String, _ read: @escaping (MonitorEvent) -> T?,
        decoded: @escaping (T) -> String = { _ in "" }
    ) -> Column {
        Column("field.\(field.rawValue)", name, enumID: field.rawValue, numeric: true) { event, _ in
            read(event).map { raw($0, decoded: decoded($0)) }
        }
    }

    private static let timeColumn = Column(
        "time", NSLocalizedString("monitor-time", comment: "Time column"),
        width: 82, minimum: 67, numeric: true, visibleByDefault: true, value: eventTime
    )
    private static let captureTapColumn = Column(
        "captureTap", captureTapTitle, width: 168, minimum: 108, visibleByDefault: true
    ) { event, _ in event.captureTap.map(tapName) }

    private static let scrollColumns = [
        timeColumn,
        Column("stage", NSLocalizedString("monitor-stage", comment: "Event stage column"), width: 100,
               minimum: 80, visibleByDefault: true) { event, _ in event.scroll.map { stageName($0.stage) } },
        captureTapColumn,
        Column("postTap", postTapTitle, width: 108, minimum: 70, visibleByDefault: true) { event, _ in
            event.postTap.map(tapName)
        },
        Column("deltaX", "ΔX", width: 58, minimum: 44, numeric: true, visibleByDefault: true) { event, _ in
            event.scroll.map { displacement($0.delta.x) }
        },
        Column("deltaY", "ΔY", width: 58, minimum: 44, numeric: true, visibleByDefault: true) { event, _ in
            event.scroll.map { displacement($0.delta.y) }
        },
    ]

    private static let buttonColumns = [
        timeColumn,
        Column("input", NSLocalizedString("monitor-input", comment: "Button or key column"),
               width: 135, minimum: 96, visibleByDefault: true) { event, _ in event.button.map(buttonInput) },
        captureTapColumn,
    ]

    // The inspector, export and selectable columns read the same field definitions.
    private static let quartzFields = [
        Column("eventType", "Event type", width: 156) { event, _ in
            event.quartz.map { raw($0.type.rawValue, decoded: $0.typeName) }
        },
        Column("timestamp", "Timestamp (ns)", width: 156, numeric: true) { event, _ in
            event.quartz.map { String($0.timestamp) }
        },
        Column("flags", "Flags", numeric: true) { event, _ in event.quartz.map { flags($0.flags) } },
        field(.eventSourceUnixProcessID, "Source PID", { $0.quartz?.sourcePID }),
        field(.eventTargetUnixProcessID, "Event target PID", { $0.quartz?.targetPID }),
        field(.eventSourceUserData, "User data", { $0.quartz?.userData }),
    ]

    private static let scrollFields = [
        field(.scrollWheelEventPointDeltaAxis1, "Point Y", { $0.scroll?.delta.y }),
        field(.scrollWheelEventPointDeltaAxis2, "Point X", { $0.scroll?.delta.x }),
        field(.scrollWheelEventScrollPhase, "Scroll phase", { $0.scroll?.fields?.phase }, decoded: {
            [0: "None", 1: "Began", 2: "Changed", 4: "Ended", 8: "Cancelled", 128: "MayBegin"][$0] ?? ""
        }),
        field(.scrollWheelEventMomentumPhase, "Momentum", { $0.scroll?.fields?.momentum }, decoded: {
            [0: "None", 1: "Begin", 2: "Continue", 3: "End"][$0] ?? ""
        }),
        field(.scrollWheelEventDeltaAxis1, "Line Y", { $0.scroll?.fields?.lineY }),
        field(.scrollWheelEventDeltaAxis2, "Line X", { $0.scroll?.fields?.lineX }),
        field(.scrollWheelEventFixedPtDeltaAxis1, "Fixed Y", { $0.scroll?.fields?.fixed.y }),
        field(.scrollWheelEventFixedPtDeltaAxis2, "Fixed X", { $0.scroll?.fields?.fixed.x }),
        field(TrackpadEventField.acceleratedY, "Accelerated Y", { $0.scroll?.fields?.accelerated.y }),
        field(TrackpadEventField.acceleratedX, "Accelerated X", { $0.scroll?.fields?.accelerated.x }),
        field(TrackpadEventField.rawY, "Raw Y", { $0.scroll?.fields?.raw.y }),
        field(TrackpadEventField.rawX, "Raw X", { $0.scroll?.fields?.raw.x }),
        field(TrackpadEventField.sender, "Sender", { $0.scroll?.fields?.sender }),
        field(.scrollWheelEventIsContinuous, "Continuous", { $0.scroll?.fields?.continuous }),
        field(.scrollWheelEventScrollCount, "Scroll count", { $0.scroll?.fields?.count }),
        field(MonitorEvent.ScrollSnapshot.invertedField, "Inverted", { $0.scroll?.fields?.inverted }),
        field(MonitorEvent.ScrollSnapshot.momentumOptionsField, "Momentum options", { $0.scroll?.fields?.momentumOptions }),
    ]

    private static let buttonFields = [
        quartzFields[0],
        field(.keyboardEventKeycode, "KeyCode", { $0.keyCode }, decoded: keyName),
        field(.mouseEventButtonNumber, "Button number", { $0.mouse?.number }, decoded: buttonName),
    ] + Array(quartzFields.dropFirst()) + [
        field(.mouseEventNumber, "Mouse event number", { $0.mouse?.eventNumber }),
        field(.mouseEventClickState, "Click count", { $0.mouse?.clickCount }),
        field(.mouseEventDeltaX, "Mouse ΔX", { $0.mouse?.deltaX }),
        field(.mouseEventDeltaY, "Mouse ΔY", { $0.mouse?.deltaY }),
    ]
}

private extension MonitorEvent {
    var scroll: ScrollSample? {
        if case .scroll(let sample) = payload { return sample }
        return nil
    }

    var button: ButtonSnapshot? {
        if case .button(let snapshot, _) = payload { return snapshot }
        return nil
    }

    var quartz: QuartzSnapshot? {
        scroll?.fields?.quartz ?? button?.quartz
    }

    var captureTap: CGEventTapLocation? {
        switch payload {
        case .scroll(let sample): return sample.stage == .captured ? sample.tap : nil
        case .button(_, let tap): return tap
        }
    }

    var postTap: CGEventTapLocation? {
        guard let sample = scroll, sample.stage == .posted else { return nil }
        return sample.tap
    }

    var keyCode: UInt16? {
        guard case .key(let code)? = button?.input else { return nil }
        return code
    }

    var mouse: (number: UInt16, eventNumber: Int64, clickCount: Int64, deltaX: Int64, deltaY: Int64)? {
        guard case let .mouse(number, eventNumber, clickCount, deltaX, deltaY)? = button?.input else { return nil }
        return (number, eventNumber, clickCount, deltaX, deltaY)
    }
}
