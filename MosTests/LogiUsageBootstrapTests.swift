import XCTest
@testable import Mos_Debug

final class LogiUsageBootstrapTests: XCTestCase {

    /// Smoke: refreshAll runs without crashing and reads Options without trapping.
    /// Cannot deterministically assert registry content because Options.shared has live state.
    func testRefreshAll_runsWithoutCrash() {
        LogiUsageBootstrap.refreshAll()
        XCTAssertNotNil(LogiCenter.shared)
    }
}
