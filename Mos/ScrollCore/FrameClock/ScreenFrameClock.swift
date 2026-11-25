import AppKit
import QuartzCore

enum FrameClockFactory {
    static func screen(displayID: CGDirectDisplayID?, onTimeout: @escaping () -> Void) -> ScrollFrameClock? {
        guard #available(macOS 14.0, *) else { return nil }
        let screens = NSScreen.screens
        let matched = displayID.flatMap { id in screens.first { $0.frameClockDisplayID == id } }
        guard let screen = matched ?? NSScreen.main ?? screens.first else { return nil }
        return ScreenFrameClock(screen: screen, onTimeout: onTimeout)
    }
}

@available(macOS 14.0, *)
private final class ScreenFrameClock: NSObject, ScrollFrameClock {
    // The display link is hosted away from the preferences and Monitor run loop.
    private static let runLoop: CFRunLoop = {
        let ready = DispatchSemaphore(value: 0)
        var runLoop: CFRunLoop!
        let thread = Thread {
            RunLoop.current.add(NSMachPort(), forMode: .default)
            runLoop = CFRunLoopGetCurrent()
            ready.signal()
            CFRunLoopRun()
        }
        thread.name = "me.caldis.mos.screen-frame-clock"
        thread.qualityOfService = .userInteractive
        thread.start()
        ready.wait()
        return runLoop
    }()

    let kind = ScrollFrameClockKind.screen
    var onTick: ((FrameTick) -> Void)?
    private let screen: NSScreen
    private let onTimeout: () -> Void
    private var firstFrameTimer: Timer?
    private let lock = NSLock()
    private var link: CADisplayLink?
    private var lastTimestamp: CFTimeInterval?

    init(screen: NSScreen, onTimeout: @escaping () -> Void) {
        self.screen = screen
        self.onTimeout = onTimeout
    }

    var isAvailable: Bool {
        guard let display = screen.frameClockDisplayID else { return false }
        return CGDisplayIsOnline(display) != 0
    }

    var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return link != nil
    }

    func prepare() {}

    @discardableResult
    func start() -> Bool {
        if isRunning { return true }
        guard isAvailable else { return false }
        let created = screen.displayLink(target: self, selector: #selector(step(_:)))
        lock.lock()
        link = created
        lastTimestamp = nil
        lock.unlock()
        let runLoop = Self.runLoop
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue) {
            created.add(to: .current, forMode: .default)
        }
        CFRunLoopWakeUp(runLoop)

        let timer = Timer(timeInterval: 2.0, repeats: false) { [weak self] _ in
            self?.checkFirstFrame()
        }
        firstFrameTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        return true
    }

    func stop() {
        stopMonitoring()
        lock.lock()
        let stopped = link
        link = nil
        lastTimestamp = nil
        lock.unlock()
        guard let stopped = stopped else { return }
        let runLoop = Self.runLoop
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue) { stopped.invalidate() }
        CFRunLoopWakeUp(runLoop)
    }

    func rebuild() -> Bool {
        let wasRunning = isRunning
        stop()
        return !wasRunning || start()
    }

    func startMonitoring() {}

    func stopMonitoring() {
        firstFrameTimer?.invalidate()
        firstFrameTimer = nil
    }

    private func checkFirstFrame() {
        firstFrameTimer = nil
        lock.lock()
        let timedOut = link != nil && lastTimestamp == nil
        lock.unlock()
        if timedOut { onTimeout() }
    }

    @objc private func step(_ source: CADisplayLink) {
        lock.lock()
        guard source === link else { lock.unlock(); return }
        let timestamp = source.timestamp
        let interval = lastTimestamp.map { timestamp - $0 } ?? (source.targetTimestamp - timestamp)
        lastTimestamp = timestamp
        lock.unlock()
        onTick?(FrameTick(timestamp: CACurrentMediaTime(), interval: interval))
    }
}
