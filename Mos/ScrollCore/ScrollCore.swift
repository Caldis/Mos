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
    var scrollPool = ( y: 0.0, x: 0.0 )  // 滚动数据池
    var scrollCurr = ( y: 0.0, x: 0.0 )  // 当前滚动 (最新一次的数据)
    var scrollDelta = ( y: 0.0, x: 0.0 ) // 滚动方向 (最新一次的数据)
    // 事件发送器
    var scrollEventPoster: CVDisplayLink?
    
    // 更新滚动数据池
    func updateScrollPool(y: Double, x: Double) {
        let speed = Options.shared.current.advanced.speed
        // 更新 Y 轴数据
        if y*scrollDelta.y > 0 {
            scrollPool.y += speed * y
        } else {
            scrollPool.y = speed * y
            scrollCurr.y = 0.0
        }
        // 更新 X 轴数据
        if x*scrollDelta.x>0 {
            scrollPool.x += speed * x
        } else {
            scrollPool.x = speed * x
            scrollCurr.x = 0.0
        }
        scrollDelta = ( y: y, x: x )
    }

    // 处理滚动事件
    func handleScroll() {
        // 计算线性插值
        let scrollPulse = (
            y: Interpolation.lerp(src: scrollCurr.y, dest: scrollPool.y),
            x: Interpolation.lerp(src: scrollCurr.x, dest: scrollPool.x)
        )
        // 更新当前滚动位置
        scrollCurr = (
            y: scrollCurr.y + scrollPulse.y,
            x: scrollCurr.x + scrollPulse.x
        )
        // 发送滚动结果
        MouseEvent.scroll(axis.YX, yScroll: Int32(scrollPulse.y), xScroll: Int32(scrollPulse.x))
        // 如果临近目标则停止滚动
        if abs(scrollPulse.y) <= 1 && abs(scrollPulse.x) <= 1 {
            disableScrollEventPoster()
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

            // 获取目标窗口的 BundleId
            let eventTargetBID = ScrollUtils.shared.getCurrentEventTargetBundleId(from: event)
            
            // 获取列表中应用程序的设置信息
            let exceptionalApplications = ScrollUtils.shared.applicationInExceptionalApplications(bundleId: eventTargetBID)
            let enableReverse = ScrollUtils.shared.enableReverse(application: exceptionalApplications)
            let enableSmooth = ScrollUtils.shared.enableSmooth(application: exceptionalApplications)
            
            // 格式化滚动数据
            var scrollFixY = Int64(event.getIntegerValueField(.scrollWheelEventDeltaAxis1))
            var scrollFixX = Int64(event.getIntegerValueField(.scrollWheelEventDeltaAxis2))
            var scrollPtY = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)
            var scrollPtX = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2)
            var scrollFixPtY = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
            var scrollFixPtX = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2)
            
            // 处理事件
            var scrollValue = ( Y: 0.0, X: 0.0 )
            // Y轴
            if var scrollY = ScrollUtils.shared.axisDataIsExistIn(scrollFixY, scrollPtY, scrollFixPtY) {
                // 是否翻转滚动
                if enableReverse {
                    event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: -scrollFixY)
                    event.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: -scrollPtY)
                    event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: -scrollFixPtY)
                    scrollY.value = -scrollY.value
                }
                // 是否平滑滚动
                if enableSmooth {
                    // 禁止返回原始事件
                    returnOriginalEvent = false
                    // 如果输入值为Fixed型则不处理; 如果为非Fixed类型且小于10则归一化为10
                    if scrollY.isFixed {
                        scrollValue.Y = scrollY.value
                    } else {
                        let absY = abs(scrollY.value)
                        if 0.0<absY && absY<10.0 {
                            scrollValue.Y = scrollY.value<0.0 ? -10.0 : 10.0
                        } else {
                            scrollValue.Y = scrollY.value
                        }
                    }
                }
            }
            // X轴
            if var scrollX = ScrollUtils.shared.axisDataIsExistIn(scrollFixX, scrollPtX, scrollFixPtX) {
                // 是否翻转滚动
                if enableReverse {
                    event.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: -scrollFixX)
                    event.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: -scrollPtX)
                    event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: -scrollFixPtX)
                    scrollX.value = -scrollX.value
                }
                // 是否平滑滚动
                if enableSmooth {
                    // 禁止返回原始事件
                    returnOriginalEvent = false
                    // 如果输入值为Fixed型则不处理; 如果为非Fixed类型且小于10则归一化为10
                    if scrollX.isFixed {
                        scrollValue.X = scrollX.value
                    } else {
                        let absX = abs(scrollX.value)
                        if 0.0<absX && absX<10.0 {
                            scrollValue.X = scrollX.value<0.0 ? -10.0 : 10.0
                        } else {
                            scrollValue.X = scrollX.value
                        }
                    }
                }
            }
            
            // 启动一下事件
            if (scrollValue.Y != 0.0 || scrollValue.X != 0.0) {
                ScrollCore.shared.updateScrollPool(y: scrollValue.Y, x: scrollValue.X)
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
    // 截取滚动事件
    func startCapture(event mask: CGEventMask, to eventHandler: @escaping CGEventTapCallBack, at eventTap: CGEventTapLocation, where eventPlace: CGEventTapPlacement, for behaver: CGEventTapOptions) -> CFMachPort {
        guard let eventTap = CGEvent.tapCreate(tap: eventTap, place: eventPlace, options: behaver, eventsOfInterest: mask, callback: eventHandler, userInfo: nil) else {
            fatalError("Failed to create event tap")
        }
        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        return eventTap
    }
    // 停止截取事件
    func stopCapture(tap: CFMachPort?) {
        if let eventTap = tap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        } else {
            fatalError("Failed to disable eventTap")
        }
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
    
    // 入口函数
    // 启动滚动处理
    func startHandlingScroll() {
        // 开始截取事件
        eventTap = startCapture(event: mask, to: eventCallBack, at: .cghidEventTap, where: .tailAppendEventTap, for: .defaultTap)
        // 初始化事件发送器
        initScrollEventPoster()
    }
    // 停止滚动处理
    func endHandlingScroll() {
        // 停止事件发送器
        disableScrollEventPoster()
        // 停止截取事件
        stopCapture(tap: eventTap)
    }
    
}
