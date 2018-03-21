//
//  ScrollCore.swift
//  Mos
//  滚动事件截取与插值计算核心类
//  Created by Caldis on 2017/1/14.
//  Copyright © 2017年 Caldis. All rights reserved.
//

import Cocoa

class ScrollCore {
    
    // 单例
    static let shared = ScrollCore()
    init() { print("Class 'ScrollCore' is a singleton, use the 'ScrollCore.shared' to access it.") }
    
    // 鼠标事件轴
    let axis = ( Y: UInt32(1), X: UInt32(1), YX: UInt32(2), YXZ: UInt32(3) )
    // 滚动数据
    var scrollCurr   = ( y: 0.0, x: 0.0 )  // 当前滚动距离
    var scrollBuffer = ( y: 0.0, x: 0.0 )  // 滚动缓冲距离
    var scrollDelta  = ( y: 0.0, x: 0.0 )  // 滚动方向记录
    // 滚动数值滤波器, 用于去除滚动的起始抖动
    var scrollFilter = ScrollFilter()
    // 事件发送器
    var scrollEventPoster: CVDisplayLink?
    
    // 处理滚动事件
    func handleScroll() {
        // 计算插值
        let scrollPulse = (
            y: Interpolation.lerp(src: scrollCurr.y, dest: scrollBuffer.y),
            x: Interpolation.lerp(src: scrollCurr.x, dest: scrollBuffer.x)
        )
        // 更新滚动位置
        scrollCurr = (
            y: scrollCurr.y + scrollPulse.y,
            x: scrollCurr.x + scrollPulse.x
        )
        // 对峰值进行滤波
        scrollFilter.update(with: scrollPulse)
        if scrollFilter.onRunningState() {
            let filteredValue = scrollFilter.value()
            // 发送滚动结果
            MouseEvent.scroll(axis.YX, yScroll: Int32(filteredValue.y), xScroll: Int32(filteredValue.x))
            // 如果临近目标距离小于精确度门限则停止滚动
            if abs(scrollPulse.y)<=Options.shared.advanced.precision && abs(scrollPulse.x)<=Options.shared.advanced.precision {
                disableScrollEventPoster()
                scrollFilter.clean()
            }
        }
    }
    
    // eventTap 相关, 用于拦截以及获取系统的滚动事件
    // 拦截层句柄
    var eventTap:CFMachPort?
    // 拦截层掩码
    let mask = CGEventMask(1 << CGEventType.scrollWheel.rawValue)
    // 拦截层处理函数
    let eventCallBack: CGEventTapCallBack = { (proxy, type, event, refcon) in
        // 是否返回原始事件 (不启用平滑时)
        var returnOriginalEvent = true
        // 判断输入源 (无法区分黑苹果, 因为黑苹果的触控板驱动直接模拟鼠标输入)
        // 当鼠标输入, 根据需要执行翻转方向/平滑滚动
        if ScrollUtils.shared.isMouse(of: event) {
            // 获取目标窗口 BundleId
            let eventTargetBID = ScrollUtils.shared.getCurrentEventTargetBundleId(from: event)
            // 获取列表中应用程序的列外设置信息
            let exceptionalApplications = ScrollUtils.shared.applicationInExceptionalApplications(bundleId: eventTargetBID)
            let enableReverse = ScrollUtils.shared.enableReverse(application: exceptionalApplications)
            let enableSmooth = ScrollUtils.shared.enableSmooth(application: exceptionalApplications)
            // 处理滚动事件
            let scrollEventY = ScrollEvent(with: event, use: ScrollEvent.axis.Y)
            let scrollEventX = ScrollEvent(with: event, use: ScrollEvent.axis.X)
            // Y轴
            if scrollEventY.isUsable() {
                // 是否翻转滚动
                if enableReverse {
                    scrollEventY.reverse(axis: ScrollEvent.axis.Y)
                }
                // 是否平滑滚动
                if enableSmooth {
                    // 禁止返回原始事件
                    returnOriginalEvent = false
                    // 如果输入值为非 Fixed 类型, 则使用 Step 作为门限值将数据归一化
                    if !scrollEventY.isFixedType() {
                        scrollEventY.normalize(threshold: Options.shared.advanced.step)
                    }
                }
            }
            // X轴
            if scrollEventX.isUsable() {
                // 是否翻转滚动
                if enableReverse {
                    scrollEventX.reverse(axis: ScrollEvent.axis.X)
                }
                // 是否平滑滚动
                if enableSmooth {
                    // 禁止返回原始事件
                    returnOriginalEvent = false
                    // 如果输入值为非 Fixed 类型, 则使用 Step 作为门限值将数据归一化
                    if !scrollEventX.isFixedType() {
                        scrollEventX.normalize(threshold: Options.shared.advanced.step)
                    }
                }
            }
            // 触发滚动事件推送
            if (enableSmooth) {
                ScrollCore.shared.updateScrollBuffer(y: scrollEventY.getValue(), x: scrollEventX.getValue())
                ScrollCore.shared.enableScrollEventPoster()
            }
        }
        // 返回事件对象
        if returnOriginalEvent {
            return Unmanaged.passRetained(event)
        } else {
            return nil
        }
    }
    
    
    // 更新滚动缓冲区
    func updateScrollBuffer(y: Double, x: Double) {
        let speed = Options.shared.advanced.speed
        // 更新 Y 轴数据
        if y*scrollDelta.y > 0 {
            scrollBuffer.y += speed * y
        } else {
            scrollBuffer.y = speed * y
            scrollCurr.y = 0.0
        }
        // 更新 X 轴数据
        if x*scrollDelta.x>0 {
            scrollBuffer.x += speed * x
        } else {
            scrollBuffer.x = speed * x
            scrollCurr.x = 0.0
        }
        scrollDelta = ( y: y, x: x )
    }
    
    
    // CVDisplayLink 相关, 用于推送插值后的滚动事件
    // 初始化
    func initScrollEventPoster() {
        // 新建一个 CVDisplayLinkSetOutputCallback 来执行循环
        CVDisplayLinkCreateWithActiveCGDisplays(&scrollEventPoster)
        CVDisplayLinkSetOutputCallback(scrollEventPoster!, {
            (displayLink, inNow, inOutputTime, flagsIn, flagsOut, displayLinkContext) -> CVReturn in ScrollCore.shared.handleScroll()
            return kCVReturnSuccess
        }, nil)
    }
    // 启动事件发送器
    func enableScrollEventPoster() {
        if !CVDisplayLinkIsRunning(scrollEventPoster!) {
            CVDisplayLinkStart(scrollEventPoster!)
        }
    }
    // 停止事件发送器
    func disableScrollEventPoster() {
        if let poster = scrollEventPoster {
            CVDisplayLinkStop(poster)
        }
    }
    
    // 启动滚动处理
    func startHandlingScroll() {
        // 开始截取事件
        eventTap = Interception.start(event: mask, to: eventCallBack, at: .cghidEventTap, where: .tailAppendEventTap, for: .defaultTap)
        // 初始化滚动事件发送器
        initScrollEventPoster()
    }
    // 停止滚动处理
    func endHandlingScroll() {
        // 停止发送滚动事件
        disableScrollEventPoster()
        // 停止截取事件
        Interception.stop(tap: eventTap)
    }
    
}
