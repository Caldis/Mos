//
//  ScrollPoster.swift
//  Mos
//
//  Created by Caldis on 2020/12/3.
//  Copyright © 2020 Caldis. All rights reserved.
//

import Cocoa
import os

class ScrollPoster {

    // 单例
    static let shared = ScrollPoster(clockOverride: ScrollFrameClockKind.launchOverride(in: CommandLine.arguments))

    typealias ScreenClockFactory = (CGDirectDisplayID?, @escaping () -> Void) -> ScrollFrameClock?

    init(clockOverride: ScrollFrameClockKind? = nil,
         makeDisplayClock: @escaping () -> ScrollFrameClock = { DisplayLinkFrameClock() },
         makeFixedClock: @escaping () -> ScrollFrameClock = { FixedRateFrameClock() },
         makeScreenClock: @escaping ScreenClockFactory = FrameClockFactory.screen,
         displayLayout: @escaping () -> ScrollDisplayLayout = ScrollDisplayLayout.active) {
        self.clockOverride = clockOverride
        self.makeDisplayClock = makeDisplayClock
        self.makeFixedClock = makeFixedClock
        self.makeScreenClock = makeScreenClock
        self.displayLayout = displayLayout
        clock = clockOverride == .fixedRate ? makeFixedClock() : makeDisplayClock()
        NSLog("Module initialized: ScrollPoster")
        bindClock()
    }

    // 插值器
    private let filter = ScrollFilter()
    // 帧时钟
    private var clock: ScrollFrameClock
    private let clockOverride: ScrollFrameClockKind?
    private let makeDisplayClock: () -> ScrollFrameClock
    private let makeFixedClock: () -> ScrollFrameClock
    private let makeScreenClock: ScreenClockFactory
    private let displayLayout: () -> ScrollDisplayLayout
    // Display notifications and session setup access this cache on the main thread.
    private var cachedDisplayLayout: ScrollDisplayLayout?
    private var monitorsClock = false
    private var clockSessionActive = false
    private var screenClockUnavailable = false
    private var inputLocation: CGPoint?
    private var virtualTrackpadTargetPID: pid_t?
    // Match callbacks and queued stops against the active clock and input under stateLock.
    private var clockRevision: UInt64 = 0
    private var inputRevision: UInt64 = 0
    private var frameStopScheduled = false
    // 滚动数据
    private var current = (y: 0.0, x: 0.0)  // 当前滚动距离
    private var delta = (y: 0.0, x: 0.0)  // 滚动方向记录
    private var buffer = (y: 0.0, x: 0.0)  // 滚动缓冲距离
    private var pointAccumulator = ScrollPointAccumulator()
    // 滚动配置
    private var shifting = false
    private var duration = Options.shared.scroll.durationTransition
    // 输入节奏追踪
    private var lastManualEventTime: CFTimeInterval = 0.0
    private var manualInputEnded = true
    private var momentumActive = false
    private var momentumEndScheduledTime: CFTimeInterval? = nil
    private var trackingEndScheduledTime: CFTimeInterval? = nil
    // 阈值: 鼠标滚轮事件间隔低于 continuationThreshold 视为持续跟随
    //      介于 continuationThreshold 与 separationThreshold 之间模拟惯性衔接
    private let manualContinuationThreshold: CFTimeInterval = 0.18
    private let manualSeparationThreshold: CFTimeInterval = 0.45
    private let trackingEndAdvance: CFTimeInterval = 0.04
    private let momentumEndDelay: CFTimeInterval = 0.13
    // 状态锁和投递上下文
    private var stateLock = os_unfair_lock_s()
    private let dispatchContext = ScrollDispatchContext.shared
    // 滚动配置快照: 主线程在 update 时捕获, 帧时钟线程只读, 避免热路径跨线程读 Options/ScrollCore
    private struct ConfigSnapshot {
        var deadZone: Double
        var normalizesTiming = false
        var usesVirtualTrackpad = false
    }
    private var config = ConfigSnapshot(deadZone: 1.0)
    // 主线程访问, 无需锁
    var isAvailable: Bool {
        if clock.isAvailable { return true }
        return !clockSessionActive && requestedClockKind != .displayLink
    }
}

// MARK: - 滚动数据更新控制
extension ScrollPoster {
    func update(event: CGEvent, duration: Double, y: Double, x: Double, speed: Double, amplification: Double = 1,
                route: ScrollDispatchContext.Route = .process, targetPID: pid_t? = nil) -> Self {
        let virtualTarget = route.usesVirtualTrackpad
            ? (targetPID ?? pid_t(event.getIntegerValueField(.eventTargetUnixProcessID)))
            : nil
        if clockSessionActive && virtualTrackpadTargetPID != virtualTarget {
            stop(.TrackingEnd)
        }
        guard dispatchContext.capture(event: event, route: route, targetPID: targetPID) else {
            return self
        }
        virtualTrackpadTargetPID = virtualTarget
        if !clockSessionActive && inputLocation == nil {
            let kind = requestedClockKind
            if kind == .screen || (kind == .displayLink && Options.shared.scrollNormalizeTiming) {
                inputLocation = event.location
            }
        }
        os_unfair_lock_lock(&stateLock)
        defer { os_unfair_lock_unlock(&stateLock) }
        inputRevision &+= 1
        frameStopScheduled = !clockSessionActive
        // 捕获本次手势的配置快照 (主线程读 Options/ScrollCore, 帧时钟线程只读)
        captureConfigSnapshotLocked(usesVirtualTrackpad: route.usesVirtualTrackpad)
        // 更新滚动配置
        self.duration = duration
        // 更新滚动数据
        if y*delta.y > 0 {
            buffer.y += y * speed * amplification
        } else {
            buffer.y = y * speed * amplification
            current.y = 0.0
        }
        if x*delta.x > 0 {
            buffer.x += x * speed * amplification
        } else {
            buffer.x = x * speed * amplification
            current.x = 0.0
        }
        delta = (y: y, x: x)
        let now = CFAbsoluteTimeGetCurrent()
        let interval = lastManualEventTime > 0.0 ? now - lastManualEventTime : nil
        let separatedByTime = interval == nil ? true : interval! >= manualSeparationThreshold
        let phase = ScrollPhase.shared.phase
        let separatedPhase = (phase == .Idle || phase == .Leave || phase == .MomentumEnd || phase == .TrackingEnd)
        let separated = manualInputEnded || separatedByTime || separatedPhase
        if separated { pointAccumulator = ScrollPointAccumulator() }
        let plan = ScrollPhase.shared.onManualInputDetected(isSeparated: separated)
        perform(plan, emitTargetImmediately: false)
        lastManualEventTime = now
        manualInputEnded = false
        momentumActive = false
        momentumEndScheduledTime = nil
        trackingEndScheduledTime = nil
        return self
    }
    func updateShifting(enable: Bool) {
        os_unfair_lock_lock(&stateLock)
        shifting = enable
        os_unfair_lock_unlock(&stateLock)
    }
    func shift(with nextValue: ( y: Double, x: Double )) -> (y: Double, x: Double) {
        // 如果按下 Shift, 则始终将滚动转为横向
        if shifting {
            // 判断哪个轴有值, 有值则赋给 X
            // 某些鼠标 (MXMaster/MXAnywhere), 按下 Shift 后会显式转换方向为横向, 此处针对这类转换进行归一化处理
            if nextValue.y != 0.0 && nextValue.x == 0.0 {
                return (y: nextValue.x, x: nextValue.y)
            } else {
                return (y: nextValue.y, x: nextValue.x)
            }
        } else {
            return (y: nextValue.y, x: nextValue.x)
        }
    }
    func brake() {
        os_unfair_lock_lock(&stateLock)
        buffer = current
        pointAccumulator = ScrollPointAccumulator()
        perform(ScrollPhase.shared.onMomentumFinish(), emitTargetImmediately: true)
        manualInputEnded = true
        momentumActive = false
        momentumEndScheduledTime = nil
        os_unfair_lock_unlock(&stateLock)
    }
    func reset() {
        clockSessionActive = false
        inputLocation = nil
        virtualTrackpadTargetPID = nil
        dispatchContext.enqueueAdapterEnd()
        dispatchContext.invalidateAll()
        os_unfair_lock_lock(&stateLock)
        inputRevision &+= 1
        frameStopScheduled = true
        resetUnlocked()
        os_unfair_lock_unlock(&stateLock)
    }

#if DEBUG
    func captureConfigSnapshotForTests() {
        os_unfair_lock_lock(&stateLock)
        captureConfigSnapshotLocked()
        os_unfair_lock_unlock(&stateLock)
    }
    var configSnapshotForTests: (deadZone: Double, normalizesTiming: Bool, usesVirtualTrackpad: Bool) {
        os_unfair_lock_lock(&stateLock)
        defer { os_unfair_lock_unlock(&stateLock) }
        return (config.deadZone, config.normalizesTiming, config.usesVirtualTrackpad)
    }

    var frameClockKindForTests: ScrollFrameClockKind { clock.kind }
    var selectedDisplayForTests: ScrollDisplayLayout.Display? { cachedDisplayLayout?.lastDisplay }

    func recordSkippedSyntheticEvent() {
        dispatchContext.recordSkippedSyntheticEvent()
    }

    func diagnosticsSnapshot() -> (postedFrames: UInt64, droppedFramesByGeneration: UInt64, droppedFramesByTTL: UInt64, skippedSyntheticEvents: UInt64, updateSnapshotFailures: UInt64) {
        dispatchContext.diagnosticsSnapshot()
    }
#endif

    private func resetUnlocked() {
        // 重置数值
        dispatchContext.clearContext()
        current = ( y: 0.0, x: 0.0 )
        delta = ( y: 0.0, x: 0.0 )
        buffer = ( y: 0.0, x: 0.0 )
        pointAccumulator = ScrollPointAccumulator()
        // 重置插值器
        filter.reset()
        ScrollPhase.shared.reset()
        manualInputEnded = true
        momentumActive = false
        lastManualEventTime = 0.0
        momentumEndScheduledTime = nil
        trackingEndScheduledTime = nil
    }
}

// MARK: - 插值数据发送控制
extension ScrollPoster {
    // 初始化帧时钟
    func create() {
        clock.prepare()
    }
    // 启动事件发送器
    func tryStart() {
        if !clockSessionActive {
            selectClockForSession()
            configureFrameRateForSession()
        }
        if clock.start() {
            clockSessionActive = true
        } else if clock.kind == .screen {
            useFixedClockAfterScreenFailure()
        } else {
            reset()
        }
    }
    func stopVirtualTrackpadOutput() {
        if virtualTrackpadTargetPID != nil { stop(.TrackingEnd) }
    }

    // 停止事件发送器
    func stop(_ requestedPhase: Phase = Phase.MomentumEnd) {
        clockSessionActive = false
        inputLocation = nil
        virtualTrackpadTargetPID = nil
        os_unfair_lock_lock(&stateLock)
        inputRevision &+= 1
        frameStopScheduled = true
        os_unfair_lock_unlock(&stateLock)
        // 停止循环, 然后准备发送最后一次事件
        clock.stop()
        // 失效旧会话异步帧，收尾帧使用新代次
        dispatchContext.advanceGeneration()
        os_unfair_lock_lock(&stateLock)

        if requestedPhase == .MomentumEnd {
            _ = ScrollPhase.shared.onMomentumFinish()
        } else {
            _ = ScrollPhase.shared.onManualInputEnded()
        }

        if let snapshot = dispatchContext.preparePostingSnapshot(),
           case .process = snapshot.route,
           ScrollUtils.shared.isEventTargetingChrome(snapshot.event),
           let phaseValues = phaseValues(for: .TrackingEnd) {
            _ = post(snapshot, (y: 0.0, x: 0.0), phaseOverride: phaseValues)
        }
        // 适配器路由不使用阶段帧, 会话结束时单独结束其手势
        dispatchContext.enqueueAdapterEnd()
        manualInputEnded = true
        momentumActive = false
        // 重置参数 (不递增 generation, 保留本次收尾帧有效性)
        resetUnlocked()
        os_unfair_lock_unlock(&stateLock)
#if DEBUG
        let diag = diagnosticsSnapshot()
        if diag.droppedFramesByGeneration > 0 || diag.droppedFramesByTTL > 0 || diag.updateSnapshotFailures > 0 {
            NSLog("[ScrollPoster] diag: posted=%llu dropGen=%llu dropTTL=%llu skipSynth=%llu snapFail=%llu",
                  diag.postedFrames, diag.droppedFramesByGeneration, diag.droppedFramesByTTL,
                  diag.skippedSyntheticEvents, diag.updateSnapshotFailures)
        }
#endif
    }
    func invalidateDisplayLayout() {
        cachedDisplayLayout = nil
    }

    // 重建帧时钟 (带冷却期), 显示器参数变化时调用
    @discardableResult
    func recreateDisplayLink() -> Bool {
        if clock.rebuild() { return true }
        guard clock.kind == .screen else { return false }
        useFixedClockAfterScreenFailure()
        return clockSessionActive
    }
    // 守护定时器
    func startKeeper() {
        monitorsClock = true
        clock.startMonitoring()
    }
    func stopKeeper() {
        monitorsClock = false
        clock.stopMonitoring()
    }
}

private extension ScrollPoster {
    func bindClock() {
        let revision = clockRevision
        clock.onTick = { [weak self] tick in self?.processing(tick, clockRevision: revision) }
    }

    func selectClockForSession() {
        var desiredKind = requestedClockKind
        if desiredKind == .screen {
            let display = displayForSession()
            if let screenClock = makeScreenClock(display?.id, { [weak self] in self?.useFixedClockAfterScreenFailure() }) {
                installClock(screenClock)
                return
            }
            markScreenClockUnavailable()
            desiredKind = .fixedRate
        }
        guard clock.kind != desiredKind else { return }
        installClock(desiredKind == .fixedRate ? makeFixedClock() : makeDisplayClock())
    }

    var requestedClockKind: ScrollFrameClockKind {
        if let clockOverride = clockOverride {
            return clockOverride == .screen && screenClockUnavailable ? .fixedRate : clockOverride
        }
        return .displayLink
    }

    func configureFrameRateForSession() {
        os_unfair_lock_lock(&stateLock)
        let normalizesTiming = config.normalizesTiming
        os_unfair_lock_unlock(&stateLock)

        let display = normalizesTiming && clock.kind == .displayLink ? displayForSession() : nil
        (clock as? DisplayLinkFrameClock)?.setPreferredDisplay(display)

        os_unfair_lock_lock(&stateLock)
        frameStopScheduled = false
        os_unfair_lock_unlock(&stateLock)
    }

    func displayForSession() -> ScrollDisplayLayout.Display? {
        if cachedDisplayLayout == nil { cachedDisplayLayout = displayLayout() }
        return cachedDisplayLayout?.display(at: inputLocation)
    }

    func markScreenClockUnavailable() {
        screenClockUnavailable = true
        NSLog("ScrollPoster: NSScreen display link unavailable, using 60 Hz timer")
    }

    func useFixedClockAfterScreenFailure() {
        guard clock.kind == .screen else { return }
        markScreenClockUnavailable()
        installClock(makeFixedClock())
        clockSessionActive = clock.start()
        if !clockSessionActive { reset() }
    }

    func installClock(_ replacement: ScrollFrameClock) {
        os_unfair_lock_lock(&stateLock)
        clockRevision &+= 1
        frameStopScheduled = false
        os_unfair_lock_unlock(&stateLock)
        clock.stopMonitoring()
        clock.stop()
        clock = replacement
        bindClock()
        clock.prepare()
        if monitorsClock { clock.startMonitoring() }
    }
}

// MARK: - 数据处理及发送
private extension ScrollPoster {
    func perform(_ plan: ScrollPhase.TransitionPlan, emitTargetImmediately: Bool, delta: (y: Double, x: Double) = (0.0, 0.0)) {
        if plan.queue.isEmpty && plan.target == nil {
            return
        }
        for item in plan.queue {
            emitPhase(item, delta: delta)
        }
        if let target = plan.target {
            if emitTargetImmediately {
                emitPhase(target, delta: delta)
            } else {
                ScrollPhase.shared.apply(phase: target.0, autoAdvance: target.1)
            }
        }
    }

    func emitPhase(_ item: (Phase, Phase?), delta: (y: Double, x: Double)) {
        ScrollPhase.shared.apply(phase: item.0, autoAdvance: item.1)
        guard let snapshot = dispatchContext.preparePostingSnapshot(), !snapshot.route.usesVirtualTrackpad else {
            ScrollPhase.shared.didDeliverFrame()
            return
        }
        _ = post(snapshot, delta)
    }

    // 处理滚动事件
    func processing(_ tick: FrameTick, clockRevision: UInt64) {
        var pendingStopPhase: Phase?
        os_unfair_lock_lock(&stateLock)
        guard self.clockRevision == clockRevision, !frameStopScheduled else {
            os_unfair_lock_unlock(&stateLock)
            return
        }
        let timing = config.normalizesTiming ? FrameTiming(interval: tick.interval, enabled: true) : .legacy
        let transition = timing.fraction(duration)
        // 计算插值
        let frame = (
            y: Interpolator.lerp(src: current.y, dest: buffer.y, trans: transition),
            x: Interpolator.lerp(src: current.x, dest: buffer.x, trans: transition)
        )
        // 更新滚动位置
        current = (
            y: current.y + frame.y,
            x: current.x + frame.x
        )
        // 平滑滚动结果
        let filledValue = filter.fill(with: frame, timing: timing)
        // 变换滚动结果，将滤波后的插值映射到当前姿态（考虑灵敏度、方向等因素）
        let shiftedValue = shift(with: filledValue)
        let now = CFAbsoluteTimeGetCurrent()
        // 检测是否已经超过手动输入的持续时间阈值，准备结束手动阶段
        if !manualInputEnded && lastManualEventTime > 0.0 && now - lastManualEventTime > manualContinuationThreshold {
            let endPlan = ScrollPhase.shared.onManualInputEnded()
            if !(endPlan.queue.isEmpty && endPlan.target == nil) {
                perform(endPlan, emitTargetImmediately: true)
            }
            manualInputEnded = true
            if trackingEndScheduledTime == nil {
                trackingEndScheduledTime = now + trackingEndAdvance
            }
        }
        // 计算缓冲值与当前位置的剩余距离，用于判断滚动是否已收敛
        let residualY = buffer.y - current.y
        let residualX = buffer.x - current.x
        let residualMagnitude = max(residualY.magnitude, residualX.magnitude)
        let deadZone = config.deadZone
        let frameDeadZone = deadZone * timing.scale
        let outputMagnitude = max(abs(shiftedValue.y), abs(shiftedValue.x))
        if config.usesVirtualTrackpad && manualInputEnded
            && outputMagnitude <= frameDeadZone && max(abs(frame.y), abs(frame.x)) <= frameDeadZone {
            // Holding stationary contacts until the CGEvent tail converges delays the native scroll's release.
            pendingStopPhase = .TrackingEnd
        } else if manualInputEnded && residualMagnitude > deadZone {
            if !momentumActive {
                perform(ScrollPhase.shared.onMomentumStart(), emitTargetImmediately: false)
                momentumActive = true
            } else {
                perform(ScrollPhase.shared.onMomentumOngoing(), emitTargetImmediately: false)
            }
            momentumEndScheduledTime = nil
            trackingEndScheduledTime = nil
        } else if momentumActive && residualMagnitude <= deadZone {
            if momentumEndScheduledTime == nil {
                momentumEndScheduledTime = now + momentumEndDelay
            }
        } else {
            momentumEndScheduledTime = nil
            if momentumActive {
                momentumActive = false
            }
        }
        // 发送滚动结果 - 只有当输出值超过死区阈值时才发送
        if outputMagnitude > frameDeadZone {
            if ScrollMonitorTrace.isRecording {
                ScrollMonitorTrace.shared.recordFrame(y: shiftedValue.y, x: shiftedValue.x)
            }
            postFrame(shiftedValue)
        } else if config.usesVirtualTrackpad && pendingStopPhase == nil {
            // A contact remains active between nonzero motion frames.
            postFrame((y: 0, x: 0))
        }

        if pendingStopPhase == nil, let scheduled = momentumEndScheduledTime, momentumActive {
            if now >= scheduled {
                momentumEndScheduledTime = nil
                momentumActive = false
                pendingStopPhase = .MomentumEnd
            }
        }
        if pendingStopPhase == nil && manualInputEnded && !momentumActive && residualMagnitude <= deadZone {
            let pendingStop = trackingEndScheduledTime != nil && now >= trackingEndScheduledTime!
            let outputSettled = outputMagnitude <= frameDeadZone
            if pendingStop && outputSettled {
                trackingEndScheduledTime = nil
                pendingStopPhase = .TrackingEnd
            }
        } else {
            trackingEndScheduledTime = nil
        }
        let inputRevision = self.inputRevision
        frameStopScheduled = pendingStopPhase != nil
        os_unfair_lock_unlock(&stateLock)
        guard let phase = pendingStopPhase else { return }

        // Clock lifecycle runs on the event-tap thread. A newer input can keep the session alive.
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            os_unfair_lock_lock(&self.stateLock)
            let isCurrent = self.frameStopScheduled && self.inputRevision == inputRevision
                && self.clockRevision == clockRevision
            os_unfair_lock_unlock(&self.stateLock)
            if isCurrent { self.stop(phase) }
        }
    }

    /// 主线程读取当前 (全局 / 例外应用) 配置存入快照。调用方须持有 stateLock。
    func captureConfigSnapshotLocked(usesVirtualTrackpad: Bool = false) {
        config = ConfigSnapshot(
            deadZone: Options.shared.scroll.deadZone,
            normalizesTiming: clockSessionActive ? config.normalizesTiming : Options.shared.scrollNormalizeTiming,
            usesVirtualTrackpad: usesVirtualTrackpad
        )
    }

    func phaseValues(for phase: Phase) -> (scroll: Double, momentum: Double)? {
        guard let scrollValue = PhaseValueMapping[phase]?[.Scroll],
              let momentumValue = PhaseValueMapping[phase]?[.Momentum] else {
            return nil
        }
        return (scroll: scrollValue, momentum: momentumValue)
    }

    @discardableResult
    func post(_ snapshot: ScrollDispatchContext.PostingSnapshot, _ v: (y: Double, x: Double), phaseOverride: (scroll: Double, momentum: Double)? = nil) -> Bool {
        // 适配器路由只取帧位移, 阶段由适配器的输出端生成
        if let sink = snapshot.route.sink {
            dispatchContext.enqueueAdapterFrame(snapshot, sink: sink, y: v.y, x: v.x)
            ScrollPhase.shared.didDeliverFrame()
            return true
        }
        if let override = phaseOverride {
            snapshot.event.setDoubleValueField(.scrollWheelEventScrollPhase, value: override.scroll)
            snapshot.event.setDoubleValueField(.scrollWheelEventMomentumPhase, value: override.momentum)
        }
        snapshot.event.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: v.y)
        snapshot.event.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: v.x)
        // 是否连续滚动: 始终为 1.0
        snapshot.event.setDoubleValueField(.scrollWheelEventIsContinuous, value: 1.0)
        ScrollUtils.shared.markSyntheticSmoothEvent(snapshot.event)
        // 通过 CGEventPostToPid 直投目标进程:
        // 不依赖 proxy (消除崩溃), 不经过 tap 链重新路由 (动量不跟随光标)
        // ref: @shichangone MR: https://github.com/Caldis/Mos/pull/523, issue #868
        dispatchContext.enqueue(snapshot)
        ScrollPhase.shared.didDeliverFrame()
        return true
    }

    func postFrame(_ delta: (y: Double, x: Double)) {
        guard let snapshot = dispatchContext.preparePostingSnapshot() else { return }
        if config.normalizesTiming, case .process = snapshot.route {
            post(snapshot, pointAccumulator.quantize(delta, for: snapshot.targetPID))
        } else {
            post(snapshot, delta)
        }
    }
}
