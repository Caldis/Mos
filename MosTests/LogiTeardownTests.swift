import IOKit
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

    // MARK: - BLE mice whose PrimaryUsage is Keyboard (M720 Triathlon, 0x046D:0xB015)

    /// Raw `DeviceUsagePairs` captured from an M720 over BLE: Keyboard, Mouse, Pointer, HID++ (0xFF43/0x0202).
    private let m720UsagePairs: [[String: Any]] = [
        ["DeviceUsagePage": 1, "DeviceUsage": 6],
        ["DeviceUsagePage": 1, "DeviceUsage": 2],
        ["DeviceUsagePage": 1, "DeviceUsage": 1],
        ["DeviceUsagePage": 0xFF43, "DeviceUsage": 0x0202],
    ]

    /// MX Mechanical-style keyboard: no Mouse collection.
    private let keyboardUsagePairs: [[String: Any]] = [
        ["DeviceUsagePage": 1, "DeviceUsage": 6],
        ["DeviceUsagePage": 12, "DeviceUsage": 1],
        ["DeviceUsagePage": 0xFF43, "DeviceUsage": 0x0202],
    ]

    func test_hasMouseCollection_readsDeviceUsagePairs() {
        XCTAssertTrue(LogiSessionManager.hasMouseCollection(m720UsagePairs))
        XCTAssertFalse(LogiSessionManager.hasMouseCollection(keyboardUsagePairs))
        XCTAssertFalse(LogiSessionManager.hasMouseCollection(nil))
        XCTAssertFalse(LogiSessionManager.hasMouseCollection("not an array"))
    }

    func test_shouldAttachSession_attachesBLEMouseWithKeyboardPrimaryUsage() {
        XCTAssertTrue(LogiSessionManager.shouldAttachSession(
            usagePage: 0x0001, usage: 0x0006, isBLE: true,
            hasMouseCollection: LogiSessionManager.hasMouseCollection(m720UsagePairs)
        ))
    }

    func test_shouldAttachSession_stillSkipsKeyboardsWithoutMouseCollection() {
        // #948: pure keyboards (BLE or not) keep being skipped.
        XCTAssertFalse(LogiSessionManager.shouldAttachSession(
            usagePage: 0x0001, usage: 0x0006, isBLE: true,
            hasMouseCollection: LogiSessionManager.hasMouseCollection(keyboardUsagePairs)
        ))
        XCTAssertFalse(LogiSessionManager.shouldAttachSession(
            usagePage: 0x0001, usage: 0x0006, isBLE: false, hasMouseCollection: true
        ))
    }

    func test_isHIDPPCandidate_acceptsBLEMouseWithKeyboardPrimaryUsage() {
        XCTAssertTrue(LogiDeviceSession.isHIDPPCandidate(
            isBLE: true, usagePage: 0x0001, usage: 0x0006, hasMouseCollection: true))
        XCTAssertFalse(LogiDeviceSession.isHIDPPCandidate(
            isBLE: true, usagePage: 0x0001, usage: 0x0006, hasMouseCollection: false))
        // Unchanged behavior.
        XCTAssertTrue(LogiDeviceSession.isHIDPPCandidate(
            isBLE: true, usagePage: 0x0001, usage: 0x0002, hasMouseCollection: false))
        XCTAssertFalse(LogiDeviceSession.isHIDPPCandidate(
            isBLE: false, usagePage: 0x0001, usage: 0x0006, hasMouseCollection: true))
        XCTAssertTrue(LogiDeviceSession.isHIDPPCandidate(
            isBLE: false, usagePage: 0xFF00, usage: 0x0001, hasMouseCollection: false))
    }

    // MARK: - Lock Screen / kIOReturnNotPermitted recovery for Keyboard-primary BLE mice

    func test_permissionDeniedAndKeyboardClientDetection() {
        XCTAssertTrue(LogiDeviceSession.isPermissionDeniedIOReturn(kIOReturnNotPermitted))
        XCTAssertTrue(LogiDeviceSession.isPermissionDeniedIOReturn(kIOReturnNotPrivileged))
        XCTAssertFalse(LogiDeviceSession.isPermissionDeniedIOReturn(kIOReturnSuccess))
        XCTAssertFalse(LogiDeviceSession.isPermissionDeniedIOReturn(kIOReturnNotOpen))

        XCTAssertTrue(LogiDeviceSession.requiresUnlockedKeyboardClient(usagePage: 0x0001, usage: 0x0006))
        XCTAssertFalse(LogiDeviceSession.requiresUnlockedKeyboardClient(usagePage: 0x0001, usage: 0x0002))
        XCTAssertFalse(LogiDeviceSession.requiresUnlockedKeyboardClient(usagePage: 0xFF43, usage: 0x0202))
    }

    func test_shouldReopenSessionsOnUnlock_andBoundedRetryRules() {
        XCTAssertFalse(LogiSessionManager.shouldReopenSessionsOnUnlock(
            isActive: false, anySessionNeedsReopen: true, anyCandidateIncomplete: true
        ))
        XCTAssertFalse(LogiSessionManager.shouldReopenSessionsOnUnlock(
            isActive: true, anySessionNeedsReopen: false, anyCandidateIncomplete: false
        ))
        XCTAssertTrue(LogiSessionManager.shouldReopenSessionsOnUnlock(
            isActive: true, anySessionNeedsReopen: true, anyCandidateIncomplete: false
        ))
        XCTAssertTrue(LogiSessionManager.shouldReopenSessionsOnUnlock(
            isActive: true, anySessionNeedsReopen: false, anyCandidateIncomplete: true
        ))

        XCTAssertEqual(LogiSessionManager.nextPermissionRetryDelay(completedAttempts: 0), 0.5)
        XCTAssertEqual(LogiSessionManager.nextPermissionRetryDelay(completedAttempts: 1), 1.5)
        XCTAssertEqual(LogiSessionManager.nextPermissionRetryDelay(completedAttempts: 2), 3.0)
        XCTAssertNil(LogiSessionManager.nextPermissionRetryDelay(completedAttempts: 3))

        XCTAssertFalse(LogiSessionManager.canAttemptLazyActivityRecovery(
            isScreenLocked: true, completedAttempts: 0, now: 100, lastAttemptTime: 0
        ))
        XCTAssertTrue(LogiSessionManager.canAttemptLazyActivityRecovery(
            isScreenLocked: false, completedAttempts: 0, now: 100, lastAttemptTime: 0
        ))
        XCTAssertFalse(LogiSessionManager.canAttemptLazyActivityRecovery(
            isScreenLocked: false, completedAttempts: 1, now: 101.5, lastAttemptTime: 100
        ))
        XCTAssertTrue(LogiSessionManager.canAttemptLazyActivityRecovery(
            isScreenLocked: false, completedAttempts: 1, now: 103.5, lastAttemptTime: 100
        ))
        XCTAssertFalse(LogiSessionManager.canAttemptLazyActivityRecovery(
            isScreenLocked: false, completedAttempts: 2, now: 110, lastAttemptTime: 100
        ))
    }

    func test_shouldRecoverIncompleteBLESession_distinguishesTimeoutFromUnsupportedFeature() {
        // Timed-out BLE candidate handshake (feature supported or unknown, activity idle) -> recover.
        XCTAssertTrue(LogiDeviceSession.shouldRecoverIncompleteBLESession(
            isBLEDirect: true,
            isCandidate: true,
            reprogInitComplete: false,
            reprogFeatureUnsupported: false,
            isActivityInProgress: false
        ))
        // Still in flight -> wait.
        XCTAssertFalse(LogiDeviceSession.shouldRecoverIncompleteBLESession(
            isBLEDirect: true,
            isCandidate: true,
            reprogInitComplete: false,
            reprogFeatureUnsupported: false,
            isActivityInProgress: true
        ))
        // Device genuinely lacks REPROG_CONTROLS_V4 -> do not reopen in a loop.
        XCTAssertFalse(LogiDeviceSession.shouldRecoverIncompleteBLESession(
            isBLEDirect: true,
            isCandidate: true,
            reprogInitComplete: false,
            reprogFeatureUnsupported: true,
            isActivityInProgress: false
        ))
    }

    func test_deliveryModeStore_resetAll_clearsContendedStateAcrossStop() {
        let store = LogiButtonDeliveryModeStore()
        let key = LogiOwnershipKey(
            vendorId: 0x046D,
            productId: 0xB015,
            name: "M720 Triathlon",
            transport: .bleDirect,
            cid: 0x005B
        )
        let t0 = Date(timeIntervalSince1970: 1_000)
        _ = store.recordExternalClear(for: key, at: t0)
        XCTAssertEqual(store.recordExternalClear(for: key, at: t0.addingTimeInterval(1)), .contended)

        store.resetAll()
        XCTAssertEqual(store.mode(for: key), .hidpp)
    }
}
