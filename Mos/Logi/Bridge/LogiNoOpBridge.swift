// Mos/Logi/LogiNoOpBridge.swift
import Foundation

/// Default LogiExternalBridge before Mos/Integration/LogiIntegrationBridge is
/// installed in Step 4. Steps 2 and 3 use this so the app boots; the call paths
/// that would invoke the bridge are not yet rewired in those steps.
internal final class LogiNoOpBridge: LogiExternalBridge {
    static let shared = LogiNoOpBridge()
    private init() {}
    func dispatchLogiButtonEvent(_ event: InputEvent) -> LogiDispatchResult { .unhandled }
    func handleLogiScrollHotkey(code: UInt16, phase: InputPhase) {}
    func showLogiToast(_ message: String, severity: LogiToastSeverity) {}
}
