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
    
    // 处理鼠标事件的方向
    let mousePos = ( Y: UInt32(1), X: UInt32(1), YX: UInt32(2), YXZ: UInt32(3) )
    // 事件发送器相关
    var scrollEventPoster: CVDisplayLink?
    // 滚动数据
    var scrollPool = ( y: 0.0, x: 0.0 )  // 滚动数据池
    var scrollCurr = ( y: 0.0, x: 0.0 )  // 当前滚动 (最新一次的数据)
    var scrollDelta = ( y: 0.0, x: 0.0 ) // 滚动方向 (最新一次的数据)
    // 例外应用相关
    var lastEventTargetPID:pid_t = 1     // 目标进程 PID(先前的)
    var eventTargetPID:pid_t = 1         // 事件的目标进程 PID
    var eventTargetBID:String!           // 事件的目标进程 BID
    
    // eventTap相关
    var eventTap:CFMachPort?
    let mask = CGEventMask(1 << CGEventType.scrollWheel.rawValue)
    let eventCallBack: CGEventTapCallBack = {
        (proxy, type, event, refcon) in
        
        // 是否返回原始事件
        var handbackOriginalEvent = true
        
        // 判断输入源 (无法区分黑苹果, 因为黑苹果的触控板驱动是模拟鼠标输入的)
        // 当鼠标输入, 根据需要执行翻转方向/平滑滚动
        if ScrollUtils.shared.isMouse(of: event) {
            
            // 获取光标当前窗口信息, 用于在某些窗口中禁用, 更新每次的PID
            ScrollCore.shared.lastEventTargetPID = ScrollCore.shared.eventTargetPID
            ScrollCore.shared.eventTargetPID = pid_t(event.getIntegerValueField(.eventTargetUnixProcessID))
            // 如果目标PID有变化, 则重新获取一次窗口名字, 更新到 eventTargetName 里面
            if ScrollCore.shared.lastEventTargetPID != ScrollCore.shared.eventTargetPID {
                if let bundleId = ScrollUtils.shared.getApplicationBundleIdFrom(pid: ScrollCore.shared.eventTargetPID) {
                    ScrollCore.shared.eventTargetBID = bundleId
                }
            }
            
            // 获取列表中应用程序的设置信息
            let exceptionalApplications = ScrollUtils.shared.applicationInExceptionalApplications(bundleId: ScrollCore.shared.eventTargetBID)
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
                    scrollY.data = -scrollY.data
                }
                // 是否平滑滚动
                if enableSmooth {
                    // 禁止返回原始事件
                    handbackOriginalEvent = false
                    // 如果输入值为Fixed型则不处理; 如果为非Fixed类型且小于10则归一化为10
                    if scrollY.isFixed {
                        scrollValue.Y = scrollY.data
                    } else {
                        let absY = abs(scrollY.data)
                        if absY > 0.0 && absY < 10.0 {
                            scrollValue.Y = scrollY.data<0.0 ? -10.0 : 10.0
                        } else {
                            scrollValue.Y = scrollY.data
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
                    scrollX.data = -scrollX.data
                }
                // 是否平滑滚动
                if enableSmooth {
                    // 禁止返回原始事件
                    handbackOriginalEvent = false
                    // 如果输入值为Fixed型则不处理; 如果为非Fixed类型且小于10则归一化为10
                    if scrollX.isFixed {
                        scrollValue.X = scrollX.data
                    } else {
                        let absX = abs(scrollX.data)
                        if absX > 0.0 && absX < 10.0 {
                            scrollValue.X = scrollX.data<0.0 ? -10.0 : 10.0
                        } else {
                            scrollValue.X = scrollX.data
                        }
                    }
                }
            }
            // 启动一下事件
            if (scrollValue.Y != 0.0 || scrollValue.X != 0.0) {
                ScrollCore.shared.updateScrollPool(y: scrollValue.Y, x: scrollValue.X)
                ScrollCore.shared.activeScrollEventPoster()
            }
        }
        
        // 返回事件对象
        if handbackOriginalEvent {
            return Unmanaged.passRetained(event)
        } else {
            return nil
        }
    }
    
    // 启动滚动处理
    func startHandling() {
        // 开始截取事件
        eventTap = ScrollCore.startCapture(event: mask, to: eventCallBack, at: .cghidEventTap, where: .tailAppendEventTap, for: .defaultTap)
        // 初始化事件发送器
        initScrollEventPoster()
    }
    // 停止滚动处理
    func endHandling() {
        // 停止截取事件
        stopCapture(tap: eventTap)
        // 停止事件发送器
        stopScrollEventPoster()
    }
    
    // 截取滚动事件
    class func startCapture(event mask: CGEventMask, to eventHandler: @escaping CGEventTapCallBack, at eventTap: CGEventTapLocation, where eventPlace: CGEventTapPlacement, for behaver: CGEventTapOptions) -> CFMachPort {
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
    
    // 更新滚动数据池
    func updateScrollPool(y: Double, x: Double) {
        // 更新 Y 轴数据
        if y*scrollDelta.y > 0 {
            scrollPool.y += 4.2 * y
        } else {
            scrollPool.y = 4.2 * y
            scrollCurr.y = 0.0
        }
        // 更新 X 轴数据
        if x*scrollDelta.x>0 {
            scrollPool.x += 4.2 * x
        } else {
            scrollPool.x = 4.2 * x
            scrollCurr.x = 0.0
        }
        scrollDelta = ( y: y, x: x )
    }
    
    // 初始化 CVDisplayLink, 用于循环处理滚动事件
    func initScrollEventPoster() {
        // 新建一个 CVDisplayLinkSetOutputCallback 来执行循环
        CVDisplayLinkCreateWithActiveCGDisplays(&scrollEventPoster)
        CVDisplayLinkSetOutputCallback(scrollEventPoster!, {
            (displayLink, inNow, inOutputTime, flagsIn, flagsOut, displayLinkContext) -> CVReturn in ScrollCore.shared.handleScroll()
            return kCVReturnSuccess
        }, nil)
    }
    // 激活事件发送器
    @objc func activeScrollEventPoster() {
        if !CVDisplayLinkIsRunning(scrollEventPoster!) {
            // 如果事件发送器没有在运行, 则启动之
            CVDisplayLinkStart(scrollEventPoster!)
        }
    }
    // 停止事件发送器
    func stopScrollEventPoster() {
        if let poster = scrollEventPoster {
            CVDisplayLinkStop(poster)
        }
    }
    
    // 处理滚动事件
    func handleScroll() {
        // 计算插值结果
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
        MouseEvent.scroll(mousePos.YX, yScroll: Int32(scrollPulse.y), xScroll: Int32(scrollPulse.x))
        
        // 根据处理结果选择是否需要迭代循环
        if abs(scrollPool.x-scrollCurr.x) <= 2 && abs(scrollPool.y-scrollCurr.y) <= 2 {
            stopScrollEventPoster()
        }
    }
    
}
