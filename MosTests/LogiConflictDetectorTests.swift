import XCTest
@testable import Mos_Debug

final class LogiConflictDetectorTests: XCTestCase {

    private let cid: UInt16 = 0x0053

    func testNotQueried_unknown() {
        let s = LogiConflictDetector.status(reportingFlags: 0, targetCID: 0, cid: cid, reportingQueried: false, mosOwnsDivert: false)
        XCTAssertEqual(s, .unknown)
    }

    func testForeignDivert_flagsNonZero_notMos() {
        let s = LogiConflictDetector.status(reportingFlags: 0x01, targetCID: 0, cid: cid, reportingQueried: true, mosOwnsDivert: false)
        XCTAssertEqual(s, .foreignDivert)
        XCTAssertTrue(s.isConflict)
    }

    func testMosOwned_pureNoForeign() {
        let s = LogiConflictDetector.status(
            reportingFlags: 0,      // no foreign bit
            targetCID: 0,
            cid: cid,
            reportingQueried: true,
            mosOwnsDivert: true     // mos owns it cleanly
        )
        XCTAssertEqual(s, .mosOwned)
        XCTAssertFalse(s.isConflict)
    }

    func testMosOwned_whenTemporaryDivertIsActiveAndMosOwnsIt() {
        let s = LogiConflictDetector.status(
            reportingFlags: 0x01,   // tmpDivert is expected after Mos owns divert
            targetCID: 0,
            cid: cid,
            reportingQueried: true,
            mosOwnsDivert: true
        )
        XCTAssertEqual(s, .mosOwned)
        XCTAssertFalse(s.isConflict)
    }

    func testRemapped_targetDiffers() {
        let s = LogiConflictDetector.status(reportingFlags: 0, targetCID: 0x0050, cid: cid, reportingQueried: true, mosOwnsDivert: false)
        XCTAssertEqual(s, .remapped)
        XCTAssertTrue(s.isConflict)
    }

    func testForeignBeatsRemap_whenBothPresent() {
        let s = LogiConflictDetector.status(reportingFlags: 0x01, targetCID: 0x0050, cid: cid, reportingQueried: true, mosOwnsDivert: false)
        XCTAssertEqual(s, .foreignDivert, "Foreign divert takes precedence over remap when both present")
    }

    func testClear_allZero() {
        let s = LogiConflictDetector.status(reportingFlags: 0, targetCID: 0, cid: cid, reportingQueried: true, mosOwnsDivert: false)
        XCTAssertEqual(s, .clear)
        XCTAssertFalse(s.isConflict)
    }

    func testSelfRemap_isClear() {
        let s = LogiConflictDetector.status(reportingFlags: 0, targetCID: cid, cid: cid, reportingQueried: true, mosOwnsDivert: false)
        XCTAssertEqual(s, .clear)
    }
}
