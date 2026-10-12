//
//  IPhoneMirroringAdapter.swift
//  Mos
//  iPhone 镜像 (com.apple.ScreenContinuity) 的滚动适配器
//
//  镜像在 sender 非零时读取 175-178, 并按 sender 查找设备属性; 只有 sender 指向触控板类设备时,
//  phased 事件才能得到连续滚动。镜像不跟随 Mac 侧惯性事件, iOS 按 Ended 时的手势速度自行滑行。
//  实验记录见 docs/plans/2026-10-12-iphone-mirroring-scroll.md
//

import Cocoa
import os

final class IPhoneMirroringAdapter: ScrollAdapter {

    static let descriptor = ScrollAdapterDescriptor(
        identifier: "iphone-mirroring",
        bundleIdentifiers: ["com.apple.ScreenContinuity"],
        minimumSystemVersion: OperatingSystemVersion(majorVersion: 15, minorVersion: 0, patchVersion: 0)
    )

    var descriptor: ScrollAdapterDescriptor { Self.descriptor }

    private let identity = VirtualTrackpadIdentity.shared
    private lazy var sink = PhasedTrackpadSink(identity: identity) { [weak self] location in
        self?.sharedVisibility.contains(location) ?? false
    }
    private var application: NSRunningApplication?
    private var windowID: CGWindowID?
    /// 主线程使用的窗口可见区域缓存
    private var visibility = WindowVisibility() {
        didSet {
            os_unfair_lock_lock(&visibilityLock)
            _sharedVisibility = visibility
            os_unfair_lock_unlock(&visibilityLock)
        }
    }
    /// 供投递队列读取的副本
    private var visibilityLock = os_unfair_lock_s()
    private var _sharedVisibility = WindowVisibility()
    private var sharedVisibility: WindowVisibility {
        os_unfair_lock_lock(&visibilityLock)
        defer { os_unfair_lock_unlock(&visibilityLock) }
        return _sharedVisibility
    }
    private var refreshCount = 0
    /// 镜像不在前台时每隔若干次刷新才查询一次窗口; 找不到窗口时同样降频全量扫描
    private let backgroundStride = 4
    private let fullScanStride = 8

    func activate(_ application: NSRunningApplication) {
        self.application = application
        refreshCount = 0
        identity.retain()
        refresh()
    }

    func deactivate() {
        application = nil
        windowID = nil
        visibility = WindowVisibility()
        identity.release()
    }

    func refresh() {
        guard let application = application else { return }
        defer { refreshCount += 1 }
        if let id = windowID {
            let isFrontmost = application.isActive
            guard isFrontmost || refreshCount % backgroundStride == 0 else { return }
            if let found = Self.visibility(of: id, owner: application.processIdentifier, frontmost: isFrontmost) {
                visibility = found
                return
            }
            windowID = nil
            visibility = WindowVisibility()
        }
        guard refreshCount % fullScanStride == 0,
              let id = Self.mainWindowID(pid: application.processIdentifier) else { return }
        windowID = id
        visibility = Self.visibility(of: id, owner: application.processIdentifier, frontmost: application.isActive) ?? WindowVisibility()
    }

    func route(at location: CGPoint) -> ScrollAdapterRoute? {
        guard let application = application, visibility.contains(location), sink.isReady else {
            return nil
        }
        return ScrollAdapterRoute(application: application, sink: sink)
    }

    // MARK: - 窗口查询

    /// 取得镜像窗口的可见区域; 窗口关闭或离屏时返回 nil。
    /// 镜像在前台时其他应用的普通窗口不会位于其上方, 只查询窗口本身 (约 0.2 ms);
    /// 在后台时一并查询上方窗口 (约 0.7 ms, 本机 70 个窗口), 刷新频率同时降为 1 秒
    static func visibility(of windowID: CGWindowID, owner pid: pid_t, frontmost: Bool) -> WindowVisibility? {
        let options: CGWindowListOption = frontmost ? .optionIncludingWindow : [.optionOnScreenAboveWindow, .optionIncludingWindow]
        guard let windows = CGWindowListCopyWindowInfo(options, windowID) as? [[String: Any]] else {
            return nil
        }
        var occluders: [CGRect] = []
        for window in windows {
            guard let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds) else { continue }
            if (window[kCGWindowNumber as String] as? CGWindowID) == windowID {
                guard (window[kCGWindowIsOnscreen as String] as? Bool) == true else { return nil }
                return WindowVisibility(frame: rect, occluders: occluders)
            }
            // 镜像自身的弹出窗口不算遮挡; 程序坞与菜单栏等系统层 (20 及以上) 不覆盖窗口内容区
            let layer = window[kCGWindowLayer as String] as? Int ?? 0
            let owner = window[kCGWindowOwnerPID as String] as? pid_t
            let alpha = window[kCGWindowAlpha as String] as? Double ?? 1
            if owner != pid, (0..<20).contains(layer), alpha > 0, rect.width > 1, rect.height > 1 {
                occluders.append(rect)
            }
        }
        return nil
    }

    /// 镜像进程在普通窗口层的第一个可见窗口
    private static func mainWindowID(pid: pid_t) -> CGWindowID? {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        for window in windows {
            guard (window[kCGWindowOwnerPID as String] as? pid_t) == pid,
                  (window[kCGWindowLayer as String] as? Int) == 0,
                  let id = window[kCGWindowNumber as String] as? CGWindowID,
                  let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds),
                  rect.width > 100 else {
                continue
            }
            return id
        }
        return nil
    }
}

/// 目标窗口的可见区域: 窗口矩形减去位于其上方的其他应用窗口
struct WindowVisibility {
    var frame: CGRect?
    var occluders: [CGRect] = []

    func contains(_ point: CGPoint) -> Bool {
        guard let frame = frame, frame.contains(point) else { return false }
        return !occluders.contains { $0.contains(point) }
    }
}
