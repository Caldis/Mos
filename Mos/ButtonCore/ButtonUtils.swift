//
//  ButtonUtils.swift
//  Mos
//  按钮绑定工具类 - 获取配置和管理绑定 (带缓存)
//  Created by Claude on 2025/8/10.
//  Copyright © 2025年 Caldis. All rights reserved.
//

import Cocoa

struct ButtonBindingTriggerKey: Hashable {
    let type: EventType
    let code: UInt16
}

class ButtonUtils {

    // 单例
    static let shared = ButtonUtils()
    init() {}

    // MARK: - 缓存

    /// 缓存的绑定列表 (已预解析 custom:: 字段)
    private var cachedBindings: [ButtonBinding] = []
    private var cachedBindingsByTriggerKey: [ButtonBindingTriggerKey: [ButtonBinding]] = [:]
    private var isDirty = true

    // MARK: - 获取按钮绑定配置

    /// 获取当前应用的按钮绑定配置 (带缓存和预解析)
    /// - Returns: 按钮绑定列表
    func getButtonBindings() -> [ButtonBinding] {
        refreshCacheIfNeeded()
        return cachedBindings
    }

    func getButtonBindings(for type: EventType, code: UInt16) -> [ButtonBinding] {
        refreshCacheIfNeeded()
        return cachedBindingsByTriggerKey[ButtonBindingTriggerKey(type: type, code: code)] ?? []
    }

    func getBestMatchingBinding(
        for event: InputEvent,
        where predicate: ((ButtonBinding) -> Bool)? = nil
    ) -> ButtonBinding? {
        let candidates = getButtonBindings(for: event.type, code: event.code)
        var bestBinding: ButtonBinding?
        var bestPriority = Int.min

        for binding in candidates {
            guard binding.isEnabled else {
                continue
            }
            if let predicate, !predicate(binding) {
                continue
            }
            guard let priority = binding.triggerEvent.matchPriority(for: event) else {
                continue
            }
            if priority > bestPriority {
                bestBinding = binding
                bestPriority = priority
            }
        }

        return bestBinding
    }

    /// 标记缓存失效 (绑定变更后调用)
    func invalidateCache() {
        isDirty = true
    }

    private func refreshCacheIfNeeded() {
        guard isDirty else { return }

        cachedBindings = Options.shared.buttons.binding.map { binding in
            var b = binding
            b.prepareCustomCache()
            return b
        }

        cachedBindingsByTriggerKey = Dictionary(grouping: cachedBindings) { binding in
            ButtonBindingTriggerKey(
                type: binding.triggerEvent.type,
                code: binding.triggerEvent.code
            )
        }

        isDirty = false
    }

    // MARK: - 分应用支持 (预留接口)

    /// 获取当前焦点应用的配置对象 (预留)
    /// - Returns: Application 对象或 nil
    private func getTargetApplication() -> Application? {
        return nil
    }
}
