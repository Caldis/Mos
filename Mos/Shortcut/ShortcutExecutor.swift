//
//  ShortcutExecutor.swift
//  Mos
//  系统快捷键执行器 - 发送快捷键事件
//  Created by Claude on 2025/8/10.
//  Copyright © 2025年 Caldis. All rights reserved.
//

import Cocoa

enum MouseButtonActionKind {
    case left
    case right
    case middle
    case back
    case forward

    init?(shortcutIdentifier: String) {
        switch shortcutIdentifier {
        case "mouseLeftClick":
            self = .left
        case "mouseRightClick":
            self = .right
        case "mouseMiddleClick":
            self = .middle
        case "mouseBackClick":
            self = .back
        case "mouseForwardClick":
            self = .forward
        default:
            return nil
        }
    }
}

enum MosScrollActionKind {
    case dash
    case toggle
    case block

    init?(shortcutIdentifier: String) {
        switch shortcutIdentifier {
        case "mosScrollDash":
            self = .dash
        case "mosScrollToggle":
            self = .toggle
        case "mosScrollBlock":
            self = .block
        default:
            return nil
        }
    }

    var role: ScrollRole {
        switch self {
        case .dash:
            return .dash
        case .toggle:
            return .toggle
        case .block:
            return .block
        }
    }
}

enum ResolvedAction {
    case customKey(code: UInt16, modifiers: UInt64)
    case mouseButton(kind: MouseButtonActionKind)
    case mosScroll(role: ScrollRole)
    case systemShortcut(identifier: String)
    case logiAction(identifier: String)
    case openTarget(payload: OpenTargetPayload)

    var executionMode: ActionExecutionMode {
        switch self {
        case .customKey, .mouseButton, .mosScroll:
            return .stateful
        case .logiAction, .openTarget:
            return .trigger
        case .systemShortcut(let identifier):
            return SystemShortcut.getShortcut(named: identifier)?.executionMode ?? .trigger
        }
    }
}


struct ActionExecutionResult {
    let mouseSessionID: UUID?

    static let none = ActionExecutionResult(mouseSessionID: nil)
}

struct MouseTapReplayContext {
    let buttonNumber: Int64
    let location: CGPoint?
    let modifiers: CGEventFlags
}

class ShortcutExecutor {

    // 单例
    static let shared = ShortcutExecutor()
    init() {
        NSLog("Module initialized: ShortcutExecutor")
    }

    private var testingMouseEventObserver: ((CGEvent) -> Void)?

    /// 快速识别 Mos Scroll 三个 stateful 动作, 供事件热路径避免完整 action 解析。
    static func isMosScrollActionIdentifier(_ shortcutName: String) -> Bool {
        MosScrollActionKind(shortcutIdentifier: shortcutName) != nil
    }

    // MARK: - 执行快捷键 (统一接口)

    /// 执行快捷键 (底层接口, 使用原始flags)
    /// - Parameters:
    ///   - code: 虚拟键码
    ///   - flags: 修饰键flags (UInt64原始值)
    ///   - preserveFlagsOnKeyUp: KeyUp 时是否保留修饰键 flags (默认 false)
    func execute(code: CGKeyCode, flags: UInt64, preserveFlagsOnKeyUp: Bool = false) {
        // 创建事件源
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            return
        }

        // 发送按键按下事件
        if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true) {
            keyDown.flags = CGEventFlags(rawValue: flags)
            keyDown.post(tap: .cghidEventTap)
        }

        // 发送按键抬起事件
        if let keyUp = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false) {
            if preserveFlagsOnKeyUp {
                keyUp.flags = CGEventFlags(rawValue: flags)
            }
            keyUp.post(tap: .cghidEventTap)
        }
    }

    /// 执行系统快捷键 (从SystemShortcut.Shortcut对象)
    /// - Parameter shortcut: SystemShortcut.Shortcut对象
    func execute(_ shortcut: SystemShortcut.Shortcut) {
        execute(code: shortcut.code, flags: UInt64(shortcut.modifiers.rawValue), preserveFlagsOnKeyUp: shortcut.preserveFlagsOnKeyUp)
    }

    /// 执行系统快捷键 (从名称解析, 支持动态读取系统配置)
    /// - Parameters:
    ///   - shortcutName: 快捷键名称
    ///   - phase: 事件阶段 (down/up), 默认 .down
    ///   - binding: 可选的 ButtonBinding (用于访问预解析的 custom cache)
    func execute(named shortcutName: String, phase: InputPhase = .down, binding: ButtonBinding? = nil, inputModifiers: CGEventFlags? = nil) {
        guard let action = resolveAction(named: shortcutName, binding: binding) else { return }
        _ = execute(action: action, phase: phase, inputModifiers: inputModifiers)
    }

    @discardableResult
    func execute(
        action: ResolvedAction,
        phase: InputPhase,
        mouseSessionID: UUID? = nil,
        inputModifiers: CGEventFlags? = nil
    ) -> ActionExecutionResult {
        switch action {
        case .customKey(let code, let modifiers):
            executeCustom(code: code, modifiers: modifiers, phase: phase)
            return .none
        case .mouseButton(let kind):
            return ActionExecutionResult(
                mouseSessionID: executeMouseButton(
                    kind,
                    phase: phase,
                    mouseSessionID: mouseSessionID,
                    inputModifiers: inputModifiers
                )
            )
        case .mosScroll(let role):
            ScrollCore.shared.handleMosScrollAction(role: role, isDown: phase == .down)
            return .none
        case .logiAction(let identifier):
            guard phase == .down else { return .none }
            executeLogiAction(identifier)
            return .none
        case .openTarget(let payload):
            guard phase == .down else { return .none }
            executeOpenTarget(payload)
            return .none
        case .systemShortcut(let identifier):
            guard phase == .down else { return .none }
            executeResolvedSystemShortcut(named: identifier)
            return .none
        }
    }

    func resolveAction(named shortcutName: String, binding: ButtonBinding? = nil) -> ResolvedAction? {
        // 优先: 结构化 payload (在 cachedCustomCode 之前判定, 避免命名冲突)
        if let payload = binding?.openTarget,
           shortcutName == ButtonBinding.openTargetSentinel {
            return .openTarget(payload: payload)
        }
        if let code = binding?.cachedCustomCode {
            let modifiers = binding?.cachedCustomModifiers ?? 0
            return .customKey(code: code, modifiers: modifiers)
        }
        if let code = SystemShortcut.predefinedModifierCode(for: shortcutName) {
            return .customKey(code: code, modifiers: 0)
        }
        if let kind = MouseButtonActionKind(shortcutIdentifier: shortcutName) {
            return .mouseButton(kind: kind)
        }
        if let scrollAction = MosScrollActionKind(shortcutIdentifier: shortcutName) {
            return .mosScroll(role: scrollAction.role)
        }
        if shortcutName.hasPrefix("logi") {
            return .logiAction(identifier: shortcutName)
        }
        guard !shortcutName.isEmpty else { return nil }
        return .systemShortcut(identifier: shortcutName)
    }

    private func executeResolvedSystemShortcut(named shortcutName: String) {
        // 优先使用系统实际配置 (对于Mission Control相关快捷键)
        if let resolved = SystemShortcut.resolveSystemShortcut(shortcutName) {
            execute(code: resolved.code, flags: resolved.modifiers)
            return
        }

        // Fallback到内置快捷键定义
        guard let shortcut = SystemShortcut.getShortcut(named: shortcutName) else {
            return
        }

        execute(shortcut)
    }

    // MARK: - Custom Binding Execution

    /// 执行自定义绑定 (1:1 down/up 映射)
    private func executeCustom(code: UInt16, modifiers: UInt64, phase: InputPhase) {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        let isModifierKey = KeyCode.modifierKeys.contains(code)

        if isModifierKey {
            // 修饰键: 使用 flagsChanged 事件类型
            guard let event = CGEvent(source: source) else { return }
            event.type = .flagsChanged
            event.setIntegerValueField(.keyboardEventKeycode, value: Int64(code))
            if phase == .down {
                // 按下: 设置所有修饰键 flags (自身 + 附加修饰键)
                let keyMask = KeyCode.getKeyMask(code)
                event.flags = CGEventFlags(rawValue: modifiers | keyMask.rawValue)
            } else {
                // 松开: 清除所有 flags (释放全部修饰键)
                event.flags = CGEventFlags(rawValue: 0)
            }
            // 标记为 Mos 合成事件, 避免被 ScrollCore/ButtonCore/KeyRecorder 误处理
            event.setIntegerValueField(.eventSourceUserData, value: MosEventMarker.syntheticCustom)
            event.post(tap: .cghidEventTap)
        } else {
            // 普通键: 使用 keyDown/keyUp
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: phase == .down) else { return }
            event.flags = CGEventFlags(rawValue: modifiers)
            // 标记为 Mos 合成事件
            event.setIntegerValueField(.eventSourceUserData, value: MosEventMarker.syntheticCustom)
            event.post(tap: .cghidEventTap)
        }
    }

    // MARK: - Mouse Actions

    /// 执行鼠标按键动作 (1:1 down/up 映射)
    private func executeMouseButton(
        _ kind: MouseButtonActionKind,
        phase: InputPhase,
        mouseSessionID: UUID?,
        inputModifiers: CGEventFlags?
    ) -> UUID? {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return nil }
        let location = NSEvent.mouseLocation
        // 转换坐标: NSEvent 用左下角原点, CGEvent 用左上角原点
        let screenHeight = NSScreen.main?.frame.height ?? 0
        let point = CGPoint(x: location.x, y: screenHeight - location.y)
        let spec = mouseEventSpec(for: kind, phase: phase)
        guard let event = CGEvent(
            mouseEventSource: source,
            mouseType: spec.type,
            mouseCursorPosition: point,
            mouseButton: spec.button
        ) else {
            return nil
        }

        let createdSessionID: UUID?
        if phase == .down {
            createdSessionID = MouseInteractionSessionController.shared.beginSession(target: syntheticTarget(for: kind))
        } else {
            createdSessionID = nil
            if let mouseSessionID {
                MouseInteractionSessionController.shared.endSession(id: mouseSessionID)
            } else {
                MouseInteractionSessionController.shared.clearAllSessions()
            }
        }

        if let buttonNumber = spec.buttonNumber {
            event.setIntegerValueField(.mouseEventButtonNumber, value: buttonNumber)
        }
        event.flags = InputProcessor.shared.combinedModifierFlags(physicalModifiers: inputModifiers)
        event.setIntegerValueField(.eventSourceUserData, value: MosEventMarker.syntheticCustom)
        notifyOrPostMouseEvent(event)
        return createdSessionID
    }

    func setTestingMouseEventObserver(_ observer: @escaping (CGEvent) -> Void = { _ in }) {
        testingMouseEventObserver = observer
    }

    func clearTestingMouseEventObserver() {
        testingMouseEventObserver = nil
    }

    func mouseTapReplayContext(for event: InputEvent) -> MouseTapReplayContext? {
        guard event.type == .mouse,
              let buttonNumber = mouseButtonNumberForTapReplay(event) else {
            return nil
        }
        let location: CGPoint?
        if case .cgEvent(let cgEvent) = event.source {
            location = cgEvent.location
        } else {
            location = nil
        }
        return MouseTapReplayContext(
            buttonNumber: buttonNumber,
            location: location,
            modifiers: event.modifiers
        )
    }

    func replayMouseTap(_ context: MouseTapReplayContext) {
        replayMouseEvent(context, phase: .down)
        replayMouseEvent(context, phase: .up)
    }

    private func syntheticTarget(for kind: MouseButtonActionKind) -> SyntheticMouseTarget {
        switch kind {
        case .left:
            return .left
        case .right:
            return .right
        case .middle:
            return .other(buttonNumber: 2)
        case .back:
            return .other(buttonNumber: 3)
        case .forward:
            return .other(buttonNumber: 4)
        }
    }

    private func mouseButtonNumberForTapReplay(_ event: InputEvent) -> Int64? {
        switch event.code {
        case 2...20:
            return Int64(event.code)
        case 1003:
            return 0
        case 1004:
            return 1
        case 1005:
            return 2
        case 1006:
            return 3
        case 1007:
            return 4
        default:
            return nil
        }
    }

    private func replayMouseEvent(
        _ context: MouseTapReplayContext,
        phase: InputPhase
    ) {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        let spec = mouseEventSpec(buttonNumber: context.buttonNumber, phase: phase)
        guard let event = CGEvent(
            mouseEventSource: source,
            mouseType: spec.type,
            mouseCursorPosition: context.location ?? currentMouseLocationForCGEvent(),
            mouseButton: spec.button
        ) else {
            return
        }

        if let buttonNumber = spec.buttonNumber {
            event.setIntegerValueField(.mouseEventButtonNumber, value: buttonNumber)
        }
        event.flags = InputProcessor.shared.combinedModifierFlags(physicalModifiers: context.modifiers)
        event.setIntegerValueField(.eventSourceUserData, value: MosEventMarker.syntheticCustom)
        notifyOrPostMouseEvent(event)
    }

    private func mouseEventSpec(for kind: MouseButtonActionKind, phase: InputPhase) -> (type: CGEventType, button: CGMouseButton, buttonNumber: Int64?) {
        switch kind {
        case .left:
            return (phase == .down ? .leftMouseDown : .leftMouseUp, .left, nil)
        case .right:
            return (phase == .down ? .rightMouseDown : .rightMouseUp, .right, nil)
        case .middle:
            return (phase == .down ? .otherMouseDown : .otherMouseUp, .center, 2)
        case .back:
            return (phase == .down ? .otherMouseDown : .otherMouseUp, .center, 3)
        case .forward:
            return (phase == .down ? .otherMouseDown : .otherMouseUp, .center, 4)
        }
    }

    private func mouseEventSpec(buttonNumber: Int64, phase: InputPhase) -> (type: CGEventType, button: CGMouseButton, buttonNumber: Int64?) {
        switch buttonNumber {
        case 0:
            return (phase == .down ? .leftMouseDown : .leftMouseUp, .left, nil)
        case 1:
            return (phase == .down ? .rightMouseDown : .rightMouseUp, .right, nil)
        default:
            return (phase == .down ? .otherMouseDown : .otherMouseUp, .center, buttonNumber)
        }
    }

    private func currentMouseLocationForCGEvent() -> CGPoint {
        let location = NSEvent.mouseLocation
        let screenHeight = NSScreen.main?.frame.height ?? 0
        return CGPoint(x: location.x, y: screenHeight - location.y)
    }

    // MARK: - Logi HID++ Actions

    /// 执行 Logitech HID++ 动作
    private func executeLogiAction(_ name: String) {
        switch name {
        case "logiSmartShiftToggle":
            LogiCenter.shared.executeSmartShiftToggle()
        case "logiDPICycleUp":
            LogiCenter.shared.executeDPICycle(direction: .up)
        case "logiDPICycleDown":
            LogiCenter.shared.executeDPICycle(direction: .down)
        default:
            break
        }
    }

    // MARK: - Open Target Actions

    /// 专用串行后台队列, 用于把 OpenTarget 实际执行 (NSWorkspace/Process/FileManager)
    /// 调离 CGEvent tap 回调链.
    private static let openTargetQueue = DispatchQueue(
        label: "com.caldis.Mos.openTarget",
        qos: .userInitiated
    )

    private func executeOpenTarget(_ payload: OpenTargetPayload) {
        // CRITICAL: dispatch to background queue.
        // 调用栈: ButtonCore CGEvent tap → InputProcessor → ShortcutExecutor.execute(action:phase:).
        // CGEvent tap 有严格的回调延迟约束 (默认 1s 超时), 超时后系统会自动禁用 tap, 整个
        // 鼠标事件流断掉. NSWorkspace.openApplication / Process.run() / FileManager 都可能
        // 卡在 LaunchServices RPC、网络盘 stat、fork+exec、文件系统查询上, 同步执行有真实风险.
        Self.openTargetQueue.async { [payload] in
            switch payload.kind {
            case .application: self.launchApplication(payload)
            case .script:      self.runScript(payload)
            case .file:        self.openFile(payload)
            }
        }
    }

    /// 用系统默认 app 打开任意文件 (PNG / PDF / 文本 / etc.).
    /// NSWorkspace.open(_:) 不支持参数, payload.arguments 在此忽略.
    private func openFile(_ payload: OpenTargetPayload) {
        let url = URL(fileURLWithPath: payload.path)
        let fileName = url.lastPathComponent

        guard FileManager.default.fileExists(atPath: url.path) else {
            Toast.show(
                String(format: NSLocalizedString("openTargetFileNotFound", comment: ""), fileName),
                style: .error
            )
            NSLog("OpenTarget: file not found: \(payload.path)")
            return
        }

        if !NSWorkspace.shared.open(url) {
            Toast.show(
                String(format: NSLocalizedString("openTargetFileFailed", comment: ""), fileName),
                style: .error
            )
            NSLog("OpenTarget: NSWorkspace.open returned false for: \(payload.path)")
        }
    }

    private func launchApplication(_ payload: OpenTargetPayload) {
        let workspace = NSWorkspace.shared
        // Bundle ID 优先 (即便 .app 被移动到别的目录也能找到), 其次绝对路径.
        let resolvedURL: URL? = {
            if let bundleID = payload.bundleID,
               let url = workspace.urlForApplication(withBundleIdentifier: bundleID) {
                return url
            }
            let url = URL(fileURLWithPath: payload.path)
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }()

        guard let resolvedURL else {
            let appName = (payload.path as NSString).lastPathComponent
            Toast.show(
                String(format: NSLocalizedString("openTargetAppNotFound", comment: ""), appName),
                style: .error
            )
            NSLog("OpenTarget: cannot resolve application path=\(payload.path) bundleID=\(payload.bundleID ?? "-")")
            return
        }

        // 走 NSWorkspace 而不是 Process(/usr/bin/open):
        // - LaunchServices 路径, 目标 App 由 launchd 启动, 拿到 launchd 的干净 env;
        //   不会继承 Mos 自身的 DYLD_*/__XPC_DYLD_* 等调试器注入 env vars.
        // - 这是 OS 层面的隔离, 不依赖 sanitize 黑名单.
        let appArguments = ArgumentSplitter.split(payload.arguments)
        let appName = resolvedURL.deletingPathExtension().lastPathComponent

        if #available(macOS 10.15, *) {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true   // 已运行则置前 (不重启)
            configuration.arguments = appArguments
            workspace.openApplication(at: resolvedURL, configuration: configuration) { _, error in
                if let error = error {
                    Toast.show(
                        String(format: NSLocalizedString("openTargetAppLaunchFailed", comment: ""), appName),
                        style: .error
                    )
                    NSLog("OpenTarget: NSWorkspace.openApplication failed: \(error.localizedDescription)")
                }
            }
        } else {
            // macOS 10.13 / 10.14 fallback: legacy launchApplication. 同样走 LaunchServices,
            // 同样隔离 env. Deprecated 但在现代 macOS 上仍然工作.
            var configuration: [NSWorkspace.LaunchConfigurationKey: Any] = [:]
            if !appArguments.isEmpty {
                configuration[.arguments] = appArguments
            }
            do {
                _ = try workspace.launchApplication(
                    at: resolvedURL,
                    options: [.default],
                    configuration: configuration
                )
            } catch {
                Toast.show(
                    String(format: NSLocalizedString("openTargetAppLaunchFailed", comment: ""), appName),
                    style: .error
                )
                NSLog("OpenTarget: launchApplication (legacy) failed: \(error.localizedDescription)")
            }
        }
    }

    /// 在 Mos 自身进程启动后, 立刻 unsetenv 掉污染 keys.
    ///
    /// 必须这么做的原因: 当 Mos Debug 由 Xcode 启动时, env 里带 DYLD_INSERT_LIBRARIES=
    /// .../libViewDebuggerSupport.dylib, 还有 __XPC_DYLD_* 等. 这些 keys 即使通过
    /// NSWorkspace.openApplication (XPC 到 launchservicesd) 启动子 App, 仍会被 macOS
    /// 沿着 XPC 链路传递到 launchservicesd 再到目标 App, 导致依赖 AVKit 的 sealed
    /// system app 加载 libViewDebuggerSupport 时找不到符号, dyld halt → SIGABRT.
    ///
    /// `Process.environment = sanitizedSubprocessEnvironment()` 只能堵 Process 这一条
    /// 路径; XPC 走的是 libxpc 内部读 live env, 必须从源头 unsetenv 才能根治.
    ///
    /// 调用时机: AppDelegate.applicationWillFinishLaunching 最早调一次. dyld 已经在
    /// app 启动时读完 DYLD_*, 之后 unsetenv 不会卸载已加载的 dylib (Xcode 视图调试
    /// 在 Mos 自身进程里继续工作), 但任何之后启动的子进程都拿不到这些 vars 了.
    ///
    /// Release 版本环境里这些 keys 本来就不存在, unsetenv 是 no-op. 安全无副作用.
    static func sanitizeOwnLaunchEnvironment() {
        for key in ProcessInfo.processInfo.environment.keys where shouldStripEnvKey(key) {
            unsetenv(key)
        }
    }

    /// 已 unsetenv 后再读, 返回当前 env 的副本 (供 Process.environment 显式赋值用).
    /// 双重保险: sanitizeOwnLaunchEnvironment 已经清干净源头, 这里再过滤一遍兜底.
    static func sanitizedSubprocessEnvironment() -> [String: String] {
        return filterEnvironment(ProcessInfo.processInfo.environment)
    }

    /// 纯函数: 输入一个 env dict, 输出剥离了污染 keys 的副本. 暴露出来供单测用控制输入验证.
    static func filterEnvironment(_ env: [String: String]) -> [String: String] {
        var out = env
        for key in env.keys where shouldStripEnvKey(key) {
            out.removeValue(forKey: key)
        }
        return out
    }

    private static func shouldStripEnvKey(_ key: String) -> Bool {
        // dyld 注入 / fallback 路径 / 框架路径
        if key.hasPrefix("DYLD_") { return true }
        // Xcode 通过 launchd XPC 传递的 dyld 注入 (会跨 XPC 边界变成子进程的 DYLD_*)
        if key.hasPrefix("__XPC_DYLD_") { return true }
        // Xcode 调试器附加 (LLVM profile / SwiftUI 视图调试 等)
        if key.hasPrefix("__XPC_LLVM_") { return true }
        if key == "SWIFTUI_VIEW_DEBUG" { return true }
        if key.hasPrefix("OS_ACTIVITY_DT_") { return true }
        // 内存分析器
        if key.hasPrefix("MallocStack") { return true }
        if key == "NSZombieEnabled" { return true }
        if key == "NSDeallocateZombies" { return true }
        // Sanitizer ABI shim
        if key.hasPrefix("LSAN_") || key.hasPrefix("ASAN_") || key.hasPrefix("TSAN_") || key.hasPrefix("UBSAN_") { return true }
        return false
    }

    private func runScript(_ payload: OpenTargetPayload) {
        let url = URL(fileURLWithPath: payload.path)
        let scriptName = url.lastPathComponent

        guard FileManager.default.fileExists(atPath: url.path) else {
            Toast.show(
                String(format: NSLocalizedString("openTargetScriptNotFound", comment: ""), scriptName),
                style: .error
            )
            NSLog("OpenTarget: script not found: \(payload.path)")
            return
        }

        guard FileManager.default.isExecutableFile(atPath: url.path) else {
            Toast.show(
                String(format: NSLocalizedString("openTargetScriptNotExecutable", comment: ""), scriptName),
                style: .warning
            )
            NSLog("OpenTarget: script not executable: \(payload.path)")
            return
        }

        let process = Process()
        process.executableURL = url
        process.arguments = ArgumentSplitter.split(payload.arguments)
        process.environment = Self.sanitizedSubprocessEnvironment()
        do {
            try process.run()
        } catch {
            Toast.show(
                String(format: NSLocalizedString("openTargetScriptFailed", comment: ""), scriptName),
                style: .error
            )
            NSLog("OpenTarget: script execution failed: \(error.localizedDescription)")
        }
    }

    private func notifyOrPostMouseEvent(_ event: CGEvent) {
        if let testingMouseEventObserver {
            testingMouseEventObserver(event)
            return
        }
        event.post(tap: .cghidEventTap)
    }
}
