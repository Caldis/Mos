//
//  Interceptor.swift
//  Mos
//  事件截取工具函数
//  Created by Caldis on 2018/3/18.
//  Copyright © 2018年 Caldis. All rights reserved.
//

import Foundation

class Interceptor {
    
    var eventTapRef: CFMachPort?
    var runLoopSourceRef: CFRunLoopSource?
    
    public init(event mask: CGEventMask, handleBy eventHandler: @escaping CGEventTapCallBack, listenOn eventTap: CGEventTapLocation, placeAt eventPlace: CGEventTapPlacement, for behaver: CGEventTapOptions) {
        guard let tap = CGEvent.tapCreate(tap: eventTap, place: eventPlace, options: behaver, eventsOfInterest: mask, callback: eventHandler, userInfo: nil) else {
            fatalError("Failed to create event tap")
        }
        eventTapRef = tap
        runLoopSourceRef = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        start()
    }
    deinit {
        stop()
    }
    
    @objc public func start() {
        guard let tap = eventTapRef, let source = runLoopSourceRef else {
            fatalError("Failed to start event tap")
        }
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }
    public func stop() {
        guard let tap = eventTapRef, let source = runLoopSourceRef else {
            fatalError("Failed to stop event tap")
        }
        CGEvent.tapEnable(tap: tap, enable: false)
        CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
    }
    
    public func check() {
        if !isRunning() {
            restart()
        }
    }
    public func isRunning() -> Bool {
        if let tap = eventTapRef {
            return CGEvent.tapIsEnabled(tap: tap)
        } else {
            return false
        }
    }
    public func restart() {
        stop()
        Timer.scheduledTimer(timeInterval: 0.5, target: self, selector: #selector(start), userInfo: nil, repeats: true)
    }
}
