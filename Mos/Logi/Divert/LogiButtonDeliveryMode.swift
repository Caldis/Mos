//
//  LogiButtonDeliveryMode.swift
//  Mos
//

import Foundation

enum LogiTransportIdentity: Hashable {
    case bleDirect
    case receiver
    case unsupported
}

struct LogiOwnershipKey: Hashable {
    let vendorId: UInt16
    let productId: UInt16
    let name: String
    let transport: LogiTransportIdentity
    let cid: UInt16
}

enum LogiButtonDeliveryMode: Equatable {
    case hidpp
    case contended

    var debugLabel: String {
        switch self {
        case .hidpp:
            return "hidpp"
        case .contended:
            return "contended"
        }
    }
}

struct LogiControlReportingQueryProbe: Equatable {
    let featureIndex: UInt8
    let functionId: UInt8
    let params: [UInt8]
    let targetCID: UInt16
}

struct LogiBLEStandardButtonUndivertPlanner {
    func reportingQueryProbes(
        activeTargets: Set<UInt16>,
        reprogFeatureIndex: UInt8?
    ) -> [LogiControlReportingQueryProbe] {
        guard let reprogFeatureIndex else { return [] }
        return activeTargets.sorted().map { cid in
            LogiControlReportingQueryProbe(
                featureIndex: reprogFeatureIndex,
                functionId: 2,
                params: [UInt8(cid >> 8), UInt8(cid & 0xFF)],
                targetCID: cid
            )
        }
    }

    func undivertTargets(
        activeNativeFirstCIDs: Set<UInt16>,
        reportingFlagsByCID: [UInt16: UInt8]
    ) -> Set<UInt16> {
        return activeNativeFirstCIDs.filter { cid in
            guard let flags = reportingFlagsByCID[cid] else { return false }
            return (flags & 0x01) != 0
        }
    }
}

struct LogiButtonCaptureDiagnosis: Equatable {
    let ownership: ConflictStatus
    let delivery: LogiButtonDeliveryMode
    let ownershipKey: LogiOwnershipKey?
    let nativeMouseButton: UInt16?
    let usesNativeEvents: Bool

    init(
        ownership: ConflictStatus,
        delivery: LogiButtonDeliveryMode,
        ownershipKey: LogiOwnershipKey?,
        nativeMouseButton: UInt16?,
        usesNativeEvents: Bool = false
    ) {
        self.ownership = ownership
        self.delivery = delivery
        self.ownershipKey = ownershipKey
        self.nativeMouseButton = nativeMouseButton
        self.usesNativeEvents = usesNativeEvents
    }

    var isContention: Bool {
        return delivery == .contended
    }

    var canUseStandardMouseAlias: Bool {
        return ownershipKey?.transport == .bleDirect
            && nativeMouseButton != nil
            && (delivery == .contended || usesNativeEvents)
    }

    var isBLEHIDPPOnlyControl: Bool {
        return ownershipKey?.transport == .bleDirect
            && nativeMouseButton == nil
            && !usesNativeEvents
    }

    static func unknown(nativeMouseButton: UInt16?) -> LogiButtonCaptureDiagnosis {
        return LogiButtonCaptureDiagnosis(
            ownership: .unknown,
            delivery: .hidpp,
            ownershipKey: nil,
            nativeMouseButton: nativeMouseButton,
            usesNativeEvents: false
        )
    }
}

final class LogiButtonDeliveryModeStore {
    private struct ClearWindow {
        var startedAt: Date
        var count: Int
    }

    private let clearWindow: TimeInterval
    private let clearThreshold: Int
    private var modes: [LogiOwnershipKey: LogiButtonDeliveryMode] = [:]
    private var clearWindows: [LogiOwnershipKey: ClearWindow] = [:]

    init(clearWindow: TimeInterval = 30, clearThreshold: Int = 2) {
        self.clearWindow = clearWindow
        self.clearThreshold = max(1, clearThreshold)
    }

    func mode(for key: LogiOwnershipKey) -> LogiButtonDeliveryMode {
        return modes[key] ?? .hidpp
    }

    @discardableResult
    func recordExternalClear(for key: LogiOwnershipKey, at now: Date = Date()) -> LogiButtonDeliveryMode {
        var window = clearWindows[key] ?? ClearWindow(startedAt: now, count: 0)
        if now.timeIntervalSince(window.startedAt) > clearWindow {
            window = ClearWindow(startedAt: now, count: 0)
        }
        window.count += 1
        clearWindows[key] = window

        guard window.count >= clearThreshold else {
            return mode(for: key)
        }

        modes[key] = .contended
        return modes[key] ?? .hidpp
    }

    func deliveryMode(forMosCode mosCode: UInt16, matching keys: [LogiOwnershipKey]) -> LogiButtonDeliveryMode? {
        guard let cid = LogiCIDDirectory.toCID(mosCode) else { return nil }
        for key in keys where key.cid == cid {
            let mode = mode(for: key)
            if mode != .hidpp { return mode }
        }
        return nil
    }

    func removeModes(forDeviceNamed name: String, productId: UInt16) {
        modes = modes.filter { $0.key.name != name || $0.key.productId != productId }
        clearWindows = clearWindows.filter { $0.key.name != name || $0.key.productId != productId }
    }
}

extension LogiTransportIdentity {
    init(_ mode: LogiDeviceSession.ConnectionMode) {
        switch mode {
        case .bleDirect:
            self = .bleDirect
        case .receiver:
            self = .receiver
        case .unsupported:
            self = .unsupported
        }
    }
}
