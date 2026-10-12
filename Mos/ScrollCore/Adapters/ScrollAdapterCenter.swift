//
//  ScrollAdapterCenter.swift
//  Mos
//  应用滚动适配器的注册、生命周期与 session 层捕获闸门
//

import Cocoa

/// 管理全部滚动适配器, 并持有它们共用的一个 session 层 tap。
/// session 层位于 HID 层改键工具之后、Annotated Session 层之前; 镜像在 Annotated Session 层之前接收滚动,
/// 该层的事件尚未标注目标 pid (目标 pid 字段为前台应用), 目标窗口由适配器自行判断。
///
/// 开销控制:
/// - 没有适配器满足系统版本时不注册任何监听
/// - 没有目标应用运行时不创建 tap, 也不运行定时器
/// - 目标应用运行时 tap 默认禁用, 只有光标进入目标窗口 (或目标应用切到前台) 时才启用, 离开后立即禁用;
///   闸门关闭期间滚动事件只经过现有的 Annotated Session tap
///
/// 全部方法在主线程调用
final class ScrollAdapterCenter {

    static let shared = ScrollAdapterCenter()

    /// 激活期间刷新窗口缓存与检测光标位置的间隔: 目标应用在前台时用较短间隔, 否则用较长间隔
    let foregroundRefreshInterval: TimeInterval = 0.25
    let backgroundRefreshInterval: TimeInterval = 1.0

    private var registrations: [ScrollAdapterRegistration] = []
    /// 已创建的适配器, 以 descriptor.identifier 为键, 目标应用退出后保留实例以便复用
    private var adapters: [String: ScrollAdapter] = [:]
    /// 目标应用正在运行的适配器
    private var activeAdapters: [ScrollAdapter] = []
    private var observers: [NSObjectProtocol] = []
    private var interceptor: Interceptor?
    private var refreshTimer: Timer?
    /// 适配器 tap 已启用且未被系统禁用
    private(set) var isGateOpen = false
    /// 适配器 tap 最近一次处理并放行的事件时间戳; 标准路径据此跳过同一事件, 避免翻转执行两次
    private var lastPassthroughTimestamp: CGEventTimestamp = 0
    private(set) var isStarted = false

    #if DEBUG
    func setPassthroughTimestampForTests(_ timestamp: CGEventTimestamp, armed: Bool) {
        lastPassthroughTimestamp = timestamp
        isArmed = armed
    }
    #endif

    /// 有适配器处于激活状态; 标准路径的热路径钩子只读取这个值
    private(set) var isArmed = false

    // MARK: - 生命周期

    func start(registrations all: [ScrollAdapterRegistration] = ScrollAdapterCatalog.registrations) {
        guard !isStarted else { return }
        #if DEBUG
        // 用于同一二进制的开销对照
        if ProcessInfo.processInfo.environment["MOS_DISABLE_SCROLL_ADAPTERS"] != nil { return }
        #endif
        let version = ProcessInfo.processInfo.operatingSystemVersion
        registrations = all.filter { $0.isSupported(on: version) }
        guard !registrations.isEmpty else { return }
        isStarted = true

        let center = NSWorkspace.shared.notificationCenter
        let launched: (Notification) -> Void = { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.applicationLaunched(app)
        }
        let terminated: (Notification) -> Void = { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.applicationTerminated(app)
        }
        let activated: (Notification) -> Void = { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.applicationActivated(app)
        }
        observers = [
            center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main, using: launched),
            center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main, using: terminated),
            center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main, using: activated),
        ]
        for app in NSWorkspace.shared.runningApplications {
            applicationLaunched(app)
        }
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers = []
        activeAdapters.forEach { $0.deactivate() }
        activeAdapters = []
        updateArming()
    }

    private func registration(for app: NSRunningApplication) -> ScrollAdapterRegistration? {
        guard let bundleIdentifier = app.bundleIdentifier else { return nil }
        return registrations.first { $0.descriptor.bundleIdentifiers.contains(bundleIdentifier) }
    }

    private func applicationLaunched(_ app: NSRunningApplication) {
        guard let registration = registration(for: app) else { return }
        let identifier = registration.descriptor.identifier
        guard let adapter = adapters[identifier] ?? registration.make() else { return }
        adapters[identifier] = adapter
        guard !activeAdapters.contains(where: { $0 === adapter }) else { return }
        adapter.activate(app)
        activeAdapters.append(adapter)
        updateArming()
    }

    private func applicationTerminated(_ app: NSRunningApplication) {
        guard let registration = registration(for: app),
              let adapter = adapters[registration.descriptor.identifier],
              activeAdapters.contains(where: { $0 === adapter }) else { return }
        adapter.deactivate()
        activeAdapters.removeAll { $0 === adapter }
        updateArming()
    }

    private func applicationActivated(_ app: NSRunningApplication) {
        guard isArmed else { return }
        scheduleRefreshTimer()
        if registration(for: app) != nil {
            refreshAndProbeCursor()
        }
    }

    /// 按前台应用选择刷新间隔; 间隔不变时保留现有定时器
    private func scheduleRefreshTimer() {
        let frontmostIsTarget = NSWorkspace.shared.frontmostApplication.map { registration(for: $0) != nil } ?? false
        let interval = frontmostIsTarget ? foregroundRefreshInterval : backgroundRefreshInterval
        if let timer = refreshTimer, timer.isValid, timer.timeInterval == interval { return }
        refreshTimer?.invalidate()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in self?.refreshAndProbeCursor() }
        // 允许系统合并唤醒
        timer.tolerance = interval * 0.2
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    /// 根据激活的适配器创建或释放共享 tap 与刷新定时器
    private func updateArming() {
        let armed = !activeAdapters.isEmpty
        guard armed != isArmed else { return }
        isArmed = armed
        if armed {
            scheduleRefreshTimer()
            createInterceptor()
            refreshAndProbeCursor()
        } else {
            refreshTimer?.invalidate()
            refreshTimer = nil
            closeGate()
            interceptor?.stop()
            interceptor = nil
        }
    }

    // MARK: - 闸门

    private func createInterceptor() {
        do {
            let tap = try Interceptor(
                event: ScrollCore.shared.scrollEventMask,
                handleBy: ScrollAdapterCenter.callback,
                listenOn: .cgSessionEventTap,
                placeAt: .headInsertEventTap,
                for: .defaultTap
            )
            tap.onRestart = {
                ScrollPoster.shared.stop(.TrackingEnd)
            }
            // 闸门关闭时 keeper 不应自动恢复 tap
            tap.shouldRestart = { ScrollAdapterCenter.shared.isGateOpen }
            tap.pause()
            interceptor = tap
        } catch {
            NSLog("ScrollAdapterCenter: create adapter interceptor failure: \(error)")
        }
    }

    private func openGate() {
        guard !isGateOpen, let interceptor = interceptor else { return }
        do {
            try interceptor.start()
            isGateOpen = true
        } catch {
            NSLog("ScrollAdapterCenter: enable adapter interceptor failure: \(error)")
        }
    }

    private func closeGate() {
        guard isGateOpen else { return }
        isGateOpen = false
        interceptor?.pause()
    }

    /// 刷新窗口缓存, 并按当前光标位置开关闸门: 光标进入目标窗口时启用 tap, 离开时禁用
    private func refreshAndProbeCursor() {
        activeAdapters.forEach { $0.refresh() }
        guard let location = CGEvent(source: nil)?.location else { return }
        if route(at: location) != nil {
            openGate()
        } else {
            closeGate()
        }
    }

    private func route(at location: CGPoint) -> ScrollAdapterRoute? {
        for adapter in activeAdapters {
            if let route = adapter.route(at: location) {
                return route
            }
        }
        return nil
    }

    // MARK: - 热路径

    /// 标准路径 (Annotated Session tap) 的钩子, 返回 true 表示跳过该事件。
    /// - 该事件已由适配器 tap 处理并放行 (按事件时间戳识别): 跳过, 避免翻转执行两次
    /// - 闸门关闭且滚动落在目标窗口内: 打开闸门, 本事件仍走标准路径, 后续事件改由适配器 tap 接管
    /// 用时间戳而非事件标记: eventSourceUserData 一经写入非零值便无法覆盖, 来源进程写过的事件无法再标记
    /// 未激活任何适配器时只读取一个布尔值
    func screenStandardScroll(_ event: CGEvent) -> Bool {
        guard isArmed else { return false }
        if lastPassthroughTimestamp != 0 && event.timestamp == lastPassthroughTimestamp {
            return true
        }
        if !isGateOpen, route(at: event.location) != nil {
            openGate()
        }
        return false
    }

    private static let callback: CGEventTapCallBack = { (proxy, type, event, refcon) in
        let center = ScrollAdapterCenter.shared
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            // 系统禁用了 tap: 标记闸门关闭, 由标准路径接手, 下一次窗口内滚动重新启用
            ScrollPoster.shared.stop(.TrackingEnd)
            center.closeGate()
            return Unmanaged.passUnretained(event)
        }
        guard type == .scrollWheel, !ScrollUtils.shared.isSyntheticSmoothEvent(event) else {
            return Unmanaged.passUnretained(event)
        }
        guard let route = center.route(at: event.location) else {
            // 光标已离开全部目标窗口, 后续事件只走标准路径
            center.closeGate()
            return Unmanaged.passUnretained(event)
        }
        let result = ScrollCore.shared.handleScroll(event, route: .adapter(route))
        if result != nil {
            center.lastPassthroughTimestamp = event.timestamp
        }
        return result
    }
}
