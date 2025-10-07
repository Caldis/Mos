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
    var application: Application?
    var currentApplication: Application? // 用于区分按下热键及抬起时的作用目标
    // 拦截层
    var scrollEventInterceptor: Interceptor?
    var hotkeyEventInterceptor: Interceptor?
    var mouseEventInterceptor: Interceptor?
    // 拦截掩码
    let scrollEventMask = CGEventMask(1 << CGEventType.scrollWheel.rawValue)
    let hotkeyEventMask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
    let mouseLeftEventMask = CGEventMask(1 << CGEventType.leftMouseDown.rawValue)
    
    // MARK: - 滚动事件处理
    let scrollEventCallBack: CGEventTapCallBack = { (proxy, type, event, refcon) in
        // 不处理触控板
        // 无法区分黑苹果, 因为黑苹果的触控板驱动直接模拟鼠标输入
        // 无法区分 Magic Mouse, 因为其滚动特征与内置的 Trackpad 一致
        if ScrollEvent.isTrackpad(with: event) {
            return Unmanaged.passUnretained(event)
        }
        // 滚动阶段介入
        ScrollPhase.shared.kickIn()
        // 是否返回原始事件 (不启用平滑时)
        var returnOriginalEvent = true
        // 当鼠标输入, 根据需要执行翻转方向/平滑滚动
        // 获取事件目标
        let targetRunningApplication = ScrollUtils.shared.getRunningApplication(from: event)
        // 获取列表中应用程序的列外设置信息
        ScrollCore.shared.application = ScrollUtils.shared.getTargetApplication(from: targetRunningApplication)
        // 平滑/翻转
        var enableSmooth = false,
            enableReverse = false
        var step = Options.shared.scroll.step,
            speed = Options.shared.scroll.speed,
            duration = Options.shared.scroll.durationTransition
        if let targetApplication = ScrollCore.shared.application {
            enableSmooth = targetApplication.isSmooth(ScrollCore.shared.blockSmooth)
            enableReverse = targetApplication.isReverse()
            step = targetApplication.getStep()
            speed = targetApplication.getSpeed()
            duration = targetApplication.getDuration()
        } else if !Options.shared.application.allowlist {
            enableSmooth = Options.shared.scroll.smooth && !ScrollCore.shared.blockSmooth
            enableReverse = Options.shared.scroll.reverse
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
        let keyCode = event.keyCode

        // 记录按键时的目标应用
        if event.isKeyDown && ScrollCore.shared.currentApplication == nil {
            ScrollCore.shared.currentApplication = ScrollCore.shared.application
        }

        // Dash
        let (dashKeyCode, dashKeyMask) = ScrollUtils.shared.optionsDashKey(application: ScrollCore.shared.application)
        if keyCode == dashKeyCode {
            let dashKeyIsPressed = event.flags.contains(dashKeyMask)
            ScrollCore.shared.dashScroll = dashKeyIsPressed
            ScrollCore.shared.dashAmplification = dashKeyIsPressed ? 5.0 : 1.0
        }
        // Toggle
        let (toggleKeyCode, toggleKeyMask) = ScrollUtils.shared.optionsToggleKey(application: ScrollCore.shared.application)
        if keyCode == toggleKeyCode {
            let toggleKeyIsPressed = event.flags.contains(toggleKeyMask)
            ScrollCore.shared.toggleScroll = toggleKeyIsPressed
        }
        // Block
        let (blockKeyCode, blockKeyMask) = ScrollUtils.shared.optionsBlockKey(application: ScrollCore.shared.application)
        if keyCode == blockKeyCode {
            let blockKeyIsPressed = event.flags.contains(blockKeyMask)
            ScrollCore.shared.blockSmooth = blockKeyIsPressed
        }
        // 处理抬起时焦点 App 变化
        let isAppTargetChanged = ScrollCore.shared.currentApplication != ScrollCore.shared.application
        if isAppTargetChanged && event.isKeyUp {
            // 关闭全部
            ScrollCore.shared.dashScroll = false
            ScrollCore.shared.dashAmplification = 1.0
            ScrollCore.shared.toggleScroll = false
            ScrollCore.shared.blockSmooth = false
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
