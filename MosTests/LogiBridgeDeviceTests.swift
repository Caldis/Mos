import XCTest
@testable import Mos_Debug

/// Tier 3a — real-device bridge round-trip.
/// Validates rawButtonEvent fires when a real Logi button is pressed.
/// Interactive: tester must press the Back button within the timeout window.
/// Default timeout is short so the test SKIPS gracefully in unattended runs.
final class LogiBridgeDeviceTests: LogiDeviceIntegrationBase {

    /// Interactive test: requires a Back button press within `pressWindow`.
    /// Set `LOGI_INTERACTIVE_PRESS=1` to actually wait and validate; otherwise
    /// the test SKIPS so unattended LOGI_REAL_DEVICE=1 runs don't hang.
    func testRealButtonPressTriggersRawEvent() throws {
        let interactive = ProcessInfo.processInfo.environment["LOGI_INTERACTIVE_PRESS"] == "1"
        try XCTSkipUnless(interactive, "Set LOGI_INTERACTIVE_PRESS=1 and press Back button when prompted")

        // Ensure the bridge is wired (controller's AppDelegate did this for the
        // app process, but tests run in a separate executable — install here).
        if !(LogiCenter.shared.externalBridge is LogiIntegrationBridge) {
            LogiCenter.shared.installBridge(LogiIntegrationBridge.shared)
        }
        LogiCenter.shared.start()

        print("[LogiBridgeDeviceTests] Press the Back button on your Logi device within 30 seconds...")
        let exp = expectation(forNotification: LogiCenter.rawButtonEvent, object: nil) { notif in
            return (notif.userInfo?["mosCode"] as? UInt16) == 1006
        }
        let result = XCTWaiter.wait(for: [exp], timeout: 30)
        XCTAssertEqual(result, .completed, "rawButtonEvent for Back (mosCode 1006) was not observed within 30s")
    }
}
