//
//  LogiButtonDeliveryPolicy.swift
//  Mos
//

import Foundation

enum LogiButtonDeliveryPhase {
    case normal
    case recording
}

struct LogiButtonDeliveryPolicy {
    let standardMouseButtonsUseNativeEvents: Bool
    let standardButtonUndivertGuardEnabled: Bool
    let standardButtonUndivertGuardInterval: TimeInterval

    init(
        standardMouseButtonsUseNativeEvents: Bool,
        standardButtonUndivertGuardEnabled: Bool = true,
        standardButtonUndivertGuardInterval: TimeInterval = 2.0
    ) {
        self.standardMouseButtonsUseNativeEvents = standardMouseButtonsUseNativeEvents
        self.standardButtonUndivertGuardEnabled = standardButtonUndivertGuardEnabled
        self.standardButtonUndivertGuardInterval = standardButtonUndivertGuardInterval
    }

    static var `default`: LogiButtonDeliveryPolicy {
        return LogiButtonDeliveryPolicy(
            standardMouseButtonsUseNativeEvents: boolDefaultingTrue(forKey: "LogiBLEStandardButtonsNativeFirst"),
            standardButtonUndivertGuardEnabled: boolDefaultingTrue(forKey: "LogiBLEStandardUndivertGuardEnabled"),
            standardButtonUndivertGuardInterval: intervalDefaultingTwoSeconds(forKey: "LogiBLEStandardUndivertGuardInterval")
        )
    }

    func shouldUseHIDPPDelivery(
        transport: LogiTransportIdentity,
        cid: UInt16,
        phase: LogiButtonDeliveryPhase
    ) -> Bool {
        switch transport {
        case .receiver:
            return true
        case .unsupported:
            return false
        case .bleDirect:
            if standardMouseButtonsUseNativeEvents,
               LogiCIDDirectory.nativeMouseButton(forCID: cid) != nil {
                return false
            }
            return true
        }
    }

    private static func boolDefaultingTrue(forKey key: String) -> Bool {
        guard UserDefaults.standard.object(forKey: key) != nil else { return true }
        return UserDefaults.standard.bool(forKey: key)
    }

    private static func intervalDefaultingTwoSeconds(forKey key: String) -> TimeInterval {
        guard UserDefaults.standard.object(forKey: key) != nil else { return 2.0 }
        let value = UserDefaults.standard.double(forKey: key)
        return value > 0 ? value : 2.0
    }
}
