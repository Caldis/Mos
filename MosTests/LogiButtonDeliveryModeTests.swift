import XCTest
@testable import Mos_Debug

final class LogiButtonDeliveryModeTests: XCTestCase {

    func testBLEStandardAliasUsesNativeByDefault() {
        let policy = LogiButtonDeliveryPolicy.default

        XCTAssertFalse(policy.shouldUseHIDPPDelivery(
            transport: .bleDirect,
            cid: 0x0053,
            phase: .normal
        ))
    }

    func testBLENonStandardControlUsesHIDPPByDefault() {
        let policy = LogiButtonDeliveryPolicy.default

        XCTAssertTrue(policy.shouldUseHIDPPDelivery(
            transport: .bleDirect,
            cid: 0x00C3,
            phase: .normal
        ))
    }

    func testReceiverStandardAliasStillUsesHIDPP() {
        let policy = LogiButtonDeliveryPolicy.default

        XCTAssertTrue(policy.shouldUseHIDPPDelivery(
            transport: .receiver,
            cid: 0x0053,
            phase: .normal
        ))
    }

    func testInitialModeIsHIDPP() {
        let store = LogiButtonDeliveryModeStore()
        let key = LogiOwnershipKey(
            vendorId: 0x046D,
            productId: 0xB034,
            name: "LIFT",
            transport: .bleDirect,
            cid: 0x0053
        )

        XCTAssertEqual(store.mode(for: key), .hidpp)
    }

    func testRepeatedExternalClearPromotesStandardButtonToContended() {
        let store = LogiButtonDeliveryModeStore(clearWindow: 5, clearThreshold: 2)
        let key = LogiOwnershipKey(
            vendorId: 0x046D,
            productId: 0xB034,
            name: "LIFT",
            transport: .bleDirect,
            cid: 0x0053
        )
        let t0 = Date(timeIntervalSince1970: 100)

        XCTAssertEqual(store.recordExternalClear(for: key, at: t0), .hidpp)
        XCTAssertEqual(store.recordExternalClear(for: key, at: t0.addingTimeInterval(1)), .contended)
    }

    func testRepeatedExternalClearPromotesNonStandardCIDToContended() {
        let store = LogiButtonDeliveryModeStore(clearWindow: 5, clearThreshold: 2)
        let key = LogiOwnershipKey(
            vendorId: 0x046D,
            productId: 0xB034,
            name: "LIFT",
            transport: .bleDirect,
            cid: 0x00C3
        )
        let t0 = Date(timeIntervalSince1970: 100)

        _ = store.recordExternalClear(for: key, at: t0)
        XCTAssertEqual(store.recordExternalClear(for: key, at: t0.addingTimeInterval(1)), .contended)
    }

    func testClearWindowResetsAfterInterval() {
        let store = LogiButtonDeliveryModeStore(clearWindow: 5, clearThreshold: 2)
        let key = LogiOwnershipKey(
            vendorId: 0x046D,
            productId: 0xB034,
            name: "LIFT",
            transport: .bleDirect,
            cid: 0x0053
        )
        let t0 = Date(timeIntervalSince1970: 100)

        XCTAssertEqual(store.recordExternalClear(for: key, at: t0), .hidpp)
        XCTAssertEqual(store.recordExternalClear(for: key, at: t0.addingTimeInterval(6)), .hidpp)
    }

    func testDefaultClearWindowTreatsRecentExternalClearsAsContention() {
        let store = LogiButtonDeliveryModeStore()
        let key = LogiOwnershipKey(
            vendorId: 0x046D,
            productId: 0xB034,
            name: "LIFT",
            transport: .bleDirect,
            cid: 0x0053
        )
        let t0 = Date(timeIntervalSince1970: 100)

        XCTAssertEqual(store.recordExternalClear(for: key, at: t0), .hidpp)
        XCTAssertEqual(store.recordExternalClear(for: key, at: t0.addingTimeInterval(15)), .contended)
    }

    func testDeliveryModeLookupByMosCodeUsesActiveMode() {
        let store = LogiButtonDeliveryModeStore()
        let key = LogiOwnershipKey(
            vendorId: 0x046D,
            productId: 0xB034,
            name: "LIFT",
            transport: .bleDirect,
            cid: 0x0053
        )
        let t0 = Date(timeIntervalSince1970: 100)
        _ = store.recordExternalClear(for: key, at: t0)
        _ = store.recordExternalClear(for: key, at: t0.addingTimeInterval(1))

        XCTAssertEqual(store.deliveryMode(forMosCode: 1006, matching: [key]), .contended)
        XCTAssertNil(store.deliveryMode(forMosCode: 1007, matching: [key]))
    }

    func testDefaultButtonDeliveryPolicyUsesTwoSecondStandardUndivertGuardInterval() {
        let key = "LogiBLEStandardUndivertGuardInterval"
        let defaults = UserDefaults.standard
        let original = defaults.object(forKey: key)
        defaults.removeObject(forKey: key)
        defer {
            if let original {
                defaults.set(original, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }

        XCTAssertEqual(LogiButtonDeliveryPolicy.default.standardButtonUndivertGuardInterval, 2)
    }

    func testDefaultButtonDeliveryPolicyEnablesStandardUndivertGuard() {
        let key = "LogiBLEStandardUndivertGuardEnabled"
        let defaults = UserDefaults.standard
        let original = defaults.object(forKey: key)
        defaults.removeObject(forKey: key)
        defer {
            if let original {
                defaults.set(original, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }

        XCTAssertTrue(LogiButtonDeliveryPolicy.default.standardButtonUndivertGuardEnabled)
    }

    func testDiagnosisSessionPreferenceFollowsCurrentTransport() {
        let connectedReceiverRank = LogiSessionManager.diagnosisSessionRankForTests(
            transport: .receiver,
            receiverTargetConnected: true
        )
        let bleRank = LogiSessionManager.diagnosisSessionRankForTests(
            transport: .bleDirect,
            receiverTargetConnected: true
        )
        let disconnectedReceiverRank = LogiSessionManager.diagnosisSessionRankForTests(
            transport: .receiver,
            receiverTargetConnected: false
        )
        let unsupportedRank = LogiSessionManager.diagnosisSessionRankForTests(
            transport: .unsupported,
            receiverTargetConnected: false
        )

        XCTAssertLessThan(connectedReceiverRank, bleRank)
        XCTAssertLessThan(bleRank, disconnectedReceiverRank)
        XCTAssertLessThan(disconnectedReceiverRank, unsupportedRank)
    }

    func testStandardButtonUndivertPlannerClearsOnlyActiveTemporarilyDivertedTargets() {
        let planner = LogiBLEStandardButtonUndivertPlanner()

        let targets = planner.undivertTargets(
            activeNativeFirstCIDs: [0x0053, 0x0056],
            reportingFlagsByCID: [
                0x0053: 0x01,
                0x0056: 0x00,
                0x00FD: 0x01,
            ]
        )

        XCTAssertEqual(targets, [0x0053])
    }

    func testStandardButtonUndivertPlannerBuildsTargetedReportingQueries() {
        let planner = LogiBLEStandardButtonUndivertPlanner()

        let probes = planner.reportingQueryProbes(
            activeTargets: [0x00FD, 0x00D7],
            reprogFeatureIndex: 0x09
        )

        XCTAssertEqual(probes.map(\.targetCID), [0x00D7, 0x00FD])
        XCTAssertEqual(probes.map(\.featureIndex), [0x09, 0x09])
        XCTAssertEqual(probes.map(\.functionId), [2, 2])
        XCTAssertEqual(probes.map(\.params), [
            [0x00, 0xD7],
            [0x00, 0xFD],
        ])
    }

    func testStandardButtonUndivertPlannerDoesNotBuildReportingQueriesWithoutReprogFeature() {
        let planner = LogiBLEStandardButtonUndivertPlanner()

        let probes = planner.reportingQueryProbes(
            activeTargets: [0x00FD],
            reprogFeatureIndex: nil
        )

        XCTAssertTrue(probes.isEmpty)
    }

    func testDefaultRecordingStillDispatchesHIDPPRecordingEvents() {
        let manager = LogiSessionManager()

        manager.temporarilyDivertAll()

        XCTAssertTrue(manager.isRecording)
    }
}
