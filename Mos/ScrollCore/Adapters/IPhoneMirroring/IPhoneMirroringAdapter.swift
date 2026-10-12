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
        self?.sharedFrame?.contains(location) ?? false
    }
    private var application: NSRunningApplication?
    private var windowID: CGWindowID?
    /// 主窗口矩形 (全局坐标, 左上角原点, 与 CGEvent.location 一致)
    private var windowFrame: CGRect? {
        didSet {
            os_unfair_lock_lock(&frameLock)
            _sharedFrame = windowFrame
            os_unfair_lock_unlock(&frameLock)
            hitCache = nil
        }
    }
    /// 供投递队列读取的副本
    private var frameLock = os_unfair_lock_s()
    private var _sharedFrame: CGRect?
    private var sharedFrame: CGRect? {
        os_unfair_lock_lock(&frameLock)
        defer { os_unfair_lock_unlock(&frameLock) }
        return _sharedFrame
    }
    /// 主屏高度, 用于把全局坐标换算为 AppKit 屏幕坐标
    private var primaryScreenHeight: CGFloat = 0
    /// 最近一次最上层窗口判断; 同一位置在有效期内复用, 连续滚动时只有第一个事件需要查询
    private var hitCache: (location: CGPoint, time: CFTimeInterval, isTopmost: Bool)?
    private let hitCacheLifetime: CFTimeInterval = 0.05
    private var screenObserver: NSObjectProtocol?
    /// 找不到镜像窗口 (未打开或已关闭) 时, 每隔若干次刷新才做一次全量窗口扫描
    private var missedScans = 0
    private let fullScanStride = 4

    func activate(_ application: NSRunningApplication) {
        self.application = application
        missedScans = 0
        identity.retain()
        updatePrimaryScreenHeight()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.updatePrimaryScreenHeight()
            self?.refresh()
        }
        refresh()
    }

    func deactivate() {
        application = nil
        windowID = nil
        windowFrame = nil
        if let observer = screenObserver {
            NotificationCenter.default.removeObserver(observer)
            screenObserver = nil
        }
        identity.release()
    }

    private func updatePrimaryScreenHeight() {
        primaryScreenHeight = NSScreen.screens.first?.frame.height ?? 0
    }

    func refresh() {
        guard let application = application else { return }
        if let id = windowID {
            switch Self.state(of: id) {
            case .onscreen(let frame):
                windowFrame = frame
                return
            case .offscreen:
                // 最小化, 收进台前调度或位于其他桌面: 保留窗口编号, 继续只查询该窗口
                windowFrame = nil
                return
            case .gone:
                windowID = nil
                windowFrame = nil
                missedScans = 0
            }
        }
        defer { missedScans += 1 }
        guard missedScans % fullScanStride == 0,
              let found = Self.mainWindow(pid: application.processIdentifier) else { return }
        windowID = found.id
        windowFrame = found.frame
    }

    /// 先用窗口矩形粗筛; 位于矩形内时再判断该位置最上层的窗口是否为镜像, 被其他应用的窗口遮挡时放行
    func route(at location: CGPoint) -> ScrollAdapterRoute? {
        guard let application = application, let id = windowID,
              let frame = windowFrame, frame.contains(location),
              sink.isReady, isTopmost(id, at: location) else {
            return nil
        }
        return ScrollAdapterRoute(application: application, sink: sink)
    }

    private func isTopmost(_ id: CGWindowID, at location: CGPoint) -> Bool {
        let now = CFAbsoluteTimeGetCurrent()
        if let cache = hitCache, cache.location == location, now - cache.time < hitCacheLifetime {
            return cache.isTopmost
        }
        let point = Self.screenPoint(fromGlobal: location, primaryScreenHeight: primaryScreenHeight)
        let isTopmost = NSWindow.windowNumber(at: point, belowWindowWithWindowNumber: 0) == Int(id)
        hitCache = (location, now, isTopmost)
        return isTopmost
    }

    /// CGEvent 全局坐标 (主屏左上角为原点, y 向下) 换算为 AppKit 屏幕坐标 (主屏左下角为原点, y 向上)
    static func screenPoint(fromGlobal location: CGPoint, primaryScreenHeight: CGFloat) -> NSPoint {
        return NSPoint(x: location.x, y: primaryScreenHeight - location.y)
    }

    // MARK: - 窗口查询

    enum WindowState: Equatable {
        case onscreen(CGRect)
        case offscreen
        case gone
    }

    /// 只查询已知窗口 (约 0.2 ms)
    private static func state(of windowID: CGWindowID) -> WindowState {
        guard let info = (CGWindowListCopyWindowInfo(.optionIncludingWindow, windowID) as? [[String: Any]])?.first else {
            return .gone
        }
        guard (info[kCGWindowIsOnscreen as String] as? Bool) == true,
              let bounds = info[kCGWindowBounds as String] as? NSDictionary,
              let frame = CGRect(dictionaryRepresentation: bounds) else {
            return .offscreen
        }
        return .onscreen(frame)
    }

    /// 镜像进程在普通窗口层面积最大的屏上窗口。不按尺寸过滤: 收进台前调度时主窗口缩成约 25 x 82 的缩略图,
    /// 仍需识别出它的窗口编号, 之后只按编号查询; 缩略图位置的最上层窗口属于 WindowManager, route 会放行
    private static func mainWindow(pid: pid_t) -> (id: CGWindowID, frame: CGRect)? {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        var best: (id: CGWindowID, frame: CGRect)?
        for window in windows {
            guard (window[kCGWindowOwnerPID as String] as? pid_t) == pid,
                  (window[kCGWindowLayer as String] as? Int) == 0,
                  let id = window[kCGWindowNumber as String] as? CGWindowID,
                  let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds) else {
                continue
            }
            if best.map({ rect.width * rect.height > $0.frame.width * $0.frame.height }) ?? true {
                best = (id, rect)
            }
        }
        return best
    }
}
