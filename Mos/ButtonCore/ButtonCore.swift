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
    // 左/右键的点击安全性质由"完全不监听"保证: dispatchEventMask 不含 left/right 事件,
    // 任何路径都无法修改或吞掉主键点击 (原 listen-only 观察 tap 为诊断预留, 零消费但
    // 每次点击有真实 tap 开销, 已随质量清理移除, 见 2026-04-15 left-click-safety 设计)
    var dispatchInterceptor: Interceptor?

    // 组合的按钮事件掩码
    let otherDown = CGEventMask(1 << CGEventType.otherMouseDown.rawValue)
    let keyDown = CGEventMask(1 << CGEventType.keyDown.rawValue)
    let otherUp = CGEventMask(1 << CGEventType.otherMouseUp.rawValue)
    let keyUp = CGEventMask(1 << CGEventType.keyUp.rawValue)
    var dispatchEventMask: CGEventMask {
        return otherDown | otherUp | keyDown | keyUp
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
                isActive = true
            } catch {
                dispatchInterceptor?.stop()
                dispatchInterceptor = nil
                NSLog("ButtonCore: Failed to create interceptor: \(error)")
            }
        }
    }

    // 禁用按钮监控
    func disable() {
        if isActive {
            NSLog("ButtonCore disabled")
            dispatchInterceptor?.stop()
            dispatchInterceptor = nil
            InputProcessor.shared.clearActiveBindings()
            isActive = false
        }
    }
    
    // 切换状态
    func toggle() {
        isActive ? disable() : enable()
    }
}
