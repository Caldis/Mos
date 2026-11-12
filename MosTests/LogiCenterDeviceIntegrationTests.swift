import XCTest
@testable import Mos_Debug

class LogiDeviceIntegrationBase: XCTestCase {
    static var hasDevice: Bool {
        ProcessInfo.processInfo.environment["LOGI_REAL_DEVICE"] == "1"
    }
    override func setUpWithError() throws {
        try XCTSkipUnless(Self.hasDevice, "requires LOGI_REAL_DEVICE=1")
    }
}

final class LogiCenterDeviceIntegrationTests: LogiDeviceIntegrationBase {

    /// Tier 3a baseline (Step 3 scope): verify the registry+facade round-trip
    /// reaches a real device. Hardware read-back of reportingFlags is deferred
    /// to Task 4.4 (bridge-driven dispatch makes the round-trip signal natural).
    /// This test asserts:
    ///   1. LogiCenter.start() establishes at least one HID++ session.
    ///   2. setUsage(.buttonBinding, codes: [...]) registers the source.
    ///   3. setUsage(.buttonBinding, codes: []) removes the source.
    /// LogiOpti+ ownership of CID 0x0053 does NOT block this test (registry
    /// state is local to Mos).
    func testBaselineTransition_BackButton() throws {
        // 1. Wait for first session ready (best-effort; some setups may not have
        //    a Logi mouse with REPROG_V4 reachable). XCTSkip if no session.
        let sessionExp = expectation(forNotification: LogiCenter.reportingDidComplete, object: nil)
        LogiCenter.shared.start()
        let waitResult = XCTWaiter.wait(for: [sessionExp], timeout: 30)
        try XCTSkipIf(waitResult != .completed, "No Logi HID++ session became ready in 30s")
        try XCTSkipIf(LogiCenter.shared.activeSessionsSnapshot().isEmpty, "No active session")

        // 2. Apply Mos divert: registry should record the buttonBinding source.
        LogiCenter.shared.setUsage(source: .buttonBinding, codes: [1006])  // MosCode for Back
        drainMainQueue()
        XCTAssertTrue(LogiCenter.shared.usages(of: 1006).contains(.buttonBinding),
                      "After setUsage([.buttonBinding: 1006]), usages(1006) should report .buttonBinding")

        // 3. Clear: registry should remove the source.
        LogiCenter.shared.setUsage(source: .buttonBinding, codes: [])
        drainMainQueue()
        XCTAssertFalse(LogiCenter.shared.usages(of: 1006).contains(.buttonBinding),
                       "After setUsage([.buttonBinding: []]), usages(1006) should NOT report .buttonBinding")
    }

    /// Drain the main queue so UsageRegistry's coalesced async recompute fires
    /// before the next assertion.
    private func drainMainQueue() {
        let exp = expectation(description: "main-drain")
        DispatchQueue.main.async { exp.fulfill() }
        wait(for: [exp], timeout: 1.0)
    }

    /// Kept private to indicate this read path will be revived in Task 4.4
    /// once bridge-driven dispatch provides a deterministic post-write signal.
    private func readReportingBit0(snapshot: LogiDeviceSessionSnapshot, cid: UInt16) -> Bool {
        guard let ctrl = snapshot.discoveredControls.first(where: { $0.cid == cid }) else { return false }
        return (ctrl.reportingFlags & 0x01) != 0
    }
}
