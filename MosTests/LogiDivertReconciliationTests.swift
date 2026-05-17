import XCTest
@testable import Mos_Debug

final class LogiDivertReconciliationTests: XCTestCase {

    func testQueriedMissingDivertIsRemovedFromAppliedAndDivertedCIDs() {
        let result = LogiDeviceSession.reconciledDivertStateForTests(
            lastApplied: [0x0053, 0x0056],
            divertedCIDs: [0x0053, 0x0056, 0x0057],
            queriedControls: [
                .init(cid: 0x0053, reportingFlags: 0x00, reportingQueried: true),
                .init(cid: 0x0056, reportingFlags: 0x01, reportingQueried: true)
            ]
        )

        XCTAssertEqual(result.lastApplied, [0x0056])
        XCTAssertEqual(result.divertedCIDs, [0x0056, 0x0057])
    }

    func testStillDivertedCIDIsKept() {
        let result = LogiDeviceSession.reconciledDivertStateForTests(
            lastApplied: [0x0053],
            divertedCIDs: [0x0053],
            queriedControls: [
                .init(cid: 0x0053, reportingFlags: 0x01, reportingQueried: true)
            ]
        )

        XCTAssertEqual(result.lastApplied, [0x0053])
        XCTAssertEqual(result.divertedCIDs, [0x0053])
    }

    func testUnqueriedCIDIsKept() {
        let result = LogiDeviceSession.reconciledDivertStateForTests(
            lastApplied: [0x0053],
            divertedCIDs: [0x0053],
            queriedControls: [
                .init(cid: 0x0053, reportingFlags: 0x00, reportingQueried: false)
            ]
        )

        XCTAssertEqual(result.lastApplied, [0x0053])
        XCTAssertEqual(result.divertedCIDs, [0x0053])
    }

    func testStaleAppliedCIDAbsentFromQueriedControlsIsKept() {
        let result = LogiDeviceSession.reconciledDivertStateForTests(
            lastApplied: [0x0053, 0x9999],
            divertedCIDs: [0x0053, 0x9999],
            queriedControls: [
                .init(cid: 0x0053, reportingFlags: 0x01, reportingQueried: true)
            ]
        )

        XCTAssertEqual(result.lastApplied, [0x0053, 0x9999])
        XCTAssertEqual(result.divertedCIDs, [0x0053, 0x9999])
    }

    func testForeignSetControlReportingAckClearingOwnedDivertRequiresReassertion() {
        let cid = LogiDeviceSession.reassertionCIDForSetControlReportingAckForTests(
            lastApplied: [0x0053],
            divertedCIDs: [0x0053],
            ackBytes: [0x11, 0xFF, 0x09, 0x31, 0x00, 0x53, 0x02, 0x00, 0x00],
            isOwnAck: false
        )

        XCTAssertEqual(cid, 0x0053)
    }

    func testOwnSetControlReportingAckClearingDivertDoesNotRequireReassertion() {
        let cid = LogiDeviceSession.reassertionCIDForSetControlReportingAckForTests(
            lastApplied: [0x0053],
            divertedCIDs: [0x0053],
            ackBytes: [0x11, 0xFF, 0x09, 0x31, 0x00, 0x53, 0x02, 0x00, 0x00],
            isOwnAck: true
        )

        XCTAssertNil(cid)
    }

    func testSetControlReportingAckKeepingDivertDoesNotRequireReassertion() {
        let cid = LogiDeviceSession.reassertionCIDForSetControlReportingAckForTests(
            lastApplied: [0x0053],
            divertedCIDs: [0x0053],
            ackBytes: [0x11, 0xFF, 0x09, 0x31, 0x00, 0x53, 0x03, 0x00, 0x00],
            isOwnAck: false
        )

        XCTAssertNil(cid)
    }

    func testReportingNotificationClearingOwnedDivertRequiresReassertion() {
        let cid = LogiDeviceSession.reassertionCIDForReportingStateForTests(
            lastApplied: [0x0053],
            divertedCIDs: [0x0053],
            bytes: [0x11, 0xFF, 0x09, 0x20, 0x00, 0x53, 0x00, 0x00, 0x00]
        )

        XCTAssertEqual(cid, 0x0053)
    }

    func testReportingNotificationKeepingDivertDoesNotRequireReassertion() {
        let cid = LogiDeviceSession.reassertionCIDForReportingStateForTests(
            lastApplied: [0x0053],
            divertedCIDs: [0x0053],
            bytes: [0x11, 0xFF, 0x09, 0x20, 0x00, 0x53, 0x01, 0x00, 0x00]
        )

        XCTAssertNil(cid)
    }

    func testExternalClearReassertsOnlyWhileHIDPPModeIsActive() {
        XCTAssertTrue(LogiDeviceSession.shouldReassertAfterExternalClearForTests(mode: .hidpp))
        XCTAssertFalse(LogiDeviceSession.shouldReassertAfterExternalClearForTests(mode: .contended))
    }

    func testUsageProjectionSkipsCIDsOutsideHIDPPDeliveryMode() {
        let target = LogiDeviceSession.targetCIDsForUsageForTests(
            aggregateMosCodes: [1006, 1007],
            divertableCIDs: [0x0053, 0x0056],
            deliveryModeForCID: { cid in
                cid == 0x0053 ? .contended : .hidpp
            }
        )

        XCTAssertEqual(target, [0x0056])
    }

    func testBLEPolicyExcludesNativeBackFromNormalTargets() {
        let target = LogiDeviceSession.targetCIDsForUsageForTests(
            aggregateMosCodes: [1006, 1002],
            divertableCIDs: [0x0053, 0x00D7],
            transport: .bleDirect,
            phase: .normal,
            policy: LogiButtonDeliveryPolicy(standardMouseButtonsUseNativeEvents: true),
            deliveryModeForCID: { _ in .hidpp }
        )

        XCTAssertEqual(target, [0x00D7])
    }

    func testBLEPolicyMarksNativeBackForNormalUndivertEvenWhenTargetExcludesIt() {
        let nativeFirst = LogiDeviceSession.nativeFirstCIDsForUsageForTests(
            aggregateMosCodes: [1006, 1002],
            divertableCIDs: [0x0053, 0x00D7],
            transport: .bleDirect,
            phase: .normal,
            policy: LogiButtonDeliveryPolicy(standardMouseButtonsUseNativeEvents: true)
        )

        XCTAssertEqual(nativeFirst, [0x0053])
    }

    func testBLEPolicyMarksRecordedNativeSideButtonsForNormalUndivert() {
        let nativeFirst = LogiDeviceSession.nativeFirstCIDsForUsageForTests(
            aggregateMosCodes: [3, 4, 2253],
            divertableCIDs: [0x0053, 0x0056, 0x00FD],
            transport: .bleDirect,
            phase: .normal,
            policy: LogiButtonDeliveryPolicy(standardMouseButtonsUseNativeEvents: true)
        )

        XCTAssertEqual(nativeFirst, [0x0053, 0x0056])
    }

    func testReceiverPolicyKeepsNativeBackInNormalTargets() {
        let target = LogiDeviceSession.targetCIDsForUsageForTests(
            aggregateMosCodes: [1006, 1002],
            divertableCIDs: [0x0053, 0x00D7],
            transport: .receiver,
            phase: .normal,
            policy: LogiButtonDeliveryPolicy(standardMouseButtonsUseNativeEvents: true),
            deliveryModeForCID: { _ in .hidpp }
        )

        XCTAssertEqual(target, [0x0053, 0x00D7])
    }

    func testRecordingPlannerUndivertsPreviouslyAppliedBLEStandardAlias() {
        let result = LogiDeviceSession.recordingDivertPlanForTests(
            divertableCIDs: [0x0053, 0x00D7],
            lastApplied: [0x0053],
            transport: .bleDirect,
            policy: LogiButtonDeliveryPolicy(standardMouseButtonsUseNativeEvents: true)
        )

        XCTAssertEqual(result.desired, [0x00D7])
        XCTAssertEqual(result.toDivert, [0x00D7])
        XCTAssertEqual(result.toUndivert, [0x0053])
    }

    func testRecordingPlannerProactivelyUndivertsBLEStandardAliasesEvenWhenNotLastApplied() {
        let result = LogiDeviceSession.recordingDivertPlanForTests(
            divertableCIDs: [0x0053, 0x0056, 0x00D7],
            lastApplied: [0x00D7],
            transport: .bleDirect,
            policy: LogiButtonDeliveryPolicy(standardMouseButtonsUseNativeEvents: true)
        )

        XCTAssertEqual(result.desired, [0x00D7])
        XCTAssertEqual(result.toDivert, [])
        XCTAssertEqual(result.toUndivert, [0x0053, 0x0056])
    }

    func testRecordingPlannerKeepsReceiverStandardAlias() {
        let result = LogiDeviceSession.recordingDivertPlanForTests(
            divertableCIDs: [0x0053, 0x00D7],
            lastApplied: [0x0053],
            transport: .receiver,
            policy: LogiButtonDeliveryPolicy(standardMouseButtonsUseNativeEvents: true)
        )

        XCTAssertEqual(result.desired, [0x0053, 0x00D7])
        XCTAssertEqual(result.toDivert, [0x00D7])
        XCTAssertEqual(result.toUndivert, [])
    }
}
