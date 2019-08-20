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
    
    // 从 CGEvent 中携带的 PID 获取目标窗口的 BundleId
    // 已知问题: 获取到的始终为主激活窗口
    // 已知问题: 如果鼠标滚轮事件由 cghidEventTap 层截取, 则获取到的目标窗口 PID 为当前的激活窗口, 而不是悬停窗口
    private var lastEventTargetPID:pid_t = 1     // 目标进程 PID (先前)
    private var currEventTargetPID:pid_t = 1     // 事件的目标进程 PID (当前)
    private var currEventTargetBID:String?       // 事件的目标进程 BID (当前)
    func getCurrentEventTargetBundleId(from event: CGEvent) -> String? {
        // 保存上次 PID
        lastEventTargetPID = currEventTargetPID
        // 更新当前 PID
        currEventTargetPID = pid_t(event.getIntegerValueField(.eventTargetUnixProcessID))
        // 使用 PID 获取 BID
        // 如果目标 PID 变化, 则重新获取一次窗口 BID (查找 BID 效率较低)
        if lastEventTargetPID != currEventTargetPID {
            if let bundleId = Utils.getApplicationBundleIdFrom(pid: currEventTargetPID) {
                currEventTargetBID = bundleId
                return currEventTargetBID
            }
        }
        return currEventTargetBID
    }
    func getCurrentEventTargetBundleIdFromCache() -> String? {
        return currEventTargetBID
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
        // 如果距离上次检测时间大于 1000ms, 且鼠标移动大于阈值, 或缓存值为空, 则重新检测一遍, 否则直接返回上次的结果
        let nowTime = NSDate().timeIntervalSince1970
        if nowTime-self.bundleIdDetectTime>1.0 && !mouseStayStill(location, mouseLocationCache) || bundleIdCache==nil {
            // 获取坐标下的元素信息
            var element: AXUIElement?
            let pointAsCGPoint = carbonScreenPointFromCocoaScreenPoint(mouseLocation: location)
            let copyElementRes = AXUIElementCopyElementAtPosition(systemWideElement, Float(pointAsCGPoint.x), Float(pointAsCGPoint.y), &element )
            // 更新缓存值
            mouseLocationCache = location
            bundleIdDetectTime = nowTime
            // 先尝试从鼠标坐标查找, 如果无法找到, 则使用事件携带的信息查找
            if copyElementRes == .success {
                let pid = getPidFrom(element: element!)
                bundleIdCache = Utils.getApplicationBundleIdFrom(pid: pid)
            } else {
                bundleIdCache = getCurrentEventTargetBundleId(from: event)
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
    private func isLaunchpadActive() -> Bool {
        // 如果距离上次检测时间大于 1000ms, 则重新检测一遍, 否则直接返回上次的结果
        let nowTime = NSDate().timeIntervalSince1970
        if nowTime - launchpadLastDetectTime > 1.0 {
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

    // 判断 MissionControl 是否激活
    var missioncontrolActiveCache = false
    var missioncontrolLastDetectTime = 0.0
    private func isMissioncontrolActive() -> Bool {
        // 如果距离上次检测时间大于 1000ms, 则重新检测一遍, 否则直接返回上次的结果
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
            return Options.shared.global.applications.get(from: targetBundleId)
        }
        return nil
    }

    // 获取应用
    // 基础参数
    func isEnableSmoothOn(application: ExceptionalApplication?) -> Bool {
        if Options.shared.scroll.smooth && !ScrollCore.shared.blockSmooth {
            // 针对 Launchpad 特殊处理, 不论是否在列表内均禁用平滑
            if isLaunchpadActive() {
                return false
            }
            if let target = application {
                return target.scroll.smooth
            } else {
                return !Options.shared.global.whitelist
            }
        } else {
            return false
        }
    }
    func isEnableReverseOn(application: ExceptionalApplication?) -> Bool {
        if Options.shared.scroll.reverse {
            // 针对 Launchpad 特殊处理
            if isLaunchpadActive() {
                if let launchpad = Options.shared.global.applications.get(from: "com.apple.launchpad.launcher") {
                    return launchpad.scroll.reverse
                }
            }
            if let target = application {
                return target.scroll.reverse
            } else {
                return !Options.shared.global.whitelist
            }
        } else {
            return false
        }
    }
    // 高级参数
    func optionsToggleOn(application: ExceptionalApplication?) -> Int {
        if let targetApplication = application {
            return targetApplication.followGlobal ? Options.shared.scroll.toggle : targetApplication.scroll.toggle
        } else {
            return Options.shared.scroll.toggle
        }
    }
    func optionsBlockOn(application: ExceptionalApplication?) -> Int {
        if let targetApplication = application {
            return targetApplication.followGlobal ? Options.shared.scroll.block : targetApplication.scroll.block
        } else {
            return Options.shared.scroll.block
        }
    }
    func optionsStepOn(application: ExceptionalApplication?) -> Double {
        if let targetApplication = application {
            return targetApplication.followGlobal ? Options.shared.scroll.step : targetApplication.scroll.step
        } else {
            return Options.shared.scroll.step
        }
    }
    func optionsSpeedOn(application: ExceptionalApplication?) -> Double {
        if let targetApplication = application {
            return targetApplication.followGlobal ? Options.shared.scroll.speed : targetApplication.scroll.speed
        } else {
            return Options.shared.scroll.speed
        }
    }
    func optionsDurationTransitionOn(application: ExceptionalApplication?) -> Double {
        if let targetApplication = application {
            return targetApplication.followGlobal ? Options.shared.scroll.durationTransition : targetApplication.scroll.durationTransition
        } else {
            return Options.shared.scroll.durationTransition
        }
    }
}
