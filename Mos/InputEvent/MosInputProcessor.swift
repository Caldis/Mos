//
//  MosInputProcessor.swift
//  Mos
//  统一事件处理器 - 接收 MosInputEvent, 匹配 ButtonBinding, 执行动作
//  Created by Mos on 2026/3/16.
//  Copyright © 2026 Caldis. All rights reserved.
//

import Cocoa

// MARK: - MosInputResult
/// 事件处理结果
enum MosInputResult {
    case consumed     // 事件已处理,不再传递
    case passthrough  // 事件未匹配,继续传递
}

// MARK: - MosInputProcessor
/// 统一事件处理器 (无状态单例)
/// 从 ButtonUtils 获取绑定配置, 匹配 MosInputEvent, 执行 ShortcutExecutor
class MosInputProcessor {
    static let shared = MosInputProcessor()
    init() { NSLog("Module initialized: MosInputProcessor") }

    /// 处理输入事件
    /// - Parameter event: 统一输入事件
    /// - Returns: .consumed 表示事件已处理, .passthrough 表示未匹配
    func process(_ event: MosInputEvent) -> MosInputResult {
        // 只处理按下事件 (避免 down+up 触发两次)
        guard event.phase == .down else { return .passthrough }

        let bindings = ButtonUtils.shared.getButtonBindings()
        guard let binding = bindings.first(where: {
            $0.triggerEvent.matchesMosInput(event) && $0.isEnabled
        }) else {
            return .passthrough
        }

        ShortcutExecutor.shared.execute(named: binding.systemShortcutName)
        return .consumed
    }
}
