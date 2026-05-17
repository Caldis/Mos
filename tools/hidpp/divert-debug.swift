#!/usr/bin/env swift
// 对比测试: 批量 divert vs 顺序 divert, 并验证 divert 状态
import Foundation
import IOKit
import IOKit.hid

let VID = 0x046D
func hex(_ d: [UInt8], n: Int? = nil) -> String { d.prefix(n ?? d.count).map { String(format: "%02X", $0) }.joined(separator: " ") }

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

// Step 1: Discover REPROG
print("\n=== Feature Discovery ===")
send(pkt(0x00, 0, [0x1B, 0x04]))
guard let r = wait(), r[4] != 0 else { print("REPROG not found"); exit(1) }
let reprogIdx = r[4]
print("REPROG at index 0x\(String(format: "%02X", reprogIdx))")

// Step 2: Get control count
send(pkt(reprogIdx, 0))
guard let cr = wait() else { print("No count response"); exit(1) }
let count = Int(cr[4])
print("Controls: \(count)")

// Step 3: Enumerate divertable controls
struct Ctrl { let cid: UInt16; let name: String; let divertable: Bool }
var ctrls: [Ctrl] = []
let names: [UInt16: String] = [0x0052:"Middle",0x0053:"Back",0x0056:"Forward",0x00C3:"Gesture",0x00C4:"SmartShift",0x00D7:"DPI"]
for i in 0..<count {
    send(pkt(reprogIdx, 1, [UInt8(i)]))
    guard let ir = wait(1.0) else { continue }
    let cid = (UInt16(ir[4]) << 8) | UInt16(ir[5])
    let f1 = ir[8]
    let dvrt = (f1 & 0x20) != 0
    ctrls.append(Ctrl(cid: cid, name: names[cid] ?? "?", divertable: dvrt))
}
let divertable = ctrls.filter { $0.divertable }
print("Divertable: \(divertable.map { $0.name })")

// Step 4: TEST A - 顺序 divert (等待每个 ACK)
print("\n=== TEST A: Sequential divert (wait for each ACK) ===")
for c in divertable {
    send(pkt(reprogIdx, 3, [UInt8(c.cid >> 8), UInt8(c.cid & 0xFF), 0x01]))
    let ack = wait(1.0)
    print("  Divert \(c.name): \(ack != nil ? "ACK" : "timeout")")
}

// Step 5: 验证 divert 状态 (GetControlReporting, function 2)
print("\n=== Verify divert status (GetControlReporting) ===")
for c in divertable {
    send(pkt(reprogIdx, 2, [UInt8(c.cid >> 8), UInt8(c.cid & 0xFF)]))
    if let vr = wait(1.0) {
        let reportedFlags = vr[6]
        let isDiverted = (reportedFlags & 0x01) != 0
        print("  \(c.name) (CID=\(String(format: "0x%04X", c.cid))): flags=0x\(String(format: "%02X", reportedFlags)) diverted=\(isDiverted)")
    } else {
        print("  \(c.name): no response")
    }
}

// Step 6: 捕获按键 (10 秒)
print("\n=== Button capture (10s) - PRESS BUTTONS NOW ===")
ctx.reports.removeAll()
var lastCIDs: Set<UInt16> = []
let end = Date(timeIntervalSinceNow: 10.0)
while Date() < end {
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
    for rpt in ctx.reports {
        if rpt[2] == reprogIdx {
            let fn = rpt[3] >> 4
            if fn == 0 { // divertedButtonsEvent
                var active: Set<UInt16> = []
                var off = 4
                while off + 1 < rpt.count { let c = (UInt16(rpt[off]) << 8) | UInt16(rpt[off+1]); if c == 0 { break }; active.insert(c); off += 2 }
                for c in active.subtracting(lastCIDs) { print("  DOWN: \(names[c] ?? "?") (0x\(String(format: "%04X", c)))") }
                for c in lastCIDs.subtracting(active) { print("  UP:   \(names[c] ?? "?") (0x\(String(format: "%04X", c)))") }
                lastCIDs = active
            } else {
                print("  [func\(fn)] \(hex(rpt, n: 10))")
            }
        } else {
            let fi = rpt[2]
            print("  [feat=0x\(String(format: "%02X", fi))] \(hex(rpt, n: 10))")
        }
    }
    ctx.reports.removeAll()
}

// Step 7: Undivert
print("\n=== Undivert ===")
for c in divertable {
    send(pkt(reprogIdx, 3, [UInt8(c.cid >> 8), UInt8(c.cid & 0xFF), 0x00]))
    let _ = wait(0.5)
}
print("Done")

buf.deallocate()
IOHIDDeviceClose(dev, IOOptionBits(kIOHIDOptionsTypeNone))
IOHIDManagerClose(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
