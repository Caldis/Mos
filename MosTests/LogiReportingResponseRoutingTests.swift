import XCTest
@testable import Mos_Debug

final class LogiReportingResponseRoutingTests: XCTestCase {

    func testFunction2SoftwareId1IsAQueryResponse() {
        XCTAssertTrue(LogiDeviceSession.isGetControlReportingQueryResponseForTests([
            0x11, 0xFF, 0x09, 0x21, 0x00, 0x53, 0x01, 0x00, 0x53
        ]))
    }

    func testFunction2SoftwareId0IsANotificationNotAQueryResponse() {
        XCTAssertFalse(LogiDeviceSession.isGetControlReportingQueryResponseForTests([
            0x11, 0xFF, 0x09, 0x20, 0x00, 0x53, 0x01, 0x00, 0x00
        ]))
    }

    func testReportingResponseMustMatchExpectedCID() {
        XCTAssertTrue(LogiDeviceSession.reportingResponseForTests(
            [0x11, 0xFF, 0x09, 0x21, 0x00, 0x53, 0x01, 0x00, 0x53],
            matchesExpectedCID: 0x0053
        ))

        XCTAssertFalse(LogiDeviceSession.reportingResponseForTests(
            [0x11, 0xFF, 0x09, 0x21, 0x00, 0x52, 0x01, 0x00, 0x52],
            matchesExpectedCID: 0x0053
        ))
    }

    func testNotificationDoesNotMatchExpectedCID() {
        XCTAssertFalse(LogiDeviceSession.reportingResponseForTests(
            [0x11, 0xFF, 0x09, 0x20, 0x00, 0x53, 0x01, 0x00, 0x53],
            matchesExpectedCID: 0x0053
        ))
    }

    func testSetControlReportingAckParsesCIDFlagsAndTarget() {
        let ack = LogiDeviceSession.setControlReportingAckForTests([
            0x11, 0xFF, 0x09, 0x31, 0x00, 0x53, 0x02, 0x00, 0x00
        ])

        XCTAssertEqual(ack?.cid, 0x0053)
        XCTAssertEqual(ack?.flagsByte, 0x02)
        XCTAssertEqual(ack?.targetCID, 0x0000)
    }

    func testSetControlReportingAckRequiresFunction3SoftwareId1() {
        XCTAssertNil(LogiDeviceSession.setControlReportingAckForTests([
            0x11, 0xFF, 0x09, 0x30, 0x00, 0x53, 0x02, 0x00, 0x00
        ]))
    }

    func testReportingStateNotificationParsesFunction2SoftwareId0() {
        let notification = LogiDeviceSession.reportingStateNotificationForTests([
            0x11, 0xFF, 0x09, 0x20, 0x00, 0x53, 0x00, 0x00, 0x00
        ])

        XCTAssertEqual(notification?.cid, 0x0053)
        XCTAssertEqual(notification?.reportingFlags, 0x00)
        XCTAssertEqual(notification?.targetCID, 0x0000)
    }

    func testFunction0SoftwareId0IsDivertedButtonEvent() {
        XCTAssertTrue(LogiDeviceSession.isDivertedButtonEventForTests([
            0x11, 0xFF, 0x09, 0x00, 0x00, 0x53, 0x00, 0x00, 0x00
        ]))
    }

    func testFunction0SoftwareId1IsNotDivertedButtonEvent() {
        XCTAssertFalse(LogiDeviceSession.isDivertedButtonEventForTests([
            0x11, 0xFF, 0x09, 0x01, 0x07, 0x00, 0x00, 0x00, 0x00
        ]))
    }

    func testInitPhaseFunction0SoftwareId0RoutesAsButtonEvent() {
        XCTAssertEqual(
            LogiDeviceSession.reprogInitFunction0RouteForTests([
                0x11, 0xFF, 0x09, 0x00, 0x00, 0x53, 0x00, 0x00, 0x00
            ]),
            .divertedButtonEvent
        )
    }

    func testInitPhaseFunction0SoftwareId1RoutesAsControlCountResponse() {
        XCTAssertEqual(
            LogiDeviceSession.reprogInitFunction0RouteForTests([
                0x11, 0xFF, 0x09, 0x01, 0x07, 0x00, 0x00, 0x00, 0x00
            ]),
            .getControlCountResponse
        )
    }

    func testBLEControlInfoTimeoutRetriesBeforeSkipping() {
        XCTAssertTrue(LogiDeviceSession.shouldRetryControlInfoTimeoutForTests(
            connectionMode: .bleDirect,
            retryCount: 0
        ))
        XCTAssertFalse(LogiDeviceSession.shouldRetryControlInfoTimeoutForTests(
            connectionMode: .bleDirect,
            retryCount: 1
        ))
    }

    func testReceiverControlInfoTimeoutDoesNotRetry() {
        XCTAssertFalse(LogiDeviceSession.shouldRetryControlInfoTimeoutForTests(
            connectionMode: .receiver,
            retryCount: 0
        ))
    }

    func testIRootPingResponseIsNotADivertedButtonEvent() {
        let pingResponse: [UInt8] = [
            0x11, 0xFF, 0x00, 0x11, 0x07, 0x00, 0x00, 0x00, 0x00
        ]

        XCTAssertTrue(LogiDeviceSession.isIRootPingResponseForTests(pingResponse))
        XCTAssertFalse(LogiDeviceSession.isDivertedButtonEventForTests(pingResponse))
    }
}
