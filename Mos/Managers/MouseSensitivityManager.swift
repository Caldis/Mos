//
//  MouseSensitivityManager.swift
//  Mos
//  鼠标灵敏度管理器
//  Created by Mos on 2026/4/25.
//

import Cocoa

class MouseSensitivityManager {
    static let shared = MouseSensitivityManager()
    
    private var isActive = false
    private var mouseMoveInterceptor: Interceptor?
    
    private static let mouseMoveEventMask: CGEventMask =
        (CGEventMask(1 << CGEventType.mouseMoved.rawValue)) |
        (CGEventMask(1 << CGEventType.leftMouseDragged.rawValue)) |
        (CGEventMask(1 << CGEventType.rightMouseDragged.rawValue)) |
        (CGEventMask(1 << CGEventType.otherMouseDragged.rawValue))
    
    private static let mouseMoveEventCallback: CGEventTapCallBack = { _, type, event, _ in
        MouseSensitivityManager.shared.handleMouseMoveEvent(type: type, event: event)
    }
    
    init() {
        NSLog("Module initialized: MouseSensitivityManager")
    }
    
    func enable() {
        if isActive { return }
        isActive = true
        
        do {
            mouseMoveInterceptor = try Interceptor(
                event: Self.mouseMoveEventMask,
                handleBy: Self.mouseMoveEventCallback,
                listenOn: .cgAnnotatedSessionEventTap,
                placeAt: .tailAppendEventTap,
                for: .defaultTap
            )
            mouseMoveInterceptor?.onRestart = { [weak self] in
                self?.restartIfNeeded()
            }
            mouseMoveInterceptor?.shouldRestart = { [weak self] in
                    self?.isActive ?? false
                }
        } catch {
            NSLog("MouseSensitivityManager: Failed to create interceptor: \(error)")
            isActive = false
        }
    }
    
    func disable() {
        if !isActive { return }
        isActive = false
        
        mouseMoveInterceptor?.stop()
        mouseMoveInterceptor = nil
    }
    
    func refresh() {
        if Options.shared.mouse.enableSensitivity {
            enable()
        } else {
            disable()
        }
    }
    
    private func restartIfNeeded() {
        if isActive {
            mouseMoveInterceptor?.restart()
        }
    }
    
    private func handleMouseMoveEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            restartIfNeeded()
            return Unmanaged.passUnretained(event)
        }
        
        guard Options.shared.mouse.enableSensitivity else {
            return Unmanaged.passUnretained(event)
        }
        
        let sensitivity = Options.shared.mouse.sensitivity
        
        guard sensitivity != 1.0 else {
            return Unmanaged.passUnretained(event)
        }
        
        let deltaX = event.getIntegerValueField(.mouseEventDeltaX)
        let deltaY = event.getIntegerValueField(.mouseEventDeltaY)
        
        let adjustedDeltaX = Int64(Double(deltaX) * sensitivity)
        let adjustedDeltaY = Int64(Double(deltaY) * sensitivity)
        
        event.setIntegerValueField(.mouseEventDeltaX, value: adjustedDeltaX)
        event.setIntegerValueField(.mouseEventDeltaY, value: adjustedDeltaY)
        
        return Unmanaged.passUnretained(event)
    }
}
