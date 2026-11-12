import XCTest
@testable import Mos_Debug

final class UsageRegistryEndToEndTests: XCTestCase {

    private var session: FakeLogiDeviceSession!

    override func setUp() {
        super.setUp()
        session = FakeLogiDeviceSession()
        session.divertableCIDs = [0x0050, 0x0051, 0x0052, 0x0053, 0x0056]
    }

    func testCoalescedDrain_multipleSetUsage_singleRecompute() {
        var recomputeCount = 0
        let registry = UsageRegistry(sessionProvider: { [] }) {
            recomputeCount += 1
        }
        // Multiple setUsage in the same main-queue tick should collapse to 1 recompute.
        registry.setUsage(source: .buttonBinding, codes: [1006])
        registry.setUsage(source: .globalScroll(.dash), codes: [1007])
        registry.setUsage(source: .appScroll(key: "Chrome", role: .toggle), codes: [1005])
        let drained = expectation(description: "main drain")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 1.0)
        XCTAssertEqual(recomputeCount, 1, "3 setUsage in same tick should trigger 1 recompute")
    }

    func testReconnectNoDiff_freshSessionApplyAggregate() {
        // Models reconnect-no-diff: registry holds the source map, and a freshly
        // arrived session must apply the aggregate even though sources haven't
        // changed since the previous session disconnected. We verify the fake's
        // diff math correctly produces the divertedCIDs Set, since real
        // LogiDeviceSession integration is exercised in Tier 3a (Task 3.14).
        let registry = UsageRegistry(sessionProvider: { [] })
        registry.setUsage(source: .buttonBinding, codes: [1006])
        let drained = expectation(description: "drain")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 1.0)

        // Fresh session arrives. Apply the aggregate as the prime path would.
        let s2 = FakeLogiDeviceSession()
        s2.divertableCIDs = session.divertableCIDs
        s2.applyUsage([1006])
        XCTAssertEqual(s2.divertedCIDs, [0x0053])  // CID for MosCode 1006 (Back)
        XCTAssertEqual(s2.applyUsageCallCount, 1)
        XCTAssertEqual(s2.lastApplied, [0x0053])
    }

    func testInheritToggle_lifecycle() {
        // App delete / inherit-true / inherit-false transitions per Round 4 L1.
        let registry = UsageRegistry(sessionProvider: { [] })
        let key = "Chrome.app"
        registry.setUsage(source: .appScroll(key: key, role: .dash), codes: [1007])
        XCTAssertNotNil(registry.sourcesForTests[.appScroll(key: key, role: .dash)])

        // inherit toggled true -> clear all 3 roles
        for role: ScrollRole in [.dash, .toggle, .block] {
            registry.setUsage(source: .appScroll(key: key, role: role), codes: [])
        }
        for role: ScrollRole in [.dash, .toggle, .block] {
            XCTAssertNil(registry.sourcesForTests[.appScroll(key: key, role: role)])
        }

        // inherit toggled false -> re-push
        registry.setUsage(source: .appScroll(key: key, role: .toggle), codes: [1005])
        XCTAssertEqual(registry.sourcesForTests[.appScroll(key: key, role: .toggle)], [1005])

        // app deletion -> clear all 3 again
        for role: ScrollRole in [.dash, .toggle, .block] {
            registry.setUsage(source: .appScroll(key: key, role: role), codes: [])
        }
        for role: ScrollRole in [.dash, .toggle, .block] {
            XCTAssertNil(registry.sourcesForTests[.appScroll(key: key, role: role)])
        }
    }
}
