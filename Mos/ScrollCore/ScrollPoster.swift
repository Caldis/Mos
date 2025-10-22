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
    // 外部依赖
    var ref: (event: CGEvent?, proxy: CGEventTapProxy?) = (event: nil, proxy: nil)
}

// MARK: - 滚动数据更新控制
extension ScrollPoster {
    func update(event: CGEvent, proxy: CGEventTapProxy, duration: Double, y: Double, x: Double, speed: Double, amplification: Double = 1) -> Self {
        // 更新依赖数据
        ref.event = event
        ref.proxy = proxy
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
    }
    func reset() {
        // 重置数值
        ref = (event: nil, proxy: nil)
        current = ( y: 0.0, x: 0.0 )
        delta = ( y: 0.0, x: 0.0 )
        buffer = ( y: 0.0, x: 0.0 )
        // 重置插值器
        filter.reset()
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

        // 设置停止阶段
        // 规则: 只有当前为 Momentum 才允许用 MomentumEnd
        let currentPhase = ScrollPhase.shared.phase
        if requestedPhase == Phase.MomentumEnd && currentPhase == Phase.MomentumOngoing {
            ScrollPhase.shared.stop(Phase.MomentumEnd)
        } else {
            ScrollPhase.shared.stop(Phase.TrackingEnd)
        }

        // 发送结束事件
        if enableSimTrackpad {
            // 触控板模拟启用: 发送正确的 Phase 结束事件
            // MomentumEnded (0, 3) 或 Cancelled (4, 0)
            if ref.event != nil {
                post(ref, (y: 0.0, x: 0.0))
            }
        } else {
            // 触控板模拟未启用: 保留 Chrome 特殊处理
            if let validEvent = ref.event, ScrollUtils.shared.isEventTargetingChrome(validEvent) {
                // 需要附加特定的阶段数据, 只有 Phase.PauseManual 对应的 [4.0, 0.0] 可以正确使 Chrome 恢复
                validEvent
                    .setDoubleValueField(
                        .scrollWheelEventScrollPhase,
                        value: PhaseValueMapping[Phase.TrackingEnd]![PhaseItem.Scroll]!
                    )
                validEvent.setDoubleValueField(.scrollWheelEventMomentumPhase, value: PhaseValueMapping[Phase.TrackingEnd]![PhaseItem.Momentum]!)
                post(ref, (y: 0.0, x: 0.0))
            }
        }
        // 重置参数
        reset()
    }
}

// MARK: - 数据处理及发送
private extension ScrollPoster {
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
        // 变换滚动结果
        let shiftedValue = shift(with: filledValue)
        // 发送滚动结果
        post(ref, shiftedValue)
        // 如果临近目标距离小于精确度门限则暂停滚动
        if (
            frame.y.magnitude <= Options.shared.scroll.precision &&
            frame.x.magnitude <= Options.shared.scroll.precision
        ) {
            stop(Phase.MomentumEnd)
        }
    }
    func post(_ r: (event: CGEvent?, proxy: CGEventTapProxy?), _ v: (y: Double, x: Double)) {
        if let proxy = r.proxy, let eventClone = r.event?.copy() {
            // 判断是否需要模拟触控板 Phase
            var enableSimTrackpad = Options.shared.scroll.smoothSimTrackpad
            if let application = ScrollCore.shared.application {
                enableSimTrackpad = application.inherit ? Options.shared.scroll.smoothSimTrackpad : application.scroll.smoothSimTrackpad
            }
            // 设置阶段数据和触控板特征字段
            if enableSimTrackpad {
                let currentPhase = ScrollPhase.shared.phase
                eventClone.setDoubleValueField(.scrollWheelEventScrollPhase, value: PhaseValueMapping[currentPhase]![PhaseItem.Scroll]!)
                eventClone.setDoubleValueField(.scrollWheelEventMomentumPhase, value: PhaseValueMapping[currentPhase]![PhaseItem.Momentum]!)
                ScrollPhase.shared.transfrom()
            }
            // 设置滚动数据
            eventClone.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: v.y)
            eventClone.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: v.x)
            eventClone.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: 0.0)
            eventClone.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: 0.0)
            // 是否连续滚动: 始终为 1.0
            eventClone.setDoubleValueField(.scrollWheelEventIsContinuous, value: 1.0)
            // EventTapProxy:
            // 标识了 EventTapCallback 在事件流中接收到事件的特定位置, 其粒度小于 tap 本身
            // 使用 tapPostEvent 可以将自定义的事件发布到 proxy 标识的位置, 避免被 EventTapCallback 本身重复接收或处理
            // 新发布的事件将早于 EventTapCallback 所处理的事件进入系统, 也如同 EventTapCallback 所处理的事件, 会被所有后续的 EventTap 接收
            // fixed by @shichangone MR: https://github.com/Caldis/Mos/pull/523
            DispatchQueue.main.async { eventClone.tapPostEvent(proxy) }
        }
    }
}
