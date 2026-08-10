import XCTest
@testable import Mos_Debug

final class ButtonCapturePresentationStatusTests: XCTestCase {

    private let bleKey = LogiOwnershipKey(
        vendorId: 0x046D,
        productId: 0xB034,
        name: "BLE Mouse",
        transport: .bleDirect,
        cid: 0x0053
    )

    private let receiverKey = LogiOwnershipKey(
        vendorId: 0x046D,
        productId: 0xC548,
        name: "Bolt Mouse",
        transport: .receiver,
        cid: 0x0053
    )

    private let bleDPIKey = LogiOwnershipKey(
        vendorId: 0x046D,
        productId: 0xB034,
        name: "BLE Mouse",
        transport: .bleDirect,
        cid: 0x00FD
    )

    private let receiverDPIKey = LogiOwnershipKey(
        vendorId: 0x046D,
        productId: 0xC548,
        name: "Bolt Mouse",
        transport: .receiver,
        cid: 0x00FD
    )

    func testContendedPresentationStatusUsesDedicatedCopy() {
        let status = ButtonCapturePresentationStatus.contended

        XCTAssertTrue(status.shouldShowIndicator)
        XCTAssertFalse(status.keepsPopoverOpenOnMouseExit)
        XCTAssertEqual(status.titleKey, "button_contended_title")
        XCTAssertEqual(status.detailKey, "button_contended_detail")
    }

    func testStandardMouseAliasPresentationStatusUsesStandardMouseAliasCopy() {
        let status = ButtonCapturePresentationStatus.standardMouseAliasAvailable

        XCTAssertTrue(status.shouldShowIndicator)
        XCTAssertTrue(status.keepsPopoverOpenOnMouseExit)
        XCTAssertEqual(status.titleKey, "button_standard_mouse_alias_title")
        XCTAssertEqual(status.detailKey, "button_standard_mouse_alias_detail")
    }

    func testBLEHIDPPUnstablePresentationStatusUsesRiskCopy() {
        let status = ButtonCapturePresentationStatus.bleHIDPPUnstable

        XCTAssertTrue(status.shouldShowIndicator)
        XCTAssertFalse(status.keepsPopoverOpenOnMouseExit)
        XCTAssertEqual(status.titleKey, "button_ble_hidpp_unstable_title")
        XCTAssertEqual(status.detailKey, "button_ble_hidpp_unstable_detail")
    }

    func testConflictPresentationStatusRemainsHoverOnly() {
        let status = ButtonCapturePresentationStatus.conflict(.foreignDivert)

        XCTAssertTrue(status.shouldShowIndicator)
        XCTAssertFalse(status.keepsPopoverOpenOnMouseExit)
    }

    func testClearPresentationStatusDoesNotShowIndicator() {
        XCTAssertFalse(ButtonCapturePresentationStatus.normal.shouldShowIndicator)
    }

    func testDiagnosisDoesNotShowIndicatorForMosOwnedTemporaryDivert() {
        let diagnosis = LogiButtonCaptureDiagnosis(
            ownership: .mosOwned,
            delivery: .hidpp,
            ownershipKey: bleKey,
            nativeMouseButton: 3
        )

        XCTAssertEqual(ButtonCapturePresentationStatus.from(diagnosis), .normal)
    }

    func testDiagnosisShowsStandardMouseAliasOnlyForBLEContentionWithMappedButton() {
        let diagnosis = LogiButtonCaptureDiagnosis(
            ownership: .mosOwned,
            delivery: .contended,
            ownershipKey: bleKey,
            nativeMouseButton: 3
        )

        XCTAssertEqual(ButtonCapturePresentationStatus.from(diagnosis), .standardMouseAliasAvailable)
    }

    func testDiagnosisDoesNotUseStandardMouseAliasForReceiverContention() {
        let diagnosis = LogiButtonCaptureDiagnosis(
            ownership: .mosOwned,
            delivery: .contended,
            ownershipKey: receiverKey,
            nativeMouseButton: 3
        )

        XCTAssertEqual(ButtonCapturePresentationStatus.from(diagnosis), .contended)
    }

    func testDiagnosisDoesNotUseStandardMouseAliasWithoutLiveContention() {
        let diagnosis = LogiButtonCaptureDiagnosis(
            ownership: .clear,
            delivery: .hidpp,
            ownershipKey: bleKey,
            nativeMouseButton: 3
        )

        XCTAssertEqual(ButtonCapturePresentationStatus.from(diagnosis), .normal)
    }

    func testHistoricalBLEStandardAliasShowsStandardMouseAliasMigration() {
        let diagnosis = LogiButtonCaptureDiagnosis(
            ownership: .unknown,
            delivery: .hidpp,
            ownershipKey: bleKey,
            nativeMouseButton: 3,
            usesNativeEvents: true
        )

        XCTAssertEqual(ButtonCapturePresentationStatus.from(diagnosis), .standardMouseAliasAvailable)
    }

    func testBLEHIDPPOnlyControlShowsUnstableRisk() {
        let diagnosis = LogiButtonCaptureDiagnosis(
            ownership: .mosOwned,
            delivery: .hidpp,
            ownershipKey: bleDPIKey,
            nativeMouseButton: nil,
            usesNativeEvents: false
        )

        XCTAssertEqual(ButtonCapturePresentationStatus.from(diagnosis), .bleHIDPPUnstable)
    }

    func testReceiverHIDPPOnlyControlDoesNotShowBLERisk() {
        let diagnosis = LogiButtonCaptureDiagnosis(
            ownership: .mosOwned,
            delivery: .hidpp,
            ownershipKey: receiverDPIKey,
            nativeMouseButton: nil,
            usesNativeEvents: false
        )

        XCTAssertEqual(ButtonCapturePresentationStatus.from(diagnosis), .normal)
    }

    func testConfirmedHIDPPConflictTakesPriorityOverBLERisk() {
        let diagnosis = LogiButtonCaptureDiagnosis(
            ownership: .foreignDivert,
            delivery: .hidpp,
            ownershipKey: bleDPIKey,
            nativeMouseButton: nil,
            usesNativeEvents: false
        )

        XCTAssertEqual(ButtonCapturePresentationStatus.from(diagnosis), .conflict(.foreignDivert))
    }

    func testReceiverStandardAliasDoesNotShowStandardMouseAliasMigration() {
        let diagnosis = LogiButtonCaptureDiagnosis(
            ownership: .mosOwned,
            delivery: .hidpp,
            ownershipKey: receiverKey,
            nativeMouseButton: 3,
            usesNativeEvents: false
        )

        XCTAssertEqual(ButtonCapturePresentationStatus.from(diagnosis), .normal)
    }
}
