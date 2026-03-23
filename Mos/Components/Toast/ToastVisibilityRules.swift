//
//  ToastVisibilityRules.swift
//  Mos
//  Toast 可见性规则纯逻辑 - 去重与活跃计数
//

import Foundation

struct ToastVisibilityEntry {
    let id: UInt
    let message: String
    let isDismissing: Bool
}

enum ToastVisibilityRules {

    static func containsVisibleMessage(_ message: String, in entries: [ToastVisibilityEntry]) -> Bool {
        return entries.contains(where: { $0.message == message })
    }

    static func activeCount(in entries: [ToastVisibilityEntry]) -> Int {
        return entries.reduce(0) { partialResult, entry in
            partialResult + (entry.isDismissing ? 0 : 1)
        }
    }

    static func oldestActiveIndex(in entries: [ToastVisibilityEntry]) -> Int? {
        return entries.firstIndex(where: { !$0.isDismissing })
    }
}
