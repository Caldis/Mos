import XCTest
@testable import Mos_Debug

final class UsageRegistryTests: XCTestCase {

    func testSetUsage_sameCodes_doesNotScheduleRecompute() {
        var recomputeCount = 0
        let registry = UsageRegistry(sessionProvider: { [] }, onRecompute: {
            recomputeCount += 1
        })
        registry.setUsage(source: .buttonBinding, codes: [1006])
        // Drain the main queue so the async block runs.
        let drained = self.expectation(description: "main drain")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 1.0)
        XCTAssertEqual(recomputeCount, 1)

        // Identical codes again must NOT schedule another recompute.
        registry.setUsage(source: .buttonBinding, codes: [1006])
        let drained2 = self.expectation(description: "main drain 2")
        DispatchQueue.main.async { drained2.fulfill() }
        wait(for: [drained2], timeout: 1.0)
        XCTAssertEqual(recomputeCount, 1, "Identical setUsage should short-circuit before scheduling")
    }

    func testSetUsage_emptyCodes_removesSource() {
        let registry = UsageRegistry(sessionProvider: { [] }, onRecompute: {})
        registry.setUsage(source: .buttonBinding, codes: [1006])
        registry.setUsage(source: .buttonBinding, codes: [])
        XCTAssertNil(registry.sourcesForTests[.buttonBinding],
                     "Empty codes must removeValue, not store empty Set")
    }

    func testCoalescing_multipleSetUsage_singleRecompute() {
        var recomputeCount = 0
        let registry = UsageRegistry(sessionProvider: { [] }, onRecompute: {
            recomputeCount += 1
        })
        registry.setUsage(source: .buttonBinding, codes: [1006])
        registry.setUsage(source: .globalScroll(.dash), codes: [1007])
        registry.setUsage(source: .appScroll(key: "Chrome", role: .toggle), codes: [1005])
        let drained = self.expectation(description: "main drain")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 1.0)
        XCTAssertEqual(recomputeCount, 1, "3 setUsage in same task should collapse to 1 recompute")
    }
}
