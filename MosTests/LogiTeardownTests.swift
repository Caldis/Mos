import XCTest
@testable import Mos_Debug

/// Spec §4.4 / Round 4 M2 — emit `.up` via bridge before clearing per-session
/// state on each of: teardown, setTargetSlot, rediscoverFeatures, LogiCenter.stop.
/// Cannot construct LogiDeviceSession easily in unit tests; this case is
/// covered by Tier 3a real-device test (LogiBridgeDeviceTests, Task 4.4).
final class LogiTeardownTests: XCTestCase {
    func test_pathsCovered_byTier3a() {
        // Smoke marker for the test plan; full coverage is in Tier 3a.
        XCTAssertTrue(true)
    }

    // MARK: - Keyboard interface skip (issue #948)

    /// A Logitech keyboard interface must NOT get a session attached. Attaching
    /// one registers an input-report callback that keeps the keyboard's HID
    /// endpoint active, so it never sleeps and its backlight stays on (#948).
    /// `shouldAttachSession` gates session creation in `deviceConnected`.
    func test_shouldAttachSession_skipsKeyboardInterface() {
        // Generic Desktop (0x0001) Keyboard (0x0006) — e.g. MX Mechanical.
        XCTAssertFalse(
            LogiSessionManager.shouldAttachSession(usagePage: 0x0001, usage: 0x0006),
            "Keyboard interfaces must be skipped so the device can sleep / dim its backlight"
        )
    }

    func test_shouldAttachSession_attachesMouseAndHIDPPInterfaces() {
        // Generic Desktop Mouse (0x0002) — BLE HID++ candidate.
        XCTAssertTrue(LogiSessionManager.shouldAttachSession(usagePage: 0x0001, usage: 0x0002))
        // Vendor-specific HID++ interfaces (USB receiver / Bolt / Unifying).
        XCTAssertTrue(LogiSessionManager.shouldAttachSession(usagePage: 0xFF00, usage: 0x0000))
        XCTAssertTrue(LogiSessionManager.shouldAttachSession(usagePage: 0xFF43, usage: 0x0000))
        XCTAssertTrue(LogiSessionManager.shouldAttachSession(usagePage: 0xFFC0, usage: 0x0000))
        // Consumer Control interface some Logi devices also expose.
        XCTAssertTrue(LogiSessionManager.shouldAttachSession(usagePage: 0x000C, usage: 0x0001))
    }

    /// Regression guard: the skip must be keyboard-specific, not a blanket drop
    /// of the whole Generic Desktop usage page (which would also drop BLE mice).
    func test_shouldAttachSession_doesNotBlanketDropGenericDesktop() {
        // Generic Desktop Pointer (0x0001) must still attach.
        XCTAssertTrue(LogiSessionManager.shouldAttachSession(usagePage: 0x0001, usage: 0x0001),
                      "Pointer (Generic Desktop) must still attach")
    }
}
