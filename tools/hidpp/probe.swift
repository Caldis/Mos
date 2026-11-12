#!/usr/bin/env swift
// HID++ 2.0 BLE 探测工具 v3 - 精确复现 hidapi 行为
// swift tools/hidpp/probe.swift

import Foundation
import IOKit
import IOKit.hid

let LOGITECH_VID = 0x046D

func hex(_ data: [UInt8], n: Int? = nil) -> String {
    data.prefix(n ?? data.count).map { String(format: "%02X", $0) }.joined(separator: " ")
}

class Ctx { var reports: [[UInt8]] = [] }
let ctx = Ctx()
let ctxPtr = Unmanaged.passRetained(ctx).toOpaque()

let rxCallback: IOHIDReportCallback = { context, result, sender, type, reportID, report, reportLength in
    guard let context = context else { return }
    let c = Unmanaged<Ctx>.fromOpaque(context).takeUnretainedValue()
    let data = Array(UnsafeBufferPointer(start: report, count: reportLength))
    if data.count >= 7 && (data[0] == 0x10 || data[0] == 0x11) {
        c.reports.append(data)
        print("  >> HID++ RX: \(hex(data, n: min(data.count, 20)))")
    }
}

// Enumerate
let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
IOHIDManagerSetDeviceMatching(mgr, [kIOHIDVendorIDKey as String: LOGITECH_VID] as CFDictionary)
IOHIDManagerScheduleWithRunLoop(mgr, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.5))

guard let devs = IOHIDManagerCopyDevices(mgr) as? Set<IOHIDDevice>,
      let bleDev = devs.first(where: {
          let tr = IOHIDDeviceGetProperty($0, kIOHIDTransportKey as CFString) as? String ?? ""
          return tr.contains("Bluetooth")
      }) else { print("No BLE Logitech device"); exit(1) }

let name = IOHIDDeviceGetProperty(bleDev, kIOHIDProductKey as CFString) as? String ?? "?"
print("Target: \(name) (BLE)\n")
IOHIDDeviceOpen(bleDev, IOOptionBits(kIOHIDOptionsTypeNone))

let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)
buf.initialize(repeating: 0, count: 64)
IOHIDDeviceRegisterInputReportCallback(bleDev, buf, 64, rxCallback, ctxPtr)

// hidapi 精确行为: report_id != 0 时, data 包含 report ID, length = 全长
// IOHIDDeviceSetReport(dev, OUTPUT, data[0], data, length)
func hidapiWrite(_ device: IOHIDDevice, _ data: [UInt8]) -> IOReturn {
    let reportId = CFIndex(data[0])
    return IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, reportId, data, data.count)
}

func waitResponse(sec: TimeInterval = 3.0) -> Bool {
    let deadline = Date(timeIntervalSinceNow: sec)
    while Date() < deadline && ctx.reports.isEmpty {
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
    }
    return !ctx.reports.isEmpty
}

// MARK: - Test 1: hidapi 精确行为, IRoot.GetFeature(0x1B04)
print("=== Test 1: hidapi-exact, IRoot.GetFeature(0x1B04) ===\n")
for devIdx: UInt8 in [0xFF, 0x01, 0x00] {
    ctx.reports.removeAll()
    var pkt = [UInt8](repeating: 0, count: 20)
    pkt[0] = 0x11; pkt[1] = devIdx; pkt[2] = 0x00; pkt[3] = 0x01; pkt[4] = 0x1B; pkt[5] = 0x04
    let r = hidapiWrite(bleDev, pkt)
    print("devIdx=\(String(format: "0x%02X", devIdx)): TX \(hex(pkt, n: 8))... -> \(r == kIOReturnSuccess ? "OK" : String(format: "0x%08x", r))")
    if !waitResponse() { print("  No response\n") } else { print() }
}

// MARK: - Test 2: IRoot.Ping (GetProtocolVersion)
print("=== Test 2: IRoot.Ping ===\n")
for devIdx: UInt8 in [0xFF, 0x01, 0x00] {
    ctx.reports.removeAll()
    var pkt = [UInt8](repeating: 0, count: 20)
    pkt[0] = 0x11; pkt[1] = devIdx; pkt[2] = 0x00; pkt[3] = 0x11  // func 1, swId 1
    let r = hidapiWrite(bleDev, pkt)
    print("devIdx=\(String(format: "0x%02X", devIdx)): TX \(hex(pkt, n: 8))... -> \(r == kIOReturnSuccess ? "OK" : String(format: "0x%08x", r))")
    if !waitResponse() { print("  No response\n") } else { print() }
}

// MARK: - Test 3: 对比 - 不含 report ID (我们之前的方法)
print("=== Test 3: no-id in payload (19 bytes) ===\n")
for devIdx: UInt8 in [0xFF] {
    ctx.reports.removeAll()
    var pkt = [UInt8](repeating: 0, count: 20)
    pkt[0] = 0x11; pkt[1] = devIdx; pkt[2] = 0x00; pkt[3] = 0x01; pkt[4] = 0x1B; pkt[5] = 0x04
    let payload = Array(pkt.dropFirst())  // 19 bytes, no report ID
    let r = IOHIDDeviceSetReport(bleDev, kIOHIDReportTypeOutput, CFIndex(pkt[0]), payload, payload.count)
    print("no-id 19B: TX -> \(r == kIOReturnSuccess ? "OK" : String(format: "0x%08x", r))")
    if !waitResponse(sec: 2.0) { print("  No response\n") } else { print() }
}

// MARK: - Test 4: SetReport with kIOHIDOptionsTypeSeizeDevice
print("=== Test 4: Seize device then write ===\n")
IOHIDDeviceClose(bleDev, IOOptionBits(kIOHIDOptionsTypeNone))
let seizeResult = IOHIDDeviceOpen(bleDev, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
print("IOHIDDeviceOpen(Seize): \(seizeResult == kIOReturnSuccess ? "OK" : String(format: "0x%08x", seizeResult))")
if seizeResult == kIOReturnSuccess {
    IOHIDDeviceRegisterInputReportCallback(bleDev, buf, 64, rxCallback, ctxPtr)
    ctx.reports.removeAll()
    var pkt = [UInt8](repeating: 0, count: 20)
    pkt[0] = 0x11; pkt[1] = 0xFF; pkt[2] = 0x00; pkt[3] = 0x01; pkt[4] = 0x1B; pkt[5] = 0x04
    let r = hidapiWrite(bleDev, pkt)
    print("Seized write: TX -> \(r == kIOReturnSuccess ? "OK" : String(format: "0x%08x", r))")
    if !waitResponse() { print("  No response\n") } else { print() }
    IOHIDDeviceClose(bleDev, IOOptionBits(kIOHIDOptionsTypeNone))
    // 重新正常打开
    IOHIDDeviceOpen(bleDev, IOOptionBits(kIOHIDOptionsTypeNone))
}

// MARK: - Test 5: 被动监听 10s (请按按键)
print("=== Test 5: Passive listen 10s - PRESS BUTTONS NOW ===\n")
IOHIDDeviceRegisterInputReportCallback(bleDev, buf, 64, rxCallback, ctxPtr)
ctx.reports.removeAll()
let end = Date(timeIntervalSinceNow: 10.0)
while Date() < end {
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.2))
}
print("\nHID++ reports in 10s: \(ctx.reports.count)")

print("\n=== Done ===")
buf.deallocate()
IOHIDDeviceClose(bleDev, IOOptionBits(kIOHIDOptionsTypeNone))
IOHIDManagerClose(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
