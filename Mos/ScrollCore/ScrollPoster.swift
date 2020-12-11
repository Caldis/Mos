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
    
    var ts = Date.currentTimeStamp
    // 插值器
    private let filler = ScrollFiller()
    private let interpolator = Interpolator.lerp
    // 发送器
    private var poster: CVDisplayLink?
    // 滚动数据
    private var scrollCurr   = ( y: 0.0, x: 0.0 )  // 当前滚动距离
    private var scrollDelta  = ( y: 0.0, x: 0.0 )  // 滚动方向记录
    private var scrollBuffer = ( y: 0.0, x: 0.0 )  // 滚动缓冲距离
    // 外部依赖
    var ref: ( event: CGEvent?, proxy: CGEventTapProxy?, swap: Bool, duration: Double ) = ( event: nil, proxy: nil, swap: false, duration: Options.shared.scrollAdvanced.durationTransition )
}

// MARK: - 滚动数据更新控制
extension ScrollPoster {
    func update(event: CGEvent, proxy: CGEventTapProxy, swap: Bool, duration: Double, y: Double, x: Double, speed: Double, amplification: Double = 1) -> Self {
        // 更新依赖数据
        ref.event = event
        ref.proxy = proxy
        ref.swap = swap
        ref.duration = duration
        // 更新滚动数据
        if y*scrollDelta.y > 0 {
            scrollBuffer.y += y * speed * amplification
        } else {
            scrollBuffer.y = y * speed * amplification
            scrollCurr.y = 0.0
        }
        if x*scrollDelta.x > 0 {
            scrollBuffer.x += x * speed * amplification
        } else {
            scrollBuffer.x = x * speed * amplification
            scrollCurr.x = 0.0
        }
        scrollDelta = ( y: y, x: x )
        return self
    }
    func swap(with nextValue: ( y: Double, x: Double ), flag: Bool) -> (y: Double, x: Double) {
        // 如果按下 Shift, 则始终将滚动转为横向
        if flag {
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
    func reset() {
        // 重置数值
        scrollCurr = ( y: 0.0, x: 0.0 )
        scrollDelta = ( y: 0.0, x: 0.0 )
        scrollBuffer = ( y: 0.0, x: 0.0 )
        // 重置插值器
        filler.reset()
    }
}

extension Date {
    static var currentTimeStamp: Int64{
        return Int64(Date().timeIntervalSince1970 * 1000)
    }
}

// MARK: - 插值数据发送控制
extension ScrollPoster {
    // 初始化 CVDisplayLink
    func create() {
        // 新建一个 CVDisplayLinkSetOutputCallback 来执行循环
        CVDisplayLinkCreateWithActiveCGDisplays(&poster)
        CVDisplayLinkSetOutputCallback(poster!, { (displayLink, inNow, inOutputTime, flagsIn, flagsOut, displayLinkContext) -> CVReturn in
//            let cur = Date.currentTimeStamp
//            NSLog("%d, %d", cur - ScrollPoster.shared.ts, cur)
//            ScrollPoster.shared.ts = cur
            ScrollPoster.shared.beforePost()
            return kCVReturnSuccess
        }, nil)
    }
    // 启动事件发送器
    func enable() {
        if !CVDisplayLinkIsRunning(poster!) {
            CVDisplayLinkStart(poster!)
        }
    }
    // 暂停事件发送器
    func pause() {
        ScrollCore.shared.phase = Phase.Pause
        reset()
    }
    // 停止事件发送器
    func disable() {
        pause()
        if let validPoster = poster {
            CVDisplayLinkStop(validPoster)
            afterPost()
        }
    }
}

// MARK: - 数据处理及发送
private extension ScrollPoster {
    // 预处理滚动事件
    func beforePost() {
        // 计算插值
        let scrollPulse = (
            y: interpolator(scrollCurr.y, scrollBuffer.y, ref.duration),
            x: interpolator(scrollCurr.x, scrollBuffer.x, ref.duration)
        )
        // 更新滚动位置
        scrollCurr = (
            y: scrollCurr.y + scrollPulse.y,
            x: scrollCurr.x + scrollPulse.x
        )
        // 平滑滚动结果
        let filledValue = filler.fill(with: scrollPulse)
        // 变换滚动结果
        let swapedValue = swap(with: filledValue, flag: ref.swap)
        // 发送滚动结果
        if let proxy = ref.proxy, let event = ref.event {
            post(proxy, event, swapedValue)
        }
        // 如果临近目标距离小于精确度门限则暂停滚动
        if (
            scrollPulse.y.magnitude <= Options.shared.scrollAdvanced.precision &&
            scrollPulse.x.magnitude <= Options.shared.scrollAdvanced.precision
        ) {
             disable()
        }
    }
    // 发送滚动事件
    func post(_ proxy: CGEventTapProxy, _ event: CGEvent, _ value: ( y: Double, x: Double )) {
        if let eventClone = event.copy() {
            let phase = ScrollCore.shared.consume()
            if phase == Phase.Pause {
                let phaseValue = PhaseValueMapping[phase]
                if let validPhaseValue = phaseValue {
                    eventClone.setDoubleValueField(.scrollWheelEventScrollPhase, value: validPhaseValue.s)
                    eventClone.setDoubleValueField(.scrollWheelEventMomentumPhase, value: validPhaseValue.m)
                }
            }
            eventClone.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: value.y)
            eventClone.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: value.x)
            eventClone.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: 0.0)
            eventClone.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: 0.0)
            eventClone.setDoubleValueField(.scrollWheelEventIsContinuous, value: 1.0)
            // EventTapProxy 标识了 EventTapCallback 在事件流中接收到事件的特定位置, 其粒度小于 tap 本身
            // 使用 tapPostEvent 可以将自定义的事件发布到 proxy 标识的位置, 避免被 EventTapCallback 本身重复接收或处理
            // 新发布的事件将早于 EventTapCallback 所处理的事件进入系统, 也如同 EventTapCallback 所处理的事件, 会被所有后续的 EventTap 接收
            eventClone.tapPostEvent(proxy)
        }
    }
    // 后处理滚动事件
    func afterPost() {
        if let proxy = ref.proxy, let event = ref.event {
            post(proxy, event, ( x: 0.0, y: 0.0 ))
        }
    }
}
