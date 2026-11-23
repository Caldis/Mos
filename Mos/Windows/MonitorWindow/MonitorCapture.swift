import Cocoa
import QuartzCore

/// Main-thread owner of the recording lifecycle and the histories shared by
/// the table, plot, inspector, and export. Producers never access these rings.
final class MonitorCapture {
    enum State: Equatable {
        case paused
        case recording
        case accessibilityRequired
        case tapUnavailable
    }

    enum EventList: Equatable {
        case scroll(ScrollMonitorStage)
        case buttons
    }

    struct Update: OptionSet {
        let rawValue: Int

        static let scroll = Update(rawValue: 1 << 0)
        static let buttons = Update(rawValue: 1 << 1)
        static let state = Update(rawValue: 1 << 2)

        func includes(_ channel: MonitorChannel) -> Bool {
            contains(channel == .scroll ? .scroll : .buttons)
        }
    }

    // Observe at the head of Session so buttons stopped by an active filter
    // later in that tap still appear here. No decisions are inferred from it.
    private static let buttonTap = CGEventTapLocation.cgSessionEventTap
    private static let observedButtons = [
        CGEventType.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp,
        .otherMouseDown, .otherMouseUp, .keyDown, .keyUp, .flagsChanged,
    ].reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }

    private let trace = ScrollMonitorTrace.shared
    private var scroll = MonitorScrollHistory(capacity: 16_384)
    private var buttons = MonitorHistory<MonitorEvent>(capacity: 8_192)
    private var incoming: [MonitorEvent] = []
    private var tap: Interceptor?
    private var timer: Timer?

    private(set) var state: State = .paused
    private(set) var origin = CACurrentMediaTime()
    private(set) var displayTime = CACurrentMediaTime()
    private(set) var missed = 0
    var didUpdate: ((Update) -> Void)?

    deinit {
        if state == .recording { ScrollMonitorTrace.setSharedRecording(false) }
        timer?.invalidate()
        tap?.stop()
        if state == .recording { trace.clear() }
    }

    var isEmpty: Bool { scroll.history.isEmpty && buttons.isEmpty }

    func start() {
        guard state != .recording else { return }
        guard InputPermissionMonitor.shared.isAuthorized else {
            state = .accessibilityRequired
            didUpdate?(.state)
            return
        }

        do {
            tap = try Interceptor(
                event: Self.observedButtons,
                handleBy: { _, type, event, _ in
                    if Self.observedButtons.containsEvent(type), ScrollMonitorTrace.isRecording {
                        ScrollMonitorTrace.shared.recordButton(event, tap: Self.buttonTap)
                    }
                    return Unmanaged.passUnretained(event)
                },
                listenOn: Self.buttonTap,
                placeAt: .headInsertEventTap,
                for: .listenOnly
            )
        } catch {
            state = .tapUnavailable
            didUpdate?(.state)
            return
        }

        ScrollMonitorTrace.setSharedRecording(true)
        state = .recording
        displayTime = CACurrentMediaTime()
        let refresh = Timer(timeInterval: 1.0 / 24.0, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        refresh.tolerance = 0.006
        RunLoop.main.add(refresh, forMode: .common)
        timer = refresh
        didUpdate?(.state)
    }

    func pause() {
        stop(as: .paused)
    }

    func clear() {
        origin = trace.clear()
        displayTime = origin
        scroll.removeAll()
        buttons.removeAll()
        incoming.removeAll(keepingCapacity: false)
        missed = 0
        didUpdate?([.scroll, .buttons, .state])
    }

    func count(_ channel: MonitorChannel) -> Int {
        channel == .scroll ? scroll.history.count : buttons.count
    }

    func rowCount(in list: EventList) -> Int {
        switch list {
        case .scroll(let stage): return scroll.rowCount(for: stage)
        case .buttons: return buttons.count
        }
    }

    func event(at row: Int, in list: EventList) -> MonitorEvent? {
        switch list {
        case .scroll(let stage): return scroll.event(at: row, in: stage)
        case .buttons: return buttons.newest(at: row)
        }
    }

    func row(for id: UInt64, in list: EventList) -> Int? {
        switch list {
        case .scroll(let stage): return scroll.row(for: id, in: stage)
        case .buttons: return buttons.newestIndex(matching: id, by: { $0.id })
        }
    }

    func timeline(in range: ClosedRange<CFTimeInterval>) -> [MonitorTimelineSample] {
        scroll.history.events(in: range).compactMap(MonitorTimelineSample.init(event:))
    }

    func export(_ channel: MonitorChannel) -> String {
        let history = channel == .scroll ? scroll.history : buttons
        return history.map {
            MonitorPresentation.export($0, origin: origin)
        }.joined(separator: "\n\n")
    }

    private func refresh() {
        guard InputPermissionMonitor.shared.isAuthorized else {
            stop(as: .accessibilityRequired)
            return
        }
        guard tap?.isRunning() == true else {
            stop(as: .tapUnavailable)
            return
        }
        let update = drain()
        displayTime = CACurrentMediaTime()
        didUpdate?(update)
    }

    private func stop(as next: State) {
        guard state == .recording else { return }
        ScrollMonitorTrace.setSharedRecording(false)
        timer?.invalidate()
        timer = nil
        tap?.stop()
        tap = nil
        state = next
        displayTime = CACurrentMediaTime()
        didUpdate?(drain().union(.state))
    }

    private func drain() -> Update {
        var update: Update = []
        let newlyMissed = trace.drain(into: &incoming)
        if newlyMissed > 0 {
            missed += newlyMissed
            update.insert(.state)
        }
        for event in incoming {
            switch event.payload {
            case .scroll(let sample):
                scroll.append(event, stage: sample.stage)
                update.insert(.scroll)
            case .button:
                buttons.append(event)
                update.insert(.buttons)
            }
        }
        incoming.removeAll(keepingCapacity: state == .recording)
        return update
    }
}

/// The event lists index the same bounded history used by the timeline and
/// export. Indices older than the current history window are ignored.
struct MonitorScrollHistory {
    private(set) var history: MonitorHistory<MonitorEvent>
    private var inputs: MonitorHistory<UInt64>
    private var posted: MonitorHistory<UInt64>

    init(capacity: Int) {
        history = MonitorHistory(capacity: capacity)
        inputs = MonitorHistory(capacity: capacity)
        posted = MonitorHistory(capacity: capacity)
    }

    mutating func append(_ event: MonitorEvent, stage: ScrollMonitorStage) {
        history.append(event)
        switch stage {
        case .captured: inputs.append(event.id)
        case .posted: posted.append(event.id)
        case .frame: break
        }
    }

    mutating func removeAll() {
        history.removeAll()
        inputs.removeAll()
        posted.removeAll()
    }

    func rowCount(for stage: ScrollMonitorStage) -> Int {
        guard let oldest = history.first, let ids = ids(for: stage) else { return 0 }
        return ids.count - ids.lowerBound { $0 >= oldest.id }
    }

    func event(at row: Int, in stage: ScrollMonitorStage) -> MonitorEvent? {
        guard let id = ids(for: stage)?.newest(at: row),
              let index = history.newestIndex(matching: id, by: { $0.id }) else { return nil }
        return history.newest(at: index)
    }

    func row(for id: UInt64, in stage: ScrollMonitorStage) -> Int? {
        guard let oldest = history.first, id >= oldest.id else { return nil }
        return ids(for: stage)?.newestIndex(matching: id, by: { $0 })
    }

    private func ids(for stage: ScrollMonitorStage) -> MonitorHistory<UInt64>? {
        switch stage {
        case .captured: return inputs
        case .posted: return posted
        case .frame: return nil
        }
    }
}

private extension CGEventMask {
    func containsEvent(_ type: CGEventType) -> Bool {
        Int(type.rawValue) < Self.bitWidth && self & (1 << type.rawValue) != 0
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

    func newest(at index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[endIndex - 1 - index]
    }

    func newestIndex<Value: Comparable>(matching value: Value, by key: (Element) -> Value) -> Int? {
        let index = lowerBound { key($0) >= value }
        guard index < endIndex, key(self[index]) == value else { return nil }
        return endIndex - 1 - index
    }

    fileprivate func lowerBound(_ predicate: (Element) -> Bool) -> Int {
        var first = startIndex
        var last = endIndex
        while first < last {
            let middle = first + (last - first) / 2
            if predicate(self[middle]) {
                last = middle
            } else {
                first = middle + 1
            }
        }
        return first
    }
}

extension MonitorHistory where Element == MonitorEvent {
    func events(in range: ClosedRange<CFTimeInterval>) -> Slice<Self> {
        let first = lowerBound { $0.time >= range.lowerBound }
        let last = lowerBound { $0.time > range.upperBound }
        return self[first..<last]
    }
}
