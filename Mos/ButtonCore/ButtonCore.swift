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
    var dispatchInterceptor: Interceptor?
    var primaryObservationInterceptor: Interceptor?

    // 组合的按钮事件掩码
    let leftDown = CGEventMask(1 << CGEventType.leftMouseDown.rawValue)
    let leftUp = CGEventMask(1 << CGEventType.leftMouseUp.rawValue)
    let rightDown = CGEventMask(1 << CGEventType.rightMouseDown.rawValue)
    let rightUp = CGEventMask(1 << CGEventType.rightMouseUp.rawValue)
    let otherDown = CGEventMask(1 << CGEventType.otherMouseDown.rawValue)
    let keyDown = CGEventMask(1 << CGEventType.keyDown.rawValue)
    let flagsChanged = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
    let otherUp = CGEventMask(1 << CGEventType.otherMouseUp.rawValue)
    let keyUp = CGEventMask(1 << CGEventType.keyUp.rawValue)
    var dispatchEventMask: CGEventMask {
        return otherDown | otherUp | keyDown | keyUp
    }

    var primaryObservationEventMask: CGEventMask {
        return leftDown | leftUp | rightDown | rightUp
    }

    // MARK: - 按钮事件处理
    let buttonEventCallBack: CGEventTapCallBack = { (proxy, type, event, refcon) in
        // Tap 被系统禁用时, 清理活跃绑定状态并直接放行
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            InputProcessor.shared.clearActiveBindings()
            return Unmanaged.passUnretained(event)
        }
        // 跳过 Mos 合成事件, 避免 executeCustom 发出的事件被重复处理
        if event.getIntegerValueField(.eventSourceUserData) == MosEventMarker.syntheticCustom {
            return Unmanaged.passUnretained(event)
        }

        // 使用原始 flags 匹配绑定 (不注入虚拟修饰键, 保证匹配准确)
        let mosEvent = InputEvent(fromCGEvent: event)
        let result = InputProcessor.shared.process(mosEvent)
        switch result {
        case .consumed:
            // FIX: Alterar o button number do evento consumido para evitar
            // que o macOS o processe como back/forward em uma camada
            // abaixo do CGEventTap (workaround para issue #907).
            if type == .otherMouseDown || type == .otherMouseUp {
                event.setIntegerValueField(.mouseEventButtonNumber, value: 99)
            }
            return nil
        case .passthrough:
            // 注入虚拟修饰键 flags 到 passthrough 事件
            // 使长按鼠标侧键(绑定到修饰键) + 键盘/鼠标输入 = 修饰键组合输入
            let activeFlags = InputProcessor.shared.activeModifierFlags
            let supportsVirtualModifiers =
                type == .keyDown ||
                type == .keyUp
            if activeFlags != 0 && supportsVirtualModifiers {
                event.flags = CGEventFlags(rawValue: event.flags.rawValue | activeFlags)
            }
            return Unmanaged.passUnretained(event)
        }
    }

    let primaryMouseObservationCallBack: CGEventTapCallBack = { (_, type, event, _) in
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            return Unmanaged.passUnretained(event)
        }
        if event.getIntegerValueField(.eventSourceUserData) == MosEventMarker.syntheticCustom {
            return Unmanaged.passUnretained(event)
        }
        return Unmanaged.passUnretained(event)
    }
    
    // MARK: - 启用和禁用
    
    // 启用按钮监控
    func enable() {
        if !isActive {
            do {
                dispatchInterceptor = try Interceptor(
                    event: dispatchEventMask,
                    handleBy: buttonEventCallBack,
                    listenOn: .cgAnnotatedSessionEventTap,
                    placeAt: .tailAppendEventTap,
                    for: .defaultTap
                )
                dispatchInterceptor?.onRestart = {
                    InputProcessor.shared.clearActiveBindings()
                }
                primaryObservationInterceptor = try Interceptor(
                    event: primaryObservationEventMask,
                    handleBy: primaryMouseObservationCallBack,
                    listenOn: .cgAnnotatedSessionEventTap,
                    placeAt: .tailAppendEventTap,
                    for: .listenOnly
                )
                isActive = true
            } catch {
                dispatchInterceptor?.stop()
                primaryObservationInterceptor?.stop()
                dispatchInterceptor = nil
                primaryObservationInterceptor = nil
                NSLog("ButtonCore: Failed to create interceptor: \(error)")
            }
        }
    }
    
    // 禁用按钮监控
    func disable() {
        if isActive {
            NSLog("ButtonCore disabled")
            dispatchInterceptor?.stop()
            primaryObservationInterceptor?.stop()
            dispatchInterceptor = nil
            primaryObservationInterceptor = nil
            InputProcessor.shared.clearActiveBindings()
            isActive = false
        }
    }
    
    // 切换状态
    func toggle() {
        isActive ? disable() : enable()
    }
}
