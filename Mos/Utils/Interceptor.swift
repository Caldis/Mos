import Cocoa

final class Interceptor {
    private var keeper: Timer?
    /// keeper 触发的自动重启时间戳, 仅保留冷却窗口内的记录
    private var autoRestartHistory: [Date] = []

    // 防自锁: 主线程被阻塞时 (如 TCC 权限弹窗挂起同步文件调用), active tap 无响应,
    // 系统超时禁用 tap 后输入才恢复; keeper 若盲目重启会把刚恢复的输入再次冻住,
    // 用户永远点不到弹窗. 窗口期内重启达到上限即进入冷却, 让系统输入保持可用.
    static let autoRestartWindow: TimeInterval = 60
    static let autoRestartLimit = 3

    /// 纯函数: 窗口期内自动重启次数达到上限 → 冷却 (跳过本轮重启)
    static func isAutoRestartThrottled(history: [Date], now: Date) -> Bool {
        let windowStart = now.addingTimeInterval(-autoRestartWindow)
        return history.filter { $0 > windowStart }.count >= autoRestartLimit
    }

    private var registration: UUID?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private let ownerRunLoop = CFRunLoopGetCurrent()
    typealias Handler = (CGEventTapProxy, CGEventType, CGEvent, UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>?
    private let handler: Handler
    private let gate: InputPermissionGate
    var onRestart: (() -> Void)?
    var shouldRestart: (() -> Bool)?

    var eventTapRef: CFMachPort? { tap }
    var runLoopSourceRef: CFRunLoopSource? { source }

    enum InterceptorError: Error {
        case eventTapCreationFailed
        case eventTapEnableFailed
    }

    init(event mask: CGEventMask, handleBy eventHandler: @escaping Handler,
         listenOn location: CGEventTapLocation, placeAt placement: CGEventTapPlacement,
         for options: CGEventTapOptions) throws {
        handler = eventHandler
        gate = InputPermissionMonitor.shared.gate
        guard gate.isAuthorized else { throw InterceptorError.eventTapEnableFailed }
        guard let created = CGEvent.tapCreate(tap: location, place: placement, options: options,
            eventsOfInterest: mask, callback: { proxy, type, event, context in
                guard let context = context else { return Unmanaged.passUnretained(event) }
                let owner = Unmanaged<Interceptor>.fromOpaque(context).takeUnretainedValue()
                guard owner.gate.isAuthorized else { return Unmanaged.passUnretained(event) }
                return owner.handler(proxy, type, event, nil)
            }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            throw InterceptorError.eventTapCreationFailed
        }
        CGEvent.tapEnable(tap: created, enable: false)
        tap = created
        guard let createdSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, created, 0) else {
            CFMachPortInvalidate(created)
            throw InterceptorError.eventTapCreationFailed
        }
        source = createdSource
        try start()
    }

    deinit { stop() }

    func start() throws {
        keeper?.invalidate()
        guard let tap = tap, let source = source, CFMachPortIsValid(tap) else {
            throw InterceptorError.eventTapEnableFailed
        }
        if let id = registration { gate.remove(id) }
        registration = nil
        // Registration and enable share the lease lock with revocation.
        registration = gate.register(activate: {
            CFRunLoopAddSource(ownerRunLoop, source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
        }, release: {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
            CFRunLoopSourceInvalidate(source)
        })
        guard registration != nil, gate.isAuthorized, CFMachPortIsValid(tap) else {
            throw InterceptorError.eventTapEnableFailed
        }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if !self.isRunning() {
                let now = Date()
                self.autoRestartHistory.removeAll { now.timeIntervalSince($0) >= Self.autoRestartWindow }
                guard !Self.isAutoRestartThrottled(history: self.autoRestartHistory, now: now) else { return }
                self.autoRestartHistory.append(now)
                self.restart()
            }
        }
        keeper = timer
        RunLoop.current.add(timer, forMode: .common)
    }

    func stop() {
        keeper?.invalidate()
        keeper = nil
        if let id = registration { gate.remove(id) }
        registration = nil
        if let tap = tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source = source {
            CFRunLoopRemoveSource(ownerRunLoop, source, .commonModes)
            CFRunLoopSourceInvalidate(source)
        }
        source = nil
        tap = nil
    }

    func pause() {
        keeper?.invalidate()
        keeper = nil
        if let tap = tap { CGEvent.tapEnable(tap: tap, enable: false) }
    }

    func isRunning() -> Bool {
        guard let tap = tap, CFMachPortIsValid(tap) else { return false }
        return gate.isAuthorized && CGEvent.tapIsEnabled(tap: tap)
    }

    func restart() {
        guard gate.isAuthorized, let tap = tap, CFMachPortIsValid(tap) else {
            stop()
            onRestart?()
            return
        }
        pause()
        onRestart?()
        guard shouldRestart?() ?? true else { return }
        try? start()
    }
}
