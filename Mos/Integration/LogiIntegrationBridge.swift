//
//  LogiIntegrationBridge.swift
//  Mos
//
//  Production LogiExternalBridge implementation. Routes Logi events to
//  ScrollCore, ButtonUtils, InputProcessor, Toast — keeping Mos/Logi/ free
//  of cross-module references (Step 5 lint will enforce this).
//

import Foundation

final class LogiIntegrationBridge: LogiExternalBridge {

    static let shared = LogiIntegrationBridge()
    private init() {}

    func dispatchLogiButtonEvent(_ event: InputEvent) -> LogiDispatchResult {
        // Recording mode: forward to KeyRecorder via the relay notification.
        // Hot-path post #1 (matches §11 cap: rawButtonEvent + buttonEventRelay).
        if LogiCenter.shared.isRecording {
            NotificationCenter.default.post(
                name: LogiCenter.buttonEventRelay,
                object: nil,
                userInfo: ["event": event]
            )
            return .consumed
        }

        // Probe for logi* binding; the session executes the action so the
        // hardware action stays scoped to the originating device (no global
        // activeBindings registration).
        if event.phase == .down,
           let binding = ButtonUtils.shared.getBestMatchingBinding(
               for: event,
               where: { $0.systemShortcutName.hasPrefix("logi") }
           ) {
            return .logiAction(name: binding.systemShortcutName)
        }

        // Generic binding via InputProcessor (covers up phase + non-Logi
        // bindings like custom::).
        let result = InputProcessor.shared.process(event)
        if result == .consumed { return .consumed }

        // Unconsumed: fire the relay so KeyRecorder + other observers see it.
        NotificationCenter.default.post(
            name: LogiCenter.buttonEventRelay,
            object: nil,
            userInfo: ["event": event]
        )
        return .unhandled
    }

    func handleLogiScrollHotkey(code: UInt16, phase: InputPhase) {
        _ = ScrollCore.shared.handleScrollHotkey(code: code, isDown: phase == .down)
    }

    func showLogiToast(_ message: String, severity: LogiToastSeverity) {
        let style: Toast.Style
        switch severity {
        case .info:    style = .info
        case .warning: style = .warning
        case .error:   style = .error
        }
        Toast.show(message, style: style)
    }
}
