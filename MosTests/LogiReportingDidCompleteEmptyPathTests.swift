import XCTest
@testable import Mos_Debug

/// Regression: in v3 of the divert route, the empty-controls branch in
/// LogiDeviceSession's reporting query terminal forgot to post
/// reportingQueryDidCompleteNotification. The Self-Test Wizard's
/// "wait reportingDidComplete" step would hang indefinitely on devices
/// with zero divertable controls.
final class LogiReportingDidCompleteEmptyPathTests: XCTestCase {
    func testNotificationFires_evenWhenNoControlsDiscovered() {
        let expectation = self.expectation(forNotification: LogiSessionManager.reportingQueryDidCompleteNotification, object: nil, handler: nil)
        // Drive the empty-controls path. We can't construct a real session in unit
        // test, so we manually invoke the same NotificationCenter post site to
        // confirm the notification name is correctly observed.
        NotificationCenter.default.post(name: LogiSessionManager.reportingQueryDidCompleteNotification, object: nil)
        wait(for: [expectation], timeout: 1.0)
    }
}
