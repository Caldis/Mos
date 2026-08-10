// Mos/Logi/LogiExternalBridge.swift
import Foundation

/// Outward-facing contract from Logi to integrations. Step 2 introduces stubs
/// (only handleLogiScrollHotkey called; dispatchLogiButtonEvent and showLogiToast
/// added in Step 4 alongside production wiring). Lives inside Mos/Logi/ but is
/// `internal` access — same Xcode target as InputEvent / InputPhase, which it
/// references; making it `public` would force those types public too.
internal protocol LogiExternalBridge: AnyObject {
    func dispatchLogiButtonEvent(_ event: InputEvent) -> LogiDispatchResult
    func handleLogiScrollHotkey(code: UInt16, phase: InputPhase)
    func showLogiToast(_ message: String, severity: LogiToastSeverity)
}

internal enum LogiDispatchResult: Equatable {
    case consumed
    case unhandled
    case logiAction(name: String)
}

internal enum LogiToastSeverity {
    case info, warning, error
}
