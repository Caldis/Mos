import XCTest
@testable import Mos_Debug

final class LogiCenterPublicSurfaceTests: XCTestCase {

    func testIsLogiCode_known() {
        XCTAssertTrue(LogiCenter.shared.isLogiCode(1006))   // Back
        XCTAssertFalse(LogiCenter.shared.isLogiCode(42))    // arbitrary non-Logi
    }

    func testNameForMosCode_known() {
        let name = LogiCenter.shared.name(forMosCode: 1006)
        XCTAssertNotNil(name)
        XCTAssertFalse(name!.isEmpty)
    }

    func testActiveSessionsSnapshot_returnsArray() {
        let snapshot = LogiCenter.shared.activeSessionsSnapshot()
        // No assumption about content; just that the call succeeds.
        XCTAssertNotNil(snapshot)
    }

    func testNotificationNamesNonEmpty() {
        XCTAssertFalse(LogiCenter.sessionChanged.rawValue.isEmpty)
        XCTAssertFalse(LogiCenter.discoveryStateChanged.rawValue.isEmpty)
        XCTAssertFalse(LogiCenter.reportingDidComplete.rawValue.isEmpty)
        XCTAssertFalse(LogiCenter.activityChanged.rawValue.isEmpty)
        XCTAssertFalse(LogiCenter.conflictChanged.rawValue.isEmpty)
        XCTAssertFalse(LogiCenter.rawButtonEvent.rawValue.isEmpty)
        XCTAssertFalse(LogiCenter.buttonEventRelay.rawValue.isEmpty)
    }
}
