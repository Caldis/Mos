import Foundation
import IOKit
import os
#if canImport(CoreHID)
import CoreHID
#endif

protocol VirtualTrackpadDevice: AnyObject, Sendable {
    @available(macOS 15.0, *)
    func activateTrackpad() async -> Int64?

    @available(macOS 15.0, *)
    func sendTrackpadReport(_ report: Data) async throws
}

/// The shared virtual Magic Trackpad 2 provides a sender ID and accepts one touch gesture at a time.
final class VirtualTrackpadIdentity {
    static let shared = VirtualTrackpadIdentity()

    enum TouchError: Error, Equatable {
        case deviceNotReady
        case gestureInProgress
    }

    private let makeDevice: () -> VirtualTrackpadDevice?
    private var lock = os_unfair_lock_s()
    private var device: VirtualTrackpadDevice?
    private var currentSender: Int64?
    private var deviceStart = DispatchTime.now()
    private var retainCount = 0
    private var gestureInProgress = false
    private var nextContactID: UInt8 = 1

    init(makeDevice: @escaping () -> VirtualTrackpadDevice? = VirtualTrackpadIdentity.makeCoreHIDDevice) {
        self.makeDevice = makeDevice
    }

    /// Registry ID of the AppleMultitouchDevice after the driver handshake.
    var sender: Int64? {
        withLock { currentSender }
    }

    // The adapters own these references on the main thread.
    func retain() {
        let shouldCreate = withLock {
            retainCount += 1
            return device == nil
        }
        if shouldCreate { create() }
    }

    func release() {
        withLock {
            guard retainCount > 0 else { return }
            retainCount -= 1
            if retainCount == 0 && !gestureInProgress { clearDevice() }
        }
    }

    /// Positions are absolute touch coordinates. Finishing or cancelling the stream lifts both fingers.
    @available(macOS 15.0, *)
    func sendTouchGesture(
        from start: VirtualTrackpadTouchReport.Position,
        moves: AsyncStream<VirtualTrackpadTouchReport.Position>
    ) async throws {
        try Task.checkCancellation()
        let (device, firstID, started) = try beginGesture()
        var unusable = false
        defer { finishGesture(discardDevice: unusable) }

        var position = start
        var movementError: Error?
        do {
            try await device.sendTrackpadReport(VirtualTrackpadTouchReport.contactReport(
                at: start, firstID: firstID, phase: .began, milliseconds: milliseconds(since: started)
            ))
            for await move in moves {
                try Task.checkCancellation()
                position = move
                try await device.sendTrackpadReport(VirtualTrackpadTouchReport.contactReport(
                    at: move, firstID: firstID, phase: .moved, milliseconds: milliseconds(since: started)
                ))
            }
            try Task.checkCancellation()
        } catch {
            movementError = error
        }

        let release = VirtualTrackpadTouchReport.releaseReports(
            at: position, firstID: firstID, milliseconds: milliseconds(since: started)
        )
        do {
            // Keep the release sequence alive after cancellation of the input stream.
            try await Task {
                var releaseError: Error?
                for report in release {
                    do {
                        try await device.sendTrackpadReport(report)
                    } catch {
                        releaseError = releaseError ?? error
                    }
                }
                if let releaseError = releaseError { throw releaseError }
            }.value
        } catch {
            unusable = true
            throw movementError ?? error
        }

        if let movementError = movementError { throw movementError }
    }

    private func beginGesture() throws -> (VirtualTrackpadDevice, UInt8, DispatchTime) {
        try withLock {
            guard retainCount > 0, currentSender != nil, let device = device else {
                throw TouchError.deviceNotReady
            }
            guard !gestureInProgress else { throw TouchError.gestureInProgress }
            gestureInProgress = true
            let firstID = nextContactID
            nextContactID = (nextContactID + 1) % 15 + 1
            return (device, firstID, deviceStart)
        }
    }

    private func finishGesture(discardDevice: Bool) {
        withLock {
            gestureInProgress = false
            if discardDevice || retainCount == 0 { clearDevice() }
        }
    }

    private func create() {
        guard #available(macOS 15.0, *), let created = makeDevice() else { return }
        withLock {
            deviceStart = .now()
            device = created
        }
        Task { [weak self] in
            let sender = await created.activateTrackpad()
            guard let self = self else { return }
            self.withLock {
                if self.device === created { self.currentSender = sender }
            }
        }
    }

    private func clearDevice() {
        currentSender = nil
        device = nil
    }

    private func withLock<T>(_ body: () throws -> T) rethrows -> T {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return try body()
    }

    private func milliseconds(since started: DispatchTime) -> UInt32 {
        UInt32(truncatingIfNeeded: (DispatchTime.now().uptimeNanoseconds - started.uptimeNanoseconds) / 1_000_000) &+ 100
    }

    private static func makeCoreHIDDevice() -> VirtualTrackpadDevice? {
        #if canImport(CoreHID)
        guard #available(macOS 15.0, *) else { return nil }
        guard let device = HIDVirtualDevice(properties: VirtualTrackpadDescriptor.properties) else {
            NSLog("VirtualTrackpadIdentity: HIDVirtualDevice creation failed (missing com.apple.developer.hid.virtual.device?)")
            return nil
        }
        return device
        #else
        return nil
        #endif
    }

    /// 查找序列号与 Mos 虚拟设备一致的 AppleMultitouchDevice
    static func multitouchDeviceID() -> Int64? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMasterPortDefault, IOServiceMatching("AppleMultitouchDevice"), &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }
        var result: Int64?
        var service = IOIteratorNext(iterator)
        while service != 0 {
            let serial = IORegistryEntryCreateCFProperty(service, "SerialNumber" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String
            var entry: UInt64 = 0
            if result == nil, serial == VirtualTrackpadDescriptor.serialNumber,
               IORegistryEntryGetRegistryEntryID(service, &entry) == KERN_SUCCESS {
                result = Int64(bitPattern: entry)
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        return result
    }
}

#if canImport(CoreHID)
@available(macOS 15.0, *)
extension HIDVirtualDevice: VirtualTrackpadDevice {
    func activateTrackpad() async -> Int64? {
        activate(delegate: VirtualTrackpadDescriptor.Delegate())
        // The driver publishes AppleMultitouchDevice after its feature-report handshake.
        for _ in 0..<50 {
            if let id = VirtualTrackpadIdentity.multitouchDeviceID() { return id }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        NSLog("VirtualTrackpadIdentity: AppleMultitouchDevice did not appear")
        return nil
    }

    func sendTrackpadReport(_ report: Data) async throws {
        try await dispatchInputReport(data: report, timestamp: SuspendingClock().now)
    }
}
#endif
