//
//  MirroringScrollCoordinator.swift
//  Mos
//  iPhone 镜像滚动方向协调器 (路线 A: 前台聚焦时临时切换系统自然滚动)
//  Created by Claude on 2026/7/3.
//  Copyright © 2026 Caldis. All rights reserved.
//

import Cocoa

/// iPhone 镜像 (com.apple.ScreenContinuity) 滚动方向协调器。
///
/// 原理见 `SwipeScrollDirection`: Mos 的 CGEventTap 改不到镜像, 唯一杠杆是系统自然滚动方向。
///
/// 策略: 当 iPhone 镜像成为前台应用时, 把系统自然滚动方向临时改写为"用户在其它应用中的等效
/// 方向", 使镜像内滚动手感与别处一致; 失焦 / 退出 / 停止时恢复用户原值。
///
/// 等效方向推导 (仅垂直, 因 swipescrolldirection 为全局单值且 iOS 滚动以垂直为主):
///   其它应用净方向 = 系统自然滚动 XOR Mos 垂直翻转
/// 即用户若开了 Mos 翻转, 聚焦镜像时把系统方向翻过来抵消; 未开 Mos 翻转时本协调器不动作。
///
/// 注意: 该改写会临时改变系统级"自然滚动"这一可见设置 (失焦即恢复), 因此由开关
/// `overrideMirroringDirection` 显式门控, 默认关闭。
final class MirroringScrollCoordinator {

    static let shared = MirroringScrollCoordinator()
    private init() {}

    /// iPhone 镜像的 Bundle Identifier
    static let mirroringBundleIdentifier = "com.apple.ScreenContinuity"

    /// 门控开关的持久化键 (未接入正式 Options 前先独立读取, 默认关闭)
    static let enabledDefaultsKey = "overrideMirroringDirection"

    private var isActive = false
    private var isOverriding = false
    private var savedSystemNatural: Bool?          // 覆盖前的系统原值, 用于恢复
    private var observers: [NSObjectProtocol] = []

    /// 用户是否开启了本特性
    private var isFeatureEnabled: Bool {
        UserDefaults.standard.bool(forKey: Self.enabledDefaultsKey)
    }

    /// 启动监听 (幂等; 可随 ScrollCore 生命周期重复调用)
    func enable() {
        guard !isActive else { return }
        guard SwipeScrollDirection.isAvailable else {
            NSLog("MirroringScrollCoordinator: SwipeScrollDirection symbols unavailable, skip")
            return
        }
        isActive = true
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] note in self?.handleActivation(note) })
        observers.append(center.addObserver(
            forName: NSWorkspace.didDeactivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] note in self?.handleDeactivation(note) })
        // 处理"启动/启用时镜像已在前台"的情况
        if isFeatureEnabled, isMirroring(NSWorkspace.shared.frontmostApplication) {
            applyOverride()
        }
    }

    /// 停止监听并恢复系统原值 (幂等)
    func disable() {
        guard isActive else { return }
        isActive = false
        let center = NSWorkspace.shared.notificationCenter
        observers.forEach { center.removeObserver($0) }
        observers.removeAll()
        restoreOverride()
    }

    // MARK: - 前台切换处理

    private func isMirroring(_ app: NSRunningApplication?) -> Bool {
        app?.bundleIdentifier == Self.mirroringBundleIdentifier
    }

    private func runningApplication(from note: Notification) -> NSRunningApplication? {
        note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
    }

    private func handleActivation(_ note: Notification) {
        guard isFeatureEnabled else { return }
        if isMirroring(runningApplication(from: note)) { applyOverride() }
    }

    private func handleDeactivation(_ note: Notification) {
        if isMirroring(runningApplication(from: note)) { restoreOverride() }
    }

    // MARK: - 覆盖与恢复

    private func applyOverride() {
        guard !isOverriding else { return }
        let current = SwipeScrollDirection.isNatural()
        // 用户在其它应用中的等效垂直方向 = 系统自然 XOR Mos 垂直翻转
        let mosReverseVertical = Options.shared.scroll.reverse && Options.shared.scroll.reverseVertical
        let desiredNatural = current != mosReverseVertical   // Bool != 即 XOR
        // 仅当需要改变时才写入并记录, 避免无谓地改动系统设置
        guard desiredNatural != current else { return }
        savedSystemNatural = current
        SwipeScrollDirection.set(natural: desiredNatural)
        isOverriding = true
    }

    private func restoreOverride() {
        guard isOverriding else { return }
        isOverriding = false
        guard let saved = savedSystemNatural else { return }
        savedSystemNatural = nil
        if SwipeScrollDirection.isNatural() != saved {
            SwipeScrollDirection.set(natural: saved)
        }
    }
}
