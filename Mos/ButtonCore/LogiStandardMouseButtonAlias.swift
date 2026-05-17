//
//  LogiStandardMouseButtonAlias.swift
//  Mos
//

import Cocoa

/// Standard HID++ mouse controls that can be treated as stable macOS mouse
/// button triggers.
enum LogiStandardMouseButtonAlias {
    static func nativeButtonCode(forMosCode code: UInt16) -> UInt16? {
        return LogiCenter.shared.nativeMouseButton(forMosCode: code)
    }

    static func convertedRecordedEvent(from event: RecordedEvent) -> RecordedEvent? {
        guard event.type == .mouse else {
            return nil
        }
        guard let nativeCode = nativeButtonCode(forMosCode: event.code) else {
            return nil
        }

        return RecordedEvent(
            type: .mouse,
            code: nativeCode,
            modifiers: event.modifiers,
            deviceFilter: nil
        )
    }

    static func convertedBinding(from binding: ButtonBinding) -> ButtonBinding? {
        guard let nativeTrigger = convertedRecordedEvent(from: binding.triggerEvent) else {
            return nil
        }
        return binding.replacingTriggerEvent(nativeTrigger)
    }
}
