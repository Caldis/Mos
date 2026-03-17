#!/usr/bin/env swift
// 测试如何正确清除 persistDivert
import Foundation
import IOKit
import IOKit.hid

let VID = 0x046D
class Ctx { var reports: [[UInt8]] = [] }
let ctx = Ctx()
let ctxPtr = Unmanaged.passRetained(ctx).toOpaque()
let cb: IOHIDReportCallback = { c, _, _, _, _, r, l in
    guard let c = c else { return }
    Unmanaged<Ctx>.fromOpaque(c).takeUnretainedValue().reports.append(Array(UnsafeBufferPointer(start: r, count: l)))
}
let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
IOHIDManagerSetDeviceMatching(mgr, [kIOHIDVendorIDKey as String: VID] as CFDictionary)
IOHIDManagerScheduleWithRunLoop(mgr, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.5))
guard let devs = IOHIDManagerCopyDevices(mgr) as? Set<IOHIDDevice>,
      let dev = devs.first(where: { (IOHIDDeviceGetProperty($0, kIOHIDTransportKey as CFString) as? String ?? "").contains("Bluetooth") })
else { print("No BLE device"); exit(1) }
IOHIDDeviceOpen(dev, IOOptionBits(kIOHIDOptionsTypeNone))
let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)
buf.initialize(repeating: 0, count: 64)
IOHIDDeviceRegisterInputReportCallback(dev, buf, 64, cb, ctxPtr)

func send(_ d: [UInt8]) { IOHIDDeviceSetReport(dev, kIOHIDReportTypeOutput, CFIndex(d[0]), d, d.count) }
func pkt(_ fi: UInt8, _ fn: UInt8, _ p: [UInt8] = []) -> [UInt8] {
    var r = [UInt8](repeating: 0, count: 20); r[0] = 0x11; r[1] = 0xFF; r[2] = fi; r[3] = (fn << 4) | 0x01
    for (i, v) in p.prefix(16).enumerated() { r[4+i] = v }; return r
}
func wait(_ t: TimeInterval = 2.0) -> [UInt8]? {
    ctx.reports.removeAll()
    let dl = Date(timeIntervalSinceNow: t)
    while Date() < dl && ctx.reports.isEmpty { RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05)) }
    return ctx.reports.first
}
func getStatus(_ ri: UInt8, _ cid: UInt16) -> (UInt8, UInt16) {
    send(pkt(ri, 2, [UInt8(cid >> 8), UInt8(cid & 0xFF)]))
    if let vr = wait(1.0) { return (vr[6], (UInt16(vr[7]) << 8) | UInt16(vr[8])) }
    return (0xFF, 0)
}

// Discover REPROG
send(pkt(0x00, 0, [0x1B, 0x04]))
guard let r = wait(), r[4] != 0 else { print("REPROG not found"); exit(1) }
let ri = r[4]
let cid: UInt16 = 0x00C4  // SmartShift
let h = UInt8(cid >> 8), l = UInt8(cid & 0xFF)

// Check current status
let (curFlags, curTarget) = getStatus(ri, cid)
print("Current: flags=0x\(String(format: "%02X", curFlags)) diverted=\((curFlags & 0x01) != 0)")

// Try each undivert method
let tests: [(String, [UInt8])] = [
    ("flags=0x00, target=self",  [h, l, 0x00, h, l]),
    ("flags=0x00, target=0x00",  [h, l, 0x00, 0x00, 0x00]),
    ("flags=0x02, target=self (clear persist only)", [h, l, 0x02, h, l]),
    ("flags=0x00, no target (3 bytes)", [h, l, 0x00]),
]

for (desc, params) in tests {
    // First ensure it's diverted
    send(pkt(ri, 3, [h, l, 0x03, h, l]))
    let _ = wait(0.5)
    let (bf, _) = getStatus(ri, cid)
    guard (bf & 0x01) != 0 else {
        print("\n\(desc): SKIP - couldn't set divert first")
        continue
    }

    // Try to undivert
    send(pkt(ri, 3, params))
    let _ = wait(0.5)
    let (af, at) = getStatus(ri, cid)
    let cleared = (af & 0x01) == 0
    print("\n\(desc):")
    print("  After: flags=0x\(String(format: "%02X", af)) target=0x\(String(format: "%04X", at)) diverted=\(!cleared) -> \(cleared ? "CLEARED" : "STILL DIVERTED")")
}

// Final cleanup: try all methods to ensure clean state
print("\n=== Final cleanup ===")
send(pkt(ri, 3, [h, l, 0x00, h, l])); let _ = wait(0.3)
send(pkt(ri, 3, [h, l, 0x00, 0x00, 0x00])); let _ = wait(0.3)
let (final, _) = getStatus(ri, cid)
print("Final: flags=0x\(String(format: "%02X", final)) diverted=\((final & 0x01) != 0)")
print("\nPress SmartShift to check if original function is restored (5s)...")
let end = Date(timeIntervalSinceNow: 5.0)
while Date() < end {
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
    for rpt in ctx.reports where rpt.count >= 7 && (rpt[0] == 0x10 || rpt[0] == 0x11) {
        let fi = rpt[2]
        if fi != ri { print("  SmartShift notification received -> original function RESTORED") }
        else { print("  REPROG event -> still diverted") }
    }
    ctx.reports.removeAll()
}

print("Done")
buf.deallocate()
IOHIDDeviceClose(dev, IOOptionBits(kIOHIDOptionsTypeNone))
IOHIDManagerClose(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
