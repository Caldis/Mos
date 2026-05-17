//
//  LogiUsageBootstrap.swift
//  Mos
//
//  Pushes initial Options state into LogiCenter at app launch.
//  Idempotent. Preference-panel save paths push their own slice afterward.
//

import Foundation

enum LogiUsageBootstrap {

    static func refreshAll() {
        // 1. Button bindings
        let buttonCodes: Set<UInt16> = Set(
            ButtonUtils.shared.getButtonBindings()
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
        let apps = Options.shared.application.applications
        for i in 0..<apps.count {
            guard let app = apps.get(by: i) else { continue }
            for role in ScrollRole.allCases {
                let codes = appScrollCodes(app: app, role: role)
                LogiCenter.shared.setUsage(source: .appScroll(key: app.path, role: role), codes: codes)
            }
        }
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
