//
//  ButtonCore.swift
//  Mos
//  鼠标按钮事件截取与处理核心类
//  Created by Claude on 2025/8/10.
//  Copyright © 2025年 Caldis. All rights reserved.
//

import Cocoa

class ButtonCore {
    
    // 单例
    static let shared = ButtonCore()
    init() { NSLog("Module initialized: ButtonCore") }
    
    // 执行状态
    var isActive = false
    
    // 拦截层
    var buttonEventInterceptor: Interceptor?
    
    // 按钮事件掩码
    let leftMouseDownMask = CGEventMask(1 << CGEventType.leftMouseDown.rawValue)
    let leftMouseUpMask = CGEventMask(1 << CGEventType.leftMouseUp.rawValue)
    let rightMouseDownMask = CGEventMask(1 << CGEventType.rightMouseDown.rawValue)
    let rightMouseUpMask = CGEventMask(1 << CGEventType.rightMouseUp.rawValue)
    let otherMouseDownMask = CGEventMask(1 << CGEventType.otherMouseDown.rawValue)
    let otherMouseUpMask = CGEventMask(1 << CGEventType.otherMouseUp.rawValue)
    
    // 组合的按钮事件掩码
    var buttonEventMask: CGEventMask {
        return leftMouseDownMask | leftMouseUpMask | rightMouseDownMask | 
               rightMouseUpMask | otherMouseDownMask | otherMouseUpMask
    }
    
    // MARK: - 按钮事件处理
    let buttonEventCallBack: CGEventTapCallBack = { (proxy, type, event, refcon) in
        // 创建按钮事件对象
        let buttonEvent = ButtonEvent(with: event, type: type)
        
        // 发送按钮事件通知
        NotificationCenter.default.post(
            name: NSNotification.Name("ButtonEvent"),
            object: buttonEvent
        )
        
        // 过滤处理
        if let filteredEvent = ButtonFilter.shared.filterButtonEvent(buttonEvent) {
            // 如果需要修改事件，在这里实现
            // 目前先返回原始事件
            return Unmanaged.passUnretained(event)
        }
        
        return Unmanaged.passUnretained(event)
    }
    
    // MARK: - 启用和禁用
    
    // 启用按钮监控
    func enable() {
        if !isActive {
            NSLog("ButtonCore enabled")
            do {
                buttonEventInterceptor = try Interceptor(
                    event: buttonEventMask,
                    handleBy: buttonEventCallBack,
                    listenOn: .cgAnnotatedSessionEventTap,
                    placeAt: .tailAppendEventTap,
                    for: .listenOnly
                )
                isActive = true
            } catch {
                NSLog("ButtonCore: Failed to create interceptor: \(error)")
            }
        }
    }
    
    // 禁用按钮监控
    func disable() {
        if isActive {
            NSLog("ButtonCore disabled")
            buttonEventInterceptor?.stop()
            buttonEventInterceptor = nil
            isActive = false
        }
    }
    
    // 切换状态
    func toggle() {
        isActive ? disable() : enable()
    }
}