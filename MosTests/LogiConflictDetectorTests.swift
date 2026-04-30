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

    func testCoDivert_mosAndForeignBothDivert() {
        let s = LogiConflictDetector.status(
            reportingFlags: 0x01,   // foreign set the bit
            targetCID: 0,
            cid: cid,
            reportingQueried: true,
            mosOwnsDivert: true     // mos also set divert
        )
        XCTAssertEqual(s, .coDivert)
        XCTAssertTrue(s.isConflict, "co-divert must surface as conflict so user sees the double-fire risk")
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
