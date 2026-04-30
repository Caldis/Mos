//
//  SessionActivityStatus.swift
//  Mos
//  Logi HID session 的活动状态快照 — 供 UI hover popover 展示"正在做什么".
//  只读值类型, 不持有 session 引用, 可安全跨线程传递.
//  Created by Mos on 2026/4/25.
//  Copyright © 2026 Caldis. All rights reserved.
//

import Foundation

struct SessionActivityStatus {
    /// 活动阶段. 粗粒度枚举, 与 UI 文案一一对应.
    enum Phase {
        /// 初次连接后的 feature / control 枚举阶段.
        case discovery
        /// reporting query 循环 (GetControlReporting), 也是唯一能提供进度的阶段.
        case reportingQuery
    }

    let phase: Phase
    let deviceName: String
    /// 仅 `.reportingQuery` 阶段给出 (current, total); 其他阶段为 nil.
    let progress: (current: Int, total: Int)?
}
