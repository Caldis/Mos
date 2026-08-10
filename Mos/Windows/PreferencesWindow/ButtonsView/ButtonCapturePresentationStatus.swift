//
//  ButtonCapturePresentationStatus.swift
//  Mos
//

import Foundation

enum ButtonCapturePresentationStatus: Equatable {
    case normal
    case conflict(ConflictStatus)
    case contended
    case standardMouseAliasAvailable
    case bleHIDPPUnstable

    var shouldShowIndicator: Bool {
        switch self {
        case .normal:
            return false
        case .conflict(let status):
            return status.isConflict
        case .contended, .standardMouseAliasAvailable, .bleHIDPPUnstable:
            return true
        }
    }

    var keepsPopoverOpenOnMouseExit: Bool {
        switch self {
        case .standardMouseAliasAvailable:
            return true
        case .normal, .conflict, .contended, .bleHIDPPUnstable:
            return false
        }
    }

    var titleKey: String {
        switch self {
        case .normal:
            return ""
        case .conflict:
            return "button_conflict_title"
        case .contended:
            return "button_contended_title"
        case .standardMouseAliasAvailable:
            return "button_standard_mouse_alias_title"
        case .bleHIDPPUnstable:
            return "button_ble_hidpp_unstable_title"
        }
    }

    var detailKey: String {
        switch self {
        case .normal:
            return ""
        case .conflict:
            return "button_conflict_detail"
        case .contended:
            return "button_contended_detail"
        case .standardMouseAliasAvailable:
            return "button_standard_mouse_alias_detail"
        case .bleHIDPPUnstable:
            return "button_ble_hidpp_unstable_detail"
        }
    }

    static func from(_ diagnosis: LogiButtonCaptureDiagnosis) -> ButtonCapturePresentationStatus {
        if diagnosis.canUseStandardMouseAlias { return .standardMouseAliasAvailable }
        if diagnosis.ownership.isConflict { return .conflict(diagnosis.ownership) }
        if diagnosis.isContention {
            return .contended
        }
        if diagnosis.isBLEHIDPPOnlyControl { return .bleHIDPPUnstable }
        return .normal
    }
}
