//
//  Interceptor.swift
//  Mos
//  事件截取工具函数
//  Created by Caldis on 2018/3/18.
//  Copyright © 2018年 Caldis. All rights reserved.
//

import Cocoa

class Interceptor {
    
    private var keeper: Timer?
    private var _eventTapRef: CFMachPort?
    private var _runLoopSourceRef: CFRunLoopSource?
    
    // 可访问对象只读
    public var eventTapRef: CFMachPort? { _eventTapRef }
    public var runLoopSourceRef: CFRunLoopSource? { _runLoopSourceRef }
    
    public init(event mask: CGEventMask, handleBy eventHandler: @escaping CGEventTapCallBack, listenOn eventTap: CGEventTapLocation, placeAt eventPlace: CGEventTapPlacement, for behaver: CGEventTapOptions) throws {
        // 创建拦截层
        guard let tap = CGEvent.tapCreate(tap: eventTap, place: eventPlace, options: behaver, eventsOfInterest: mask, callback: eventHandler, userInfo: nil) else {
            throw InterceptorError.eventTapCreationFailed
        }
        _eventTapRef = tap
        _runLoopSourceRef = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        // 启动
        try start()
    }
    
    deinit {
        // 先停止所有操作
        stop()
        // 清理 event tap
        if let tap = _eventTapRef {
            CGEvent.tapEnable(tap: tap, enable: false)
            _eventTapRef = nil
        }
        // 清理 run loop source
        if let source = _runLoopSourceRef {
            if CFRunLoopContainsSource(CFRunLoopGetCurrent(), source, .commonModes) {
                CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            }
            _runLoopSourceRef = nil
        }
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
        // 创建拦截层
        guard let tap = _eventTapRef, let source = _runLoopSourceRef else {
            throw InterceptorError.eventTapEnableFailed
        }
        // 确保 source 没有被重复添加
        if !CFRunLoopContainsSource(CFRunLoopGetCurrent(), source, .commonModes) {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        // 启动拦截层
        CGEvent.tapEnable(tap: tap, enable: true)
        // 启动守护
        keeper = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            if let self = self, !self.isRunning() {
                self.restart()
            }
        }
    }
    
    public func stop() {
        // 停止守护
        keeper?.invalidate()
        keeper = nil
        // 关闭拦截层
        if let tap = _eventTapRef, let source = _runLoopSourceRef {
            CGEvent.tapEnable(tap: tap, enable: false)
            if CFRunLoopContainsSource(CFRunLoopGetCurrent(), source, .commonModes) {
                CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            }
        }
    }
}

// MARK: - 状态
extension Interceptor {
    public func isRunning() -> Bool {
        if let tap = _eventTapRef {
            return CGEvent.tapIsEnabled(tap: tap)
        } else {
            return false
        }
    }
    
    public func restart() {
        stop()
        // 保存 timer 的引用以防止提前释放
        keeper = Timer.scheduledTimer(
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
