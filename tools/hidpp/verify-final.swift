#!/usr/bin/env swift
// 最终验证: flags=0x03 + targetCID=self + button capture
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

let names: [UInt16:String] = [0x0052:"Middle",0x0053:"Back",0x0056:"Forward",0x00C3:"Gesture",0x00C4:"SmartShift",0x00D7:"DPI"]

// Discover
send(pkt(0x00, 0, [0x1B, 0x04])); let ri = wait()![4]
send(pkt(ri, 0)); let count = Int(wait()![4])
print("REPROG at 0x\(String(format: "%02X", ri)), \(count) controls")

// Enumerate divertable
var divertable: [(UInt16, String)] = []
for i in 0..<count {
    send(pkt(ri, 1, [UInt8(i)])); guard let ir = wait(1.0) else { continue }
    let cid = (UInt16(ir[4]) << 8) | UInt16(ir[5])
    if (ir[8] & 0x20) != 0 { divertable.append((cid, names[cid] ?? "?")) }
}
print("Divertable: \(divertable.map { $0.1 })")

// Divert with flags=0x03 + targetCID=self
print("\nDiverting with flags=0x03...")
for (cid, name) in divertable {
    let h = UInt8(cid >> 8), l = UInt8(cid & 0xFF)
    send(pkt(ri, 3, [h, l, 0x03, h, l]))
    let _ = wait(0.5)
    // Verify
    send(pkt(ri, 2, [h, l]))
    if let vr = wait(0.5) {
        let diverted = (vr[6] & 0x01) != 0
        print("  \(name): diverted=\(diverted)")
    }
}

// Capture
print("\n>>> PRESS ALL BUTTONS (15s) <<<\n")
ctx.reports.removeAll()
var lastCIDs: Set<UInt16> = []
let end = Date(timeIntervalSinceNow: 15.0)
while Date() < end {
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
    for rpt in ctx.reports where rpt.count >= 7 && (rpt[0] == 0x10 || rpt[0] == 0x11) {
        let fi = rpt[2], fn = rpt[3] >> 4
        if fi == ri && fn == 0 {
            var active: Set<UInt16> = []
            var off = 4
            while off+1 < rpt.count { let c = (UInt16(rpt[off])<<8)|UInt16(rpt[off+1]); if c==0{break}; active.insert(c); off+=2 }
            for c in active.subtracting(lastCIDs) { print("DOWN: \(names[c] ?? String(format:"0x%04X",c))") }
            for c in lastCIDs.subtracting(active) { print("UP:   \(names[c] ?? String(format:"0x%04X",c))") }
            lastCIDs = active
        } else {
            print("[f=0x\(String(format:"%02X",fi)) fn=\(fn)]")
        }
    }
    ctx.reports.removeAll()
}

// Undivert
for (cid, _) in divertable {
    let h = UInt8(cid >> 8), l = UInt8(cid & 0xFF)
    send(pkt(ri, 3, [h, l, 0x00, h, l])); let _ = wait(0.3)
}
print("\nDone - undiverted")
buf.deallocate()
