import XCTest
@testable import Mos_Debug

final class LogiPersistenceCanaryTests: XCTestCase {

    /// Hard-coded golden list. NEVER derive this from production code; that defeats the canary.
    /// If this list is updated to add a new entry, the change MUST be intentional and reviewed.
    private static let frozenAutosaveNames: [String] = [
        "HIDDebug.FeaturesControls.v3",
    ]

    func testFeatureCacheKey_unchanged() {
        XCTAssertEqual(LogiDeviceSession.featureCacheKeyForTests, "logitechFeatureCache",
                       "UserDefaults key 'logitechFeatureCache' MUST NOT change — would invalidate user feature cache on upgrade.")
    }

    func testAutosaveNames_match_golden() {
        let production = LogiDebugPanel.autosaveNamesSnapshotForTests.sorted()
        let golden = Self.frozenAutosaveNames.sorted()
        XCTAssertEqual(production, golden,
                       "Debug panel autosave names drifted from frozen golden list. If intentional, update LogiPersistenceCanaryTests.frozenAutosaveNames.")
    }
}
