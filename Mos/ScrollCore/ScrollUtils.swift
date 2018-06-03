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
    init() { print("Class 'ScrollUtils' is a singleton, use the 'ScrollUtils.shared' to access it.") }
    
    // 从 PID 获取进程名称
    private func getApplicationBundleIdFrom(pid: pid_t) -> String? {
        if let runningApps = NSRunningApplication.init(processIdentifier: pid) {
            return runningApps.bundleIdentifier
        } else {
            return nil
        }
    }
    private func oldGetApplicationBundleIdFrom(pid: pid_t) -> String? {
        // 更新列表
        let runningApps = NSWorkspace.shared.runningApplications
        if let matchApp = runningApps.filter({$0.processIdentifier == pid}).first {
            // 如果找到 bundleId 则返回, 不然则判定为子进程, 通过查找其父进程Id, 递归查找其父进程的bundleId
            if let bundleId = matchApp.bundleIdentifier {
                return bundleId as String?
            } else {
                let ppid = ProcessUtils.getParentPid(from: matchApp.processIdentifier)
                return ppid==1 ? nil : getApplicationBundleIdFrom(pid: ppid)
            }
        } else {
            return nil
        }
    }
    
    // 从 CGEvent 中携带的 PID 获取目标窗口的 BundleId
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
            if let bundleId = getApplicationBundleIdFrom(pid: currEventTargetPID) {
                currEventTargetBID = bundleId
                return currEventTargetBID
            }
        }
        return currEventTargetBID
    }
    func getCurrentEventTargetBundleIdFromCache() -> String? {
        return currEventTargetBID
    }
    
    // 从指针悬停位置获取窗口 BundleId
    // 原理: 获取指针坐标下的 AXUIElement 信息, 从而获取 BundleID
    // 来自: https://stackoverflow.com/questions/27584963/get-window-values-under-mouse
    // 已知问题: 外置屏幕获取到的 PID 有大约 30PX 在垂直方向上的偏移, 但内置屏幕无此问题
    // 已知问题: 效率低下，影响首次滚动性能
    let systemWideElement = AXUIElementCreateSystemWide()
    var bundleIdCache:String? = nil
    var bundleIdDetectTime = 0.0
    var mouseLocationCache = NSPoint(x: 0.0, y: 0.0)
    func getBundleIdFromMouseLocation() -> String? {
        let location = NSEvent.mouseLocation
        // 如果距离上次检测时间大于 1000ms, 且鼠标移动大于阈值, 则重新检测一遍, 否则直接返回上次的结果
        let nowTime = NSDate().timeIntervalSince1970
        if nowTime-self.bundleIdDetectTime>1.0 && (!mouseStayStill(location, mouseLocationCache) || bundleIdCache==nil) {
            let pointAsCGPoint = carbonScreenPointFromCocoaScreenPoint(mouseLocation: location)
            var element: AXUIElement?
            if AXUIElementCopyElementAtPosition(systemWideElement, Float(pointAsCGPoint.x), Float(pointAsCGPoint.y), &element ) == .success {
                let pid = getPidFrom(element: element!)
                bundleIdCache = getApplicationBundleIdFrom(pid: pid)
            }
            mouseLocationCache = location
            bundleIdDetectTime = nowTime
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
            return Options.shared.exception.applicationsDict[targetBundleId] ?? nil
        }
        return nil
    }
    
    // 判断 ExceptionalApplication 是否需要平滑滚动
    private func applicationNeedSmooth(application: ExceptionalApplication) -> Bool {
        return application.smooth
    }
    // 判断 ExceptionalApplication 是否需要翻转
    private func applicationNeedReverse(application: ExceptionalApplication) -> Bool {
        return application.reverse
    }

    // 是否启用平滑
    func enableSmooth(application: ExceptionalApplication?) -> Bool {
        if Options.shared.basic.smooth && !ScrollCore.shared.blockSmooth {
            // 针对 Launchpad 特殊处理, 不论是否在列表内均禁用平滑
            if isLaunchpadActive() {
                return false
            }
            if let target = application {
                return applicationNeedSmooth(application: target)
            } else {
                return !Options.shared.exception.whitelist
            }
        } else {
            return false
        }
    }
    // 是否启用翻转
    func enableReverse(application: ExceptionalApplication?) -> Bool {
        if Options.shared.basic.reverse {
            // 例外应用列表(Dict)
            let applicationsDict = Options.shared.exception.applicationsDict
            // 针对 Launchpad 特殊处理
            if isLaunchpadActive() {
                if let launchpad = applicationsDict["com.apple.launchpad.launcher"] {
                    return launchpad.reverse
                }
            }
            if let target = application {
                return applicationNeedReverse(application: target)
            } else {
                return !Options.shared.exception.whitelist
            }
        } else {
            return false
        }
    }
    
}
