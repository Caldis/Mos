import XCTest
@testable import Mos_Debug

/// Tier 3b — feature action smoke through the facade against a real device.
/// True hardware register read-back is deferred to Step 5 once the snapshot
/// surfaces a DPI accessor. For now, this test verifies the facade call
/// doesn't crash and a session is reachable.
final class LogiFeatureActionDeviceTests: LogiDeviceIntegrationBase {

    func testExecuteDPICycle_doesNotCrash() throws {
        if !(LogiCenter.shared.externalBridge is LogiIntegrationBridge) {
            LogiCenter.shared.installBridge(LogiIntegrationBridge.shared)
        }

        // If a previous test already brought sessions up, skip the wait-for-ready.
        if LogiCenter.shared.activeSessionsSnapshot().isEmpty {
            let ready = expectation(forNotification: LogiCenter.reportingDidComplete, object: nil)
            LogiCenter.shared.start()
            let waitResult = XCTWaiter.wait(for: [ready], timeout: 30)
            try XCTSkipIf(waitResult != .completed, "No HID++ session became ready in 30s")
        }
        try XCTSkipIf(LogiCenter.shared.activeSessionsSnapshot().isEmpty, "No active session")

        // Fire DPI cycle in both directions; must not crash.
        // Hardware register validation is deferred (TODO Step 5: expose DPI in snapshot).
        LogiCenter.shared.executeDPICycle(direction: .up)
        Thread.sleep(forTimeInterval: 0.5)
        LogiCenter.shared.executeDPICycle(direction: .down)
        Thread.sleep(forTimeInterval: 0.5)

        // Smoke: facade is still alive after feature action.
        XCTAssertNotNil(LogiCenter.shared)
    }
}
