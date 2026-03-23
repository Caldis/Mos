//
//  Toast.swift
//  Mos
//  轻量级 Toast 通知组件 - 多 toast 同时显示, 可拖拽, 可配置
//  Created by Mos on 2026/3/22.
//  Copyright © 2026 Caldis. All rights reserved.
//

import Cocoa

// MARK: - Toast (Public API)

/// 轻量级 Toast 通知
///
/// 在鼠标所在屏幕显示浮动提示, 支持多条同时展示、拖拽定位、自动堆叠。
/// 不抢占焦点, 不阻塞交互。
///
/// 基本用法:
/// ```swift
/// Toast.show("Hi-Res 滚轮已开启", style: .success)
/// Toast.show("当前设备不支持此功能", style: .warning)
/// Toast.dismissAll()
/// ```
///
/// 集成 Debug 面板:
/// ```swift
/// menu.addItem(Toast.debugMenuItem())
/// ```
struct Toast {

    /// 提示样式
    enum Style: CaseIterable {
        /// 中性提示, 用于一般信息
        case info
        /// 绿色强调, 用于操作确认
        case success
        /// 橙色强调, 用于警告/不支持的功能
        case warning
        /// 红色强调, 用于错误
        case error
    }

    /// 显示一条 Toast 通知
    ///
    /// - Parameters:
    ///   - message: 提示文本 (建议不超过两行)
    ///   - style: 提示样式, 默认为 `.info`
    ///   - duration: 显示时长 (秒), 默认 2.5 秒
    ///   - icon: 自定义图标, 传 nil 则使用样式默认图标
    ///   - allowDuplicateVisibleMessage: 是否允许在已有相同可见消息存在时继续展示, 默认 false
    static func show(
        _ message: String,
        style: Style = .info,
        duration: TimeInterval = 2.5,
        icon: NSImage? = nil,
        allowDuplicateVisibleMessage: Bool = false
    ) {
        // 始终异步调度到主线程
        // 即使已在主线程也必须 async, 因为调用方可能在 IOKit/CGEventTap 等
        // RunLoop source 回调中, 同步创建 NSPanel 会导致 RunLoop 递归死锁
        DispatchQueue.main.async {
            ToastManager.shared.present(
                message: message,
                style: style,
                duration: duration,
                icon: icon,
                allowDuplicateVisibleMessage: allowDuplicateVisibleMessage
            )
        }
    }

    /// 关闭所有通知
    static func dismissAll() {
        DispatchQueue.main.async {
            ToastManager.shared.dismissAll()
        }
    }

    /// 显示 Toast Debug 面板
    static func showTestPanel() {
        DispatchQueue.main.async {
            ToastPanel.shared.show()
        }
    }

    /// 返回可直接加入菜单的 Debug 面板入口 MenuItem
    ///
    /// 内部自包含 target/action/icon/title, 调用方无需额外配置。
    /// ```swift
    /// menu.addItem(Toast.debugMenuItem())
    /// ```
    static func debugMenuItem() -> NSMenuItem {
        return ToastPanel.shared.createMenuItem()
    }
}
