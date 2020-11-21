//
//  Archieve.swift
//  Mos
//
//  Created by Caldis on 2020/11/21.
//  Copyright © 2020 Caldis. All rights reserved.
//

import Cocoa

class Archieve {
    /*
     * 通知
     */
    class func sendNotificationMessage(_ title:String, _ subTitle:String) {
        // 定义通知
        let notification = NSUserNotification()
        notification.title = title
        notification.subtitle = subTitle
        // 发送通知
        NSUserNotificationCenter.default.deliver(notification)
    }
    
    /*
     * 坐标获取
     */
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
                bundleIdCache = Archieve.getApplicationBundleIdFrom(pid: pid)
            } else {
                // TODO
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
    
    /*
     * 从 PID 获取对应数据
     */
    class func getApplicationBundleIdFrom(pid: pid_t) -> String? {
        if let runningApps = NSRunningApplication.init(processIdentifier: pid) {
            return runningApps.bundleIdentifier
        } else {
            return nil
        }
    }
    
    /*
     * 判断 MissionControl 是否激活
     */
    var missioncontrolActiveCache = false
    var missioncontrolLastDetectTime = 0.0
    private func getMissioncontrolActivity() -> Bool {
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
}

