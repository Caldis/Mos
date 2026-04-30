//
//  ActionDisplayResolver.swift
//  Mos
//

import Cocoa

enum ActionPresentationKind: Equatable {
    case unbound
    case recordingPrompt
    case namedAction
    case keyCombo
    case openTarget
}

struct ActionPresentation {
    let kind: ActionPresentationKind
    let title: String
    let symbolName: String?
    let image: NSImage?
    let badgeComponents: [String]
    let tag: BrandTagConfig?
    var brand: BrandTagConfig? { tag }

    init(
        kind: ActionPresentationKind,
        title: String,
        symbolName: String? = nil,
        image: NSImage? = nil,
        badgeComponents: [String] = [],
        tag: BrandTagConfig? = nil,
        brand: BrandTagConfig? = nil
    ) {
        self.kind = kind
        self.title = title
        self.symbolName = symbolName
        self.image = image
        self.badgeComponents = badgeComponents
        self.tag = tag ?? brand
    }
}

/// Cell 当前展示的动作态 (互斥).
///
/// 加新动作类型 = 加一个 case, switch 站点会在编译期被强制覆盖, 不再依赖人工同步分散的字段.
/// `.recordingPrompt` 是 UI 临时态 (录制进行中), 其它都对应一种持久化绑定形式.
enum CellActionState: Equatable {
    case unbound
    case recordingPrompt
    case namedShortcut(SystemShortcut.Shortcut)
    case customBinding(name: String)
    case openTarget(OpenTargetPayload)

    /// 是否处于"已绑定"状态 (用于菜单 placeholder 显隐判定).
    var hasBoundAction: Bool {
        switch self {
        case .unbound, .recordingPrompt:
            return false
        case .namedShortcut, .customBinding, .openTarget:
            return true
        }
    }

    /// 从 ButtonBinding 推断对应的展示态 (不含临时态 .recordingPrompt).
    /// 优先级: openTarget > 预定义 systemShortcut > customBinding > unbound.
    init(binding: ButtonBinding) {
        if let openTarget = binding.openTarget {
            self = .openTarget(openTarget)
            return
        }
        if let shortcut = binding.systemShortcut {
            self = .namedShortcut(shortcut)
            return
        }
        if binding.isCustomBinding {
            self = .customBinding(name: binding.systemShortcutName)
            return
        }
        self = .unbound
    }
}

struct ActionDisplayResolver {

    /// 主入口: 接收单一态枚举, 内部 switch 全 case 强制覆盖.
    func resolve(state: CellActionState) -> ActionPresentation {
        switch state {
        case .unbound:
            return ActionPresentation(
                kind: .unbound,
                title: NSLocalizedString("unbound", comment: "")
            )
        case .recordingPrompt:
            return ActionPresentation(
                kind: .recordingPrompt,
                title: NSLocalizedString("custom-recording-prompt", comment: "")
            )
        case .namedShortcut(let shortcut):
            return namedActionPresentation(for: shortcut)
        case .openTarget(let payload):
            return openTargetPresentation(for: payload)
        case .customBinding(let name):
            // 自定义绑定有可能"升级"成已知 named action (键码与 mouseLeftClick 等系统快捷键
            // 等价时), 否则按 keyCombo 渲染.
            if let shortcut = SystemShortcut.displayShortcut(matchingBindingName: name) {
                return namedActionPresentation(for: shortcut)
            }
            if let custom = customBindingPresentation(for: name) {
                return custom
            }
            return ActionPresentation(
                kind: .unbound,
                title: NSLocalizedString("unbound", comment: "")
            )
        }
    }

    /// 旧入口: 把分散参数转 enum 后转发. 保留为兼容已有测试; 新代码请用 resolve(state:).
    func resolve(
        shortcut: SystemShortcut.Shortcut?,
        customBindingName: String?,
        isRecording: Bool,
        openTarget: OpenTargetPayload? = nil
    ) -> ActionPresentation {
        let state: CellActionState = {
            if isRecording { return .recordingPrompt }
            if let openTarget { return .openTarget(openTarget) }
            if let shortcut { return .namedShortcut(shortcut) }
            if let customBindingName { return .customBinding(name: customBindingName) }
            return .unbound
        }()
        return resolve(state: state)
    }

    private func namedActionPresentation(for shortcut: SystemShortcut.Shortcut) -> ActionPresentation {
        ActionPresentation(
            kind: .namedAction,
            title: shortcut.localizedName,
            symbolName: shortcut.symbolName,
            tag: BrandTag.tagForAction(shortcut.identifier)
        )
    }

    private func openTargetPresentation(for payload: OpenTargetPayload) -> ActionPresentation {
        let workspace = NSWorkspace.shared
        let resolvedURL: URL? = {
            if let bundleID = payload.bundleID,
               let url = workspace.urlForApplication(withBundleIdentifier: bundleID) {
                return url
            }
            let url = URL(fileURLWithPath: payload.path)
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }()

        let title: String
        let icon: NSImage?
        if let url = resolvedURL {
            if payload.kind == .application, let bundle = Bundle(url: url) {
                title = bundle.localizedDisplayName
                    ?? bundle.infoDictionary?["CFBundleDisplayName"] as? String
                    ?? bundle.infoDictionary?["CFBundleName"] as? String
                    ?? url.deletingPathExtension().lastPathComponent
            } else {
                title = url.lastPathComponent
            }
            icon = workspace.icon(forFile: url.path)
        } else {
            // Stale path: show filename + unavailable marker
            let basename = (payload.path as NSString).lastPathComponent
            let staleTag = NSLocalizedString("open-target-placeholder-stale", comment: "")
            title = basename.isEmpty ? staleTag : "\(basename) \(staleTag)"
            icon = nil
        }

        return ActionPresentation(
            kind: .openTarget,
            title: title,
            symbolName: nil,
            image: icon
        )
    }

    private func customBindingPresentation(for customBindingName: String) -> ActionPresentation? {
        guard let (code, modifiers) = ButtonBinding.normalizedCustomBindingPayload(from: customBindingName) else {
            return nil
        }

        let tag = BrandTag.tagForCode(code)
        if let tag, modifiers == 0, LogiCenter.shared.isLogiCode(code) {
            return ActionPresentation(
                kind: .namedAction,
                title: (LogiCenter.shared.name(forMosCode: code) ?? ""),
                tag: tag
            )
        }

        let event = InputEvent(
            type: inputType(for: code),
            code: code,
            modifiers: CGEventFlags(rawValue: modifiers),
            phase: .down,
            source: .hidPP,
            device: nil
        )
        let marker = tag.map { "[\($0.name)]" }
        let badgeComponents = event.displayComponents.filter { component in
            guard let marker else { return true }
            return component != marker
        }

        return ActionPresentation(
            kind: .keyCombo,
            title: "",
            badgeComponents: badgeComponents,
            tag: tag
        )
    }

    private func inputType(for code: UInt16) -> EventType {
        if KeyCode.modifierKeys.contains(code) {
            return .keyboard
        }
        return code >= 0x100 ? .mouse : .keyboard
    }
}

extension Bundle {
    var localizedDisplayName: String? {
        return localizedInfoDictionary?["CFBundleDisplayName"] as? String
            ?? localizedInfoDictionary?["CFBundleName"] as? String
    }
}
