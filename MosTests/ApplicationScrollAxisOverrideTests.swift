import XCTest
@testable import Mos_Debug

/**
 * Per-app scroll axis sub-toggle (smooth/reverse × vertical/horizontal) overrides.
 *
 * These methods read the GLOBAL master toggle (`Options.shared.scroll.smooth` /
 * `reverse`) plus the resolved per-app target (`resolvedScrollOptions()`). They must
 * NOT also gate on the GLOBAL axis sub-toggle — otherwise a per-app (inherit=false)
 * checkbox that shows ON+enabled is silently ignored at runtime whenever the
 * corresponding global axis sub-toggle is off.
 */
final class ApplicationScrollAxisOverrideTests: XCTestCase {

    // Saved global scroll axis flags — restored in tearDown so every test starts clean.
    private var savedSmooth = false
    private var savedReverse = false
    private var savedSmoothVertical = false
    private var savedSmoothHorizontal = false
    private var savedReverseVertical = false
    private var savedReverseHorizontal = false

    override func setUp() {
        super.setUp()
        let scroll = Options.shared.scroll
        savedSmooth = scroll.smooth
        savedReverse = scroll.reverse
        savedSmoothVertical = scroll.smoothVertical
        savedSmoothHorizontal = scroll.smoothHorizontal
        savedReverseVertical = scroll.reverseVertical
        savedReverseHorizontal = scroll.reverseHorizontal
    }

    override func tearDown() {
        let scroll = Options.shared.scroll
        scroll.smooth = savedSmooth
        scroll.reverse = savedReverse
        scroll.smoothVertical = savedSmoothVertical
        scroll.smoothHorizontal = savedSmoothHorizontal
        scroll.reverseVertical = savedReverseVertical
        scroll.reverseHorizontal = savedReverseHorizontal
        super.tearDown()
    }

    // MARK: - Per-app override honored when the GLOBAL axis sub-toggle is off (inherit = false)

    /// Per-app smoothVertical=true (inherit=false) must override a globally-disabled smoothVertical.
    func testPerAppSmoothVerticalOverridesGlobalDisabledAxis() {
        Options.shared.scroll.smooth = true
        Options.shared.scroll.smoothVertical = false
        let app = Application(path: "/X")
        app.inherit = false
        app.scroll.smooth = true
        app.scroll.smoothVertical = true
        XCTAssertTrue(app.isSmoothVertical(false),
            "per-app smoothVertical=true (inherit=false) must override global smoothVertical=false")
    }

    /// Per-app smoothHorizontal=true (inherit=false) must override a globally-disabled smoothHorizontal.
    func testPerAppSmoothHorizontalOverridesGlobalDisabledAxis() {
        Options.shared.scroll.smooth = true
        Options.shared.scroll.smoothHorizontal = false
        let app = Application(path: "/X")
        app.inherit = false
        app.scroll.smooth = true
        app.scroll.smoothHorizontal = true
        XCTAssertTrue(app.isSmoothHorizontal(false),
            "per-app smoothHorizontal=true (inherit=false) must override global smoothHorizontal=false")
    }

    /// Per-app reverseVertical=true (inherit=false) must override a globally-disabled reverseVertical.
    func testPerAppReverseVerticalOverridesGlobalDisabledAxis() {
        Options.shared.scroll.reverse = true
        Options.shared.scroll.reverseVertical = false
        let app = Application(path: "/X")
        app.inherit = false
        app.scroll.reverse = true
        app.scroll.reverseVertical = true
        XCTAssertTrue(app.isReverseVertical(),
            "per-app reverseVertical=true (inherit=false) must override global reverseVertical=false")
    }

    /// Per-app reverseHorizontal=true (inherit=false) must override a globally-disabled reverseHorizontal.
    func testPerAppReverseHorizontalOverridesGlobalDisabledAxis() {
        Options.shared.scroll.reverse = true
        Options.shared.scroll.reverseHorizontal = false
        let app = Application(path: "/X")
        app.inherit = false
        app.scroll.reverse = true
        app.scroll.reverseHorizontal = true
        XCTAssertTrue(app.isReverseHorizontal(),
            "per-app reverseHorizontal=true (inherit=false) must override global reverseHorizontal=false")
    }

    // MARK: - inherit = true behavior preservation (must stay false when the global axis is off)

    /// inherit=true must follow the global smoothVertical (off here), unchanged by the fix.
    func testInheritTrueSmoothVerticalFollowsGlobalDisabledAxis() {
        Options.shared.scroll.smooth = true
        Options.shared.scroll.smoothVertical = false
        let app = Application(path: "/X")
        app.inherit = true
        XCTAssertFalse(app.isSmoothVertical(false),
            "inherit=true must follow global smoothVertical=false")
    }

    /// inherit=true must follow the global smoothHorizontal (off here), unchanged by the fix.
    func testInheritTrueSmoothHorizontalFollowsGlobalDisabledAxis() {
        Options.shared.scroll.smooth = true
        Options.shared.scroll.smoothHorizontal = false
        let app = Application(path: "/X")
        app.inherit = true
        XCTAssertFalse(app.isSmoothHorizontal(false),
            "inherit=true must follow global smoothHorizontal=false")
    }

    /// inherit=true must follow the global reverseVertical (off here), unchanged by the fix.
    func testInheritTrueReverseVerticalFollowsGlobalDisabledAxis() {
        Options.shared.scroll.reverse = true
        Options.shared.scroll.reverseVertical = false
        let app = Application(path: "/X")
        app.inherit = true
        XCTAssertFalse(app.isReverseVertical(),
            "inherit=true must follow global reverseVertical=false")
    }

    /// inherit=true must follow the global reverseHorizontal (off here), unchanged by the fix.
    func testInheritTrueReverseHorizontalFollowsGlobalDisabledAxis() {
        Options.shared.scroll.reverse = true
        Options.shared.scroll.reverseHorizontal = false
        let app = Application(path: "/X")
        app.inherit = true
        XCTAssertFalse(app.isReverseHorizontal(),
            "inherit=true must follow global reverseHorizontal=false")
    }

    // MARK: - block flag + per-app master toggle still respected (proves the fix is surgical)

    /// block=true must short-circuit isSmooth* to false regardless of a per-app override.
    func testSmoothBlockFlagShortCircuitsOverride() {
        Options.shared.scroll.smooth = true
        Options.shared.scroll.smoothVertical = true
        let app = Application(path: "/X")
        app.inherit = false
        app.scroll.smooth = true
        app.scroll.smoothVertical = true
        XCTAssertFalse(app.isSmoothVertical(true),
            "block=true must force isSmoothVertical false even when the override is on")
    }

    /// A per-app that turns the master toggle off must still disable that feature for the app.
    func testPerAppMasterOffDisablesFeature() {
        Options.shared.scroll.smooth = true
        Options.shared.scroll.smoothVertical = true
        let app = Application(path: "/X")
        app.inherit = false
        app.scroll.smooth = false        // master off for this app
        app.scroll.smoothVertical = true
        XCTAssertFalse(app.isSmoothVertical(false),
            "per-app smooth=false (inherit=false) must disable smoothVertical for the app")
    }
}
