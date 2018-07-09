import Cocoa

let scrollEventCallBack: CGEventTapCallBack = { (proxy, type, event, refcon) in
    print("EventReceived")
    return Unmanaged.passUnretained(event)
}
let mask = CGEventMask(1 << CGEventType.scrollWheel.rawValue)

guard let eventTap = CGEvent.tapCreate(tap: .cghidEventTap, place: .tailAppendEventTap, options: .defaultTap, eventsOfInterest: mask, callback: scrollEventCallBack, userInfo: nil) else {
    fatalError("Failed to create event tap")
}
let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
CGEvent.tapEnable(tap: eventTap, enable: true)
 
