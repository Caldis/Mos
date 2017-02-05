//
//  Hotkey.swift
//  Mos
//  用于注册全局快捷键
//  Created by Cb on 2017/2/5.
//  Copyright © 2017年 Cb. All rights reserved.
//

import Cocoa
import Carbon

class HotKey {
    private let hotKey:EventHotKeyRef
    private let eventHandler:EventHandlerRef
    private var registered = true
    
    private init(hotKey: EventHotKeyRef, eventHandler: EventHandlerRef) {
        self.hotKey = hotKey
        self.eventHandler = eventHandler
    }

    static func register(keyCode: UInt32, modifiers: UInt32, block: @escaping () -> ()) -> HotKey? {
        var hotKey:EventHotKeyRef?
        let hotkeyHandler:EventHandlerUPP = { _, _, _ in return noErr }
        var eventHandler:EventHandlerRef?
        let hotKeyID = EventHotKeyID(signature: 1, id: 1)
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        
        let ptr = UnsafeMutablePointer<() -> ()>.allocate(capacity: 1)
        ptr.initialize(to: block)
        
        guard InstallEventHandler(GetApplicationEventTarget(), hotkeyHandler, 1, &eventType, ptr, &eventHandler) == noErr &&
            RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), OptionBits(0), &hotKey) == noErr else {return nil}
        return HotKey(hotKey: hotKey!, eventHandler: eventHandler!)
    }
    
    func unregister() {
        guard registered else {return}
        UnregisterEventHotKey(hotKey)
        RemoveEventHandler(eventHandler)
        registered = false
    }
}
