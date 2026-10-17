//
//  ScrollSourceFilterTests.swift
//  MosTests
//
//  Source identity, passthrough and backwards-compatible preferences regression tests.
//

import Cocoa
import XCTest
@testable import Mos_Debug

final class ScrollSourceFilterTests: XCTestCase {
    private let tourBox = "com.tourbox.ui.launch"

    private func event(sourcePID: Int64 = 42, targetPID: Int64 = 99) throws -> CGEvent {
        let event = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .line,
                                        wheelCount: 2, wheel1: -2, wheel2: 1, wheel3: 0))
        event.setIntegerValueField(.eventSourceUnixProcessID, value: sourcePID)
        event.setIntegerValueField(.eventTargetUnixProcessID, value: targetPID)
        return event
    }

    func testOnlyExcludedSourcePassesThrough() throws {
        let filter = ScrollSourceFilter(resolve: { $0 == 42 ? self.tourBox : "com.example.other" })
        filter.setExcludedBundleIdentifiers([tourBox])
        XCTAssertTrue(filter.shouldPassthrough(try event()))
        XCTAssertFalse(filter.shouldPassthrough(try event(sourcePID: 43)))
        // A target matching the excluded process must not exclude an unrelated source.
        XCTAssertFalse(filter.shouldPassthrough(try event(sourcePID: 43, targetPID: 42)))
    }

    func testHardwareUnknownAndEmptyListKeepExistingBehavior() throws {
        var lookups = 0
        let filter = ScrollSourceFilter(resolve: { _ in lookups += 1; return nil })
        XCTAssertFalse(filter.shouldPassthrough(try event()))
        XCTAssertEqual(lookups, 0)
        filter.setExcludedBundleIdentifiers([tourBox])
        for pid in [Int64(0), -1, Int64.max] {
            XCTAssertFalse(filter.shouldPassthrough(try event(sourcePID: pid)))
        }
        XCTAssertEqual(lookups, 0)
        XCTAssertFalse(filter.shouldPassthrough(try event()))
    }

    func testUserDataAndAstropadStyleEventsAreNotBlanketExcluded() throws {
        let filter = ScrollSourceFilter(resolve: { $0 == 42 ? self.tourBox : "com.example.astropad" })
        filter.setExcludedBundleIdentifiers([tourBox])
        let other = try event(sourcePID: 43)
        other.setIntegerValueField(.eventSourceUserData, value: 721485824)
        XCTAssertFalse(filter.shouldPassthrough(other), "Driver markers are not device identities")
        other.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        other.setIntegerValueField(.scrollWheelEventScrollPhase, value: 4)
        XCTAssertFalse(filter.shouldPassthrough(other), "Astropad keeps its existing trackpad path")
    }

    func testCacheAndConfigurationChanges() throws {
        var lookups = 0
        let filter = ScrollSourceFilter(resolve: { _ in lookups += 1; return self.tourBox })
        filter.setExcludedBundleIdentifiers([tourBox])
        let input = try event()
        XCTAssertTrue(filter.shouldPassthrough(input))
        XCTAssertTrue(filter.shouldPassthrough(input))
        XCTAssertEqual(lookups, 1)
        filter.setExcludedBundleIdentifiers([tourBox])
        XCTAssertTrue(filter.shouldPassthrough(input))
        XCTAssertEqual(lookups, 1, "Unrelated scroll setting changes must not invalidate the cache")
        filter.setExcludedBundleIdentifiers([])
        XCTAssertFalse(filter.shouldPassthrough(input))
        filter.setExcludedBundleIdentifiers([tourBox])
        XCTAssertTrue(filter.shouldPassthrough(input))
        XCTAssertEqual(lookups, 2)
    }

    func testProcessRestartAndPIDReuseReResolve() throws {
        var identifier = tourBox
        let filter = ScrollSourceFilter(resolve: { _ in identifier })
        filter.setExcludedBundleIdentifiers([tourBox])
        XCTAssertTrue(filter.shouldPassthrough(try event()))
        identifier = "com.example.other"
        filter.invalidateCache() // The same invalidation is used for workspace launch/termination.
        XCTAssertFalse(filter.shouldPassthrough(try event()))
        identifier = tourBox
        filter.invalidateCache()
        XCTAssertTrue(filter.shouldPassthrough(try event(sourcePID: 45)))
    }

    func testFailedLookupsRetryAndSuccessfulLookupsExpire() throws {
        var time: TimeInterval = 10
        var identifier: String?
        var lookups = 0
        let filter = ScrollSourceFilter(resolve: { _ in lookups += 1; return identifier }, now: { time })
        filter.setExcludedBundleIdentifiers([tourBox])
        let input = try event()
        XCTAssertFalse(filter.shouldPassthrough(input))
        identifier = tourBox
        XCTAssertFalse(filter.shouldPassthrough(input))
        XCTAssertEqual(lookups, 1)
        time += 1
        XCTAssertTrue(filter.shouldPassthrough(input))
        identifier = "com.example.other"
        time += 5
        XCTAssertFalse(filter.shouldPassthrough(input))
        XCTAssertEqual(lookups, 3)
    }

    func testCacheIsBounded() throws {
        var lookups = 0
        let filter = ScrollSourceFilter(resolve: { _ in lookups += 1; return self.tourBox })
        filter.setExcludedBundleIdentifiers([tourBox])
        for pid in 1...65 {
            XCTAssertTrue(filter.shouldPassthrough(try event(sourcePID: Int64(pid))))
        }
        XCTAssertTrue(filter.shouldPassthrough(try event(sourcePID: 1)))
        XCTAssertEqual(lookups, 66)
    }

    func testExcludedCallbackReturnsOriginalWithoutReversingOrSmoothing() throws {
        let identifier = try XCTUnwrap(NSRunningApplication.current.bundleIdentifier)
        let options = Options.shared
        let savedExclusions = options.excludedScrollSourceBundleIdentifiers
        let savedReverse = options.scroll.reverse
        let savedReverseVertical = options.scroll.reverseVertical
        let savedSmooth = options.scroll.smooth
        let savedToggle = ScrollCore.shared.toggleScroll
        defer {
            options.excludedScrollSourceBundleIdentifiers = savedExclusions
            options.scroll.reverse = savedReverse
            options.scroll.reverseVertical = savedReverseVertical
            options.scroll.smooth = savedSmooth
            ScrollCore.shared.toggleScroll = savedToggle
        }
        options.excludedScrollSourceBundleIdentifiers = [identifier]
        options.scroll.reverse = true
        options.scroll.reverseVertical = true
        options.scroll.smooth = true
        ScrollCore.shared.toggleScroll = true
        let input = try event(sourcePID: Int64(ProcessInfo.processInfo.processIdentifier))
        input.setIntegerValueField(.eventSourceUserData, value: 721485824)
        let fields: [CGEventField] = [.scrollWheelEventDeltaAxis1, .scrollWheelEventDeltaAxis2,
            .scrollWheelEventPointDeltaAxis1, .scrollWheelEventPointDeltaAxis2,
            .scrollWheelEventFixedPtDeltaAxis1, .scrollWheelEventFixedPtDeltaAxis2,
            .scrollWheelEventIsContinuous, .scrollWheelEventScrollPhase, .scrollWheelEventMomentumPhase,
            .eventSourceUnixProcessID, .eventTargetUnixProcessID, .eventSourceUserData]
        let before = fields.map { input.getDoubleValueField($0) }
        let proxy = try XCTUnwrap(CGEventTapProxy(bitPattern: 1))
        let output = ScrollCore.shared.scrollEventCallBack(proxy, .scrollWheel, input, nil)?.takeUnretainedValue()
        XCTAssertTrue(output === input)
        XCTAssertEqual(fields.map { input.getDoubleValueField($0) }, before)
    }

    func testOldPreferencesAndRoundTripDoNotChangeExistingKeys() throws {
        let suite = "Mos.ScrollSourceFilterTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "smooth")
        defaults.set(Data([1, 2, 3]), forKey: "applications")
        XCTAssertEqual(ScrollSourceExclusionStore.load(from: defaults), [])
        ScrollSourceExclusionStore.save([tourBox, "", tourBox, "com.example.other"], to: defaults)
        XCTAssertEqual(ScrollSourceExclusionStore.load(from: defaults), [tourBox, "com.example.other"])
        XCTAssertTrue(defaults.bool(forKey: "smooth"))
        XCTAssertEqual(defaults.data(forKey: "applications"), Data([1, 2, 3]))
        ScrollSourceExclusionStore.save([], to: defaults)
        XCTAssertEqual(ScrollSourceExclusionStore.load(from: defaults), [])
    }

    func testMalformedExclusionsDoNotChangeLegacyPreferences() throws {
        let suite = "Mos.ScrollSourceFilterTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: OptionItem.Scroll.Smooth)
        defaults.set("invalid", forKey: OptionItem.Scroll.ExcludedSourceBundleIdentifiers)
        XCTAssertEqual(ScrollSourceExclusionStore.load(from: defaults), [])
        XCTAssertTrue(defaults.bool(forKey: OptionItem.Scroll.Smooth))
    }

    func testExclusionsUseExistingScrollChangeNotifications() {
        let options = Options()
        var groups: [OptionsGroup] = []
        options.observe([.scroll]) { groups.append($0) }
        options.excludedScrollSourceBundleIdentifiers = [tourBox, tourBox, ""]
        XCTAssertEqual(options.excludedScrollSourceBundleIdentifiers, [tourBox])
        XCTAssertEqual(groups, [.scroll])
    }
}
