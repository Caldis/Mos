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
    init() { print("Class 'ScrollUtils' is initialized") }
    
    // 发送事件
    func postScrollEvent(proxy: CGEventTapProxy, event: CGEvent, value: ( y: Double, x: Double )) {
        if let eventClone = event.copy() {
            eventClone.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: value.y)
            eventClone.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: value.x)
            eventClone.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: 0.0)
            eventClone.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: 0.0)
            eventClone.setDoubleValueField(.scrollWheelEventIsContinuous, value: 1.0)
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
    
    // 判断 LaunchPad 是否激活
    var launchpadActiveCache = false
    var launchpadLastDetectTime = 0.0
    func getLaunchpadActivity(withRunningApplication runningApplication: NSRunningApplication?) -> Bool {
        guard let validRunningApplication = runningApplication else { return false }
        // 10.15 以上直接判断
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

    // 从 exceptionalApplications 中取回符合传入的 key 的 ExceptionalApplication 对象
    // Key 在 applications 初始化时指定于 ExceptionalApplication 中
    func getExceptionalApplication(from runningApplication: NSRunningApplication?) -> ExceptionalApplication? {
        if let applicationByBundlePath = Options.shared.general.applications.get(by: runningApplication?.bundleURL?.path) {
            return applicationByBundlePath
        }
        if let applicationByExecutablePath = Options.shared.general.applications.get(by: runningApplication?.executableURL?.path) {
            return applicationByExecutablePath
        }
        return nil
    }

    // 滚动参数: 热键
    func optionsDashOn(application: ExceptionalApplication?) -> CGKeyCode {
        if let targetApplication = application {
            return CGKeyCode(targetApplication.inherit ? Options.shared.scrollAdvanced.dash ?? 0 : targetApplication.scrollAdvanced.dash ?? 0)
        } else {
            return CGKeyCode(Options.shared.scrollAdvanced.dash ?? 0)
        }
    }
    func optionsToggleOn(application: ExceptionalApplication?) -> CGKeyCode {
        if let targetApplication = application {
            return CGKeyCode(targetApplication.inherit ? Options.shared.scrollAdvanced.toggle ?? 0 : targetApplication.scrollAdvanced.toggle ?? 0)
        } else {
            return CGKeyCode(Options.shared.scrollAdvanced.toggle ?? 0)
        }
    }
    func optionsBlockOn(application: ExceptionalApplication?) -> CGKeyCode {
        if let targetApplication = application {
            return CGKeyCode(targetApplication.inherit ? Options.shared.scrollAdvanced.block ?? 0 : targetApplication.scrollAdvanced.block ?? 0)
        } else {
            return CGKeyCode(Options.shared.scrollAdvanced.block ?? 0)
        }
    }
}
