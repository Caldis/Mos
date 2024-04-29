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
    private var startTime = 0.0 // 起始滚动时间
    private var start = (y: 0.0, x: 0.0) // 起始滚动位置
    private var current = (y: 0.0, x: 0.0)  // 当前滚动距离
    private var delta = (y: 0.0, x: 0.0)  // 滚动方向记录
    private var buffer = (y: 0.0, x: 0.0)  // 滚动缓冲距离
    private var duration = 300.0 // 最终计算后的过渡时长
    // 滚动配置
    private var shifting = false
    // 外部依赖
    var ref: (event: CGEvent?, proxy: CGEventTapProxy?) = (event: nil, proxy: nil)
}

// MARK: - 滚动数据更新控制
extension ScrollPoster {
    func update(event: CGEvent, proxy: CGEventTapProxy, duration: Double, y: Double, x: Double, speed: Double, amplification: Double = 1) -> Self {
        // 更新依赖数据
        ref.event = event
        ref.proxy = proxy

        let newDeltaY = y * speed * amplification
        let newDeltaX = x * speed * amplification

        // 根据待滚动距离计算所需过渡时长，以 300ms 为最小持续时长，到达 10000px 时持续时长达到最大，时长非线性递增
        // x，y 所需时长谁大取谁
        var dur = 0.0

        // 更新滚动数据
        if y*delta.y > 0 {
            let remaining = abs(buffer.y - current.y)
            start.y = current.y
            buffer.y += newDeltaY
            dur = max(dur, 300 + Tween.easeOutQuint(x: (abs(newDeltaY) + remaining).clamped(to: 0 ... 10000) / 10000) * duration)
        } else {
            start.y = 0.0
            current.y = 0.0
            buffer.y = newDeltaY
            dur = max(dur, 300 + Tween.easeOutQuint(x: abs(newDeltaY).clamped(to: 0 ... 10000) / 10000) * duration)
        }
        if x*delta.x > 0 {
            let remaining = abs(buffer.x - current.x)
            start.x = current.x
            current.x = 0.0
            buffer.x += newDeltaX
            dur = max(dur, 300 + Tween.easeOutQuint(x: (abs(newDeltaX) + remaining).clamped(to: 0 ... 10000) / 10000) * duration)
        } else {
            start.x = 0.0
            buffer.x = newDeltaX
            dur = max(dur, 300 + Tween.easeOutQuint(x: abs(newDeltaX).clamped(to: 0 ... 10000) / 10000) * duration)
        }

        delta = (y: y, x: x)
        startTime = NSDate().timeIntervalSince1970
        self.duration = dur

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
                startTime = NSDate().timeIntervalSince1970
            }
        }
    }
    // 停止事件发送器
    func stop(_ phase: Phase = Phase.PauseManual) {
        // 停止循环
        if let validPoster = poster {
            CVDisplayLinkStop(validPoster)
        }
        // 先设置阶段为停止
        ScrollPhase.shared.stop(phase)
        // 对于 Phase.PauseAuto, 我们在结束前额外发送一个事件来重置 Chrome 的滚动缓冲区
        if let validEvent = ref.event, ScrollUtils.shared.isEventTargetingChrome(validEvent) {
            // 需要附加特定的阶段数据, 只有 Phase.PauseManual 对应的 [4.0, 0.0] 可以正确使 Chrome 恢复
            validEvent.setDoubleValueField(.scrollWheelEventScrollPhase, value: PhaseValueMapping[Phase.PauseManual]![PhaseItem.Scroll]!)
            validEvent.setDoubleValueField(.scrollWheelEventMomentumPhase, value: PhaseValueMapping[Phase.PauseManual]![PhaseItem.Momentum]!)
            do {
                try  post(ref, (y: 0.0, x: 0.0))
            } catch {}
        }
        // 重置参数
        reset()
    }
}

// MARK: - 数据处理及发送
private extension ScrollPoster {
    // 处理滚动事件
    func processing() {
        let now = NSDate().timeIntervalSince1970
        let diffMs = (now - startTime) * 1000

        if (diffMs <= duration) {
            let perc = Tween.easeOutQuint(x: diffMs / duration)
            let oldCurrent = current
            // 计算插值
            current = (
                y: (buffer.y - start.y) * perc + start.y,
                x: (buffer.x - start.x) * perc + start.x
            )
            let nextDelta = (
                y: current.y - oldCurrent.y,
                x: current.x - oldCurrent.x
            )
            // 平滑滚动结果
            let filledValue = filter.fill(with: nextDelta)
            // 变换滚动结果
            let shiftedValue = shift(with: filledValue)
            // 发送滚动结果
            do {
                try post(ref, shiftedValue)
            } catch {}
        } else {
            stop(Phase.PauseAuto)
        }
    }
    func post(_ r: (event: CGEvent?, proxy: CGEventTapProxy?), _ v: (y: Double, x: Double)) throws {
        if let proxy = r.proxy, let eventClone = r.event?.copy() {
            // 设置阶段数据
            ScrollPhase.shared.transfrom()
            // 设置滚动数据
            eventClone.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: v.y)
            eventClone.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: v.x)
            eventClone.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: 0.0)
            eventClone.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: 0.0)
            eventClone.setDoubleValueField(.scrollWheelEventIsContinuous, value: 1.0)
            // EventTapProxy 标识了 EventTapCallback 在事件流中接收到事件的特定位置, 其粒度小于 tap 本身
            // 使用 tapPostEvent 可以将自定义的事件发布到 proxy 标识的位置, 避免被 EventTapCallback 本身重复接收或处理
            // 新发布的事件将早于 EventTapCallback 所处理的事件进入系统, 也如同 EventTapCallback 所处理的事件, 会被所有后续的 EventTap 接收
            eventClone.tapPostEvent(proxy)
        }
    }
}
