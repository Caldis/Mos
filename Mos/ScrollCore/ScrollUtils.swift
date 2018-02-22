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
    
    // 获取事件目标 BundleId
    private var lastEventTargetPID:pid_t = 1     // 目标进程 PID (先前)
    private var eventTargetPID:pid_t = 1         // 事件的目标进程 PID (当前)
    private var eventTargetBID:String!
    // 事件的目标进程 BID (当前)
    // 从Pid获取进程名称
    private func getApplicationBundleIdFrom(pid: pid_t) -> String? {
        // 更新列表
        let runningApps = NSWorkspace.shared.runningApplications
        if let matchApp = runningApps.filter({$0.processIdentifier == pid}).first {
            // 如果找到bundleId则返回, 不然则判定为子进程, 通过查找其父进程Id, 递归查找其父进程的bundleId
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
    // 获取当前事件目标 BundleId
    func getCurrentEventTargetBundleId(from event: CGEvent) -> String? {
        // 获取光标当前窗口信息, 用于在某些窗口中禁用, 更新每次的 PID
        lastEventTargetPID = eventTargetPID
        eventTargetPID = pid_t(event.getIntegerValueField(.eventTargetUnixProcessID))
        // 如果目标PID有变化, 则重新获取一次窗口名字, 更新到 eventTargetName
        if lastEventTargetPID != eventTargetPID {
            if let bundleId = getApplicationBundleIdFrom(pid: eventTargetPID) {
                eventTargetBID = bundleId
                return eventTargetBID
            }
        }
        return nil
    }
    
    // 判断指定的轴数据是否存在, 作为处理判断依据
    func axisDataIsExistIn(_ scrollFix: Int64, _ scrollPt: Double, _ scrollFixPt: Double) -> (value: Double, isFixed: Bool)? {
        if scrollPt != 0.0 {
            return (value: scrollPt, isFixed: false)
        }
        if scrollFixPt != 0.0 {
            return (value: scrollFixPt, isFixed: true)
        }
        if scrollFix != 0 {
            return (value: Double(scrollFix), isFixed: true)
        }
        return nil
    }
    
    // 判断事件类型
    func isTouchPad(of event: CGEvent) -> Bool {
        // MomentumPhase 或 ScrollPhase任一不为零, 则为触控板
        if (event.getDoubleValueField(.scrollWheelEventMomentumPhase) != 0.0) || (event.getDoubleValueField(.scrollWheelEventScrollPhase) != 0.0) {
            return true
        }
        // 累计加速度
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
    func launchpadIsActive() -> Bool {
        // 如果距离上次检测时间大于500ms, 则重新检测一遍, 否则直接返回上次的结果
        let nowTime = NSDate().timeIntervalSince1970
        if nowTime - self.missioncontrolLastDetectTime > 0.5 {
            self.missioncontrolLastDetectTime = nowTime
            let windowInfoList = CGWindowListCopyWindowInfo(CGWindowListOption.optionOnScreenOnly, CGWindowID(0)) as [AnyObject]!
            for windowInfo in windowInfoList! {
                let windowName = windowInfo[kCGWindowName]!
                if windowName != nil && windowName as! String == "LPSpringboard" {
                    launchpadActiveCache = true
                    return true
                }
            }
            launchpadActiveCache = false
            return false
        } else {
            self.missioncontrolLastDetectTime = nowTime
            return self.launchpadActiveCache
        }
    }
    
    // 判断 MissionControl 是否激活
    var missioncontrolActiveCache = false
    var missioncontrolLastDetectTime = 0.0
    func missioncontrolIsActive() -> Bool {
        // 如果距离上次检测时间大于500ms, 则重新检测一遍, 否则直接返回上次的结果
        let nowTime = NSDate().timeIntervalSince1970
        if nowTime - missioncontrolLastDetectTime > 0.5 {
            missioncontrolLastDetectTime = nowTime
            let windowInfoList = CGWindowListCopyWindowInfo(CGWindowListOption.optionOnScreenOnly, CGWindowID(0)) as [AnyObject]!
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
            return false
        } else {
            missioncontrolLastDetectTime = nowTime
            return missioncontrolActiveCache
        }
    }
    
    // 从 exceptionalApplications 中取回符合传入的 bundleId 的 ExceptionalApplication 对象
    func applicationInExceptionalApplications(bundleId: String?) -> ExceptionalApplication? {
        if let targetBundleId = bundleId {
            return Options.shared.current.exception.applicationsDict[targetBundleId] ?? nil
        }
        return nil
    }
    
    // 判断 ExceptionalApplication 是否需要平滑滚动
    func applicationNeedSmooth(application: ExceptionalApplication?) -> Bool {
        // 针对 Launchpad 和 MissionControl 特殊处理, 不论是否在列表内均禁用平滑
        if launchpadIsActive() || missioncontrolIsActive() {
            return false
        }
        // 一般 App
        if let target = application {
            return target.smooth
        }
        return false
    }

    // 判断 ExceptionalApplication 是否需要翻转滚动
    func applicationNeedReverse(application: ExceptionalApplication?) -> Bool {
        // 例外应用列表(Dict)
        let applicationsDict = Options.shared.current.exception.applicationsDict
        // 针对 Launchpad 和 MissionControl 特殊处理
        if launchpadIsActive() || missioncontrolIsActive() {
            if let launchpad = applicationsDict["com.apple.launchpad.launcher"] {
                return launchpad.reverse
            }
            if let missionControl = applicationsDict["com.apple.exposelauncher"] {
                return missionControl.reverse
            }
        }
        // 一般 App
        if let target = application {
            return target.reverse
        }
        return false
    }
    
    // 是否启用平滑
    func enableSmooth(application: ExceptionalApplication?) -> Bool {
        if Options.shared.current.basic.smooth {
            if Options.shared.current.exception.whitelist {
                if application != nil {
                    return applicationNeedSmooth(application: application)
                } else {
                    return false
                }
            } else {
                return true
            }
        } else {
            return false
        }
    }
    
    // 是否全局启用翻转
    func enableReverse(application: ExceptionalApplication?) -> Bool {
        if Options.shared.current.basic.reverse {
            if Options.shared.current.exception.whitelist {
                if application != nil {
                    return applicationNeedReverse(application: application)
                } else {
                    return false
                }
            } else {
                return true
            }
        } else {
            return false
        }
    }
    
}
