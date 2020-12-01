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
    // 滚动数据
    var scrollCurr   = ( y: 0.0, x: 0.0 )  // 当前滚动距离
    var scrollBuffer = ( y: 0.0, x: 0.0 )  // 滚动缓冲距离
    var scrollDelta  = ( y: 0.0, x: 0.0 )  // 滚动方向记录
    // 热键数据
    var dashScroll = false
    var dashAmplification = 1.0
    var toggleScroll = false
    var blockSmooth = false
    // 插值数据
    let interpolatorWorker = Interpolator.lerp
    let interpolatorFiller = ScrollFiller()
    var interpolatorDuration = Options.shared.scrollAdvanced.durationTransition
    // 例外应用数据
    var exceptionalApplication: ExceptionalApplication?
    var currentExceptionalApplication: ExceptionalApplication? // 用于区分按下热键及抬起时的作用目标
    // 事件发送器
    var scrollEventBase: CGEvent?
    var scrollEventProxy: CGEventTapProxy?
    var scrollEventPoster: CVDisplayLink?
    // 拦截层
    var scrollEventInterceptor: Interceptor?
    var hotkeyEventInterceptor: Interceptor?
    var mouseEventInterceptor: Interceptor?
    var tapKeeperTimer: Timer?
    // 拦截掩码
    let scrollEventMask = CGEventMask(1 << CGEventType.scrollWheel.rawValue)
    let hotkeyEventMask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
    let mouseLeftEventMask = CGEventMask(1 << CGEventType.leftMouseDown.rawValue)
    let mouseRightEventMask = CGEventMask(1 << CGEventType.rightMouseDown.rawValue)
    
    // 滚动事件截取处理
    let scrollEventCallBack: CGEventTapCallBack = { (proxy, type, event, refcon) in
        // 滚动事件
        let scrollEvent = ScrollEvent(with: event)
        // 不处理触控板
        // 无法区分黑苹果, 因为黑苹果的触控板驱动直接模拟鼠标输入
        if scrollEvent.isTouchPad() { return Unmanaged.passUnretained(event) }
        // 更新引用
        ScrollCore.shared.scrollEventBase = event
        ScrollCore.shared.scrollEventProxy = proxy
        // 切换目标窗时停止滚动
        if ScrollUtils.shared.isTargetChanged(event) {
            ScrollCore.shared.pauseHandlingScroll()
            return nil
        }
        // 是否返回原始事件 (不启用平滑时)
        var returnOriginalEvent = true
        // 当鼠标输入, 根据需要执行翻转方向/平滑滚动
        // 获取事件目标
        let targetRunningApplication = ScrollUtils.shared.getRunningApplication(from: event)
        // 获取列表中应用程序的列外设置信息
        ScrollCore.shared.exceptionalApplication = ScrollUtils.shared.getExceptionalApplication(from: targetRunningApplication)
        // 平滑/翻转
        var enableSmooth = false, enableReverse = false
        var step = Options.shared.scrollAdvanced.step, speed = Options.shared.scrollAdvanced.speed
        ScrollCore.shared.interpolatorDuration = Options.shared.scrollAdvanced.durationTransition
        if let exceptionalApplication = ScrollCore.shared.exceptionalApplication {
            enableSmooth = exceptionalApplication.isSmooth(ScrollCore.shared.blockSmooth)
            enableReverse = exceptionalApplication.isReverse()
            step = exceptionalApplication.getStep()
            speed = exceptionalApplication.getSpeed()
            ScrollCore.shared.interpolatorDuration = exceptionalApplication.getDuration()
        } else if !Options.shared.general.whitelist {
            enableSmooth = Options.shared.scrollBasic.smooth
            enableReverse = Options.shared.scrollBasic.reverse
        }
        // Launchpad 激活则强制屏蔽平滑
        if ScrollUtils.shared.getLaunchpadActivity(withRunningApplication: targetRunningApplication) {
            enableSmooth = false
        }
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
            ScrollCore.shared.updateScrollBuffer(
                y: scrollEvent.Y.usableValue,
                x: scrollEvent.X.usableValue,
                s: speed,
                a: ScrollCore.shared.dashAmplification
            )
            ScrollCore.shared.enableScrollEventPoster()
        }
        // 返回事件对象
        if returnOriginalEvent {
            return Unmanaged.passUnretained(event)
        } else {
            return nil
        }
    }
    
    // 热键事件处理
    let hotkeyEventCallBack: CGEventTapCallBack = { (proxy, type, event, refcon) in
        // 获取当前按键
        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        // 获取事件目标
        let targetRunningApplication = ScrollUtils.shared.getRunningApplication(from: event)
        let targetAppliaction = ScrollUtils.shared.getExceptionalApplication(from: targetRunningApplication)
        // 判断快捷键
        switch keyCode {
        case MODIFIER_KEY.controlLeft, MODIFIER_KEY.controlRight:
            ScrollCore.shared.tryToggleEnableAllFlag(
                for: targetAppliaction,
                with: keyCode,
                using: MODIFIER_KEY_SET.control.codes,
                on: Utils.isKeyDown(event, MODIFIER_KEY_SET.control)
            )
        case MODIFIER_KEY.optionLeft, MODIFIER_KEY.optionRight:
            ScrollCore.shared.tryToggleEnableAllFlag(
                for: targetAppliaction,
                with: keyCode,
                using: MODIFIER_KEY_SET.option.codes,
                on: Utils.isKeyDown(event, MODIFIER_KEY_SET.option)
            )
        case MODIFIER_KEY.commandLeft, MODIFIER_KEY.commandRight:
            ScrollCore.shared.tryToggleEnableAllFlag(
                for: targetAppliaction,
                with: keyCode,
                using: MODIFIER_KEY_SET.command.codes,
                on: Utils.isKeyDown(event, MODIFIER_KEY_SET.command)
            )
        case MODIFIER_KEY.shiftLeft, MODIFIER_KEY.shiftRight:
            ScrollCore.shared.tryToggleEnableAllFlag(
                for: targetAppliaction,
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
    func tryEnableToggleFlag(with key:CGKeyCode, andKeyPair keyPair:[CGKeyCode]) {
        if (keyPair.contains(key)) {
            ScrollCore.shared.toggleScroll = true
        }
    }
    func tryEnableBlockFlag(with key:CGKeyCode, andKeyPair keyPair:[CGKeyCode]) {
        if (keyPair.contains(key)) {
            ScrollCore.shared.blockSmooth = true
            ScrollCore.shared.scrollBuffer = ScrollCore.shared.scrollCurr
        }
    }
    func tryDisableDashFlag(with key:CGKeyCode, andKeyPair keyPair:[CGKeyCode]) {
        if (keyPair.contains(key)) {
            ScrollCore.shared.dashScroll = false
            ScrollCore.shared.dashAmplification = 1.0
        }
    }
    func tryDisableToggleFlag(with key:CGKeyCode, andKeyPair keyPair:[CGKeyCode]) {
        if (keyPair.contains(key)) {
            ScrollCore.shared.toggleScroll = false
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
    func tryToggleEnableAllFlag(for targetAppliaction:ExceptionalApplication?, with keyCode:CGKeyCode, using keyPair:[CGKeyCode], on down:Bool) {
        // 读取快捷键
        let dashKey = ScrollUtils.shared.optionsDashOn(application: targetAppliaction)
        let toggleKey = ScrollUtils.shared.optionsToggleOn(application: targetAppliaction)
        let blockKey = ScrollUtils.shared.optionsBlockOn(application: targetAppliaction)
        if down {
            // 如果按下, 则按需激活
            ScrollCore.shared.tryEnableDashFlag(with: dashKey, andKeyPair: keyPair)
            ScrollCore.shared.tryEnableToggleFlag(with: toggleKey, andKeyPair: keyPair)
            ScrollCore.shared.tryEnableBlockFlag(with: blockKey, andKeyPair: keyPair)
            // 并更新记录器
            ScrollCore.shared.currentExceptionalApplication = targetAppliaction
        } else if ScrollCore.shared.currentExceptionalApplication == targetAppliaction {
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
    
    // 鼠标事件处理
    let mouseLeftEventCallBack: CGEventTapCallBack = { (proxy, type, event, refcon) in
        // 如果点击左键则停止滚动
        ScrollCore.shared.pauseHandlingScroll()
        return nil
    }
    
    // 启动滚动处理
    func startHandlingScroll() {
        // Guard
        if isActive { return }
        isActive = true
        // 截取事件
        scrollEventInterceptor = Interceptor(
            event: scrollEventMask,
            handleBy: scrollEventCallBack,
            listenOn: .cgAnnotatedSessionEventTap,
            placeAt: .tailAppendEventTap,
            for: .defaultTap
        )
        hotkeyEventInterceptor = Interceptor(
            event: hotkeyEventMask,
            handleBy: hotkeyEventCallBack,
            listenOn: .cgAnnotatedSessionEventTap,
            placeAt: .tailAppendEventTap,
            for: .listenOnly
        )
        mouseEventInterceptor = Interceptor(
            event: mouseLeftEventMask,
            handleBy: mouseLeftEventCallBack,
            listenOn: .cgAnnotatedSessionEventTap,
            placeAt: .tailAppendEventTap,
            for: .listenOnly
        )
        // 初始化滚动事件发送器
        initScrollEventPoster()
        // 初始化守护进程
        tapKeeperTimer = Timer.scheduledTimer(
            timeInterval: 5.0,
            target: self,
            selector: #selector(tapKeeper),
            userInfo: nil,
            repeats: true
        )
    }
    // 暂停(当前)滚动处理
    func pauseHandlingScroll() {
        cleanScrollBuffer()
        disableScrollEventPoster()
    }
    // 停止滚动处理
    func endHandlingScroll() {
        // Guard
        if !isActive {return}
        isActive = false
        // 停止守护进程
        tapKeeperTimer?.invalidate()
        // 停止滚动事件发送器
        disableScrollEventPoster()
        // 停止截取事件
        scrollEventInterceptor?.stop()
        hotkeyEventInterceptor?.stop()
        mouseEventInterceptor?.stop()
    }
    // 守护进程
    @objc func tapKeeper() {
        scrollEventInterceptor?.check()
        hotkeyEventInterceptor?.check()
        mouseEventInterceptor?.check()
    }
    
    // 鼠标数据控制
    func updateScrollBuffer(y: Double, x: Double, s: Double, a: Double = 1) {
        // 更新 Y 轴数据
        if y*scrollDelta.y > 0 {
            scrollBuffer.y += y * s * a
        } else {
            scrollBuffer.y = y * s * a
            scrollCurr.y = 0.0
        }
        // 更新 X 轴数据
        if x*scrollDelta.x > 0 {
            scrollBuffer.x += x * s * a
        } else {
            scrollBuffer.x = x * s * a
            scrollCurr.x = 0.0
        }
        scrollDelta = ( y: y, x: x )
    }
    func cleanScrollBuffer() {
        // 重置数值
        scrollCurr = ( y: 0.0, x: 0.0 )
        scrollBuffer = ( y: 0.0, x: 0.0 )
        scrollDelta = ( y: 0.0, x: 0.0 )
        // 重置插值器
        interpolatorFiller.clean()
    }
    
    // 鼠标插值数据输出
    // 初始化 CVDisplayLink
    func initScrollEventPoster() {
        // 新建一个 CVDisplayLinkSetOutputCallback 来执行循环
        CVDisplayLinkCreateWithActiveCGDisplays(&scrollEventPoster)
        CVDisplayLinkSetOutputCallback(scrollEventPoster!, {
            (displayLink, inNow, inOutputTime, flagsIn, flagsOut, displayLinkContext) -> CVReturn in ScrollCore.shared.handleScroll()
            return kCVReturnSuccess
        }, nil)
    }
    // 启动事件发送器
    func enableScrollEventPoster() {
        if !CVDisplayLinkIsRunning(scrollEventPoster!) {
            CVDisplayLinkStart(scrollEventPoster!)
        }
    }
    // 停止事件发送器
    func disableScrollEventPoster() {
        if let poster = scrollEventPoster {
            CVDisplayLinkStop(poster)
        }
    }
    
    // 根据需要变换滚动方向
    func weapScrollIfToggling(with nextValue: ( y: Double, x: Double ), toggling: Bool) -> (y: Double, x: Double) {
        // 如果按下 Shift, 则始终将滚动转为横向
        if toggling {
            // 判断哪个轴有值, 有值则赋给 X
            // 某些鼠标 (MXMaster/MXAnywhere), 按下 Shift 后会显式转换方向为横向, 此处针对这类转换进行归一化处理
            if nextValue.y != 0.0 && nextValue.x == 0.0 {
                return (y: nextValue.x, x: nextValue.y)
            } else {
                return (y: nextValue.y, x: nextValue.x)
            }
        } else {
            return (y: nextValue.y, x: nextValue.x)
        }
    }
    // 处理滚动事件
    func handleScroll() {
        // 计算插值
        let scrollPulse = (
            y: interpolatorWorker(scrollCurr.y, scrollBuffer.y, ScrollCore.shared.interpolatorDuration),
            x: interpolatorWorker(scrollCurr.x, scrollBuffer.x, ScrollCore.shared.interpolatorDuration)
        )
        // 更新滚动位置
        scrollCurr = (
            y: scrollCurr.y + scrollPulse.y,
            x: scrollCurr.x + scrollPulse.x
        )
        // 平滑滚动结果
        let filledValue = interpolatorFiller.fill(with: scrollPulse)
        // 变换滚动结果
        let swapedValue = weapScrollIfToggling(with: filledValue, toggling: toggleScroll)
        // 发送滚动结果
        if let event = scrollEventBase, let proxy = scrollEventProxy {
            ScrollUtils.shared.postScrollEvent(
                proxy,
                event,
                swapedValue
            )
        }
        // 如果临近目标距离小于精确度门限则暂停滚动
        if scrollPulse.y.magnitude<=Options.shared.scrollAdvanced.precision && scrollPulse.x.magnitude<=Options.shared.scrollAdvanced.precision {
            pauseHandlingScroll()
        }
    }
}
