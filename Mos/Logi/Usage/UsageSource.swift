// Mos/Logi/UsageSource.swift  (flat for now; Step 5 moves under Usage/)
import Foundation

public enum UsageSource: Hashable {
    case buttonBinding
    case globalScroll(ScrollRole)
    /// `key` is the stable identity used by Mos for the per-app entry.
    /// Currently `Application.path`. UsageSource does not require migration
    /// to bundleId; the key is opaque to UsageRegistry.
    case appScroll(key: String, role: ScrollRole)
}

public enum ScrollRole: Hashable, CaseIterable {
    case dash
    case toggle
    case block
}
