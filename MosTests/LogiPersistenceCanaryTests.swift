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

    func testDebugPanelLog_autoWritesLatestLocalLog() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MosLogiDebug-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        LogiDebugPanel.setTestingAutoLogDirectory(directory)
        defer { LogiDebugPanel.resetAutoLogForTests() }

        LogiDebugPanel.log(
            device: "Button Capture",
            type: .buttonEvent,
            message: "Forward standard mouse alias probe",
            decoded: "decoded payload",
            rawBytes: [0x01, 0xA4]
        )
        LogiDebugPanel.flushAutoLogForTests()

        let latestURL = directory.appendingPathComponent("hidpp-debug-latest.log")
        let latest = try String(contentsOf: latestURL, encoding: .utf8)

        XCTAssertTrue(latest.contains("[Button Capture] [Button] Forward standard mouse alias probe"))
        XCTAssertTrue(latest.contains("  > decoded payload"))
        XCTAssertTrue(latest.contains("  HEX: 01 A4"))
        XCTAssertTrue(LogiDebugPanel.currentAutoLogURLForTests?.lastPathComponent.hasPrefix("hidpp-debug-") ?? false)
    }
}
