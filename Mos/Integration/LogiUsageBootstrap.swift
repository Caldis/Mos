//
//  LogiUsageBootstrap.swift
//  Mos
//
//  Pushes Options state into LogiCenter at app launch.
//  Idempotent. Options 订阅驱动: 绑定/热键/应用列表变更时整体刷新 (installOptionsObservers).
//

import Foundation

enum LogiUsageBootstrap {

    /// 上次推送过 appScroll 用量的 app path, 用于 app 移除后推送空集清理注册表残留
    private static var lastPushedAppPaths: Set<String> = []

    /// 订阅 Options 变更, 集中刷新 Logi 用量 (替代偏好面板各处手动 setUsage)
    static func installOptionsObservers() {
        Options.shared.observe([.buttons, .scroll, .application]) { _ in
            refreshAll()
        }
    }

    static func refreshAll() {
        // 1. Button bindings (直读 Options, 不依赖 ButtonUtils 缓存失效的订阅顺序)
        let buttonCodes: Set<UInt16> = Set(
            Options.shared.buttons.binding
                .filter { $0.isEnabled && $0.triggerEvent.type == .mouse }
                .map { $0.triggerEvent.code }
                .filter { LogiCenter.shared.isLogiCode($0) }
        )
        LogiCenter.shared.setUsage(source: .buttonBinding, codes: buttonCodes)

        // 2. Global scroll
        for role in ScrollRole.allCases {
            let codes = globalScrollCodes(role: role)
            LogiCenter.shared.setUsage(source: .globalScroll(role), codes: codes)
        }

        // 3. App scroll
        var currentPaths: Set<String> = []
        let apps = Options.shared.application.applications
        for i in 0..<apps.count {
            guard let app = apps.get(by: i) else { continue }
            currentPaths.insert(app.path)
            for role in ScrollRole.allCases {
                let codes = appScrollCodes(app: app, role: role)
                LogiCenter.shared.setUsage(source: .appScroll(key: app.path, role: role), codes: codes)
            }
        }
        // 3b. 已移除 app 的用量清理
        for stalePath in lastPushedAppPaths.subtracting(currentPaths) {
            for role in ScrollRole.allCases {
                LogiCenter.shared.setUsage(source: .appScroll(key: stalePath, role: role), codes: [])
            }
        }
        lastPushedAppPaths = currentPaths
    }

    private static func globalScrollCodes(role: ScrollRole) -> Set<UInt16> {
        let hotkey: ScrollHotkey? = {
            switch role {
            case .dash:   return Options.shared.scroll.dash
            case .toggle: return Options.shared.scroll.toggle
            case .block:  return Options.shared.scroll.block
            }
        }()
        guard let h = hotkey, h.type == .mouse, LogiCenter.shared.isLogiCode(h.code) else { return [] }
        return [h.code]
    }

    private static func appScrollCodes(app: Application, role: ScrollRole) -> Set<UInt16> {
        guard !app.inherit else { return [] }
        let hotkey: ScrollHotkey? = {
            switch role {
            case .dash:   return app.scroll.dash
            case .toggle: return app.scroll.toggle
            case .block:  return app.scroll.block
            }
        }()
        guard let h = hotkey, h.type == .mouse, LogiCenter.shared.isLogiCode(h.code) else { return [] }
        return [h.code]
    }
}
