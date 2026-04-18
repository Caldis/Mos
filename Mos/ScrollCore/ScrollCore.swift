//
//  ScrollCore.swift
//  Mos
//  滚动事件截取与插值计算核心类
//  Created by Caldis on 2017/1/14.
//  Copyright © 2017年 Caldis. All rights reserved.
//

import Cocoa

class ScrollCore {
    
    // 单例
    static let shared = ScrollCore()
    init() { NSLog("Module initialized: ScrollCore") }
    
    // 执行状态
    var isActive = false
    // 热键数据
    var dashScroll = false
    var dashAmplification = 1.0
    var toggleScroll = false {
        didSet { ScrollPoster.shared.updateShifting(enable: toggleScroll) }
    }
    var blockSmooth = false
    // 非修饰键热键的按下状态跟踪
    var dashKeyHeld = false
    var toggleKeyHeld = false
    var blockKeyHeld = false
    // 例外应用数据
    var application: Application?
    var currentApplication: Application? // 用于区分按下热键及抬起时的作用目标
    // 拦截层
    var scrollEventInterceptor: Interceptor?
    var hotkeyEventInterceptor: Interceptor?
    var mouseEventInterceptor: Interceptor?
    // 拦截掩码
    let scrollEventMask = CGEventMask(1 << CGEventType.scrollWheel.rawValue)
    let hotkeyEventMask: CGEventMask = {
        let flagsChanged = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        let keyDown = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let keyUp = CGEventMask(1 << CGEventType.keyUp.rawValue)
        let otherMouseDown = CGEventMask(1 << CGEventType.otherMouseDown.rawValue)
        let otherMouseUp = CGEventMask(1 << CGEventType.otherMouseUp.rawValue)
        return flagsChanged | keyDown | keyUp | otherMouseDown | otherMouseUp
    }()
    let mouseLeftEventMask = CGEventMask(1 << CGEventType.leftMouseDown.rawValue)
    
    // MARK: - 滚动事件处理
    let scrollEventCallBack: CGEventTapCallBack = { (proxy, type, event, refcon) in
        _ = refcon
        // Tap 被系统禁用或重启边界时，强制清理 poster 上下文并失效历史异步帧
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            ScrollPoster.shared.stop(.TrackingEnd)
            return Unmanaged.passUnretained(event)
        }
        if type != .scrollWheel {
            return Unmanaged.passUnretained(event)
        }
        // 跳过 Mos 自己合成的平滑事件，避免重复进入平滑管线
        if ScrollUtils.shared.isSyntheticSmoothEvent(event) {
#if DEBUG
            ScrollPoster.shared.recordSkippedSyntheticEvent()
#endif
            return Unmanaged.passUnretained(event)
        }
        // 检查是否为自动滚动事件（带有 maskAlternate 标志）
        // 如果是，直接放行，不做任何处理
        if event.flags.contains(.maskAlternate) {
            return Unmanaged.passUnretained(event)
        }

        // 不处理触控板
        // 无法区分黑苹果, 因为黑苹果的触控板驱动直接模拟鼠标输入
        // 无法区分 Magic Mouse, 因为其滚动特征与内置的 Trackpad 一致
        if ScrollEvent.isTrackpad(with: event) {
            return Unmanaged.passUnretained(event)
        }
        // 当事件来自远程桌面，且其发送的事件 isContinuous=1.0，此时跳过本地平滑
        if ScrollUtils.shared.isRemoteSmoothedEvent(event) {
            return Unmanaged.passUnretained(event)
        }
        // 当鼠标输入, 根据需要执行翻转方向/平滑滚动
        // 获取事件目标
        let targetRunningApplication = ScrollUtils.shared.getRunningApplication(from: event)
        // 获取列表中应用程序的列外设置信息
        ScrollCore.shared.application = ScrollUtils.shared.getTargetApplication(from: targetRunningApplication)
        // 平滑/翻转
        var enableSmooth = false,
            enableSmoothVertical = false,
            enableSmoothHorizontal = false,
            enableReverseVertical = false,
            enableReverseHorizontal = false
        var step = Options.shared.scroll.step,
            speed = Options.shared.scroll.speed,
            duration = Options.shared.scroll.durationTransition
        if let targetApplication = ScrollCore.shared.application {
            enableSmooth = targetApplication.isSmooth(ScrollCore.shared.blockSmooth)
            enableSmoothVertical = targetApplication.isSmoothVertical(ScrollCore.shared.blockSmooth)
            enableSmoothHorizontal = targetApplication.isSmoothHorizontal(ScrollCore.shared.blockSmooth)
            enableReverseVertical = targetApplication.isReverseVertical()
            enableReverseHorizontal = targetApplication.isReverseHorizontal()
            step = targetApplication.getStep()
            speed = targetApplication.getSpeed()
            duration = targetApplication.getDuration()
        } else if !Options.shared.application.allowlist {
            enableSmooth = Options.shared.scroll.smooth && !ScrollCore.shared.blockSmooth
            enableSmoothVertical = enableSmooth && Options.shared.scroll.smoothVertical
            enableSmoothHorizontal = enableSmooth && Options.shared.scroll.smoothHorizontal
            let allowReverse = Options.shared.scroll.reverse
            enableReverseVertical = allowReverse && Options.shared.scroll.reverseVertical
            enableReverseHorizontal = allowReverse && Options.shared.scroll.reverseHorizontal
        }
        // Launchpad 激活则强制屏蔽平滑
        if ScrollUtils.shared.getLaunchpadActivity(withRunningApplication: targetRunningApplication) {
            enableSmooth = false
            enableSmoothVertical = false
            enableSmoothHorizontal = false
        }
        // 滚动事件
        let scrollEvent = ScrollEvent(with: event)
        let hasVerticalDelta = scrollEvent.Y.valid && scrollEvent.Y.usableValue != 0.0
        let hasHorizontalDelta = scrollEvent.X.valid && scrollEvent.X.usableValue != 0.0
        let willShiftVerticalToHorizontal = ScrollCore.shared.toggleScroll && hasVerticalDelta && !hasHorizontalDelta
        let verticalReversePreference = willShiftVerticalToHorizontal ? enableReverseHorizontal : enableReverseVertical
        if hasVerticalDelta && verticalReversePreference {
            ScrollEvent.reverseY(scrollEvent)
        }
        if hasHorizontalDelta && enableReverseHorizontal {
            ScrollEvent.reverseX(scrollEvent)
        }

        let verticalPreference = willShiftVerticalToHorizontal ? enableSmoothHorizontal : enableSmoothVertical
        var shouldSmoothVertical = hasVerticalDelta && verticalPreference
        var shouldSmoothHorizontal = hasHorizontalDelta && enableSmoothHorizontal

        if !enableSmooth {
            shouldSmoothVertical = false
            shouldSmoothHorizontal = false
        }

        var smoothedY = 0.0
        var smoothedX = 0.0

        if shouldSmoothVertical {
            if scrollEvent.Y.usableValue.magnitude < step {
                ScrollEvent.normalizeY(scrollEvent, step)
            }
            smoothedY = scrollEvent.Y.usableValue
        }
        if shouldSmoothHorizontal {
            if scrollEvent.X.usableValue.magnitude < step {
                ScrollEvent.normalizeX(scrollEvent, step)
            }
            smoothedX = scrollEvent.X.usableValue
        }

        let needVerticalPassthrough = hasVerticalDelta && !shouldSmoothVertical
        let needHorizontalPassthrough = hasHorizontalDelta && !shouldSmoothHorizontal
        let needsPassthrough = needVerticalPassthrough || needHorizontalPassthrough
        let shouldSmoothAny = (smoothedY != 0.0) || (smoothedX != 0.0)

        if shouldSmoothAny {
            ScrollPoster.shared.update(
                event: event,
                duration: duration,
                y: smoothedY,
                x: smoothedX,
                speed: speed,
                amplification: ScrollCore.shared.dashAmplification
            ).tryStart()
        }

        if needsPassthrough {
            if shouldSmoothVertical {
                ScrollEvent.clearY(scrollEvent)
            }
            if shouldSmoothHorizontal {
                ScrollEvent.clearX(scrollEvent)
            }
            return Unmanaged.passUnretained(event)
        }

        if shouldSmoothAny {
            if ScrollPoster.shared.isAvailable {
                return nil
            } else {
                return Unmanaged.passUnretained(event)
            }
        } else {
            return Unmanaged.passUnretained(event)
        }
    }
    
    // MARK: - HID++ 滚动热键处理

    /// 跟踪当前由哪个 HID++ 按键码激活了热键状态
    /// key-up 时按 code 清除, 不依赖当前 app 的热键配置, 避免跨应用释放时状态卡死
    private var hidDashHeldCode: UInt16?
    private var hidToggleHeldCode: UInt16?
    private var hidBlockHeldCode: UInt16?

    /// 处理来自 Logitech HID++ 的按键事件, 匹配 dash/toggle/block 滚动热键
    @discardableResult
    func handleScrollHotkeyFromHIDPlusPlus(code: UInt16, isDown: Bool) -> Bool {
        // Key-up: 按跟踪的 code 清除状态 (不依赖当前 app 配置, 防止焦点切换导致状态卡死)
        if !isDown {
            var matched = false
            if hidDashHeldCode == code {
                dashKeyHeld = false; dashScroll = false; dashAmplification = 1.0
                hidDashHeldCode = nil; matched = true
            }
            if hidToggleHeldCode == code {
                toggleKeyHeld = false; toggleScroll = false
                hidToggleHeldCode = nil; matched = true
            }
            if hidBlockHeldCode == code {
                blockKeyHeld = false; blockSmooth = false
                hidBlockHeldCode = nil; matched = true
            }
            return matched
        }

        // Key-down: 刷新前台应用上下文 (HID++ 事件不经过滚动事件路径, application 可能陈旧)
        application = ScrollUtils.shared.getTargetApplication(from: NSWorkspace.shared.frontmostApplication)

        let dashHotkey = ScrollUtils.shared.optionsDashKey(application: application)
        let toggleHotkey = ScrollUtils.shared.optionsToggleKey(application: application)
        let blockHotkey = ScrollUtils.shared.optionsBlockKey(application: application)

        var matched = false

        if let h = dashHotkey, h.type == .mouse, h.code == code {
            dashKeyHeld = true; dashScroll = true; dashAmplification = 5.0
            hidDashHeldCode = code; matched = true
        }
        if let h = toggleHotkey, h.type == .mouse, h.code == code {
            toggleKeyHeld = true; toggleScroll = true
            hidToggleHeldCode = code; matched = true
        }
        if let h = blockHotkey, h.type == .mouse, h.code == code {
            blockKeyHeld = true; blockSmooth = true
            hidBlockHeldCode = code; matched = true
        }

        return matched
    }

    // MARK: - 热键事件处理 (CGEventTap)
    let hotkeyEventCallBack: CGEventTapCallBack = { (proxy, type, event, refcon) in
        // 跳过 Mos 合成事件, 避免 executeCustom 的 flagsChanged 误触发 dash/toggle/block
        if event.getIntegerValueField(.eventSourceUserData) == MosEventMarker.syntheticCustom {
            return nil  // listenOnly tap 返回值无影响
        }

        let keyCode = event.keyCode
        let mouseButton = UInt16(event.getIntegerValueField(.mouseEventButtonNumber))

        // 判断事件类型
        let isMouseEvent = (type == .otherMouseDown || type == .otherMouseUp)
        let isKeyDown = (type == .keyDown || type == .otherMouseDown)
        let isKeyUp = (type == .keyUp || type == .otherMouseUp)
        let isFlagsChanged = (type == .flagsChanged)

        // 记录按键时的目标应用
        if (event.isKeyDown || isKeyDown) && ScrollCore.shared.currentApplication == nil {
            ScrollCore.shared.currentApplication = ScrollCore.shared.application
        }

        // 获取配置的热键
        let dashHotkey = ScrollUtils.shared.optionsDashKey(application: ScrollCore.shared.application)
        let toggleHotkey = ScrollUtils.shared.optionsToggleKey(application: ScrollCore.shared.application)
        let blockHotkey = ScrollUtils.shared.optionsBlockKey(application: ScrollCore.shared.application)

        // 检测热键是否匹配并更新状态
        func checkAndUpdateHotkey(_ hotkey: ScrollHotkey?, keyHeld: inout Bool) -> Bool? {
            guard let hotkey = hotkey else { return nil }

            if hotkey.isModifierKey {
                // 修饰键：通过 flagsChanged 事件检测
                if isFlagsChanged && keyCode == hotkey.code {
                    return event.flags.contains(hotkey.modifierMask)
                }
            } else if hotkey.matches(event, keyCode: keyCode, mouseButton: mouseButton, isMouseEvent: isMouseEvent) {
                // 普通按键或鼠标按键
                if isKeyDown { keyHeld = true }
                if isKeyUp { keyHeld = false }
                return keyHeld
            }
            return nil
        }

        // Dash
        if let isPressed = checkAndUpdateHotkey(dashHotkey, keyHeld: &ScrollCore.shared.dashKeyHeld) {
            ScrollCore.shared.dashScroll = isPressed
            ScrollCore.shared.dashAmplification = isPressed ? 5.0 : 1.0
        }
        // Toggle
        if let isPressed = checkAndUpdateHotkey(toggleHotkey, keyHeld: &ScrollCore.shared.toggleKeyHeld) {
            ScrollCore.shared.toggleScroll = isPressed
        }
        // Block
        if let isPressed = checkAndUpdateHotkey(blockHotkey, keyHeld: &ScrollCore.shared.blockKeyHeld) {
            ScrollCore.shared.blockSmooth = isPressed
        }

        // 处理抬起时焦点 App 变化
        let isAppTargetChanged = ScrollCore.shared.currentApplication != ScrollCore.shared.application
        let isAnyKeyUp = event.isKeyUp || isKeyUp
        if isAppTargetChanged && isAnyKeyUp {
            // 关闭全部
            ScrollCore.shared.dashScroll = false
            ScrollCore.shared.dashAmplification = 1.0
            ScrollCore.shared.toggleScroll = false
            ScrollCore.shared.blockSmooth = false
            // 重置按键状态
            ScrollCore.shared.dashKeyHeld = false
            ScrollCore.shared.toggleKeyHeld = false
            ScrollCore.shared.blockKeyHeld = false
            // 并更新记录器
            ScrollCore.shared.currentApplication = nil
        }
        // 不返回原始事件
        return nil
    }
    
    // MARK: - 鼠标事件处理
    let mouseLeftEventCallBack: CGEventTapCallBack = { (proxy, type, event, refcon) in
        // 如果点击左键则停止滚动
        ScrollPoster.shared.stop()
        return nil
    }
    
    // MARK: - 事件运行管理
    // 启动
    func enable() {
        // Guard
        if isActive { return }
        isActive = true
        // 启动事件拦截层
        do {
            scrollEventInterceptor = try Interceptor(
                event: scrollEventMask,
                handleBy: scrollEventCallBack,
                listenOn: .cgAnnotatedSessionEventTap,
                placeAt: .tailAppendEventTap,
                for: .defaultTap
            )
            scrollEventInterceptor?.onRestart = {
                ScrollPoster.shared.stop(.TrackingEnd)
            }
            hotkeyEventInterceptor = try Interceptor(
                event: hotkeyEventMask,
                handleBy: hotkeyEventCallBack,
                listenOn: .cgAnnotatedSessionEventTap,
                placeAt: .tailAppendEventTap,
                for: .listenOnly
            )
            mouseEventInterceptor = try Interceptor(
                event: mouseLeftEventMask,
                handleBy: mouseLeftEventCallBack,
                listenOn: .cgAnnotatedSessionEventTap,
                placeAt: .tailAppendEventTap,
                for: .listenOnly
            )
            // 初始化滚动事件发送器
            ScrollPoster.shared.create()
            ScrollPoster.shared.startKeeper()
        } catch {
            print("[ScrollCore] Create Interceptor failure: \(error)")
        }
    }
    // 停止
    func disable() {
        // Guard
        if !isActive {return}
        isActive = false
        // 停止滚动事件发送器
        ScrollPoster.shared.stop()
        ScrollPoster.shared.stopKeeper()
        // 停止截取事件
        scrollEventInterceptor?.stop()
        hotkeyEventInterceptor?.stop()
        mouseEventInterceptor?.stop()
        // 显式释放, 避免旧 tap 残留在对象图中
        scrollEventInterceptor = nil
        hotkeyEventInterceptor = nil
        mouseEventInterceptor = nil
    }
}
