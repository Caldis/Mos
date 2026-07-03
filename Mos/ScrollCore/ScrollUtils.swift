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
    private init() { NSLog("Module initialized: ScrollUtils") }  // 缓存字段依赖单例不变量, 禁止二次实例化
    private let syntheticSmoothEventMarker: Int64 = 0x4D4F53534D4F4F54
    // Chrome 需要显式 TrackingEnd 收尾事件 (ScrollPoster.stop 的特判依赖此判定)
    private static let chromeBundleID = "com.google.Chrome"
    
    func markSyntheticSmoothEvent(_ event: CGEvent) {
        event.setIntegerValueField(.eventSourceUserData, value: syntheticSmoothEventMarker)
    }

    func isSyntheticSmoothEvent(_ event: CGEvent) -> Bool {
        return event.getIntegerValueField(.eventSourceUserData) == syntheticSmoothEventMarker
    }
    
    // 从 CGEvent 中携带的 PID 获取应用信息
    // 缓存字段无锁, 主线程 only; CVDisplayLink 线程需要的结果 (如 Chrome 判定) 由 ScrollPoster 在 update 时捕获进快照
    private var lastEventTargetPID: pid_t = 1  // 事件的目标进程 PID (先前)
    private var currEventTargetPID: pid_t = 1  // 事件的目标进程 PID (当前)
    private var cachedRunningApplication: NSRunningApplication?
    // 路径随 PID 缓存一并翻新: 避免热路径每个滚动事件做两次 URL→String 转换分配
    private var cachedBundlePath: String?
    private var cachedExecutablePath: String?
    func getRunningApplication(from event: CGEvent) -> NSRunningApplication? {
        assertMainThread()
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
            cachedBundlePath = cachedRunningApplication?.bundleURL?.path
            cachedExecutablePath = cachedRunningApplication?.executableURL?.path
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
        if let targetBundleIdentifier = targetRunningApplication.bundleIdentifier, targetBundleIdentifier == ScrollUtils.chromeBundleID {
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
        // macOS 26+ LaunchPad 已无分页功能, 平滑滚动是预期行为, 无需特殊处理
        if #available(macOS 26.0, *) {
            return false
        }
        // 10.15 - 26 以下判断是否为 Dock (LaunchPad 依附于 Dock 进程)
        // FIXME: 当 Dock 的目录设置为 "叠放" 时, 应用对 Dock 的目录预览无法平滑, 且发送平滑后的滚动事件无法被识别, 需要找别的方式
        if #available(OSX 10.15, *) {
            // 10.15+ 无录屏权限读不到 kCGWindowName, 窗口扫描无效, 只依赖 Dock 进程判断
            launchpadActiveCache = validRunningApplication.executableURL?.path == "/System/Library/CoreServices/Dock.app/Contents/MacOS/Dock"
            return launchpadActiveCache
        }
        // 10.15 以下根据 windowList 判断; 距离上次检测大于 1s 才重新检测, 否则直接返回上次的结果
        let nowTime = NSDate().timeIntervalSince1970
        if nowTime - launchpadLastDetectTime > 1.0 {
            launchpadLastDetectTime = nowTime
            // CGWindowListCopyWindowInfo 在锁屏等场景可能返回 nil, 此时保留上次结果
            if let windowInfoList = CGWindowListCopyWindowInfo(CGWindowListOption.optionOnScreenOnly, CGWindowID(0)) as? [[String: Any]] {
                launchpadActiveCache = windowInfoList.contains { ($0[kCGWindowName as String] as? String) == "LPSpringboard" }
            }
        }
        return launchpadActiveCache
    }

    // 从 Applications 中取回符合传入的 key 的 Application 对象
    // Key 在 applications 初始化时指定于 Application 中
    func getTargetApplication(from runningApplication: NSRunningApplication?) -> Application? {
        // 热路径传入的正是 getRunningApplication 缓存的对象, 直接复用缓存路径;
        // 其他调用方 (偏好设置/前台应用查询) 传入不同对象时回退实时计算
        let bundlePath: String?
        let executablePath: String?
        if runningApplication != nil && runningApplication === cachedRunningApplication {
            bundlePath = cachedBundlePath
            executablePath = cachedExecutablePath
        } else {
            bundlePath = runningApplication?.bundleURL?.path
            executablePath = runningApplication?.executableURL?.path
        }
        if let applicationByBundlePath = Options.shared.application.applications.get(by: bundlePath) {
            return applicationByBundlePath
        }
        if let applicationByExecutablePath = Options.shared.application.applications.get(by: executablePath) {
            return applicationByExecutablePath
        }
        return nil
    }

    // MARK: - 远程桌面事件检测
    // 远程桌面事件检测缓存
    private var lastSourcePID: pid_t = 0
    private var lastSourceIsRemoteControl: Bool = false

    /// 检测事件来源是否为远程桌面应用
    func isFromRemoteApplication(_ event: CGEvent) -> Bool {
        let sourcePID = pid_t(event.getIntegerValueField(.eventSourceUnixProcessID))
        if sourcePID == 0 { return false }

        if sourcePID != lastSourcePID {
            lastSourcePID = sourcePID
            lastSourceIsRemoteControl = false

            if let app = NSRunningApplication(processIdentifier: sourcePID) {
                // 检查可执行文件路径（系统守护进程）
                if let path = app.executableURL?.path {
                    for keyword in REMOTE_CONTROL_APPLICATION.executableKeywords {
                        if path.contains(keyword) {
                            lastSourceIsRemoteControl = true
                            break
                        }
                    }
                }
                // 检查 Bundle Identifier（第三方应用）
                if !lastSourceIsRemoteControl, let bundleId = app.bundleIdentifier {
                    lastSourceIsRemoteControl = REMOTE_CONTROL_APPLICATION.bundleIdentifiers.contains(bundleId)
                }
            }
        }
        return lastSourceIsRemoteControl
    }

    /// 检测事件是否来自已被平滑的远程源
    /// 返回 true 表示应跳过平滑处理
    func isRemoteSmoothedEvent(_ event: CGEvent) -> Bool {
        if !isFromRemoteApplication(event) { return false }
        // 检查 isContinuous 字段判断是否为连续的
        let isContinuous = event.getDoubleValueField(.scrollWheelEventIsContinuous)
        return isContinuous == 1.0  // 1.0 表示主控端已平滑
    }

    // MARK: - 滚动参数: 热键
    // 返回 ScrollHotkey? 供 ScrollCore 使用
    func optionsDashKey(application: Application?) -> ScrollHotkey? {
        if let targetApplication = application {
            return targetApplication.inherit ? Options.shared.scroll.dash : targetApplication.scroll.dash
        } else {
            return Options.shared.scroll.dash
        }
    }
    func optionsToggleKey(application: Application?) -> ScrollHotkey? {
        if let targetApplication = application {
            return targetApplication.inherit ? Options.shared.scroll.toggle : targetApplication.scroll.toggle
        } else {
            return Options.shared.scroll.toggle
        }
    }
    func optionsBlockKey(application: Application?) -> ScrollHotkey? {
        if let targetApplication = application {
            return targetApplication.inherit ? Options.shared.scroll.block : targetApplication.scroll.block
        } else {
            return Options.shared.scroll.block
        }
    }
}
