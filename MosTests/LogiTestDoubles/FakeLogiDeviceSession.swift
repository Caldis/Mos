import Foundation
@testable import Mos_Debug

/// Test double that mirrors the planner contract: takes a MosCode aggregate,
/// projects to CIDs via LogiCIDDirectory.toCID, intersects with divertableCIDs,
/// and tracks divertedCIDs / lastApplied with a per-session diff.
final class FakeLogiDeviceSession {
    var divertableCIDs: Set<UInt16> = []
    var divertedCIDs: Set<UInt16> = []
    var lastApplied: Set<UInt16> = []
    var applyUsageCallCount: Int = 0
    var lastAppliedSnapshot: [Set<UInt16>] = []

    func applyUsage(_ aggregateMosCodes: Set<UInt16>) {
        applyUsageCallCount += 1
        let target: Set<UInt16> = aggregateMosCodes.reduce(into: []) { acc, code in
            if let cid = LogiCIDDirectory.toCID(code), divertableCIDs.contains(cid) {
                acc.insert(cid)
            }
        }
        let toDivert = target.subtracting(lastApplied)
        let toUndivert = lastApplied.subtracting(target)
        divertedCIDs.formUnion(toDivert)
        divertedCIDs.subtract(toUndivert)
        lastApplied = target
        lastAppliedSnapshot.append(lastApplied)
    }
}
