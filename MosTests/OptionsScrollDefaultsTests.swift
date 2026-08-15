import XCTest
@testable import Mos_Debug

/// Regression tests for `Options.readOptions()`: the scroll `step` / `speed` /
/// `duration` defaults (33.6 / 2.70 / 4.35) must survive a missing UserDefaults
/// key — mirroring the existing `deadZone` nil-guard.
///
/// `UserDefaults.double(forKey:)` returns `0.0` (not `nil`) for a missing key,
/// which previously stomped those defaults. `speed == 0.0` is especially bad:
/// `ScrollPoster.update` scales the smoothing buffer by `speed`
/// (`buffer.y += y * speed * amplification`), so with a zero speed the buffer
/// never accumulates and no smoothed event is ever posted — scrolling in the
/// affected app dies entirely.
final class OptionsScrollDefaultsTests: XCTestCase {

    private let defaults = UserDefaults.standard

    // UserDefaults keys touched by these tests, restored 1:1 in tearDown.
    private var defaultsSnapshots: [(key: String, original: Any?)] = []
    // In-memory snapshot of every scroll field readOptions() writes, so the
    // shared singleton is left exactly as we found it.
    private var scrollSnapshot: ScrollSnapshot?

    private let expectedStep = OPTIONS_SCROLL_DEFAULT().step         // 33.6
    private let expectedSpeed = OPTIONS_SCROLL_DEFAULT().speed       // 2.70
    private let expectedDuration = OPTIONS_SCROLL_DEFAULT().duration // 4.35

    // MARK: - Missing key falls back to the OPTIONS_SCROLL_DEFAULT() value

    func testReadOptions_restoresSpeedDefault_whenKeyMissing() {
        // Mark "options exist" so readOptions() skips its first-run re-seed and
        // exercises the read path directly — modelling a partial-write state
        // where optionsExist is set but a scroll key is absent.
        snapshotUserDefaultsAndSet(OptionItem.General.OptionsExist, to: "optionsExist")
        snapshotUserDefaultsAndRemove(OptionItem.Scroll.Speed)
        Options.shared.readOptions()
        XCTAssertEqual(Options.shared.scroll.speed, expectedSpeed, accuracy: 1e-9,
                       "speed must fall back to 2.70 when its key is missing, not 0.0")
    }

    func testReadOptions_restoresStepAndDurationDefaults_whenKeysMissing() {
        snapshotUserDefaultsAndSet(OptionItem.General.OptionsExist, to: "optionsExist")
        snapshotUserDefaultsAndRemove(OptionItem.Scroll.Step)
        snapshotUserDefaultsAndRemove(OptionItem.Scroll.Duration)
        Options.shared.readOptions()
        XCTAssertEqual(Options.shared.scroll.step, expectedStep, accuracy: 1e-9,
                       "step must fall back to 33.6 when its key is missing, not 0.0")
        XCTAssertEqual(Options.shared.scroll.duration, expectedDuration, accuracy: 1e-9,
                       "duration must fall back to 4.35 when its key is missing, not 0.0")
    }

    // MARK: - A genuinely stored value is honoured (regression guard)

    func testReadOptions_keepsStoredValue_whenKeyPresent() {
        snapshotUserDefaultsAndSet(OptionItem.General.OptionsExist, to: "optionsExist")
        snapshotUserDefaultsAndSet(OptionItem.Scroll.Speed, to: 5.0)
        Options.shared.readOptions()
        XCTAssertEqual(Options.shared.scroll.speed, 5.0, accuracy: 1e-9,
                       "a real stored speed must not be overwritten by the default")
    }

    // MARK: - Invariant: a missing speed key must never deaden scrolling

    func testReadOptions_doesNotDeadenScrolling_whenSpeedKeyMissing() {
        // The default speed is the contract that scrolling keeps working even
        // when the key is absent; it must never resolve to 0.
        XCTAssertNotEqual(OPTIONS_SCROLL_DEFAULT().speed, 0.0)
        snapshotUserDefaultsAndSet(OptionItem.General.OptionsExist, to: "optionsExist")
        snapshotUserDefaultsAndRemove(OptionItem.Scroll.Speed)
        Options.shared.readOptions()
        XCTAssertNotEqual(Options.shared.scroll.speed, 0.0,
                          "missing speed key must never resolve to 0.0 (deadens scrolling)")
    }

    // MARK: - setUp / tearDown

    override func setUp() {
        super.setUp()
        scrollSnapshot = ScrollSnapshot(of: Options.shared.scroll)
    }

    override func tearDown() {
        // Restore UserDefaults first, then write the captured in-memory values
        // back into the shared singleton.
        for snapshot in defaultsSnapshots {
            if let original = snapshot.original {
                defaults.set(original, forKey: snapshot.key)
            } else {
                defaults.removeObject(forKey: snapshot.key)
            }
        }
        defaultsSnapshots.removeAll()
        scrollSnapshot?.restore(into: Options.shared.scroll)
        scrollSnapshot = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func snapshotUserDefaultsAndRemove(_ key: String) {
        defaultsSnapshots.append((key: key, original: defaults.object(forKey: key)))
        defaults.removeObject(forKey: key)
    }

    private func snapshotUserDefaultsAndSet(_ key: String, to value: Any) {
        defaultsSnapshots.append((key: key, original: defaults.object(forKey: key)))
        defaults.set(value, forKey: key)
    }
}

/// Value snapshot of the mutable `OPTIONS_SCROLL_DEFAULT` fields that
/// `readOptions()` writes, for deterministic single-instance teardown.
private struct ScrollSnapshot {
    let smooth: Bool
    let reverse: Bool
    let reverseVertical: Bool
    let reverseHorizontal: Bool
    let dash: ScrollHotkey?
    let toggle: ScrollHotkey?
    let block: ScrollHotkey?
    let step: Double
    let speed: Double
    let duration: Double
    let deadZone: Double
    let smoothSimTrackpad: Bool
    let smoothVertical: Bool
    let smoothHorizontal: Bool
    let durationBeforeSimTrackpadLock: Double?

    init(of scroll: OPTIONS_SCROLL_DEFAULT) {
        self.smooth = scroll.smooth
        self.reverse = scroll.reverse
        self.reverseVertical = scroll.reverseVertical
        self.reverseHorizontal = scroll.reverseHorizontal
        self.dash = scroll.dash
        self.toggle = scroll.toggle
        self.block = scroll.block
        self.step = scroll.step
        self.speed = scroll.speed
        self.duration = scroll.duration
        self.deadZone = scroll.deadZone
        self.smoothSimTrackpad = scroll.smoothSimTrackpad
        self.smoothVertical = scroll.smoothVertical
        self.smoothHorizontal = scroll.smoothHorizontal
        self.durationBeforeSimTrackpadLock = scroll.durationBeforeSimTrackpadLock
    }

    func restore(into scroll: OPTIONS_SCROLL_DEFAULT) {
        scroll.smooth = smooth
        scroll.reverse = reverse
        scroll.reverseVertical = reverseVertical
        scroll.reverseHorizontal = reverseHorizontal
        scroll.dash = dash
        scroll.toggle = toggle
        scroll.block = block
        scroll.step = step
        scroll.speed = speed
        scroll.duration = duration
        scroll.deadZone = deadZone
        scroll.smoothSimTrackpad = smoothSimTrackpad
        scroll.smoothVertical = smoothVertical
        scroll.smoothHorizontal = smoothHorizontal
        scroll.durationBeforeSimTrackpadLock = durationBeforeSimTrackpadLock
    }
}
