//
//  Interception.swift
//  Mos
//  事件截取工具函数
//  Created by Caldis on 2018/3/18.
//  Copyright © 2018年 Caldis. All rights reserved.
//

import Foundation

struct InterceptionRef {
    var eventTap: CFMachPort?
    var runLoopSource: CFRunLoopSource?
}

class Interception {
    
    // 开始截取
    class func start(event mask: CGEventMask, handleBy eventHandler: @escaping CGEventTapCallBack, at eventTap: CGEventTapLocation, where eventPlace: CGEventTapPlacement, for behaver: CGEventTapOptions) -> InterceptionRef {
        guard let eventTap = CGEvent.tapCreate(tap: eventTap, place: eventPlace, options: behaver, eventsOfInterest: mask, callback: eventHandler, userInfo: nil) else {
            fatalError("Failed to create event tap")
        }
        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        return InterceptionRef(eventTap: eventTap, runLoopSource: runLoopSource)
    }
    
    // 停止截取
    class func stop(_ interceptionRef: InterceptionRef?) {
        if let ref = interceptionRef {
            if let eventTap = ref.eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: false)
            } else {
                fatalError("Failed to disable eventTap")
            }
            if let runLoopSource = ref.runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes);
            } else {
                fatalError("Failed to stop runLoopSource")
            }
        } else {
            fatalError("Failed to stop Interception")
        }
    }
    
}
