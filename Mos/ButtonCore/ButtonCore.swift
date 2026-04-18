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
    var eventInterceptor: Interceptor?

    // MARK: - Cursor Detection

    /// Get the current system cursor image size to detect cursor type
    /// Hand cursor is typically larger than arrow cursor
    @_silgen_name("CGSGetGlobalCursorDataSize")
    static func CGSGetGlobalCursorDataSize(_ connection: Int32, _ size: UnsafeMutablePointer<Int32>) -> Int32

    /// Get the default connection
    @_silgen_name("CGSMainConnectionID")
    static func CGSMainConnectionID() -> Int32

    /// Get cursor data including image
    @_silgen_name("CGSGetGlobalCursorData")
    static func CGSGetGlobalCursorData(
        _ connection: Int32,
        _ data: UnsafeMutableRawPointer,
        _ size: UnsafeMutablePointer<Int32>,
        _ rowBytes: UnsafeMutablePointer<Int32>,
        _ rect: UnsafeMutablePointer<CGRect>,
        _ hotspot: UnsafeMutablePointer<CGPoint>,
        _ depth: UnsafeMutablePointer<Int32>,
        _ components: UnsafeMutablePointer<Int32>,
        _ bitsPerComponent: UnsafeMutablePointer<Int32>
    ) -> Int32

    // Store known cursor characteristics
    // Arrow cursor: hotspot ~(5, 5), rect ~(28, 40)
    // Hand cursor: hotspot ~(13, 8), rect ~(32, 32)
    static var arrowCursorHotspot: CGPoint = CGPoint(x: 5, y: 5)
    static var arrowCursorRect: CGRect = CGRect(x: 0, y: 0, width: 28, height: 40)
    static var isCalibrated = false

    /// Check if the current cursor is a pointing hand
    /// Hand cursor has different hotspot than arrow (finger tip vs corner)
    static func isPointingHandCursor() -> Bool {
        let connection = CGSMainConnectionID()
        var size: Int32 = 0

        guard CGSGetGlobalCursorDataSize(connection, &size) == 0, size > 0 else {
            return false
        }

        var rowBytes: Int32 = 0
        var rect = CGRect.zero
        var hotspot = CGPoint.zero
        var depth: Int32 = 0
        var components: Int32 = 0
        var bitsPerComponent: Int32 = 0

        let data = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: 1)
        defer { data.deallocate() }

        guard CGSGetGlobalCursorData(connection, data, &size, &rowBytes, &rect, &hotspot, &depth, &components, &bitsPerComponent) == 0 else {
            return false
        }

        // Auto-calibrate if this looks like an arrow cursor
        let looksLikeArrow = hotspot.x < 8 && hotspot.y < 8
        if looksLikeArrow {
            arrowCursorHotspot = hotspot
            arrowCursorRect = rect
            if !isCalibrated {
                isCalibrated = true
            }
            return false
        }

        if !isCalibrated {
            isCalibrated = true
        }

        // Hand cursor signature: hotspot=(13, 8), rect=(32, 32)
        let hotspotMatchesHand = hotspot.x > 10 && hotspot.y >= 6 && hotspot.y <= 10
        let rectIsSquare = abs(rect.width - rect.height) < 5
        let rectIsRightSize = rect.width >= 30 && rect.width <= 34

        let looksLikeHand = hotspotMatchesHand && rectIsSquare && rectIsRightSize

        if looksLikeHand {
            return true
        }

        return false
    }

    // 组合的按钮事件掩码
    let leftDown = CGEventMask(1 << CGEventType.leftMouseDown.rawValue)
    let leftUp = CGEventMask(1 << CGEventType.leftMouseUp.rawValue)
    let rightDown = CGEventMask(1 << CGEventType.rightMouseDown.rawValue)
    let rightUp = CGEventMask(1 << CGEventType.rightMouseUp.rawValue)
    let otherDown = CGEventMask(1 << CGEventType.otherMouseDown.rawValue)
    let otherDragged = CGEventMask(1 << CGEventType.otherMouseDragged.rawValue)
    let mouseMoved = CGEventMask(1 << CGEventType.mouseMoved.rawValue)
    let keyDown = CGEventMask(1 << CGEventType.keyDown.rawValue)
    let flagsChanged = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
    let otherUp = CGEventMask(1 << CGEventType.otherMouseUp.rawValue)
    let keyUp = CGEventMask(1 << CGEventType.keyUp.rawValue)
    var eventMask: CGEventMask {
        return leftDown | leftUp | rightDown | rightUp | otherDown | otherUp | otherDragged | mouseMoved | keyDown | keyUp
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

        let buttonNumber = event.getIntegerValueField(.mouseEventButtonNumber)
        let cgLocation = event.location

        // 转换CGEvent坐标到NSScreen坐标
        // CGEvent: Y=0在屏幕顶部，向下递增
        // NSScreen: Y=0在主屏幕底部，向上递增
        func convertToScreenCoordinates(_ cgPoint: CGPoint) -> CGPoint {
            // CGEvent uses Quartz coordinates: Y=0 at TOP of primary screen, Y increases DOWNWARD
            // NSEvent uses Cocoa coordinates: Y=0 at BOTTOM of primary screen, Y increases UPWARD
            // NSScreen.screens also uses Cocoa coordinates

            // The global coordinate space origin (0,0) is at the top-left of the primary display in Quartz
            // In Cocoa, (0,0) is at the bottom-left of the primary display

            // Strategy: Find which screen contains this point in Quartz coords,
            // then convert to Cocoa coords accounting for that screen's position

            // CRITICAL: Use screens.first (primary display) not .main (focused screen)
            // .main changes based on which screen has focus, causing wrong height
            guard let primaryScreen = NSScreen.screens.first else { return cgPoint }
            let primaryScreenHeight = primaryScreen.frame.height

            // Find the screen that contains this point
            // We need to convert each screen's Cocoa frame to Quartz for comparison
            var targetScreen: NSScreen?
            for screen in NSScreen.screens {
                // Convert screen's Cocoa frame to Quartz coordinates
                let cocoaFrame = screen.frame
                // In Quartz: Y = primaryScreenHeight - (cocoaY + height)
                let quartzY = primaryScreenHeight - (cocoaFrame.origin.y + cocoaFrame.height)
                let quartzFrame = CGRect(
                    x: cocoaFrame.origin.x,
                    y: quartzY,
                    width: cocoaFrame.width,
                    height: cocoaFrame.height
                )

                if quartzFrame.contains(cgPoint) {
                    targetScreen = screen
                    break
                }
            }

            // Use primary screen as fallback
            let screen = targetScreen ?? primaryScreen
            let screenFrame = screen.frame

            // Convert point from Quartz to Cocoa relative to the target screen
            // The screen's top edge in Quartz is: primaryScreenHeight - (screenFrame.origin.y + screenFrame.height)
            // The point's offset from the screen's top in Quartz is: cgPoint.y - quartzTopEdge
            // In Cocoa, this becomes: (screenFrame.origin.y + screenFrame.height) - offsetFromTop
            let quartzTopEdge = primaryScreenHeight - (screenFrame.origin.y + screenFrame.height)
            let offsetFromTop = cgPoint.y - quartzTopEdge
            let cocoaY = (screenFrame.origin.y + screenFrame.height) - offsetFromTop

            return CGPoint(x: cgPoint.x, y: cocoaY)
        }

        let location = convertToScreenCoordinates(cgLocation)

        // 处理自动滚动相关事件
        if buttonNumber == Options.shared.autoScroll.activationButton {
            switch type {
            case .otherMouseDown:
                let browserInfo = AutoScrollCore.shared.getBrowserWindowInfo(at: location)

                // CURSOR DETECTION: Check if mouse is over a clickable element (link, button)
                var isOverClickable = false

                if Thread.isMainThread {
                    isOverClickable = ButtonCore.isPointingHandCursor()
                } else {
                    DispatchQueue.main.sync {
                        isOverClickable = ButtonCore.isPointingHandCursor()
                    }
                }

                if isOverClickable {
                    // Don't start auto-scroll, let browser handle the link click
                    return Unmanaged.passUnretained(event)
                }

                if browserInfo.isBrowser && !browserInfo.isInUIArea {
                    // Browser content area, NOT over a link - start auto-scroll
                    AutoScrollCore.shared.handleMiddleButtonDown(at: location)
                    return nil  // Consume event since we're handling it
                }

                // Non-browser: use our auto-scroll and consume event
                let shouldConsume = AutoScrollCore.shared.handleMiddleButtonDown(at: location)
                if shouldConsume || AutoScrollCore.shared.isActive {
                    return nil  // Consume event
                }
                return Unmanaged.passUnretained(event)
            case .otherMouseUp:
                // Check if cursor is pointing hand - if so, pass through for link
                var isOverClickable = false
                if Thread.isMainThread {
                    isOverClickable = ButtonCore.isPointingHandCursor()
                } else {
                    DispatchQueue.main.sync {
                        isOverClickable = ButtonCore.isPointingHandCursor()
                    }
                }

                if isOverClickable {
                    return Unmanaged.passUnretained(event)
                }

                let wasHandled = AutoScrollCore.shared.handleMiddleButtonUp(at: location)

                if wasHandled || AutoScrollCore.shared.isActive {
                    return nil  // Consume event (non-browser apps)
                }
                // Pass through for bookmarks/tabs
                return Unmanaged.passUnretained(event)
            default:
                break
            }
        }

        // 处理鼠标移动（用于拖动检测）
        if type == .mouseMoved {
            AutoScrollCore.shared.handleMouseMove(to: location)
            return Unmanaged.passUnretained(event)
        }

        // 任何鼠标点击都会停止自动滚动
        if AutoScrollCore.shared.isActive {
            if type == .leftMouseDown || type == .rightMouseDown {
                AutoScrollCore.shared.stopAutoScroll()
            }
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
                type == .keyUp ||
                type == .leftMouseDown ||
                type == .leftMouseUp ||
                type == .rightMouseDown ||
                type == .rightMouseUp ||
                type == .otherMouseDown ||
                type == .otherMouseUp
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
                eventInterceptor = try Interceptor(
                    event: eventMask,
                    handleBy: buttonEventCallBack,
                    listenOn: .cgAnnotatedSessionEventTap,
                    placeAt: .tailAppendEventTap,
                    for: .defaultTap
                )
                eventInterceptor?.onRestart = {
                    InputProcessor.shared.clearActiveBindings()
                }
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
            eventInterceptor?.stop()
            eventInterceptor = nil
            InputProcessor.shared.clearActiveBindings()
            isActive = false
        }
    }
    
    // 切换状态
    func toggle() {
        isActive ? disable() : enable()
    }
}
