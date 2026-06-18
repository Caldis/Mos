//
//  ScrollPoster.swift
//  Mos
//
//  Created by Caldis on 2020/12/3.
//  Copyright © 2020 Caldis. All rights reserved.
//

import Cocoa
import os

enum ScrollAxisInputDecision: Equatable {
    case noInput
    case acceptedContinuation
    case acceptedReversal
    case ignoredOppositePulse
}

struct ScrollReverseCandidateState: Equatable {
    var sign = 0.0
    var count = 0

    mutating func clear() {
        sign = 0.0
        count = 0
    }
}

class ScrollPoster {

    // 单例
    static let shared = ScrollPoster()
    init() { NSLog("Module initialized: ScrollPoster") }

    // 插值器
    private let filter = ScrollFilter()
    // 发送器
    private var poster: CVDisplayLink?
    // 滚动数据
    private var current = (y: 0.0, x: 0.0)  // 当前滚动距离
    private var delta = (y: 0.0, x: 0.0)  // 滚动方向记录
    private var buffer = (y: 0.0, x: 0.0)  // 滚动缓冲距离
    private var reverseCandidateY = ScrollReverseCandidateState()
    private var reverseCandidateX = ScrollReverseCandidateState()
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
    private let reverseConfirmationCount = 2
    // 状态锁和投递上下文
    private var stateLock = os_unfair_lock_s()
    private let dispatchContext = ScrollDispatchContext.shared
    // 滚动配置快照: 主线程在 update 时捕获, CVDisplayLink 线程只读, 避免热路径跨线程读 Options/ScrollCore
    private struct ConfigSnapshot {
        var simTrackpadEnabled: Bool
        var deadZone: Double
    }
    private var config = ConfigSnapshot(simTrackpadEnabled: false, deadZone: 1.0)
    // CVDisplayLink 恢复机制
    private var keeper: Timer?
    private var lastCallbackTime: CFTimeInterval = 0.0
    private var lastRecreateAttempt: CFTimeInterval = 0.0
    private let recreateCooldown: CFTimeInterval = 3.0
    // 主线程访问, 无需锁
    var isAvailable: Bool { return poster != nil }
}

// MARK: - 滚动数据更新控制
extension ScrollPoster {
    @discardableResult
    func resolveAxisInput(
        input: Double,
        speed: Double,
        amplification: Double,
        deadZone: Double,
        current: inout Double,
        buffer: inout Double,
        delta: inout Double,
        reverseCandidate: inout ScrollReverseCandidateState
    ) -> ScrollAxisInputDecision {
        guard input != 0.0 else {
            reverseCandidate.clear()
            return .noInput
        }

        let sign = input.sign == .minus ? -1.0 : 1.0
        let acceptedSign = delta == 0.0 ? 0.0 : (delta.sign == .minus ? -1.0 : 1.0)
        let isDirectionFlip = acceptedSign != 0.0 && sign != acceptedSign
        let activeResidual = max((buffer - current).magnitude, current.magnitude) > deadZone

        if isDirectionFlip && activeResidual {
            if reverseCandidate.sign == sign {
                reverseCandidate.count += 1
            } else {
                reverseCandidate.sign = sign
                reverseCandidate.count = 1
            }
            if reverseCandidate.count < reverseConfirmationCount {
                return .ignoredOppositePulse
            }
        }

        reverseCandidate.clear()

        if input * delta > 0 {
            buffer += input * speed * amplification
            delta = input
            return .acceptedContinuation
        } else {
            buffer = input * speed * amplification
            current = 0.0
            delta = input
            return isDirectionFlip ? .acceptedReversal : .acceptedContinuation
        }
    }

    func update(event: CGEvent, duration: Double, y: Double, x: Double, speed: Double, amplification: Double = 1) -> Self {
        guard dispatchContext.capture(event: event) else {
            return self
        }
        os_unfair_lock_lock(&stateLock)
        defer { os_unfair_lock_unlock(&stateLock) }
        // 捕获本次手势的配置快照 (主线程读 Options/ScrollCore, CVDisplayLink 线程只读)
        captureConfigSnapshotLocked()
        // 更新滚动配置
        self.duration = duration
        let deadZone = Options.shared.scroll.deadZone
        // 更新滚动数据
        let yDecision = resolveAxisInput(
            input: y,
            speed: speed,
            amplification: amplification,
            deadZone: deadZone,
            current: &current.y,
            buffer: &buffer.y,
            delta: &delta.y,
            reverseCandidate: &reverseCandidateY
        )
        let xDecision = resolveAxisInput(
            input: x,
            speed: speed,
            amplification: amplification,
            deadZone: deadZone,
            current: &current.x,
            buffer: &buffer.x,
            delta: &delta.x,
            reverseCandidate: &reverseCandidateX
        )

        if yDecision == .acceptedReversal || xDecision == .acceptedReversal {
            // Prevent stale opposite-direction tail from leaking into the new run.
            filter.reset()
        }

        let now = CFAbsoluteTimeGetCurrent()
        let acceptedAny = yDecision == .acceptedContinuation || yDecision == .acceptedReversal
            || xDecision == .acceptedContinuation || xDecision == .acceptedReversal
        if !acceptedAny {
            if !manualInputEnded {
                lastManualEventTime = now
                trackingEndScheduledTime = nil
            }
            return self
        }

        let interval = lastManualEventTime > 0.0 ? now - lastManualEventTime : nil
        let separatedByTime = interval == nil ? true : interval! >= manualSeparationThreshold
        let phase = ScrollPhase.shared.phase
        let separatedPhase = (phase == .Idle || phase == .Leave || phase == .MomentumEnd || phase == .TrackingEnd)
        let separated = manualInputEnded || separatedByTime || separatedPhase
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
        perform(ScrollPhase.shared.onMomentumFinish(), emitTargetImmediately: true)
        manualInputEnded = true
        momentumActive = false
        momentumEndScheduledTime = nil
        os_unfair_lock_unlock(&stateLock)
    }
    func reset() {
        dispatchContext.invalidateAll()
        os_unfair_lock_lock(&stateLock)
        resetUnlocked()
        os_unfair_lock_unlock(&stateLock)
    }

#if DEBUG
    func captureConfigSnapshotForTests() {
        os_unfair_lock_lock(&stateLock)
        captureConfigSnapshotLocked()
        os_unfair_lock_unlock(&stateLock)
    }
    var configSnapshotForTests: (simTrackpadEnabled: Bool, deadZone: Double) {
        os_unfair_lock_lock(&stateLock)
        defer { os_unfair_lock_unlock(&stateLock) }
        return (config.simTrackpadEnabled, config.deadZone)
    }

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
        reverseCandidateY.clear()
        reverseCandidateX.clear()
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
    // 初始化 CVDisplayLink
    func create() {
        // 清理旧的 CVDisplayLink
        if let old = poster {
            if CVDisplayLinkIsRunning(old) {
                CVDisplayLinkStop(old)
            }
            poster = nil
        }
        // 创建新的 CVDisplayLink, 检查返回值
        var newPoster: CVDisplayLink?
        let result = CVDisplayLinkCreateWithActiveCGDisplays(&newPoster)
        if result == kCVReturnSuccess, let validPoster = newPoster {
            CVDisplayLinkSetOutputCallback(validPoster, { (displayLink, inNow, inOutputTime, flagsIn, flagsOut, displayLinkContext) -> CVReturn in
                ScrollPoster.shared.processing()
                return kCVReturnSuccess
            }, nil)
            poster = validPoster
        } else {
            poster = nil
            NSLog("ScrollPoster: CVDisplayLink creation failed (%d)", result)
        }
    }
    // 启动事件发送器
    func tryStart() {
        guard let validPoster = poster else {
            if !recreateDisplayLink() {
                // cooldown 拒绝了重建; 清理陈旧 buffer 防止恢复后滚动跳变
                reset()
            }
            return
        }
        if !CVDisplayLinkIsRunning(validPoster) {
            let result = CVDisplayLinkStart(validPoster)
            if result == kCVReturnSuccess {
                // 给 keeper 一个宽限期, 防止误判新启动的 poster 为僵尸
                os_unfair_lock_lock(&stateLock)
                lastCallbackTime = CFAbsoluteTimeGetCurrent()
                os_unfair_lock_unlock(&stateLock)
            } else {
                let _ = recreateDisplayLink()
            }
        }
    }
    // 停止事件发送器
    func stop(_ requestedPhase: Phase = Phase.MomentumEnd) {
        // 停止循环, 然后准备发送最后一次事件
        if let validPoster = poster {
            CVDisplayLinkStop(validPoster)
        }
        // 失效旧会话异步帧，收尾帧使用新代次
        dispatchContext.advanceGeneration()
        os_unfair_lock_lock(&stateLock)

        // 判断是否启用触控板模拟 (读 update 时主线程捕获的快照, 避免跨线程读)
        let enableSimTrackpad = config.simTrackpadEnabled
        let plan: ScrollPhase.TransitionPlan
        if requestedPhase == Phase.MomentumEnd {
            plan = ScrollPhase.shared.onMomentumFinish()
        } else {
            plan = ScrollPhase.shared.onManualInputEnded()
        }

        // 发送结束事件
        if enableSimTrackpad {
            perform(plan, emitTargetImmediately: true)
        } else {
            if let snapshot = dispatchContext.preparePostingSnapshot(),
               ScrollUtils.shared.isEventTargetingChrome(snapshot.event),
               let phaseValues = phaseValues(for: .TrackingEnd) {
                _ = post(
                    snapshot,
                    (y: 0.0, x: 0.0),
                    phaseOverride: phaseValues,
                    fallbackToCurrentPhase: false
                )
            }
        }
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
    // 重建 CVDisplayLink (带冷却期)
    @discardableResult
    func recreateDisplayLink() -> Bool {
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastRecreateAttempt >= recreateCooldown else { return false }
        lastRecreateAttempt = now
        create()
        if let validPoster = poster {
            let result = CVDisplayLinkStart(validPoster)
            if result == kCVReturnSuccess {
                os_unfair_lock_lock(&stateLock)
                lastCallbackTime = CFAbsoluteTimeGetCurrent()
                os_unfair_lock_unlock(&stateLock)
            } else {
                NSLog("ScrollPoster: CVDisplayLink start failed after recreate (%d)", result)
            }
        }
        return true
    }
    // 守护定时器 (与 Interceptor 的 keeper 模式一致)
    func startKeeper() {
        keeper?.invalidate()
        keeper = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.healthCheck()
        }
    }
    func stopKeeper() {
        keeper?.invalidate()
        keeper = nil
    }
    private func healthCheck() {
        guard let validPoster = poster else {
            recreateDisplayLink()
            return
        }
        if CVDisplayLinkIsRunning(validPoster) {
            os_unfair_lock_lock(&stateLock)
            let lastTime = lastCallbackTime
            os_unfair_lock_unlock(&stateLock)
            // lastTime > 0 避免首次回调前误判
            if lastTime > 0 && CFAbsoluteTimeGetCurrent() - lastTime > 2.0 {
                NSLog("ScrollPoster: zombie CVDisplayLink detected, recreating")
                recreateDisplayLink()
            }
        }
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
        guard let snapshot = dispatchContext.preparePostingSnapshot() else {
            ScrollPhase.shared.didDeliverFrame()
            return
        }
        let phaseOverride = resolveSimTrackpadEnabled() ? phaseValues(for: item.0) : nil
        _ = post(snapshot, delta, phaseOverride: phaseOverride, fallbackToCurrentPhase: false)
    }

    // 处理滚动事件
    func processing() {
        var pendingStopPhase: Phase?
        os_unfair_lock_lock(&stateLock)
        lastCallbackTime = CFAbsoluteTimeGetCurrent()
        // 计算插值
        let frame = (
            y: Interpolator.lerp(src: current.y, dest: buffer.y, trans: duration),
            x: Interpolator.lerp(src: current.x, dest: buffer.x, trans: duration)
        )
        // 更新滚动位置
        current = (
            y: current.y + frame.y,
            x: current.x + frame.x
        )
        // 平滑滚动结果
        let filledValue = filter.fill(with: frame)
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
        if manualInputEnded && residualMagnitude > deadZone {
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
        let outputMagnitude = max(abs(shiftedValue.y), abs(shiftedValue.x))
        if outputMagnitude > deadZone {
            _ = post(shiftedValue)
        }

        if let scheduled = momentumEndScheduledTime, momentumActive {
            if now >= scheduled {
                momentumEndScheduledTime = nil
                momentumActive = false
                pendingStopPhase = .MomentumEnd
            }
        }
        if pendingStopPhase == nil && manualInputEnded && !momentumActive && residualMagnitude <= deadZone {
            let pendingStop = trackingEndScheduledTime != nil && now >= trackingEndScheduledTime!
            let outputSettled = outputMagnitude <= deadZone
            if pendingStop && outputSettled {
                trackingEndScheduledTime = nil
                pendingStopPhase = .TrackingEnd
            }
        } else {
            trackingEndScheduledTime = nil
        }
        os_unfair_lock_unlock(&stateLock)
        if let phase = pendingStopPhase {
            stop(phase)
            return
        }
    }

    /// 主线程读取当前 (全局 / 例外应用) 配置存入快照。调用方须持有 stateLock。
    func captureConfigSnapshotLocked() {
        let simTrackpad: Bool
        if let application = ScrollCore.shared.application, !application.inherit {
            simTrackpad = application.scroll.smoothSimTrackpad
        } else {
            simTrackpad = Options.shared.scroll.smoothSimTrackpad
        }
        config = ConfigSnapshot(
            simTrackpadEnabled: simTrackpad,
            deadZone: Options.shared.scroll.deadZone
        )
    }

    func resolveSimTrackpadEnabled() -> Bool {
        return config.simTrackpadEnabled
    }

    func phaseValues(for phase: Phase) -> (scroll: Double, momentum: Double)? {
        guard let scrollValue = PhaseValueMapping[phase]?[.Scroll],
              let momentumValue = PhaseValueMapping[phase]?[.Momentum] else {
            return nil
        }
        return (scroll: scrollValue, momentum: momentumValue)
    }

    @discardableResult
    func post(_ snapshot: ScrollDispatchContext.PostingSnapshot, _ v: (y: Double, x: Double), phaseOverride: (scroll: Double, momentum: Double)? = nil, fallbackToCurrentPhase: Bool = true) -> Bool {
        if let override = phaseOverride {
            snapshot.event.setDoubleValueField(.scrollWheelEventScrollPhase, value: override.scroll)
            snapshot.event.setDoubleValueField(.scrollWheelEventMomentumPhase, value: override.momentum)
        } else if fallbackToCurrentPhase,
                  resolveSimTrackpadEnabled(),
                  let currentPhaseValues = phaseValues(for: ScrollPhase.shared.phase) {
            snapshot.event.setDoubleValueField(.scrollWheelEventScrollPhase, value: currentPhaseValues.scroll)
            snapshot.event.setDoubleValueField(.scrollWheelEventMomentumPhase, value: currentPhaseValues.momentum)
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

    @discardableResult
    func post(_ v: (y: Double, x: Double), phaseOverride: (scroll: Double, momentum: Double)? = nil, fallbackToCurrentPhase: Bool = true) -> Bool {
        guard let snapshot = dispatchContext.preparePostingSnapshot() else {
            return false
        }
        return post(
            snapshot,
            v,
            phaseOverride: phaseOverride,
            fallbackToCurrentPhase: fallbackToCurrentPhase
        )
    }
}
