import CoreGraphics
import QuartzCore
import os

/// Producers enqueue samples only during recording. The window owns the
/// histories and drains the pending buffer without drawing under this lock.
final class ScrollMonitorTrace {
    static let shared = ScrollMonitorTrace()

    static var isRecording: Bool { MosMonitorIsRecording() }

    // The window owns the fast flag; the lock rejects samples already in flight.
    static func setSharedRecording(_ enabled: Bool) {
        shared.setRecording(enabled)
        MosMonitorSetRecording(enabled)
    }

    private var lock = os_unfair_lock_s()
    private var recording = false
    private var nextID: UInt64 = 0
    private var pending: [MonitorEvent] = []
    private var missed = 0
    private let pendingLimit: Int

    init(pendingLimit: Int = 4096) {
        self.pendingLimit = pendingLimit
    }

    func setRecording(_ enabled: Bool) {
        os_unfair_lock_lock(&lock)
        recording = enabled
        os_unfair_lock_unlock(&lock)
    }

    func recordCapture(_ event: CGEvent, route: ScrollRoute) {
        let tap: CGEventTapLocation
        switch route {
        case .standard: tap = .cgAnnotatedSessionEventTap
        case .adapter: tap = .cgSessionEventTap
        }
        record(event, stage: .captured, tap: tap)
    }

    func record(_ event: CGEvent, stage: ScrollMonitorStage, targetPID: pid_t? = nil, tap: CGEventTapLocation? = nil) {
        append {
            let delta = MonitorDelta(
                x: event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2),
                y: event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)
            )
            return .scroll(MonitorEvent.ScrollSample(
                stage: stage, delta: delta, fields: .init(event), tap: tap, postingPID: targetPID
            ))
        }
    }

    func recordFrame(y: Double, x: Double) {
        append { .scroll(MonitorEvent.ScrollSample(stage: .frame, delta: MonitorDelta(x: x, y: y))) }
    }

    func recordButton(_ event: CGEvent, tap: CGEventTapLocation) {
        append { MonitorEvent.ButtonSnapshot(event).map { .button($0, tap: tap) } }
    }

    private func append(_ payload: () -> MonitorEvent.Payload?) {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        guard recording else { return }
        guard pending.count < pendingLimit else {
            missed += 1
            return
        }

        let time = CACurrentMediaTime()
        guard let value = payload() else { return }
        nextID &+= 1
        pending.append(MonitorEvent(id: nextID, time: time, payload: value))
    }

    @discardableResult
    func drain(into batch: inout [MonitorEvent]) -> Int {
        batch.removeAll(keepingCapacity: true)
        os_unfair_lock_lock(&lock)
        swap(&pending, &batch)
        if !recording { pending.removeAll() }
        let count = missed
        missed = 0
        os_unfair_lock_unlock(&lock)
        return count
    }

    /// The cutoff and sample timestamps share this lock and the same clock.
    @discardableResult
    func clear() -> CFTimeInterval {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        pending.removeAll(keepingCapacity: recording)
        missed = 0
        return CACurrentMediaTime()
    }
}
