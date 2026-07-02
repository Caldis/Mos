//
//  SwipeScrollDirection.swift
//  Mos
//  系统"自然滚动"方向 (com.apple.swipescrolldirection) 的即时读写桥接
//  Created by Claude on 2026/7/3.
//  Copyright © 2026 Caldis. All rights reserved.
//

import Foundation

/// 系统"自然滚动"方向 (com.apple.swipescrolldirection) 的即时读写。
///
/// 背景: iPhone 镜像 (com.apple.ScreenContinuity, 实际承载进程 WindowManager) 经私有框架
/// UniversalHID 直接订阅 IOHIDEventSystem 层的原始滚动事件, 该层位于 Mos 的 CGEventTap
/// (CGEvent 层) 之上, 因此 Mos 的翻转/平滑对镜像不可见。而系统"自然滚动"在 IOHIDEvent
/// 分发前 (IOHIDPointerScrollFilter) 就已应用, 镜像可见 —— 这是唯一能影响镜像滚动方向的杠杆。
///
/// `defaults write com.apple.swipescrolldirection` 不会即时生效 (需注销)。真正即时生效的入口是
/// PreferencePanesSupport (私有框架) 导出的 `setSwipeScrollDirection(bool)` / `swipeScrollDirection()`。
/// 此处以运行时 dlsym 调用, 避免硬链接私有框架; 符号缺失时静默降级 (isAvailable == false)。
enum SwipeScrollDirection {
    private typealias SetFunction = @convention(c) (Bool) -> Void
    private typealias GetFunction = @convention(c) () -> Bool

    private static let frameworkPath =
        "/System/Library/PrivateFrameworks/PreferencePanesSupport.framework/PreferencePanesSupport"

    private static let handle: UnsafeMutableRawPointer? = dlopen(frameworkPath, RTLD_NOW)

    private static let setFunction: SetFunction? = handle
        .flatMap { dlsym($0, "setSwipeScrollDirection") }
        .map { unsafeBitCast($0, to: SetFunction.self) }

    private static let getFunction: GetFunction? = handle
        .flatMap { dlsym($0, "swipeScrollDirection") }
        .map { unsafeBitCast($0, to: GetFunction.self) }

    /// 当前系统/运行环境是否可用 (符号存在)
    static var isAvailable: Bool { setFunction != nil && getFunction != nil }

    /// 读取当前系统自然滚动方向 (true = 自然滚动开启); 不可用时保守返回 true (系统默认值)
    static func isNatural() -> Bool { getFunction?() ?? true }

    /// 即时设置系统自然滚动方向, 并广播变更通知令系统 UI/其它组件同步
    /// - Returns: 是否成功调用私有符号
    @discardableResult
    static func set(natural: Bool) -> Bool {
        guard let setFunction else { return false }
        setFunction(natural)
        // 该通知仅供观察者 (如系统设置面板) 同步显示, 非生效触发; setFunction 调用本身已即时生效
        DistributedNotificationCenter.default().postNotificationName(
            NSNotification.Name("SwipeScrollDirectionDidChangeNotification"),
            object: nil, userInfo: nil, deliverImmediately: true
        )
        return true
    }
}
