//
//  ConflictDetector.swift
//  Mos
//

import Foundation

/// 6-state Logi CID conflict status. Precedence:
///   coDivert > foreignDivert > remap > mosOwned > clear
/// Backed by device-truth (reportingFlags + targetCID) plus Mos's own divertedCIDs set.
public enum ConflictStatus: Equatable {
    case clear
    case foreignDivert
    case remapped
    case mosOwned
    case coDivert    // Mos AND a third party are both diverting this CID.
                     // Device fires the divertedButtonsEvent to BOTH HID++ sessions
                     // (IOKit broadcast) → both Mos and the third party act on the
                     // same press, causing visible double-trigger.
    case unknown

    /// Legacy adapter for callers that previously checked `== .conflict`.
    /// Conflict = a status the user should be alerted to (foreign divert + foreign remap + co-divert).
    public var isConflict: Bool {
        switch self {
        case .foreignDivert, .remapped, .coDivert: return true
        case .clear, .mosOwned, .unknown: return false
        }
    }
}

/// Status detector for one Logi CID.
/// Precedence (matches LogiDebugPanel cStatus column visual order):
///   co-divert > foreign-divert > remap > mos-owned > clear
struct LogiConflictDetector {
    static func status(reportingFlags: UInt8,
                       targetCID: UInt16,
                       cid: UInt16,
                       reportingQueried: Bool,
                       mosOwnsDivert: Bool) -> ConflictStatus {
        guard reportingQueried else { return .unknown }
        let foreign = reportingFlags != 0
        let remapped = targetCID != 0 && targetCID != cid
        // Both Mos and a third party have set divert on this CID → double-fire
        // is observable. mosOwned alone (no foreign) means we're the sole
        // owner — nothing to flag.
        if foreign && mosOwnsDivert { return .coDivert }
        if foreign { return .foreignDivert }
        if remapped { return .remapped }
        if mosOwnsDivert { return .mosOwned }
        return .clear
    }
}
