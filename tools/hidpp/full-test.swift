#!/usr/bin/env swift
// HID++ 2.0 全量测试 - 一次运行覆盖: 发现 → 枚举 → Divert → 捕获按键
// swift tools/hidpp/full-test.swift

import Foundation
import IOKit
import IOKit.hid
import CoreGraphics

let LOGITECH_VID = 0x046D

func hex(_ data: [UInt8], n: Int? = nil) -> String {
    data.prefix(n ?? data.count).map { String(format: "%02X", $0) }.joined(separator: " ")
}

// MARK: - Report context
class Ctx {
    var reports: [[UInt8]] = []
    func clear() { reports.removeAll() }
    func waitForHIDPP(timeout: TimeInterval = 3.0) -> [UInt8]? {
        let deadline = Date(timeIntervalSinceNow: timeout)
        while Date() < deadline && reports.isEmpty {
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
        }
        return reports.first
    }
}

let ctx = Ctx()
let ctxPtr = Unmanaged.passRetained(ctx).toOpaque()
let rxCallback: IOHIDReportCallback = { context, _, _, _, _, report, len in
    guard let context = context else { return }
    let c = Unmanaged<Ctx>.fromOpaque(context).takeUnretainedValue()
    let data = Array(UnsafeBufferPointer(start: report, count: len))
    if data.count >= 7 && (data[0] == 0x10 || data[0] == 0x11) {
        c.reports.append(data)
    }
}

// MARK: - Enumerate & find BLE device
let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
IOHIDManagerSetDeviceMatching(mgr, [kIOHIDVendorIDKey as String: LOGITECH_VID] as CFDictionary)
IOHIDManagerScheduleWithRunLoop(mgr, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.5))

guard let devs = IOHIDManagerCopyDevices(mgr) as? Set<IOHIDDevice>,
      let bleDev = devs.first(where: {
          (IOHIDDeviceGetProperty($0, kIOHIDTransportKey as CFString) as? String ?? "").contains("Bluetooth")
      }) else { print("FAIL: No BLE Logitech device"); exit(1) }

let devName = IOHIDDeviceGetProperty(bleDev, kIOHIDProductKey as CFString) as? String ?? "?"
print("Device: \(devName)")

IOHIDDeviceOpen(bleDev, IOOptionBits(kIOHIDOptionsTypeNone))
let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)
buf.initialize(repeating: 0, count: 64)
IOHIDDeviceRegisterInputReportCallback(bleDev, buf, 64, rxCallback, ctxPtr)

// MARK: - hidapi-compatible send
func send(_ data: [UInt8]) -> IOReturn {
    return IOHIDDeviceSetReport(bleDev, kIOHIDReportTypeOutput, CFIndex(data[0]), data, data.count)
}
func sendAndReceive(_ data: [UInt8], timeout: TimeInterval = 3.0) -> [UInt8]? {
    ctx.clear()
    let r = send(data)
    guard r == kIOReturnSuccess else {
        print("  TX FAILED: \(String(format: "0x%08x", r))")
        return nil
    }
    return ctx.waitForHIDPP(timeout: timeout)
}

func makePacket(featureIdx: UInt8, funcId: UInt8, params: [UInt8] = []) -> [UInt8] {
    var pkt = [UInt8](repeating: 0, count: 20)
    pkt[0] = 0x11
    pkt[1] = 0xFF  // BLE device index
    pkt[2] = featureIdx
    pkt[3] = (funcId << 4) | 0x01
    for (i, p) in params.prefix(16).enumerated() { pkt[4 + i] = p }
    return pkt
}

// ============================================================
print("\n========== PHASE 1: IRoot Ping ==========")
let pingPkt = makePacket(featureIdx: 0x00, funcId: 1)
if let resp = sendAndReceive(pingPkt) {
    print("OK: HID++ Protocol \(resp[4]).\(resp[5])")
} else {
    print("FAIL: No ping response - aborting")
    exit(1)
}

// ============================================================
print("\n========== PHASE 2: Feature Discovery ==========")

let featureIds: [(UInt16, String)] = [
    (0x0001, "FEATURE_SET"),
    (0x1B04, "REPROG_CONTROLS_V4"),
    (0x2110, "SMART_SHIFT"),
    (0x2201, "ADJUSTABLE_DPI"),
    (0x1000, "BATTERY_STATUS"),
    (0x0003, "DEVICE_FW_VERSION"),
    (0x0005, "DEVICE_NAME"),
]

var featureMap: [UInt16: UInt8] = [:]
for (fid, fname) in featureIds {
    let pkt = makePacket(featureIdx: 0x00, funcId: 0, params: [UInt8(fid >> 8), UInt8(fid & 0xFF)])
    if let resp = sendAndReceive(pkt, timeout: 2.0) {
        let idx = resp[4]
        if idx != 0 {
            featureMap[fid] = idx
            print("  \(fname) (0x\(String(format: "%04X", fid))) -> index 0x\(String(format: "%02X", idx))")
        } else {
            print("  \(fname) (0x\(String(format: "%04X", fid))) -> NOT SUPPORTED")
        }
    } else {
        print("  \(fname) -> NO RESPONSE")
    }
}

// ============================================================
print("\n========== PHASE 3: Device Name ==========")
if let nameIdx = featureMap[0x0005] {
    // GetDeviceNameCount (func 0)
    let countPkt = makePacket(featureIdx: nameIdx, funcId: 0)
    if let resp = sendAndReceive(countPkt) {
        let nameLen = Int(resp[4])
        var nameBytes: [UInt8] = []
        // GetDeviceName (func 1, param = offset)
        var offset = 0
        while offset < nameLen {
            let namePkt = makePacket(featureIdx: nameIdx, funcId: 1, params: [UInt8(offset)])
            if let resp = sendAndReceive(namePkt, timeout: 1.0) {
                let chunk = Array(resp[4..<min(resp.count, 4 + nameLen - offset)])
                nameBytes.append(contentsOf: chunk.prefix(while: { $0 != 0 }))
                offset += chunk.count
            } else { break }
        }
        print("  Name: \(String(bytes: nameBytes, encoding: .utf8) ?? "?")")
    }
}

// ============================================================
print("\n========== PHASE 4: Battery ==========")
if let batIdx = featureMap[0x1000] {
    let batPkt = makePacket(featureIdx: batIdx, funcId: 0)
    if let resp = sendAndReceive(batPkt) {
        print("  Battery: \(resp[4])%, status=\(resp[6])")
    }
}

// ============================================================
print("\n========== PHASE 5: REPROG_CONTROLS_V4 ==========")
guard let reprogIdx = featureMap[0x1B04] else {
    print("FAIL: REPROG_CONTROLS_V4 not found"); exit(1)
}

// GetControlCount
let countPkt = makePacket(featureIdx: reprogIdx, funcId: 0)
guard let countResp = sendAndReceive(countPkt) else {
    print("FAIL: GetControlCount no response"); exit(1)
}
let controlCount = Int(countResp[4])
print("  Control count: \(controlCount)")

// CID 名称查找表 (Solaar)
let cidNames: [UInt16: String] = [
    0x0050: "Left Click", 0x0051: "Right Click", 0x0052: "Middle Click",
    0x0053: "Back", 0x0056: "Forward",
    0x00C3: "Gesture Button", 0x00C4: "SmartShift",
    0x00D7: "DPI Change", 0x00FD: "Battery Status LED",
]

struct ControlInfo {
    let index: Int
    let cid: UInt16
    let taskId: UInt16
    let flags1: UInt8
    let flags2: UInt8
    let name: String
    var isReprogrammable: Bool { (flags1 & 0x10) != 0 }
    var isDivertable: Bool { (flags1 & 0x20) != 0 }
    var isPersistDivert: Bool { (flags1 & 0x40) != 0 }
}

var controls: [ControlInfo] = []
for i in 0..<controlCount {
    let infoPkt = makePacket(featureIdx: reprogIdx, funcId: 1, params: [UInt8(i)])
    guard let resp = sendAndReceive(infoPkt, timeout: 2.0) else {
        print("  Control[\(i)]: NO RESPONSE"); continue
    }
    let cid = (UInt16(resp[4]) << 8) | UInt16(resp[5])
    let taskId = (UInt16(resp[6]) << 8) | UInt16(resp[7])
    let f1 = resp[8]
    let f2: UInt8 = resp.count > 12 ? resp[12] : 0
    let name = cidNames[cid] ?? "Unknown"
    let ctrl = ControlInfo(index: i, cid: cid, taskId: taskId, flags1: f1, flags2: f2, name: name)
    controls.append(ctrl)

    let flagStr = [
        ctrl.isReprogrammable ? "reprog" : nil,
        ctrl.isDivertable ? "DIVERTABLE" : nil,
        ctrl.isPersistDivert ? "persist" : nil,
    ].compactMap { $0 }.joined(separator: ",")

    print("  [\(i)] CID=0x\(String(format: "%04X", cid)) \(name.padding(toLength: 18, withPad: " ", startingAt: 0)) flags1=0x\(String(format: "%02X", f1)) [\(flagStr)]")
}

// ============================================================
print("\n========== PHASE 6: Divert All Divertable Controls ==========")
let divertable = controls.filter { $0.isDivertable }
print("  Divertable: \(divertable.count)/\(controls.count)")

for ctrl in divertable {
    // SetControlReporting: func 3, params = CID(2) + flags(1)
    // flag bit 0 = temporaryDivert
    let divertPkt = makePacket(featureIdx: reprogIdx, funcId: 3,
                               params: [UInt8(ctrl.cid >> 8), UInt8(ctrl.cid & 0xFF), 0x01])
    let divertResp = sendAndReceive(divertPkt, timeout: 1.0)
    print("  Divert CID=0x\(String(format: "%04X", ctrl.cid)) (\(ctrl.name)): \(divertResp != nil ? "OK" : "no ack")")
}

// ============================================================
print("\n========== PHASE 7: Button Capture (20 seconds) ==========")
print(">>> 请在 20 秒内按下鼠标上的所有按键 (中键/前进/后退/手势/SmartShift/DPI) <<<\n")

ctx.clear()
let captureEnd = Date(timeIntervalSinceNow: 20.0)
var lastCIDs: Set<UInt16> = []
var capturedEvents: [(String, UInt16, String)] = []  // (direction, cid, name)

while Date() < captureEnd {
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))

    for report in ctx.reports {
        // 只处理来自 REPROG_CONTROLS_V4 的事件
        guard report[2] == reprogIdx else {
            // 其他 feature 的通知也记录
            let feat = report[2]
            let funcId = report[3] >> 4
            print("  [Other] Feature=0x\(String(format: "%02X", feat)) Func=\(funcId) Data=\(hex(report, n: 12))")
            continue
        }

        // 解析 CID pairs
        var activeCIDs: Set<UInt16> = []
        var offset = 4
        while offset + 1 < report.count {
            let cid = (UInt16(report[offset]) << 8) | UInt16(report[offset + 1])
            if cid == 0 { break }
            activeCIDs.insert(cid)
            offset += 2
        }

        let pressed = activeCIDs.subtracting(lastCIDs)
        let released = lastCIDs.subtracting(activeCIDs)
        lastCIDs = activeCIDs

        for cid in pressed {
            let name = cidNames[cid] ?? "Unknown(0x\(String(format: "%04X", cid)))"
            print("  >>> BUTTON DOWN: CID=0x\(String(format: "%04X", cid)) = \(name)")
            capturedEvents.append(("DOWN", cid, name))
        }
        for cid in released {
            let name = cidNames[cid] ?? "Unknown(0x\(String(format: "%04X", cid)))"
            print("  >>> BUTTON UP:   CID=0x\(String(format: "%04X", cid)) = \(name)")
            capturedEvents.append(("UP", cid, name))
        }
    }
    ctx.clear()
}

// ============================================================
print("\n========== PHASE 8: Undivert ==========")
for ctrl in divertable {
    let undivertPkt = makePacket(featureIdx: reprogIdx, funcId: 3,
                                 params: [UInt8(ctrl.cid >> 8), UInt8(ctrl.cid & 0xFF), 0x00])
    let _ = sendAndReceive(undivertPkt, timeout: 1.0)
}
print("  All controls undiverted")

// ============================================================
print("\n========== RESULTS ==========")
print("Device: \(devName)")
print("Controls: \(controlCount) total, \(divertable.count) divertable")
print("Captured events: \(capturedEvents.count)")
if capturedEvents.isEmpty {
    print("\n  NO BUTTON EVENTS CAPTURED")
    print("  Possible causes:")
    print("  - SetControlReporting divert didn't take effect")
    print("  - Button events use a different notification format")
    print("  - Buttons not pressed during capture window")
} else {
    let uniqueCIDs = Set(capturedEvents.map { $0.1 })
    print("\nUnique buttons detected:")
    for cid in uniqueCIDs.sorted() {
        let name = cidNames[cid] ?? "Unknown"
        let downs = capturedEvents.filter { $0.0 == "DOWN" && $0.1 == cid }.count
        print("  CID=0x\(String(format: "%04X", cid)) \(name): \(downs) presses")
    }
}

print("\n========== DONE ==========")
buf.deallocate()
IOHIDDeviceClose(bleDev, IOOptionBits(kIOHIDOptionsTypeNone))
IOHIDManagerClose(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
