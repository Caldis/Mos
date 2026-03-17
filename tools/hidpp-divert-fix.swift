#!/usr/bin/env swift
// 对比: CID+flags+0000 vs CID+flags+CID (self-mapping)
import Foundation
import IOKit
import IOKit.hid

let VID = 0x046D
class Ctx { var reports: [[UInt8]] = [] }
let ctx = Ctx()
let ctxPtr = Unmanaged.passRetained(ctx).toOpaque()
let cb: IOHIDReportCallback = { c, _, _, _, _, r, l in
    guard let c = c else { return }
    let x = Unmanaged<Ctx>.fromOpaque(c).takeUnretainedValue()
    let d = Array(UnsafeBufferPointer(start: r, count: l))
    if d.count >= 7 && (d[0] == 0x10 || d[0] == 0x11) { x.reports.append(d) }
}

let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
IOHIDManagerSetDeviceMatching(mgr, [kIOHIDVendorIDKey as String: VID] as CFDictionary)
IOHIDManagerScheduleWithRunLoop(mgr, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.5))

guard let devs = IOHIDManagerCopyDevices(mgr) as? Set<IOHIDDevice>,
      let dev = devs.first(where: { (IOHIDDeviceGetProperty($0, kIOHIDTransportKey as CFString) as? String ?? "").contains("Bluetooth") })
else { print("No BLE device"); exit(1) }

print("Device: \(IOHIDDeviceGetProperty(dev, kIOHIDProductKey as CFString) as? String ?? "?")")
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

let names: [UInt16: String] = [0x0052:"Middle",0x0053:"Back",0x0056:"Forward",0x00C3:"Gesture",0x00C4:"SmartShift",0x00D7:"DPI"]

// Discover
send(pkt(0x00, 0, [0x1B, 0x04]))
guard let r = wait(), r[4] != 0 else { print("REPROG not found"); exit(1) }
let ri = r[4]
print("REPROG at 0x\(String(format: "%02X", ri))")

// Test CID: SmartShift (0x00C4) - 最容易验证 (按下后滚轮应该不再切换)
let cid: UInt16 = 0x00C4
let cidH = UInt8(cid >> 8)
let cidL = UInt8(cid & 0xFF)

print("\n=== Test 1: SetControlReporting with targetCID=0x0000 (current method) ===")
send(pkt(ri, 3, [cidH, cidL, 0x01, 0x00, 0x00]))  // CID + flags + target=0x0000
let _ = wait(1.0)
// Verify
send(pkt(ri, 2, [cidH, cidL]))  // GetControlReporting
if let vr = wait(1.0) {
    let flags = vr[6]
    let target = (UInt16(vr[7]) << 8) | UInt16(vr[8])
    print("  GetControlReporting: flags=0x\(String(format: "%02X", flags)) target=0x\(String(format: "%04X", target)) diverted=\((flags & 0x01) != 0)")
}

// Reset
send(pkt(ri, 3, [cidH, cidL, 0x00, 0x00, 0x00]))
let _ = wait(0.5)

print("\n=== Test 2: SetControlReporting with targetCID=same CID (Solaar method) ===")
send(pkt(ri, 3, [cidH, cidL, 0x01, cidH, cidL]))  // CID + flags + target=same CID
let _ = wait(1.0)
// Verify
send(pkt(ri, 2, [cidH, cidL]))
if let vr = wait(1.0) {
    let flags = vr[6]
    let target = (UInt16(vr[7]) << 8) | UInt16(vr[8])
    print("  GetControlReporting: flags=0x\(String(format: "%02X", flags)) target=0x\(String(format: "%04X", target)) diverted=\((flags & 0x01) != 0)")
}

print("\n=== Test 3: SetControlReporting with flags=0x03 (divert + persistDivert) ===")
send(pkt(ri, 3, [cidH, cidL, 0x03, cidH, cidL]))
let _ = wait(1.0)
send(pkt(ri, 2, [cidH, cidL]))
if let vr = wait(1.0) {
    let flags = vr[6]
    let target = (UInt16(vr[7]) << 8) | UInt16(vr[8])
    print("  GetControlReporting: flags=0x\(String(format: "%02X", flags)) target=0x\(String(format: "%04X", target)) diverted=\((flags & 0x01) != 0)")
}

print("\n=== Test 4: Read current mapping FIRST, then modify flags only ===")
// First read current state
send(pkt(ri, 2, [cidH, cidL]))
if let current = wait(1.0) {
    let curFlags = current[6]
    let curTarget = [current[7], current[8]]
    print("  Current: flags=0x\(String(format: "%02X", curFlags)) target=0x\(String(format: "%02X%02X", curTarget[0], curTarget[1]))")

    // Set divert bit ON, preserve existing target
    let newFlags = curFlags | 0x01
    send(pkt(ri, 3, [cidH, cidL, newFlags, curTarget[0], curTarget[1]]))
    let _ = wait(1.0)

    // Verify
    send(pkt(ri, 2, [cidH, cidL]))
    if let vr = wait(1.0) {
        let flags = vr[6]
        let target = (UInt16(vr[7]) << 8) | UInt16(vr[8])
        print("  After divert: flags=0x\(String(format: "%02X", flags)) target=0x\(String(format: "%04X", target)) diverted=\((flags & 0x01) != 0)")
    }
}

// If any test set diverted=true, capture buttons for 10s
print("\n=== Button capture (10s) - PRESS SmartShift BUTTON ===")
ctx.reports.removeAll()
var lastCIDs: Set<UInt16> = []
let end = Date(timeIntervalSinceNow: 10.0)
while Date() < end {
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
    for rpt in ctx.reports {
        if rpt[2] == ri && (rpt[3] >> 4) == 0 {
            var active: Set<UInt16> = []
            var off = 4
            while off + 1 < rpt.count { let c = (UInt16(rpt[off]) << 8) | UInt16(rpt[off+1]); if c == 0 { break }; active.insert(c); off += 2 }
            for c in active.subtracting(lastCIDs) { let n = names[c] ?? String(format: "0x%04X", c); print("  DOWN: \(n)") }
            for c in lastCIDs.subtracting(active) { let n = names[c] ?? String(format: "0x%04X", c); print("  UP:   \(n)") }
            lastCIDs = active
        } else {
            print("  [feat=0x\(String(format: "%02X", rpt[2])) fn=\(rpt[3] >> 4)] \(rpt.prefix(10).map { String(format: "%02X", $0) }.joined(separator: " "))")
        }
    }
    ctx.reports.removeAll()
}

// Cleanup
send(pkt(ri, 3, [cidH, cidL, 0x00, cidH, cidL]))
let _ = wait(0.5)
print("\nDone")
buf.deallocate()
IOHIDDeviceClose(dev, IOOptionBits(kIOHIDOptionsTypeNone))
IOHIDManagerClose(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
