import Cocoa
import os

enum ScrollMonitorLane: CaseIterable {
    case input
    case frame
    case output
}

enum ScrollMonitorStage: String {
    case captured
    case frame
    case postedToProcess = "postToPid"
    case postedToHID = "postToHID"
    case observed = "sessionTap"

    var lane: ScrollMonitorLane? {
        switch self {
        case .captured: return .input
        case .frame: return .frame
        case .postedToProcess, .postedToHID: return .output
        case .observed: return nil
        }
    }
}

struct ScrollMonitorSample {
    let time: CFTimeInterval
    let stage: ScrollMonitorStage
    let x: Double
    let y: Double
    let fields: EventFields?

    struct EventFields {
        private static let invertedField = CGEventField(rawValue: 137)!
        private static let momentumOptionsField = CGEventField(rawValue: 173)!

        let phase: Int64
        let momentum: Int64
        let continuous: Int64
        let sender: Int64
        let sourcePID: Int64
        let targetPID: Int64
        let scrollCount: Int64
        let momentumOptions: Int64
        let inverted: Int64
        let line: (x: Int64, y: Int64)
        let fixed: (x: Double, y: Double)
        let accelerated: (x: Double, y: Double)
        let raw: (x: Double, y: Double)

        init(_ event: CGEvent, targetPID: pid_t?) {
            phase = event.getIntegerValueField(.scrollWheelEventScrollPhase)
            momentum = event.getIntegerValueField(.scrollWheelEventMomentumPhase)
            continuous = event.getIntegerValueField(.scrollWheelEventIsContinuous)
            sender = event.getIntegerValueField(TrackpadEventField.sender)
            sourcePID = event.getIntegerValueField(.eventSourceUnixProcessID)
            self.targetPID = targetPID.map(Int64.init) ?? event.getIntegerValueField(.eventTargetUnixProcessID)
            scrollCount = event.getIntegerValueField(.scrollWheelEventScrollCount)
            momentumOptions = event.getIntegerValueField(Self.momentumOptionsField)
            inverted = event.getIntegerValueField(Self.invertedField)
            line = (
                event.getIntegerValueField(.scrollWheelEventDeltaAxis2),
                event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
            )
            fixed = (
                event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2),
                event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
            )
            accelerated = (
                event.getDoubleValueField(TrackpadEventField.acceleratedX),
                event.getDoubleValueField(TrackpadEventField.acceleratedY)
            )
            raw = (
                event.getDoubleValueField(TrackpadEventField.rawX),
                event.getDoubleValueField(TrackpadEventField.rawY)
            )
        }
    }

    func logLine(since start: CFTimeInterval) -> String {
        func pair(_ x: Double, _ y: Double) -> String {
            String(format: "(%.2f, %.2f)", x, y)
        }

        var line = String(format: "%8.3f s  ", time - start) + "\(stage.rawValue)  pt=\(pair(x, y))"
        if let fields {
            line += "  phase=\(fields.phase)  momentum=\(fields.momentum)  sender=\(fields.sender)"
            line += "  pid=\(fields.sourcePID)→\(fields.targetPID)  continuous=\(fields.continuous)  count=\(fields.scrollCount)"
            line += "  line=(\(fields.line.x), \(fields.line.y))  fixed=\(pair(fields.fixed.x, fields.fixed.y))"
            line += "  acc=\(pair(fields.accelerated.x, fields.accelerated.y))  raw=\(pair(fields.raw.x, fields.raw.y))"
            line += "  opt173=\(fields.momentumOptions)  inv137=\(fields.inverted)"
        }
        return line
    }
}

/// The event and display-link threads share only the pending batch. The monitor drains it on the main thread.
final class ScrollMonitorTrace {
    static let shared = ScrollMonitorTrace()

    static var isRecording: Bool { MosMonitorIsRecording() }

    // Window lifecycle changes the fast flag on the main thread. The lock still protects in-flight samples.
    static func setSharedRecording(_ enabled: Bool) {
        shared.setRecording(enabled)
        MosMonitorSetRecording(enabled)
    }

    private var lock = os_unfair_lock_s()
    private var pending: [ScrollMonitorSample] = []
    private var dropped = 0
    private var recording = false
    private let pendingLimit: Int

    init(pendingLimit: Int = 4096) {
        self.pendingLimit = pendingLimit
    }

    func setRecording(_ enabled: Bool) {
        os_unfair_lock_lock(&lock)
        recording = enabled
        os_unfair_lock_unlock(&lock)
    }

    func record(_ event: CGEvent, stage: ScrollMonitorStage, targetPID: pid_t? = nil) {
        append(ScrollMonitorSample(
            time: CACurrentMediaTime(),
            stage: stage,
            x: event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2),
            y: event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1),
            fields: .init(event, targetPID: targetPID)
        ))
    }

    func recordFrame(y: Double, x: Double) {
        append(ScrollMonitorSample(time: CACurrentMediaTime(), stage: .frame, x: x, y: y, fields: nil))
    }

    private func append(_ sample: @autoclosure () -> ScrollMonitorSample) {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        guard recording else { return }
        guard pending.count < pendingLimit else {
            dropped += 1
            return
        }
        pending.append(sample())
    }

    @discardableResult
    func drain(into batch: inout [ScrollMonitorSample]) -> Int {
        batch.removeAll(keepingCapacity: true)
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        swap(&pending, &batch)
        if !recording { pending.removeAll() }
        let droppedCount = dropped
        dropped = 0
        return droppedCount
    }
}

struct MonitorHistory<Element>: RandomAccessCollection {
    private let capacity: Int
    private var entries: [Element] = []
    private var oldest = 0

    init(capacity: Int) {
        precondition(capacity > 0)
        self.capacity = capacity
    }

    var startIndex: Int { 0 }
    var endIndex: Int { entries.count }

    subscript(index: Int) -> Element {
        precondition(indices.contains(index))
        return entries[(oldest + index) % entries.count]
    }

    mutating func append(_ element: Element) {
        if entries.count < capacity {
            entries.append(element)
        } else {
            entries[oldest] = element
            oldest = (oldest + 1) % capacity
        }
    }

    mutating func removeAll() {
        entries.removeAll(keepingCapacity: true)
        oldest = 0
    }
}
