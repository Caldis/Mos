import Cocoa

/// Builds the gesture series that accompanies simulated trackpad wheel events.
/// Access stays on the serial posting queue with the corresponding wheel events.
struct TrackpadGestureCompanions {
    private static let seriesType = CGEventField(rawValue: 117)!
    private static let scrollX = CGEventField(rawValue: 118)!
    private static let scrollFlags = CGEventField(rawValue: 135)!

    private enum GesturePhase: Int64 {
        case began = 1, changed = 2, ended = 4, cancelled = 8, mayBegin = 128
    }

    private var lastScroll: CGEvent?
    var isActive: Bool { lastScroll != nil }

    mutating func events(for scroll: CGEvent) -> [CGEvent] {
        let phase = GesturePhase(rawValue: scroll.getIntegerValueField(.scrollWheelEventScrollPhase))
        switch phase {
        case .began:
            let closing = cancel()
            return closing + begin(with: scroll)
        case .changed:
            if lastScroll == nil { return begin(with: scroll) }
            lastScroll = scroll
            return [makeScrollGesture(.changed, from: scroll)].compactMap { $0 }
        case .ended:
            return finish(.ended, with: scroll)
        case .cancelled:
            return finish(.cancelled, with: scroll)
        default:
            return []
        }
    }

    mutating func cancel() -> [CGEvent] {
        guard let scroll = lastScroll else { return [] }
        return finish(.cancelled, with: scroll)
    }

    private mutating func begin(with scroll: CGEvent) -> [CGEvent] {
        lastScroll = scroll
        return [
            makeScrollGesture(.mayBegin, from: scroll),
            makeBoundary(started: true, from: scroll),
            makeScrollGesture(.began, from: scroll),
        ].compactMap { $0 }
    }

    private mutating func finish(_ phase: GesturePhase, with scroll: CGEvent) -> [CGEvent] {
        guard lastScroll != nil else { return [] }
        lastScroll = nil
        return [makeScrollGesture(phase, from: scroll), makeBoundary(started: false, from: scroll)].compactMap { $0 }
    }

    private func makeScrollGesture(_ phase: GesturePhase, from scroll: CGEvent) -> CGEvent? {
        guard let event = makeEvent(subtype: 6, from: scroll) else { return nil }
        event.setIntegerValueField(TrackpadEventField.gesturePhase, value: phase.rawValue)
        event.setIntegerValueField(Self.scrollFlags, value: 1)
        if phase == .began || phase == .changed {
            event.setDoubleValueField(Self.scrollX, value: scroll.getDoubleValueField(.scrollWheelEventPointDeltaAxis2))
            event.setDoubleValueField(TrackpadEventField.gestureDY, value: scroll.getDoubleValueField(.scrollWheelEventPointDeltaAxis1))
        }
        return event
    }

    private func makeBoundary(started: Bool, from scroll: CGEvent) -> CGEvent? {
        guard let event = makeEvent(subtype: started ? 61 : 62, from: scroll) else { return nil }
        event.setIntegerValueField(Self.seriesType, value: 6)
        return event
    }

    private func makeEvent(subtype: Int64, from scroll: CGEvent) -> CGEvent? {
        guard let event = CGEvent(source: nil), let type = CGEventType.appKitGesture else { return nil }
        event.type = type
        event.flags = scroll.flags
        event.location = scroll.location
        event.timestamp = scroll.timestamp
        event.setIntegerValueField(TrackpadEventField.gestureSubtype, value: subtype)
        event.setIntegerValueField(TrackpadEventField.sender, value: scroll.getIntegerValueField(TrackpadEventField.sender))
        ScrollUtils.shared.markSyntheticSmoothEvent(event)
        return event
    }
}
