//
//  ScrollUtils.swift
//  Mos
//  滚动事件截取与判断核心工具方法
//  Created by Caldis on 2018/2/19.
//  Copyright © 2018年 Caldis. All rights reserved.
//

import Cocoa

class ScrollUtils {
    
    // 单例
    static let shared = ScrollUtils()
    init() { NSLog("Module initialized: ScrollUtils") }
    
    // 判断事件目标是否变化
    var previousScrollTargetProcessID = 0.0 // 用于在鼠标移动到不同窗口时停止滚动
    var currentScrollTargetProcessID = 0.0
    func isTargetChanged(_ event: CGEvent) -> Bool {
        // 更新当前 ProcessID
        previousScrollTargetProcessID = currentScrollTargetProcessID
        currentScrollTargetProcessID = event.getDoubleValueField(.eventTargetUnixProcessID)
        // 判断是否变化
        return previousScrollTargetProcessID != currentScrollTargetProcessID && previousScrollTargetProcessID != 0.0
    }
    
    // 发送事件
    func postScrollEvent(_ proxy: CGEventTapProxy, _ event: CGEvent, _ value: ( y: Double, x: Double )) {
        if let eventClone = event.copy() {
            eventClone.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: value.y)
            eventClone.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: value.x)
            eventClone.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: 0.0)
            eventClone.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: 0.0)
            eventClone.setDoubleValueField(.scrollWheelEventIsContinuous, value: 1.0)
            // EventTapProxy 标识了 EventTapCallback 在事件流中接收到事件的特定位置, 其粒度小于 tap 本身
            // 使用 tapPostEvent 可以将自定义的事件发布到 proxy 标识的位置, 避免被 EventTapCallback 本身重复接收或处理
            // 新发布的事件将早于 EventTapCallback 所处理的事件进入系统, 也如同 EventTapCallback 所处理的事件, 会被所有后续的 EventTap 接收
            eventClone.tapPostEvent(proxy)
        }
    }
    
    // 从 CGEvent 中携带的 PID 获取应用信息
    private var lastEventTargetPID: pid_t = 1  // 事件的目标进程 PID (先前)
    private var currEventTargetPID: pid_t = 1  // 事件的目标进程 PID (当前)
    private var cachedRunningApplication: NSRunningApplication?
    func getRunningApplication(from event: CGEvent) -> NSRunningApplication? {
        // Guard
        let pid = pid_t(event.getIntegerValueField(.eventTargetUnixProcessID))
        if pid == pid_t(1) { return nil }
        // 保存上次 PID
        lastEventTargetPID = currEventTargetPID
        // 更新当前 PID
        currEventTargetPID = pid
        // 使用 PID 获取 BID
        // 如果目标 PID 变化, 则重新获取一次窗口 BID
        if lastEventTargetPID != currEventTargetPID {
            cachedRunningApplication = NSRunningApplication.init(processIdentifier: pid)
        }
        return cachedRunningApplication
    }
    
    // 判断目标是否为 Chrome
    func isEventTargetingChrome(_ event: CGEvent?) -> Bool {
        guard let validEvent = event else {
            return false
        }
        guard let targetRunningApplication = getRunningApplication(from: validEvent) else {
            return false
        }
        if let targetBundleIdentifier = targetRunningApplication.bundleIdentifier, targetBundleIdentifier == "com.google.Chrome" {
            return true
        }
        return false
    }
    
    // 判断 LaunchPad 是否激活
    var launchpadActiveCache = false
    var launchpadLastDetectTime = 0.0
    func getLaunchpadActivity(withRunningApplication runningApplication: NSRunningApplication?) -> Bool {
        guard let validRunningApplication = runningApplication else {
            return false
        }
        // 10.15 以上直接判断是否为 Dock
        // FIXME: 当 Dock 的目录设置为 "叠放" 时, 应用对 Dock 的目录预览无法平滑, 且发送平滑后的滚动事件无法被识别, 需要找别的方式
        if #available(OSX 10.15, *) {
            if validRunningApplication.executableURL?.path == "/System/Library/CoreServices/Dock.app/Contents/MacOS/Dock" {
                launchpadActiveCache = true
                return launchpadActiveCache
            }
        }
        // 如果距离上次检测时间大于 1s, 则重新检测一遍, 否则直接返回上次的结果
        let nowTime = NSDate().timeIntervalSince1970
        if nowTime - launchpadLastDetectTime > 1.0 {
            // 10.15以下需要根据 windowList 判断
            let windowInfoList = CGWindowListCopyWindowInfo(CGWindowListOption.optionOnScreenOnly, CGWindowID(0)) as [AnyObject]?
            for windowInfo in windowInfoList! {
                let windowName = windowInfo[kCGWindowName]!
                if windowName != nil && windowName as! String == "LPSpringboard" {
                    launchpadActiveCache = true
                    return true
                }
            }
            launchpadActiveCache = false
            launchpadLastDetectTime = nowTime
        }
        return launchpadActiveCache
    }

    // 从 Applications 中取回符合传入的 key 的 Application 对象
    // Key 在 applications 初始化时指定于 Application 中
    func getTargetApplication(from runningApplication: NSRunningApplication?) -> Application? {
        if let applicationByBundlePath = Options.shared.application.applications.get(by: runningApplication?.bundleURL?.path) {
            return applicationByBundlePath
        }
        if let applicationByExecutablePath = Options.shared.application.applications.get(by: runningApplication?.executableURL?.path) {
            return applicationByExecutablePath
        }
        return nil
    }

    // 滚动参数: 热键
    // 使用 0xFFFF 作为未配置的标识, 避免与 keyCode=0 (A键) 或其他功能键冲突
    func optionsDashKey(application: Application?) -> (CGKeyCode, CGEventFlags) {
        var code: CGKeyCode
        if let targetApplication = application {
            let keyValue = targetApplication.inherit ? Options.shared.scroll.dash : targetApplication.scroll.dash
            // 0 或 nil 都视为未配置,返回不可能的 keyCode
            code = (keyValue == nil || keyValue == 0) ? CGKeyCode(0xFFFF) : CGKeyCode(keyValue!)
        } else {
            let keyValue = Options.shared.scroll.dash
            code = (keyValue == nil || keyValue == 0) ? CGKeyCode(0xFFFF) : CGKeyCode(keyValue!)
        }
        let mask = KeyCode.getKeyMask(code)
        return (code, mask)
    }
    func optionsToggleKey(application: Application?) -> (CGKeyCode, CGEventFlags) {
        var code: CGKeyCode
        if let targetApplication = application {
            let keyValue = targetApplication.inherit ? Options.shared.scroll.toggle : targetApplication.scroll.toggle
            code = (keyValue == nil || keyValue == 0) ? CGKeyCode(0xFFFF) : CGKeyCode(keyValue!)
        } else {
            let keyValue = Options.shared.scroll.toggle
            code = (keyValue == nil || keyValue == 0) ? CGKeyCode(0xFFFF) : CGKeyCode(keyValue!)
        }
        let mask = KeyCode.getKeyMask(code)
        return (code, mask)
    }
    func optionsBlockKey(application: Application?) -> (CGKeyCode, CGEventFlags) {
        var code: CGKeyCode
        if let targetApplication = application {
            let keyValue = targetApplication.inherit ? Options.shared.scroll.block : targetApplication.scroll.block
            code = (keyValue == nil || keyValue == 0) ? CGKeyCode(0xFFFF) : CGKeyCode(keyValue!)
        } else {
            let keyValue = Options.shared.scroll.block
            code = (keyValue == nil || keyValue == 0) ? CGKeyCode(0xFFFF) : CGKeyCode(keyValue!)
        }
        let mask = KeyCode.getKeyMask(code)
        return (code, mask)
    }
}
