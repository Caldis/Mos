//
//  Interceptor.swift
//  Mos
//  事件截取工具函数
//  Created by Caldis on 2018/3/18.
//  Copyright © 2018年 Caldis. All rights reserved.
//

import Cocoa

class Interceptor {
    
    var keeper: Timer?
    var eventTapRef: CFMachPort?
    var runLoopSourceRef: CFRunLoopSource?
    
    public init(event mask: CGEventMask, handleBy eventHandler: @escaping CGEventTapCallBack, listenOn eventTap: CGEventTapLocation, placeAt eventPlace: CGEventTapPlacement, for behaver: CGEventTapOptions) throws {
        // 创建拦截层
        guard let tap = CGEvent.tapCreate(tap: eventTap, place: eventPlace, options: behaver, eventsOfInterest: mask, callback: eventHandler, userInfo: nil) else {
            throw InterceptorError.eventTapCreationFailed
        }
        eventTapRef = tap
        runLoopSourceRef = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        // 启动
        try start()
    }
    
    deinit {
        // 停止
        stop()
    }
}

// MARK: - Error Type
extension Interceptor {
    enum InterceptorError: Error {
        case eventTapCreationFailed
        case eventTapEnableFailed
    }
}

// MARK: - 开关
extension Interceptor {
    @objc public func start() throws {
        // 启动拦截层
        guard let tap = eventTapRef, let source = runLoopSourceRef else {
            throw InterceptorError.eventTapEnableFailed
        }
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        // 启动守护
        keeper = Timer.scheduledTimer(
            timeInterval: 5.0,
            target: self,
            selector: #selector(check),
            userInfo: nil,
            repeats: true
        )
    }
    
    public func stop() {
        // 停止守护
        keeper?.invalidate()
        // 关闭拦截层
        if let tap = eventTapRef, let source = runLoopSourceRef {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
    }
}

// MARK: - 状态
extension Interceptor {
    public func isRunning() -> Bool {
        if let tap = eventTapRef {
            return CGEvent.tapIsEnabled(tap: tap)
        } else {
            return false
        }
    }
    
    public func restart() {
        stop()
        Timer.scheduledTimer(
            timeInterval: 0.5,
            target: self,
            selector: #selector(start),
            userInfo: nil,
            repeats: false
        )
    }
    
    @objc private func check() {
        if !isRunning() {
            restart()
        }
    }
}
