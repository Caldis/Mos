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
    
    func setScrollEvent(event: CGEvent, axis: UInt32, y: Double, x: Double) -> CGEvent? {
        let eventClone = event.copy()
        eventClone?.setDoubleValueField(.scrollWheelEventScrollCount, value: Double(axis))
        eventClone?.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: y)
        eventClone?.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: x)
        return eventClone
    }
    func postScrollEvent(event: CGEvent?, proxy: CGEventTapProxy?) {
        event?.tapPostEvent(proxy)
    }
    
    // 从 CGEvent 中携带的 PID 获取目标窗口的 BundleId
    // 已知问题: 获取到的始终为主激活窗口
    // 已知问题: 如果鼠标滚轮事件由 cghidEventTap 层截取, 则获取到的目标窗口 PID 始终为当前的激活窗口, 而不是悬停窗口
    //          如果事件在 cgAnnotatedSessionEventTap 层截取, 对应目标窗口 PID 则可用，但会造成事件循环截取
    private var lastEventTargetPID:pid_t = 1  // 事件的目标进程 PID (先前)
    private var currEventTargetPID:pid_t = 1  // 事件的目标进程 PID (当前)
    private var cacheEventTargetBID:String?    // 事件的目标进程 BID (当前)
    func getBundleByPid(from event: CGEvent) -> String? {
        // Guard
        let pid = pid_t(event.getIntegerValueField(.eventTargetUnixProcessID))
        if pid == pid_t(1) {return nil}
        // 保存上次 PID
        lastEventTargetPID = currEventTargetPID
        // 更新当前 PID
        currEventTargetPID = pid
        // 使用 PID 获取 BID
        // 如果目标 PID 变化, 则重新获取一次窗口 BID (查找 BID 效率较低)
        if lastEventTargetPID != currEventTargetPID {
            if let bundleId = Utils.getApplicationBundleIdRecursivelyFrom(pid: currEventTargetPID) {
                cacheEventTargetBID = bundleId
                return cacheEventTargetBID
            }
        }
        return cacheEventTargetBID
    }
    func getCurrentEventTargetBundleIdFromCache() -> String? {
        return cacheEventTargetBID
    }
    
    // 从指针悬停坐标获取窗口 BundleId, 如果失败则从 CGEvent 获取, 但此情况下仅匹配当前激活窗口
    // 原理: 获取指针坐标下的 AXUIElement 信息, 从而获取 BundleID
    // 来自: https://stackoverflow.com/questions/27584963/get-window-values-under-mouse
    // 从坐标获取的已知问题:
    // 1.外置屏幕获取到的 PID 有大约 30PX 在垂直方向上的偏移, 但内置屏幕无此问题
    // 2.Adobe Acrobat Reader 的画布区域对 AXUIElementCopyElementAtPosition 无响应, 仅能使用 event 获取
    // 3.效率较低，影响首次滚动性能
    let systemWideElement = AXUIElementCreateSystemWide()
    var bundleIdCache:String? = nil
    var bundleIdDetectTime = 0.0
    var mouseLocationCache = NSPoint(x: 0.0, y: 0.0)
    func getBundleIdFromMouseLocation(and event: CGEvent) -> String? {
        let location = NSEvent.mouseLocation
        // 如果距离上次检测时间大于 1s, 且鼠标移动大于阈值, 或缓存值为空, 则重新检测一遍, 否则直接返回上次的结果
        let timeCurr = NSDate().timeIntervalSince1970
        let timeDiffOverThreshold = (timeCurr - self.bundleIdDetectTime) > 1.0
        let mouseMoveOverThreshold = !mouseStayStill(location, mouseLocationCache)
        if ((timeDiffOverThreshold && mouseMoveOverThreshold) || bundleIdCache==nil) {
            // 获取光标坐标下的元素信息
            // event.getDoubleValueField(.eventTargetUnixProcessID) 获取到的 PID 始终为当前激活窗口的 PID
            // 除非事件在 cgAnnotatedSessionEventTap 层监听
            var element: AXUIElement?
            let pointAsCGPoint = carbonScreenPointFromCocoaScreenPoint(mouseLocation: location)
            let copyElementRes = AXUIElementCopyElementAtPosition(systemWideElement, Float(pointAsCGPoint.x), Float(pointAsCGPoint.y), &element )
            // 更新缓存值
            mouseLocationCache = location
            bundleIdDetectTime = timeCurr
            // 先尝试从鼠标坐标查找, 如果无法找到, 则使用事件携带的信息查找
            if copyElementRes == .success {
                let pid = getPidFrom(element: element!)
                bundleIdCache = Utils.getApplicationBundleIdFrom(pid: pid)
            } else {
                bundleIdCache = getBundleByPid(from: event)
            }
        }
        return bundleIdCache
    }
    // 格式化指针坐标
    private func carbonScreenPointFromCocoaScreenPoint(mouseLocation point: NSPoint) -> CGPoint {
        var foundScreen: NSScreen?
        var targetPoint: CGPoint?
        for screen in NSScreen.screens {
            if NSPointInRect(point, screen.frame) {
                foundScreen = screen
            }
        }
        if let screen = foundScreen {
            let screenHeight = screen.frame.size.height
            targetPoint = CGPoint(x: point.x, y: screenHeight - point.y - 1)
        }
        return targetPoint ?? CGPoint(x: 0.0, y: 0.0)
    }
    // 从 AXUIElement 获取 PID
    private func getPidFrom(element: AXUIElement) -> pid_t {
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        return pid
    }
    // 确定鼠标在一定范围内 (20PX)
    let limit:CGFloat = 20
    private func mouseStayStill(_ a: CGPoint, _ b: CGPoint) -> Bool {
        return sqrt(pow(a.x - b.x, 2) + pow(a.y - b.y, 2)) < limit
    }
    
    // 判断事件类型
    func isTouchPad(of event: CGEvent) -> Bool {
        // MomentumPhase 或 ScrollPhase 任一不为零, 则为触控板
        if (event.getDoubleValueField(.scrollWheelEventMomentumPhase) != 0.0) || (event.getDoubleValueField(.scrollWheelEventScrollPhase) != 0.0) {
            return true
        }
        // 累计加速度不为零, 则为触控板
        if event.getDoubleValueField(.scrollWheelEventScrollCount) != 0.0 {
            return true
        }
        return false
    }
    func isMouse(of event: CGEvent) -> Bool {
        return !isTouchPad(of: event)
    }
    
    // 判断 LaunchPad 是否激活
    var launchpadActiveCache = false
    var launchpadLastDetectTime = 0.0
    private func isLaunchpadActive(with targetBID: String? = nil) -> Bool {
        // 如果距离上次检测时间大于 1s, 则重新检测一遍, 否则直接返回上次的结果
        let nowTime = NSDate().timeIntervalSince1970
        if nowTime - launchpadLastDetectTime > 1.0 {
            if #available(OSX 10.15, *) {
                // Launchpadu 应用在 10.15 下莫名其妙合并到了 dock 内, 不过这样反而好找了
                if let bid = targetBID, bid == "com.apple.dock" {
                    launchpadActiveCache = true
                    return true
                }
            } else {
                let windowInfoList = CGWindowListCopyWindowInfo(CGWindowListOption.optionOnScreenOnly, CGWindowID(0)) as [AnyObject]?
                for windowInfo in windowInfoList! {
                    let windowName = windowInfo[kCGWindowName]!
                    if windowName != nil && windowName as! String == "LPSpringboard" {
                        launchpadActiveCache = true
                        return true
                    }
                }
            }
            launchpadActiveCache = false
            launchpadLastDetectTime = nowTime
        }
        return launchpadActiveCache
    }

    // 判断 MissionControl 是否激活
    var missioncontrolActiveCache = false
    var missioncontrolLastDetectTime = 0.0
    private func isMissioncontrolActive() -> Bool {
        // 如果距离上次检测时间大于 1s, 则重新检测一遍, 否则直接返回上次的结果
        let nowTime = NSDate().timeIntervalSince1970
        if nowTime - missioncontrolLastDetectTime > 1.0 {
            let windowInfoList = CGWindowListCopyWindowInfo(CGWindowListOption.optionOnScreenOnly, CGWindowID(0)) as [AnyObject]?
            for windowInfo in windowInfoList! {
                let windowOwnerName = windowInfo[kCGWindowOwnerName]!
                if windowOwnerName != nil && windowOwnerName as! String == "Dock" {
                    if windowInfo[kCGWindowName]! == nil {
                        missioncontrolActiveCache = true
                        return true
                    }
                }
            }
            missioncontrolActiveCache = false
            missioncontrolLastDetectTime = nowTime
        }
        return missioncontrolActiveCache
    }
    
    // 从 exceptionalApplications 中取回符合传入的 bundleId 的 ExceptionalApplication 对象
    func applicationInExceptionalApplications(bundleId: String?) -> ExceptionalApplication? {
        if let targetBundleId = bundleId {
            return Options.shared.general.applications.get(from: targetBundleId)
        }
        return nil
    }

    // 获取应用
    // 基础参数
    func isEnableSmoothOn(application: ExceptionalApplication?, targetBundleId: String?, flag: Bool) -> Bool {
        if Options.shared.scrollBasic.smooth && !flag {
            // 针对 Launchpad 特殊处理, 不论是否在列表内均禁用平滑
            if isLaunchpadActive(with: targetBundleId) {
                return false
            }
            if let target = application {
                return target.scrollBasic.smooth
            } else {
                return !Options.shared.general.whitelist
            }
        } else {
            return false
        }
    }
    func isEnableReverseOn(application: ExceptionalApplication?, targetBundleId: String?) -> Bool {
        if Options.shared.scrollBasic.reverse {
            // 针对 Launchpad 特殊处理, 允许用户自行判断是否翻转
            if isLaunchpadActive(with: targetBundleId) {
                if let launchpad = Options.shared.general.applications.get(from: "com.apple.launchpad.launcher") {
                    return launchpad.scrollBasic.reverse
                }
            }
            if let target = application {
                return target.scrollBasic.reverse
            } else {
                return !Options.shared.general.whitelist
            }
        } else {
            return false
        }
    }
    // 高级参数
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
    func optionsStepOn(application: ExceptionalApplication?) -> Double {
        if let targetApplication = application {
            return targetApplication.inherit ? Options.shared.scrollAdvanced.step : targetApplication.scrollAdvanced.step
        } else {
            return Options.shared.scrollAdvanced.step
        }
    }
    func optionsSpeedOn(application: ExceptionalApplication?) -> Double {
        if let targetApplication = application {
            return targetApplication.inherit ? Options.shared.scrollAdvanced.speed : targetApplication.scrollAdvanced.speed
        } else {
            return Options.shared.scrollAdvanced.speed
        }
    }
    func optionsDurationTransitionOn(application: ExceptionalApplication?) -> Double {
        if let targetApplication = application {
            return targetApplication.inherit ? Options.shared.scrollAdvanced.durationTransition : targetApplication.scrollAdvanced.durationTransition
        } else {
            return Options.shared.scrollAdvanced.durationTransition
        }
    }
}
