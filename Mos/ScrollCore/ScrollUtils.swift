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
    private var currEventTargetPID:pid_t = 1     // 事件的目标进程 PID (当前)
    private var currEventTargetBID:String!
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
    func getCurrentEventTargetBundleId(from event: CGEvent) -> String {
        // 保存上次 PID
        lastEventTargetPID = currEventTargetPID
        // 更新当前 PID
        currEventTargetPID = pid_t(event.getIntegerValueField(.eventTargetUnixProcessID))
        // 如果目标 PID 变化, 则重新获取一次窗口 BID (更新 BID 消耗较高)
        if lastEventTargetPID != currEventTargetPID {
            if let bundleId = getApplicationBundleIdFrom(pid: currEventTargetPID) {
                currEventTargetBID = bundleId
                return currEventTargetBID
            }
        }
        return currEventTargetBID
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
    private func launchpadIsActive() -> Bool {
        // 如果距离上次检测时间大于500ms, 则重新检测一遍, 否则直接返回上次的结果
        let nowTime = NSDate().timeIntervalSince1970
        if nowTime - self.missioncontrolLastDetectTime > 0.5 {
            self.missioncontrolLastDetectTime = nowTime
            let windowInfoList = CGWindowListCopyWindowInfo(CGWindowListOption.optionOnScreenOnly, CGWindowID(0)) as [AnyObject]?
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
    private func missioncontrolIsActive() -> Bool {
        // 如果距离上次检测时间大于500ms, 则重新检测一遍, 否则直接返回上次的结果
        let nowTime = NSDate().timeIntervalSince1970
        if nowTime - missioncontrolLastDetectTime > 0.5 {
            missioncontrolLastDetectTime = nowTime
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
            return false
        } else {
            missioncontrolLastDetectTime = nowTime
            return missioncontrolActiveCache
        }
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
        if Options.shared.basic.smooth {
            // 针对 Launchpad 特殊处理, 不论是否在列表内均禁用平滑
            if launchpadIsActive() {
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
            if launchpadIsActive() {
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
