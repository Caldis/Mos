//
//  ScrollPoster.swift
//  Mos
//
//  Created by Caldis on 2020/12/3.
//  Copyright © 2020 Caldis. All rights reserved.
//

import Cocoa

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
    // 外部依赖
    var ref: (event: CGEvent?, proxy: CGEventTapProxy?) = (event: nil, proxy: nil)
    // 线程同步锁 - 保护 ref 的跨线程访问
    private var refLock = os_unfair_lock()
}

// MARK: - 滚动数据更新控制
extension ScrollPoster {
    func update(event: CGEvent, proxy: CGEventTapProxy, duration: Double, y: Double, x: Double, speed: Double, amplification: Double = 1) -> Self {
        // 更新依赖数据（加锁保护，防止与 CVDisplayLink 线程竞争）
        os_unfair_lock_lock(&refLock)
        ref.event = event
        ref.proxy = proxy
        os_unfair_lock_unlock(&refLock)
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
        shifting = enable
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
        ScrollPoster.shared.buffer = ScrollPoster.shared.current
        perform(ScrollPhase.shared.onMomentumFinish(), emitTargetImmediately: true)
        manualInputEnded = true
        momentumActive = false
        momentumEndScheduledTime = nil
    }
    func reset() {
        // 重置数值（加锁保护，防止与 CVDisplayLink 线程竞争）
        os_unfair_lock_lock(&refLock)
        ref = (event: nil, proxy: nil)
        os_unfair_lock_unlock(&refLock)
        current = ( y: 0.0, x: 0.0 )
        delta = ( y: 0.0, x: 0.0 )
        buffer = ( y: 0.0, x: 0.0 )
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
        // 新建一个 CVDisplayLinkSetOutputCallback 来执行循环
        CVDisplayLinkCreateWithActiveCGDisplays(&poster)
        if let validPoster = poster {
            CVDisplayLinkSetOutputCallback(validPoster, { (displayLink, inNow, inOutputTime, flagsIn, flagsOut, displayLinkContext) -> CVReturn in
                ScrollPoster.shared.processing()
                return kCVReturnSuccess
            }, nil)
        }
    }
    // 启动事件发送器
    func tryStart() {
        if let validPoster = poster {
            if !CVDisplayLinkIsRunning(validPoster) {
                CVDisplayLinkStart(validPoster)
            }
        }
    }
    // 停止事件发送器
    func stop(_ requestedPhase: Phase = Phase.MomentumEnd) {
        // 停止循环, 然后准备发送最后一次事件
        if let validPoster = poster {
            CVDisplayLinkStop(validPoster)
        }

        // 判断是否启用触控板模拟
        var enableSimTrackpad = Options.shared.scroll.smoothSimTrackpad
        if let application = ScrollCore.shared.application {
            enableSimTrackpad = application.inherit
                ? Options.shared.scroll.smoothSimTrackpad
                : application.scroll.smoothSimTrackpad
        }
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
            // 加锁获取 ref 快照，防止竞争条件
            os_unfair_lock_lock(&refLock)
            let refSnapshot = (event: ref.event, proxy: ref.proxy)
            os_unfair_lock_unlock(&refLock)
            if let validEvent = refSnapshot.event, ScrollUtils.shared.isEventTargetingChrome(validEvent) {
                validEvent
                    .setDoubleValueField(
                        .scrollWheelEventScrollPhase,
                        value: PhaseValueMapping[Phase.TrackingEnd]![PhaseItem.Scroll]!
                    )
                validEvent.setDoubleValueField(.scrollWheelEventMomentumPhase, value: PhaseValueMapping[Phase.TrackingEnd]![PhaseItem.Momentum]!)
                post(refSnapshot, (y: 0.0, x: 0.0))
            }
        }
        manualInputEnded = true
        momentumActive = false
        // 重置参数
        reset()
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
        // 加锁获取 ref 快照并立即拷贝，防止竞争条件
        os_unfair_lock_lock(&refLock)
        let proxy = ref.proxy
        let eventClone = ref.event?.copy()
        os_unfair_lock_unlock(&refLock)
        guard let validProxy = proxy, let validEventClone = eventClone else {
            ScrollPhase.shared.didDeliverFrame()
            return
        }
        var enableSimTrackpad = Options.shared.scroll.smoothSimTrackpad
        if let application = ScrollCore.shared.application {
            enableSimTrackpad = application.inherit ? Options.shared.scroll.smoothSimTrackpad : application.scroll.smoothSimTrackpad
        }
        if enableSimTrackpad {
            if let scrollValue = PhaseValueMapping[item.0]?[PhaseItem.Scroll], let momentumValue = PhaseValueMapping[item.0]?[PhaseItem.Momentum] {
                validEventClone.setDoubleValueField(.scrollWheelEventScrollPhase, value: scrollValue)
                validEventClone.setDoubleValueField(.scrollWheelEventMomentumPhase, value: momentumValue)
            }
        }
        validEventClone.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: delta.y)
        validEventClone.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: delta.x)
        validEventClone.setDoubleValueField(.scrollWheelEventIsContinuous, value: 1.0)
        DispatchQueue.main.async { validEventClone.tapPostEvent(validProxy) }
        ScrollPhase.shared.didDeliverFrame()
    }

    // 处理滚动事件
    func processing() {
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
        let deadZone = Options.shared.scroll.deadZone
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
            // 加锁获取 ref 快照，防止竞争条件
            os_unfair_lock_lock(&refLock)
            let refSnapshot = (event: ref.event, proxy: ref.proxy)
            os_unfair_lock_unlock(&refLock)
            post(refSnapshot, shiftedValue)
        }

        if let scheduled = momentumEndScheduledTime, momentumActive {
            if now >= scheduled {
                momentumEndScheduledTime = nil
                momentumActive = false
                stop(Phase.MomentumEnd)
                return
            }
        }
        if manualInputEnded && !momentumActive && residualMagnitude <= deadZone {
            let pendingStop = trackingEndScheduledTime != nil && now >= trackingEndScheduledTime!
            let outputSettled = outputMagnitude <= deadZone
            if pendingStop && outputSettled {
                trackingEndScheduledTime = nil
                stop(.TrackingEnd)
                return
            }
        } else {
            trackingEndScheduledTime = nil
        }
    }
    func post(_ r: (event: CGEvent?, proxy: CGEventTapProxy?), _ v: (y: Double, x: Double)) {
        if let proxy = r.proxy, let eventClone = r.event?.copy() {
            // 判断是否需要模拟触控板 Phase
            var enableSimTrackpad = Options.shared.scroll.smoothSimTrackpad
            if let application = ScrollCore.shared.application, !application.inherit {
                enableSimTrackpad = application.scroll.smoothSimTrackpad
            }
            
            // 设置阶段数据和触控板特征字段
            if enableSimTrackpad {
                // 获取当前 phase 值, 然后更新对应 proxy 值
                let currentPhase = ScrollPhase.shared.phase
                if let scrollValue = PhaseValueMapping[currentPhase]?[.Scroll], let momentumValue = PhaseValueMapping[currentPhase]?[.Momentum] {
                    eventClone.setDoubleValueField(.scrollWheelEventScrollPhase, value: scrollValue)
                    eventClone.setDoubleValueField(.scrollWheelEventMomentumPhase, value: momentumValue)
                }
            }

            // 设置滚动数据
            eventClone.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: v.y)
            eventClone.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: v.x)

            // 是否连续滚动: 始终为 1.0
            eventClone.setDoubleValueField(.scrollWheelEventIsContinuous, value: 1.0)

            // EventTapProxy:
            // 标识了 EventTapCallback 在事件流中接收到事件的特定位置, 其粒度小于 tap 本身
            // 使用 tapPostEvent 可以将自定义的事件发布到 proxy 标识的位置, 避免被 EventTapCallback 本身重复接收或处理
            // 新发布的事件将早于 EventTapCallback 所处理的事件进入系统, 会被所有后续的 EventTap 接收
            // fixed by @shichangone MR: https://github.com/Caldis/Mos/pull/523
            DispatchQueue.main.async { eventClone.tapPostEvent(proxy) }

            // 更新阶段切换帧
            ScrollPhase.shared.didDeliverFrame()
        }
    }
}
