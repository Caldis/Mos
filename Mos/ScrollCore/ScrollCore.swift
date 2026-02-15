//
//  ScrollCore.swift
//  Mos
//  滚动事件截取与插值计算核心类
//  Created by Caldis on 2017/1/14.
//  Copyright © 2017年 Caldis. All rights reserved.
//

import Cocoa
import os

class ScrollCore {
    
    // 单例
    static let shared = ScrollCore()
    init() { NSLog("Module initialized: ScrollCore") }
    
    // 线程同步锁
    private var _lock = os_unfair_lock()
    
    private func withLock<T>(_ body: () -> T) -> T {
        os_unfair_lock_lock(&_lock)
        defer { os_unfair_lock_unlock(&_lock) }
        return body()
    }
    
    // 执行状态
    private var _isActive = false
    var isActive: Bool {
        get { return withLock { _isActive } }
        set { withLock { _isActive = newValue } }
    }
    // 热键数据
    private var _dashScroll = false
    var dashScroll: Bool {
        get { return withLock { _dashScroll } }
        set { withLock { _dashScroll = newValue } }
    }
    private var _dashAmplification = 1.0
    var dashAmplification: Double {
        get { return withLock { _dashAmplification } }
        set { withLock { _dashAmplification = newValue } }
    }
    private var _toggleScroll = false
    var toggleScroll: Bool {
        get { return withLock { _toggleScroll } }
        set {
            withLock { _toggleScroll = newValue }
            ScrollPoster.shared.updateShifting(enable: newValue)
        }
    }
    private var _blockSmooth = false
    var blockSmooth: Bool {
        get { return withLock { _blockSmooth } }
        set { withLock { _blockSmooth = newValue } }
    }
    // 非修饰键热键的按下状态跟踪
    private var _dashKeyHeld = false
    var dashKeyHeld: Bool {
        get { return withLock { _dashKeyHeld } }
        set { withLock { _dashKeyHeld = newValue } }
    }
    private var _toggleKeyHeld = false
    var toggleKeyHeld: Bool {
        get { return withLock { _toggleKeyHeld } }
        set { withLock { _toggleKeyHeld = newValue } }
    }
    private var _blockKeyHeld = false
    var blockKeyHeld: Bool {
        get { return withLock { _blockKeyHeld } }
        set { withLock { _blockKeyHeld = newValue } }
    }
    // 例外应用数据
    private var _application: Application?
    var application: Application? {
        get { return withLock { _application } }
        set { withLock { _application = newValue } }
    }
    private var _currentApplication: Application? // 用于区分按下热键及抬起时的作用目标
    var currentApplication: Application? {
        get { return withLock { _currentApplication } }
        set { withLock { _currentApplication = newValue } }
    }
    
    func snapshotScrollState() -> (blockSmooth: Bool, toggleScroll: Bool, dashAmplification: Double, application: Application?) {
        return withLock { (_blockSmooth, _toggleScroll, _dashAmplification, _application) }
    }
    
    func resetHotkeyState() {
        withLock {
            _dashScroll = false
            _dashAmplification = 1.0
            _toggleScroll = false
            _blockSmooth = false
            _dashKeyHeld = false
            _toggleKeyHeld = false
            _blockKeyHeld = false
            _currentApplication = nil
        }
        ScrollPoster.shared.updateShifting(enable: false)
    }
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
        let targetApplication = ScrollUtils.shared.getTargetApplication(from: targetRunningApplication)
        ScrollCore.shared.application = targetApplication
        // 原子快照读取热键状态
        let state = ScrollCore.shared.snapshotScrollState()
        // 平滑/翻转
        var enableSmooth = false,
            enableSmoothVertical = false,
            enableSmoothHorizontal = false,
            enableReverseVertical = false,
            enableReverseHorizontal = false
        var step = Options.shared.scroll.step,
            speed = Options.shared.scroll.speed,
            duration = Options.shared.scroll.durationTransition
        if let targetApplication = targetApplication {
            enableSmooth = targetApplication.isSmooth(state.blockSmooth)
            enableSmoothVertical = targetApplication.isSmoothVertical(state.blockSmooth)
            enableSmoothHorizontal = targetApplication.isSmoothHorizontal(state.blockSmooth)
            enableReverseVertical = targetApplication.isReverseVertical()
            enableReverseHorizontal = targetApplication.isReverseHorizontal()
            step = targetApplication.getStep()
            speed = targetApplication.getSpeed()
            duration = targetApplication.getDuration()
        } else if !Options.shared.application.allowlist {
            enableSmooth = Options.shared.scroll.smooth && !state.blockSmooth
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
        let willShiftVerticalToHorizontal = state.toggleScroll && hasVerticalDelta && !hasHorizontalDelta
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
                proxy: proxy,
                duration: duration,
                y: smoothedY,
                x: smoothedX,
                speed: speed,
                amplification: state.dashAmplification
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
            return nil
        } else {
            return Unmanaged.passUnretained(event)
        }
    }
    
    // MARK: - 热键事件处理
    let hotkeyEventCallBack: CGEventTapCallBack = { (proxy, type, event, refcon) in
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
            ScrollCore.shared.resetHotkeyState()
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
        // 停止截取事件
        scrollEventInterceptor?.stop()
        hotkeyEventInterceptor?.stop()
        mouseEventInterceptor?.stop()
    }
}
