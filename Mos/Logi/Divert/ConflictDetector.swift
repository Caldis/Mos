//
//  ConflictDetector.swift
//  Mos
//

import Foundation

/// Logi CID ownership status backed by device truth (reportingFlags + targetCID)
/// plus Mos's own divertedCIDs set.
public enum ConflictStatus: Equatable {
    case clear
    case foreignDivert
    case remapped
    case mosOwned
    case unknown

    /// Legacy adapter for callers that previously checked `== .conflict`.
    /// Conflict = a status the user should be alerted to (foreign divert + foreign remap).
    public var isConflict: Bool {
        switch self {
        case .foreignDivert, .remapped: return true
        case .clear, .mosOwned, .unknown: return false
        }
    }
}

/// Status detector for one Logi CID.
/// Precedence (matches LogiDebugPanel cStatus column visual order):
///   foreign-divert > remap > mos-owned > clear
struct LogiConflictDetector {
    static func status(reportingFlags: UInt8,
                       targetCID: UInt16,
                       cid: UInt16,
                       reportingQueried: Bool,
                       mosOwnsDivert: Bool) -> ConflictStatus {
        guard reportingQueried else { return .unknown }
        let hasDivertFlag = (reportingFlags & 0x03) != 0
        let remapped = targetCID != 0 && targetCID != cid
        if hasDivertFlag && !mosOwnsDivert { return .foreignDivert }
        if remapped { return .remapped }
        if mosOwnsDivert { return .mosOwned }
        return .clear
    }
}
