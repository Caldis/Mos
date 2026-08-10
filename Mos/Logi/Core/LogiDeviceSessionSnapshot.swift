// Mos/Logi/LogiDeviceSessionSnapshot.swift
import Foundation

/// Read-only snapshot of LogiDeviceSession state for external consumers
/// (debug panel, self-test wizard). Captures values at construction time.
struct LogiDeviceSessionSnapshot {
    let connectionMode: LogiDeviceSession.ConnectionMode
    let deviceInfo: InputDevice
    let pairedDevices: [LogiDeviceSession.ReceiverPairedDevice]
    let discoveredControls: [LogiDeviceSession.ControlInfo]

    init(session: LogiDeviceSession) {
        self.connectionMode = session.connectionMode
        self.deviceInfo = session.deviceInfo
        self.pairedDevices = session.debugReceiverPairedDevices
        self.discoveredControls = session.debugDiscoveredControls
    }
}
