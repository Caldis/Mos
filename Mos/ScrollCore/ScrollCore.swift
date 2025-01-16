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
    // 例外应用数据
    var exceptionalApplication: ExceptionalApplication?
    var currentExceptionalApplication: ExceptionalApplication? // 用于区分按下热键及抬起时的作用目标
    // 拦截层
    var scrollEventInterceptor: Interceptor?
    var hotkeyEventInterceptor: Interceptor?
    var mouseEventInterceptor: Interceptor?
    // 拦截掩码
    let scrollEventMask = CGEventMask(1 << CGEventType.scrollWheel.rawValue)
    let hotkeyEventMask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
    let mouseLeftEventMask = CGEventMask(1 << CGEventType.leftMouseDown.rawValue)
    let mouseRightEventMask = CGEventMask(1 << CGEventType.rightMouseDown.rawValue)
    
    // MARK: - 滚动事件处理
    let scrollEventCallBack: CGEventTapCallBack = { (proxy, type, event, refcon) in
        // 不处理触控板
        // 无法区分黑苹果, 因为黑苹果的触控板驱动直接模拟鼠标输入
        // 无法区分 Magic Mouse, 因为其滚动特征与内置的 Trackpad 一致
        if ScrollEvent.isTrackpad(with: event) {
            return Unmanaged.passUnretained(event)
        }
        // 切换目标窗时停止滚动 (DEPRECATED: 目前直接往 EventTap 发送 Event)
        // if ScrollUtils.shared.isTargetChanged(event) {
        //     ScrollPoster.shared.pauseAuto()
        //     return nil
        // }
        // 滚动阶段介入
        ScrollPhase.shared.kickIn()
        // 是否返回原始事件 (不启用平滑时)
        var returnOriginalEvent = true
        // 当鼠标输入, 根据需要执行翻转方向/平滑滚动
        // 获取事件目标
        let targetRunningApplication = ScrollUtils.shared.getRunningApplication(from: event)
        // 获取列表中应用程序的列外设置信息
        ScrollCore.shared.exceptionalApplication = ScrollUtils.shared.getExceptionalApplication(from: targetRunningApplication)
        // 平滑/翻转
        var enableSmooth = false,
            enableReverse = false
        var step = Options.shared.scrollAdvanced.step,
            speed = Options.shared.scrollAdvanced.speed,
            duration = Options.shared.scrollAdvanced.durationTransition
        if let exceptionalApplication = ScrollCore.shared.exceptionalApplication {
            enableSmooth = exceptionalApplication.isSmooth(ScrollCore.shared.blockSmooth)
            enableReverse = exceptionalApplication.isReverse()
            step = exceptionalApplication.getStep()
            speed = exceptionalApplication.getSpeed()
            duration = exceptionalApplication.getDuration()
        } else if !Options.shared.general.allowlist {
            enableSmooth = Options.shared.scrollBasic.smooth && !ScrollCore.shared.blockSmooth
            enableReverse = Options.shared.scrollBasic.reverse
        }
        // Launchpad 激活则强制屏蔽平滑
        if ScrollUtils.shared.getLaunchpadActivity(withRunningApplication: targetRunningApplication) {
            enableSmooth = false
        }
        // 滚动事件
        let scrollEvent = ScrollEvent(with: event)
        // Y轴
        if scrollEvent.Y.valid {
            // 是否翻转滚动
            if enableReverse {
                ScrollEvent.reverseY(scrollEvent)
            }
            // 是否平滑滚动
            if enableSmooth {
                // 禁止返回原始事件
                returnOriginalEvent = false
                // 如果输入值为非 Fixed 类型, 则使用 Step 作为门限值将数据归一化
                if !scrollEvent.Y.fixed {
                    ScrollEvent.normalizeY(scrollEvent, step)
                }
            }
        }
        // X轴
        if scrollEvent.X.valid {
            // 是否翻转滚动
            if enableReverse {
                ScrollEvent.reverseX(scrollEvent)
            }
            // 是否平滑滚动
            if enableSmooth {
                // 禁止返回原始事件
                returnOriginalEvent = false
                // 如果输入值为非 Fixed 类型, 则使用 Step 作为门限值将数据归一化
                if !scrollEvent.X.fixed {
                    ScrollEvent.normalizeX(scrollEvent, step)
                }
            }
        }
        // 触发滚动事件推送
        if enableSmooth {
            ScrollPoster.shared.update(
                event: event,
                proxy: proxy,
                duration: duration,
                y: scrollEvent.Y.usableValue,
                x: scrollEvent.X.usableValue,
                speed: speed,
                amplification: ScrollCore.shared.dashAmplification
            ).tryStart()
        }
        // 返回事件对象
        if returnOriginalEvent {
            return Unmanaged.passUnretained(event)
        } else {
            return nil
        }
    }
    
    // MARK: - 热键事件处理
    let hotkeyEventCallBack: CGEventTapCallBack = { (proxy, type, event, refcon) in
        // 获取当前按键
        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        // 判断快捷键
        switch keyCode {
        case MODIFIER_KEY.controlLeft, MODIFIER_KEY.controlRight:
            ScrollCore.shared.tryToggleEnableAllFlag(
                for: ScrollCore.shared.exceptionalApplication,
                with: keyCode,
                using: MODIFIER_KEY_SET.control.codes,
                on: Utils.isKeyDown(event, MODIFIER_KEY_SET.control)
            )
        case MODIFIER_KEY.optionLeft, MODIFIER_KEY.optionRight:
            ScrollCore.shared.tryToggleEnableAllFlag(
                for: ScrollCore.shared.exceptionalApplication,
                with: keyCode,
                using: MODIFIER_KEY_SET.option.codes,
                on: Utils.isKeyDown(event, MODIFIER_KEY_SET.option)
            )
        case MODIFIER_KEY.commandLeft, MODIFIER_KEY.commandRight:
            ScrollCore.shared.tryToggleEnableAllFlag(
                for: ScrollCore.shared.exceptionalApplication,
                with: keyCode,
                using: MODIFIER_KEY_SET.command.codes,
                on: Utils.isKeyDown(event, MODIFIER_KEY_SET.command)
            )
        case MODIFIER_KEY.shiftLeft, MODIFIER_KEY.shiftRight:
            ScrollCore.shared.tryToggleEnableAllFlag(
                for: ScrollCore.shared.exceptionalApplication,
                with: keyCode,
                using: MODIFIER_KEY_SET.shift.codes,
                on: Utils.isKeyDown(event, MODIFIER_KEY_SET.shift)
            )
        default: break
        }
        return nil
    }
    func tryEnableDashFlag(with key:CGKeyCode, andKeyPair keyPair:[CGKeyCode]) {
        if (keyPair.contains(key)) {
            ScrollCore.shared.dashScroll = true
            ScrollCore.shared.dashAmplification = 5.0
        }
    }
    func tryDisableDashFlag(with key:CGKeyCode, andKeyPair keyPair:[CGKeyCode]) {
        if (keyPair.contains(key)) {
            ScrollCore.shared.dashScroll = false
            ScrollCore.shared.dashAmplification = 1.0
        }
    }
    func tryEnableToggleFlag(with key:CGKeyCode, andKeyPair keyPair:[CGKeyCode]) {
        if (keyPair.contains(key)) {
            ScrollCore.shared.toggleScroll = true
        }
    }
    func tryDisableToggleFlag(with key:CGKeyCode, andKeyPair keyPair:[CGKeyCode]) {
        if (keyPair.contains(key)) {
            ScrollCore.shared.toggleScroll = false
        }
    }
    func tryEnableBlockFlag(with key:CGKeyCode, andKeyPair keyPair:[CGKeyCode]) {
        if (keyPair.contains(key)) {
            ScrollCore.shared.blockSmooth = true
            ScrollPoster.shared.brake()
        }
    }
    func tryDisableBlockFlag(with key:CGKeyCode, andKeyPair keyPair:[CGKeyCode]) {
        if (keyPair.contains(key)) {
            ScrollCore.shared.blockSmooth = false
        }
    }
    func disableAllFlag() {
        ScrollCore.shared.dashScroll = false
        ScrollCore.shared.dashAmplification = 1.0
        ScrollCore.shared.toggleScroll = false
        ScrollCore.shared.blockSmooth = false
    }
    func tryToggleEnableAllFlag(for targetApplication:ExceptionalApplication?, with keyCode:CGKeyCode, using keyPair:[CGKeyCode], on down:Bool) {
        // 读取快捷键
        let dashKey = ScrollUtils.shared.optionsDashOn(application: targetApplication)
        let toggleKey = ScrollUtils.shared.optionsToggleOn(application: targetApplication)
        let blockKey = ScrollUtils.shared.optionsBlockOn(application: targetApplication)
        if down {
            // 如果按下, 则按需激活
            ScrollCore.shared.tryEnableDashFlag(with: dashKey, andKeyPair: keyPair)
            ScrollCore.shared.tryEnableToggleFlag(with: toggleKey, andKeyPair: keyPair)
            ScrollCore.shared.tryEnableBlockFlag(with: blockKey, andKeyPair: keyPair)
            // 并更新记录器
            ScrollCore.shared.currentExceptionalApplication = targetApplication
        } else if ScrollCore.shared.currentExceptionalApplication == targetApplication {
            // 如果弹起, 且与先前的目标应用相同, 则按需关闭
            ScrollCore.shared.tryDisableDashFlag(with: dashKey, andKeyPair: keyPair)
            ScrollCore.shared.tryDisableToggleFlag(with: toggleKey, andKeyPair: keyPair)
            ScrollCore.shared.tryDisableBlockFlag(with: blockKey, andKeyPair: keyPair)
        } else {
            // 否则关闭全部
            ScrollCore.shared.disableAllFlag()
            // 并更新记录器
            ScrollCore.shared.currentExceptionalApplication = nil
        }
    }
    
    // MARK: - 鼠标事件处理
    let mouseLeftEventCallBack: CGEventTapCallBack = { (proxy, type, event, refcon) in
        // 如果点击左键则停止滚动
        ScrollPoster.shared.stop()
        return nil
    }
    
    // MARK: - 事件运行管理
    // 启动
    func startHandlingScroll() {
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
    func endHandlingScroll() {
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
