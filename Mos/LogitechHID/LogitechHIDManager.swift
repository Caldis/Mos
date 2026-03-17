//
//  LogitechHIDManager.swift
//  Mos
//  Logitech HID 设备管理器 - 通过 IOKit 枚举和监控 Logitech 设备
//  Created by Mos on 2026/3/16.
//  Copyright © 2026 Caldis. All rights reserved.
//

import Foundation
import IOKit
import IOKit.hid

class LogitechHIDManager {
    static let shared = LogitechHIDManager()
    init() { NSLog("Module initialized: LogitechHIDManager") }

    // MARK: - Constants
    static let logitechVendorId: Int = 0x046D
    static let buttonEventNotification = NSNotification.Name("LogitechHIDButtonEvent")

    // MARK: - State
    private var hidManager: IOHIDManager?
    private var sessions: [IOHIDDevice: LogitechDeviceSession] = [:]
    private(set) var isActive = false

    // MARK: - Lifecycle

    func start() {
        guard !isActive else { return }
        LogitechHIDDebugPanel.log("[LogitechHID] Starting")

        hidManager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        guard let manager = hidManager else {
            LogitechHIDDebugPanel.log("[LogitechHID] Failed to create IOHIDManager")
            return
        }

        // 只匹配 Logitech 设备
        let matchDict: [String: Any] = [
            kIOHIDVendorIDKey as String: LogitechHIDManager.logitechVendorId
        ]
        IOHIDManagerSetDeviceMatching(manager, matchDict as CFDictionary)

        // 注册回调 (使用 C 函数指针 + context)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, Self.deviceMatchedCallback, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, Self.deviceRemovedCallback, context)

        // Schedule 到 main RunLoop (HID++ 事件低频, 避免线程同步)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)

        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        if result != kIOReturnSuccess {
            LogitechHIDDebugPanel.log("[LogitechHID] Failed to open IOHIDManager: \(String(format: "0x%08x", result))")
            return
        }

        isActive = true
        LogitechHIDDebugPanel.log("[LogitechHID] Started")
    }

    func stop() {
        guard isActive else { return }
        LogitechHIDDebugPanel.log("[LogitechHID] Stopping")

        // 清理所有设备会话
        for (_, session) in sessions {
            session.teardown()
        }
        sessions.removeAll()

        if let manager = hidManager {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        }
        hidManager = nil
        isActive = false
        LogitechHIDDebugPanel.log("[LogitechHID] Stopped")
    }

    // MARK: - Device Callbacks (C function pointers)

    private static let deviceMatchedCallback: IOHIDDeviceCallback = { context, result, sender, device in
        guard let context = context else { return }
        let manager = Unmanaged<LogitechHIDManager>.fromOpaque(context).takeUnretainedValue()
        manager.deviceConnected(device)
    }

    private static let deviceRemovedCallback: IOHIDDeviceCallback = { context, result, sender, device in
        guard let context = context else { return }
        let manager = Unmanaged<LogitechHIDManager>.fromOpaque(context).takeUnretainedValue()
        manager.deviceDisconnected(device)
    }

    // MARK: - Device Management

    private func deviceConnected(_ device: IOHIDDevice) {
        // 读取设备信息
        let vendorId = IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? Int ?? 0
        let productId = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int ?? 0
        let productName = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "Unknown"

        LogitechHIDDebugPanel.log("[LogitechHID] Device connected: \(productName) (VID: \(String(format: "0x%04X", vendorId)), PID: \(String(format: "0x%04X", productId)))")

        // 避免重复会话
        guard sessions[device] == nil else { return }

        // 创建会话
        let session = LogitechDeviceSession(hidDevice: device)
        sessions[device] = session
        session.setup()
        NotificationCenter.default.post(name: Self.sessionChangedNotification, object: nil)
    }

    private func deviceDisconnected(_ device: IOHIDDevice) {
        guard let session = sessions.removeValue(forKey: device) else { return }
        LogitechHIDDebugPanel.log("[LogitechHID] Device disconnected: \(session.deviceInfo.name)")
        session.teardown()
        NotificationCenter.default.post(name: Self.sessionChangedNotification, object: nil)
    }

    // MARK: - Query

    /// 获取当前已连接的 Logitech 设备列表
    var connectedDevices: [MosInputDevice] {
        return sessions.values.map { $0.deviceInfo }
    }

    /// Debug: 暴露活跃的设备会话
    var activeSessions: [LogitechDeviceSession] {
        return Array(sessions.values)
    }

    static let sessionChangedNotification = NSNotification.Name("LogitechHIDSessionChanged")
}
