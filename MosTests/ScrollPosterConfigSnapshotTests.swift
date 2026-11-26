import XCTest
@testable import Mos_Debug

final class ScrollPosterConfigSnapshotTests: XCTestCase {

    private var savedSim = false
    private var savedDead = 1.0
    private var savedNormalizeTiming = false
    private var savedApp: Application?

    override func setUp() {
        super.setUp()
        savedSim = Options.shared.scroll.smoothSimTrackpad
        savedDead = Options.shared.scroll.deadZone
        savedNormalizeTiming = Options.shared.scrollNormalizeTiming
        savedApp = ScrollCore.shared.application
    }

    override func tearDown() {
        Options.shared.scroll.smoothSimTrackpad = savedSim
        Options.shared.scroll.deadZone = savedDead
        Options.shared.scrollNormalizeTiming = savedNormalizeTiming
        ScrollCore.shared.application = savedApp
        super.tearDown()
    }

    /// 快照捕获后改动 live Options 不应影响已捕获的值 (证明快照而非实时读)
    func testConfigSnapshot_capturesValuesNotLiveReads() {
        ScrollCore.shared.application = nil
        Options.shared.scroll.smoothSimTrackpad = true
        Options.shared.scroll.deadZone = 7.0
        Options.shared.scrollNormalizeTiming = true

        ScrollPoster.shared.captureConfigSnapshotForTests()

        // 改 live 值, 快照不应跟随
        Options.shared.scroll.smoothSimTrackpad = false
        Options.shared.scroll.deadZone = 1.0
        Options.shared.scrollNormalizeTiming = false

        let snap = ScrollPoster.shared.configSnapshotForTests
        XCTAssertTrue(snap.simTrackpadEnabled, "simTrackpadEnabled 应为捕获时的 true")
        XCTAssertEqual(snap.deadZone, 7.0, "deadZone 应为捕获时的 7.0")
        XCTAssertTrue(snap.normalizesTiming)
    }
}
