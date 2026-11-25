import Dispatch
import QuartzCore

final class FixedRateFrameClock: ScrollFrameClock {
    private static let queue = DispatchQueue(label: "me.caldis.mos.fixed-rate-frame-clock", qos: .userInteractive)
    private var timer: DispatchSourceTimer?
    private var lastTimestamp: CFTimeInterval?

    let kind = ScrollFrameClockKind.fixedRate
    var onTick: ((FrameTick) -> Void)?
    let isAvailable = true
    var isRunning: Bool { timer != nil }

    deinit { timer?.cancel() }

    func prepare() {}

    @discardableResult
    func start() -> Bool {
        guard !isRunning else { return true }
        lastTimestamp = nil
        let source = DispatchSource.makeTimerSource(flags: .strict, queue: Self.queue)
        source.setEventHandler { [weak self] in self?.fire() }
        source.schedule(deadline: .now(), repeating: FrameTiming.referenceInterval, leeway: .microseconds(200))
        timer = source
        source.activate()
        return true
    }

    func stop() {
        guard let source = timer else { return }
        source.cancel()
        // Drain an in-flight callback before a later scroll session reuses this clock.
        Self.queue.sync {}
        timer = nil
    }

    // The timer's schedule is independent of the connected displays.
    func rebuild() -> Bool { true }
    func startMonitoring() {}
    func stopMonitoring() {}

    private func fire() {
        let timestamp = CACurrentMediaTime()
        let interval = lastTimestamp.map { timestamp - $0 } ?? FrameTiming.referenceInterval
        lastTimestamp = timestamp
        onTick?(FrameTick(timestamp: timestamp, interval: interval))
    }
}
