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
    private let syntheticSmoothEventMarker: Int64 = 0x4D4F53534D4F4F54
    
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
    
    func markSyntheticSmoothEvent(_ event: CGEvent) {
        event.setIntegerValueField(.eventSourceUserData, value: syntheticSmoothEventMarker)
    }

    func isSyntheticSmoothEvent(_ event: CGEvent) -> Bool {
        return event.getIntegerValueField(.eventSourceUserData) == syntheticSmoothEventMarker
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
        // macOS 26+ LaunchPad 已无分页功能, 平滑滚动是预期行为, 无需特殊处理
        if #available(macOS 26.0, *) {
            return false
        }
        // 10.15 - 26 以下判断是否为 Dock (LaunchPad 依附于 Dock 进程)
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

    // MARK: - 远程桌面事件检测
    // 远程桌面事件检测缓存
    private var lastSourcePID: pid_t = 0
    private var lastSourceIsRemoteControl: Bool = false
    private var lastSourceNeedsRawScrollPassthrough: Bool = false

    /// 检测事件来源是否为远程桌面应用
    func isFromRemoteApplication(_ event: CGEvent) -> Bool {
        refreshRemoteSourceCacheIfNeeded(event)
        return lastSourceIsRemoteControl
    }

    /// ToDesk 等远程控制应用对 Mos 合成的连续滚轮事件兼容性差，需禁用平滑但保留方向翻转等原始事件处理。
    func shouldDisableSmoothForRemoteControl(_ event: CGEvent, targetRunningApplication: NSRunningApplication?) -> Bool {
        if needsRawScrollPassthrough(from: targetRunningApplication) {
            return true
        }
        refreshRemoteSourceCacheIfNeeded(event)
        return lastSourceNeedsRawScrollPassthrough
    }

    /// 检测事件是否来自已被平滑的远程源
    /// 返回 true 表示应跳过平滑处理
    func isRemoteSmoothedEvent(_ event: CGEvent) -> Bool {
        if !isFromRemoteApplication(event) { return false }
        // 检查 isContinuous 字段判断是否为连续的
        let isContinuous = event.getDoubleValueField(.scrollWheelEventIsContinuous)
        return isContinuous == 1.0  // 1.0 表示主控端已平滑
    }

    func isKnownRemoteControlApplication(executablePath: String?, bundleIdentifier: String?) -> Bool {
        if containsAnyKeyword(in: executablePath, keywords: REMOTE_CONTROL_APPLICATION.executableKeywords) {
            return true
        }
        if let bundleIdentifier = bundleIdentifier,
           REMOTE_CONTROL_APPLICATION.bundleIdentifiers.contains(bundleIdentifier) {
            return true
        }
        return containsAnyKeyword(
            in: bundleIdentifier,
            keywords: REMOTE_CONTROL_APPLICATION.bundleIdentifierKeywords
        )
    }

    func needsRawScrollPassthrough(executablePath: String?, bundleIdentifier: String?) -> Bool {
        return containsAnyKeyword(
            in: executablePath,
            keywords: REMOTE_CONTROL_APPLICATION.rawScrollPassthroughExecutableKeywords
        ) || containsAnyKeyword(
            in: bundleIdentifier,
            keywords: REMOTE_CONTROL_APPLICATION.rawScrollPassthroughBundleIdentifierKeywords
        )
    }

    private func needsRawScrollPassthrough(from runningApplication: NSRunningApplication?) -> Bool {
        guard let runningApplication = runningApplication else { return false }
        return needsRawScrollPassthrough(
            executablePath: runningApplication.executableURL?.path,
            bundleIdentifier: runningApplication.bundleIdentifier
        ) || needsRawScrollPassthrough(
            executablePath: runningApplication.bundleURL?.path,
            bundleIdentifier: runningApplication.bundleIdentifier
        )
    }

    private func refreshRemoteSourceCacheIfNeeded(_ event: CGEvent) {
        let sourcePID = pid_t(event.getIntegerValueField(.eventSourceUnixProcessID))
        if sourcePID == 0 {
            lastSourcePID = 0
            lastSourceIsRemoteControl = false
            lastSourceNeedsRawScrollPassthrough = false
            return
        }

        if sourcePID != lastSourcePID {
            lastSourcePID = sourcePID
            lastSourceIsRemoteControl = false
            lastSourceNeedsRawScrollPassthrough = false

            guard let app = NSRunningApplication(processIdentifier: sourcePID) else { return }
            let executablePath = app.executableURL?.path
            let bundlePath = app.bundleURL?.path
            let bundleIdentifier = app.bundleIdentifier

            lastSourceIsRemoteControl = isKnownRemoteControlApplication(
                executablePath: executablePath,
                bundleIdentifier: bundleIdentifier
            ) || isKnownRemoteControlApplication(
                executablePath: bundlePath,
                bundleIdentifier: bundleIdentifier
            )
            lastSourceNeedsRawScrollPassthrough = needsRawScrollPassthrough(
                executablePath: executablePath,
                bundleIdentifier: bundleIdentifier
            ) || needsRawScrollPassthrough(
                executablePath: bundlePath,
                bundleIdentifier: bundleIdentifier
            )
        }
    }

    private func containsAnyKeyword(in value: String?, keywords: [String]) -> Bool {
        guard let lowercasedValue = value?.lowercased() else { return false }
        for keyword in keywords {
            if lowercasedValue.contains(keyword.lowercased()) {
                return true
            }
        }
        return false
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
