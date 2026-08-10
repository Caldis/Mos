import Foundation
@testable import Mos_Debug

/// Test double for LogiExternalBridge. Records all incoming calls so tests can
/// assert routing/ordering. InputEvent is not Equatable (it carries CGEvent
/// in `.cgEvent` source), so Call captures the event by reference and tests
/// must inspect properties directly rather than using `==`.
final class FakeLogiExternalBridge: LogiExternalBridge {
    enum Call {
        case dispatch(InputEvent)
        case scrollHotkey(code: UInt16, phase: InputPhase)
        case toast(String, LogiToastSeverity)
    }
    var calls: [Call] = []
    var dispatchReturn: LogiDispatchResult = .unhandled

    func dispatchLogiButtonEvent(_ event: InputEvent) -> LogiDispatchResult {
        calls.append(.dispatch(event))
        return dispatchReturn
    }
    func handleLogiScrollHotkey(code: UInt16, phase: InputPhase) {
        calls.append(.scrollHotkey(code: code, phase: phase))
    }
    func showLogiToast(_ message: String, severity: LogiToastSeverity) {
        calls.append(.toast(message, severity))
    }
}
