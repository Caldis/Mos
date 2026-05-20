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
        standardButtonUndivertGuardEnabled: Bool = false,
        standardButtonUndivertGuardInterval: TimeInterval = 2.0
    ) {
        self.standardMouseButtonsUseNativeEvents = standardMouseButtonsUseNativeEvents
        self.standardButtonUndivertGuardEnabled = standardButtonUndivertGuardEnabled
        self.standardButtonUndivertGuardInterval = standardButtonUndivertGuardInterval
    }

    static var `default`: LogiButtonDeliveryPolicy {
        return LogiButtonDeliveryPolicy(
            standardMouseButtonsUseNativeEvents: boolDefaultingTrue(forKey: "LogiBLEStandardButtonsNativeFirst"),
            standardButtonUndivertGuardEnabled: boolDefaultingFalse(
                forKey: "LogiBLEStandardUndivertGuardEnabled",
                bundleDefaultKey: "LogiBLEStandardUndivertGuardEnabledByDefault"
            ),
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
        return resolveBoolDefaultingTrue(
            userDefaultObject: UserDefaults.standard.object(forKey: key),
            userDefaultBool: UserDefaults.standard.bool(forKey: key),
            bundleDefaultValue: nil
        )
    }

    private static func boolDefaultingTrue(forKey key: String, bundleDefaultKey: String) -> Bool {
        return resolveBoolDefaulting(
            userDefaultObject: UserDefaults.standard.object(forKey: key),
            userDefaultBool: UserDefaults.standard.bool(forKey: key),
            bundleDefaultValue: Bundle.main.object(forInfoDictionaryKey: bundleDefaultKey),
            defaultValue: true
        )
    }

    private static func boolDefaultingFalse(forKey key: String, bundleDefaultKey: String) -> Bool {
        return resolveBoolDefaulting(
            userDefaultObject: UserDefaults.standard.object(forKey: key),
            userDefaultBool: UserDefaults.standard.bool(forKey: key),
            bundleDefaultValue: Bundle.main.object(forInfoDictionaryKey: bundleDefaultKey),
            defaultValue: false
        )
    }

    static func resolveBoolDefaultingTrue(
        userDefaultObject: Any?,
        userDefaultBool: Bool,
        bundleDefaultValue: Any?
    ) -> Bool {
        resolveBoolDefaulting(
            userDefaultObject: userDefaultObject,
            userDefaultBool: userDefaultBool,
            bundleDefaultValue: bundleDefaultValue,
            defaultValue: true
        )
    }

    static func resolveBoolDefaulting(
        userDefaultObject: Any?,
        userDefaultBool: Bool,
        bundleDefaultValue: Any?,
        defaultValue: Bool
    ) -> Bool {
        if userDefaultObject != nil {
            return userDefaultBool
        }
        if let bundleDefaultValue = bundleDefaultValue as? Bool {
            return bundleDefaultValue
        }
        if let bundleDefaultValue = bundleDefaultValue as? String {
            let normalized = bundleDefaultValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return ["1", "true", "yes"].contains(normalized)
        }
        return defaultValue
    }

    private static func intervalDefaultingTwoSeconds(forKey key: String) -> TimeInterval {
        guard UserDefaults.standard.object(forKey: key) != nil else { return 2.0 }
        let value = UserDefaults.standard.double(forKey: key)
        return value > 0 ? value : 2.0
    }
}
