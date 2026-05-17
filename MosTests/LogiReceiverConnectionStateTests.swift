import XCTest
@testable import Mos_Debug

final class LogiReceiverConnectionStateTests: XCTestCase {

    func testBLEIsAlwaysSendableForReceiverTargetChecks() {
        XCTAssertTrue(LogiDeviceSession.receiverTargetIsConnectedForTests(
            connectionMode: .bleDirect,
            deviceIndex: 0xFF,
            pairedDevices: []
        ))
    }

    func testKnownDisconnectedReceiverTargetIsNotSendable() {
        XCTAssertFalse(LogiDeviceSession.receiverTargetIsConnectedForTests(
            connectionMode: .receiver,
            deviceIndex: 0x03,
            pairedDevices: [
                .init(slot: 0x03, isConnected: false)
            ]
        ))
    }

    func testUnknownReceiverTargetDefaultsToSendable() {
        XCTAssertTrue(LogiDeviceSession.receiverTargetIsConnectedForTests(
            connectionMode: .receiver,
            deviceIndex: 0x03,
            pairedDevices: []
        ))
    }

    func testReconnectWithCompleteControlCacheRefreshesReporting() {
        XCTAssertEqual(LogiDeviceSession.receiverReconnectActionForTests(
            hasReprogFeature: true,
            discoveredControlCount: 7,
            reprogControlCount: 7,
            hasInflightWork: false
        ), .refreshReporting)
    }

    func testReconnectWithPartialControlCacheRediscoveresFeatures() {
        XCTAssertEqual(LogiDeviceSession.receiverReconnectActionForTests(
            hasReprogFeature: true,
            discoveredControlCount: 3,
            reprogControlCount: 7,
            hasInflightWork: false
        ), .rediscoverFeatures)
    }

    func testReconnectWhileWorkIsInFlightDoesNothing() {
        XCTAssertEqual(LogiDeviceSession.receiverReconnectActionForTests(
            hasReprogFeature: true,
            discoveredControlCount: 7,
            reprogControlCount: 7,
            hasInflightWork: true
        ), .ignore)
    }

    func testConnectedNonCurrentSlotRetargetsWhenCurrentTargetIsDisconnected() {
        XCTAssertEqual(LogiDeviceSession.receiverConnectionNotificationActionForTests(
            currentDeviceIndex: 0x01,
            incomingDeviceIndex: 0x03,
            connected: true,
            currentTargetIsConnected: false,
            reprogInitComplete: false,
            hasInflightWork: false
        ), .retarget(0x03))
    }

    func testConnectedNonCurrentSlotDoesNotRetargetWhenCurrentTargetIsReady() {
        XCTAssertEqual(LogiDeviceSession.receiverConnectionNotificationActionForTests(
            currentDeviceIndex: 0x01,
            incomingDeviceIndex: 0x03,
            connected: true,
            currentTargetIsConnected: true,
            reprogInitComplete: true,
            hasInflightWork: false
        ), .ignore)
    }
}
