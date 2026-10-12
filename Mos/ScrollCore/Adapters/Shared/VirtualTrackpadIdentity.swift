//
//  VirtualTrackpadIdentity.swift
//  Mos
//  为 phased 输出提供 sender 身份的虚拟 Magic Trackpad 2
//

import Foundation
import IOKit
import os
#if canImport(CoreHID)
import CoreHID
#endif

/// 全部适配器共用的一台虚拟 Magic Trackpad 2。设备只提供 sender 身份, 不发送触摸报文。
/// 适配器激活时 retain, 停用时 release; 计数归零时销毁设备。
/// retain / release 在主线程调用, sender 可在任意线程读取
final class VirtualTrackpadIdentity {

    static let shared = VirtualTrackpadIdentity()

    private var lock = os_unfair_lock_s()
    private var _sender: Int64?
    /// 每次创建或销毁递增, 用于丢弃过期的异步创建结果
    private var generation = 0
    /// HIDVirtualDevice 实例; 释放引用即从注册表移除设备
    private var device: AnyObject?
    private var retainCount = 0

    /// 虚拟设备 AppleMultitouchDevice 的注册表 ID, 由内核分配; 设备未就绪时为 nil
    var sender: Int64? {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return _sender
    }

    func retain() {
        retainCount += 1
        if retainCount == 1 { create() }
    }

    func release() {
        guard retainCount > 0 else { return }
        retainCount -= 1
        if retainCount == 0 { destroy() }
    }

    private func setSender(_ value: Int64?, ifGeneration expected: Int) {
        os_unfair_lock_lock(&lock)
        if generation == expected { _sender = value }
        os_unfair_lock_unlock(&lock)
    }

    private func create() {
        guard #available(macOS 15.0, *) else { return }
        #if canImport(CoreHID)
        os_unfair_lock_lock(&lock)
        generation += 1
        let current = generation
        os_unfair_lock_unlock(&lock)

        guard let created = HIDVirtualDevice(properties: VirtualTrackpadDescriptor.properties) else {
            NSLog("VirtualTrackpadIdentity: HIDVirtualDevice creation failed (missing com.apple.developer.hid.virtual.device?)")
            return
        }
        os_unfair_lock_lock(&lock)
        device = created
        os_unfair_lock_unlock(&lock)

        Task { [weak self] in
            await created.activate(delegate: VirtualTrackpadDescriptor.Delegate())
            // AppleMultitouchDevice 在驱动完成特性报文握手后才出现
            for _ in 0..<50 {
                if let id = Self.multitouchDeviceID() {
                    self?.setSender(id, ifGeneration: current)
                    return
                }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            NSLog("VirtualTrackpadIdentity: AppleMultitouchDevice did not appear")
        }
        #endif
    }

    private func destroy() {
        os_unfair_lock_lock(&lock)
        generation += 1
        _sender = nil
        device = nil
        os_unfair_lock_unlock(&lock)
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
