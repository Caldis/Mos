// 帧时钟: 引擎每帧 tick 的驱动源, 可在三种实现之间切换
// - DispatchSourceTimer: 按固定间隔自走, 与屏幕刷新不对齐
// - CVDisplayLink: 与 Mos 相同的实现 (CVDisplayLinkCreateWithActiveCGDisplays), 回调与屏幕刷新同步
// - NSScreen.displayLink: macOS 14 起替代 CVDisplayLink 的 CADisplayLink, 绑定到 iPhone 镜像窗口所在的屏幕
// 三种实现都把 tick 投递到引擎队列执行, 引擎状态仍只在该队列上访问

import AppKit
import QuartzCore
import CoreVideo

enum FrameClockKind: String, CaseIterable, Codable, Identifiable {
    case dispatchTimer, cvDisplayLink, screenDisplayLink
    var id: Self { self }
    var label: String {
        switch self {
        case .dispatchTimer: return "DispatchSourceTimer"
        case .cvDisplayLink: return "CVDisplayLink (与 Mos 相同)"
        case .screenDisplayLink: return "NSScreen.displayLink"
        }
    }
}

protocol FrameClock: AnyObject {
    func start()
    func stop()
    /// 用于状态显示的说明, 包含实际帧率
    var summary: String { get }
}

/// 把时钟回调投递到引擎队列。上一帧尚未执行时丢弃本次回调, 避免队列繁忙时 tick 堆积
final class TickForwarder {
    private let queue: DispatchQueue
    private let handler: () -> Void
    private let pending = Locked(false)

    init(queue: DispatchQueue, handler: @escaping () -> Void) {
        self.queue = queue
        self.handler = handler
    }

    func fire() {
        let skip = pending.mutate { busy -> Bool in
            if busy { return true }
            busy = true
            return false
        }
        if skip {
            Lab.stats.mutate { $0.droppedTicks += 1 }
            return
        }
        queue.async { [self] in
            pending.set(false)
            handler()
        }
    }
}

final class DispatchFrameClock: FrameClock {
    private let timer: DispatchSourceTimer
    private let hz: Double

    /// 计时器直接创建在引擎队列上, 回调本身就在该队列执行
    init(queue: DispatchQueue, hz: Double, handler: @escaping () -> Void) {
        self.hz = hz
        timer = DispatchSource.makeTimerSource(flags: .strict, queue: queue)
        timer.schedule(deadline: .now(), repeating: 1.0 / hz, leeway: .microseconds(200))
        timer.setEventHandler(handler: handler)
    }

    func start() { timer.resume() }
    func stop() { timer.cancel() }
    var summary: String { "DispatchSourceTimer \(Int(hz.rounded())) Hz" }
}

final class CVFrameClock: FrameClock {
    private var link: CVDisplayLink?
    private let forwarder: TickForwarder

    init(forwarder: TickForwarder) {
        self.forwarder = forwarder
        var created: CVDisplayLink?
        guard CVDisplayLinkCreateWithActiveCGDisplays(&created) == kCVReturnSuccess, let link = created else { return }
        // 回调运行在 CVDisplayLink 的专用线程上
        CVDisplayLinkSetOutputCallback(link, { _, _, _, _, _, context in
            Unmanaged<TickForwarder>.fromOpaque(context!).takeUnretainedValue().fire()
            return kCVReturnSuccess
        }, Unmanaged.passUnretained(forwarder).toOpaque())
        self.link = link
    }

    func start() { if let link { CVDisplayLinkStart(link) } }
    func stop() { if let link { CVDisplayLinkStop(link) } }

    var summary: String {
        guard let link else { return "CVDisplayLink 创建失败" }
        let period = CVDisplayLinkGetNominalOutputVideoRefreshPeriod(link)
        guard period.timeValue != 0, period.timeScale != 0 else { return "CVDisplayLink" }
        return "CVDisplayLink \(Int((Double(period.timeScale) / Double(period.timeValue)).rounded())) Hz"
    }
}

final class ScreenFrameClock: NSObject, FrameClock {
    /// CADisplayLink 需要挂在 RunLoop 上; 使用独立线程, 避免主线程的界面绘制影响回调时机
    private static let runLoop: CFRunLoop = {
        let ready = DispatchSemaphore(value: 0)
        var loop: CFRunLoop!
        let thread = Thread {
            RunLoop.current.add(NSMachPort(), forMode: .common)
            loop = CFRunLoopGetCurrent()
            ready.signal()
            while true { RunLoop.current.run(mode: .default, before: .distantFuture) }
        }
        thread.name = "lab.displaylink"
        thread.qualityOfService = .userInteractive
        thread.start()
        ready.wait()
        return loop
    }()

    private let forwarder: TickForwarder
    private let screen: NSScreen
    private var link: CADisplayLink?

    init(forwarder: TickForwarder) {
        self.forwarder = forwarder
        // 选择 iPhone 镜像窗口所在的屏幕; 找不到时使用主屏幕。CGWindow 坐标原点在主屏左上角, NSScreen 原点在左下角
        let mirror = MirroringLocator.shared.state.get().rect
        let mainHeight = NSScreen.screens.first?.frame.height ?? 0
        let match = mirror.flatMap { r in
            NSScreen.screens.first { $0.frame.contains(CGPoint(x: r.midX, y: mainHeight - r.midY)) }
        }
        screen = match ?? NSScreen.main ?? NSScreen.screens[0]
        super.init()
    }

    @objc private func step(_ link: CADisplayLink) { forwarder.fire() }

    func start() {
        CFRunLoopPerformBlock(Self.runLoop, CFRunLoopMode.commonModes.rawValue) { [self] in
            let l = screen.displayLink(target: self, selector: #selector(step(_:)))
            l.add(to: .current, forMode: .common)
            link = l
        }
        CFRunLoopWakeUp(Self.runLoop)
    }

    func stop() {
        CFRunLoopPerformBlock(Self.runLoop, CFRunLoopMode.commonModes.rawValue) { [self] in
            link?.invalidate()
            link = nil
        }
        CFRunLoopWakeUp(Self.runLoop)
    }

    var summary: String { "NSScreen.displayLink \(screen.maximumFramesPerSecond) Hz (\(screen.localizedName))" }
}
