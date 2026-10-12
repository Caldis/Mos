//
//  MagicTrackpadProbe — CoreHID 虚拟设备伪装 Magic Trackpad 2
//
//  目的: 验证 macOS 原生多点触控栈 (AppleMultitouch) 是否会接管一个 CoreHID 虚拟设备,
//        从而让合成的双指滑动得到与真实触控板一致的滚动与惯性。
//        描述符、特性报文应答与输入报文格式取自 acidanthera/VoodooInput (VoodooInputSimulatorDevice)。
//
//  用法:
//    mirroring-hid-probe --magic [--pid 0x281] [--transport i2c|usb|bluetooth] [--hold 8]
//                        [--swipe up|down] [--distance N] [--frames N] [--interval-ms N] [--warp X,Y]
//

import Foundation
import CoreHID
import CoreGraphics

private let mt2Descriptor: [UInt8] = [
    0x05, 0x01, 0x09, 0x02, 0xa1, 0x01, 0x09, 0x01, 0xa1, 0x00, 0x05, 0x09, 0x19, 0x01, 0x29, 0x03, 0x15, 0x00, 0x25, 0x01,
    0x85, 0x02, 0x95, 0x03, 0x75, 0x01, 0x81, 0x02, 0x95, 0x01, 0x75, 0x05, 0x81, 0x01, 0x05, 0x01, 0x09, 0x30, 0x09, 0x31,
    0x15, 0x81, 0x25, 0x7f, 0x75, 0x08, 0x95, 0x02, 0x81, 0x06, 0x95, 0x04, 0x75, 0x08, 0x81, 0x01, 0xc0, 0xc0, 0x05, 0x0d,
    0x09, 0x05, 0xa1, 0x01, 0x06, 0x00, 0xff, 0x09, 0x0c, 0x15, 0x00, 0x26, 0xff, 0x00, 0x75, 0x08, 0x95, 0x10, 0x85, 0x3f,
    0x81, 0x22, 0xc0, 0x06, 0x00, 0xff, 0x09, 0x0c, 0xa1, 0x01, 0x06, 0x00, 0xff, 0x09, 0x0c, 0x15, 0x00, 0x26, 0xff, 0x00,
    0x85, 0x44, 0x75, 0x08, 0x96, 0x6b, 0x05, 0x81, 0x00, 0xc0,
]

private let mt2MaxX = 8134, mt2MaxY = 5206
// 传感器表面 156.00 x 110.40 mm, 单位 0.01 mm
private let surface: [UInt8] = [0xD9, 0xF0, 0x3C, 0x00, 0x00, 0x20, 0x2B, 0x00, 0x00, 0x44, 0xE3, 0x52, 0xFF, 0xBD, 0x1E, 0xE4, 0x26]

private final class MT2Delegate: HIDVirtualDeviceDelegate {
    private let pending = LockedData()

    func hidVirtualDevice(_ device: HIDVirtualDevice, receivedSetReportRequestOfType type: HIDReportType,
                          id: HIDReportID?, data: Data) async throws {
        let bytes = [UInt8](data)
        print("  set  type=\(type) id=\(id.map { String(format: "0x%02X", $0.rawValue) } ?? "nil") data=\(hex(bytes))")
        guard id?.rawValue == 0x01 || bytes.first == 0x01 else { return }
        let command = bytes.first == 0x01 && bytes.count > 1 ? bytes[1] : (bytes.first ?? 0)
        let reply: [UInt8]
        switch command {
        case 0xDB: reply = [0x01, 0xDB, 0x00, 0x49, 0x00]
        case 0xD1: reply = [0x01, 0xD1, 0x00, 0x01, 0x00]
        case 0xD3: reply = [0x01, 0xD3, 0x00, 0x0C, 0x00]
        case 0xD0: reply = [0x01, 0xD0, 0x00, 0x0F, 0x00]
        case 0xA1: reply = [0x01, 0xA1, 0x00, 0x06, 0x00]
        case 0xD9: reply = surface
        case 0x7F: reply = [0x01, 0x7F, 0x00, 0x04, 0x00]
        case 0xC8: reply = [0x01, 0xC8, 0x00, 0x01, 0x00]
        default: reply = []
        }
        pending.set(Data(reply))
    }

    func hidVirtualDevice(_ device: HIDVirtualDevice, receivedGetReportRequestOfType type: HIDReportType,
                          id: HIDReportID?, maxSize: Int) async throws -> Data {
        let rid = id?.rawValue ?? 0
        let reply: [UInt8]
        switch rid {
        case 0x00: reply = [0x00, 0x01]
        case 0x01: reply = [UInt8](pending.get())
        case 0xD1: reply = [0xD1, 0x81]
        case 0xD3: reply = [0xD3, 0x01, 0x16, 0x1E, 0x03, 0x95, 0x00, 0x14, 0x1E, 0x62, 0x05, 0x00, 0x00]
        case 0xD0: reply = [0xD0, 0x02, 0x01, 0x00, 0x14, 0x01, 0x00, 0x1E, 0x00, 0x02, 0x14, 0x02, 0x01, 0x0E, 0x02, 0x00]
        case 0xA1: reply = [0xA1, 0x00, 0x00, 0x05, 0x00, 0xFC, 0x01]
        case 0xD9: reply = surface
        case 0x7F: reply = [0x7F, 0x00, 0x00, 0x00, 0x00]
        case 0xC8: reply = [0xC8, 0x08]
        case 0x02: reply = [0x02, 0x01]
        case 0xDB:
            reply = [0xDB, 0x01, 0x02, 0x00, 0xD1, 0x81, 0x0D, 0x00,
                     0xD3, 0x01, 0x16, 0x1E, 0x03, 0x95, 0x00, 0x14, 0x1E, 0x62, 0x05, 0x00, 0x00, 0x10, 0x00,
                     0xD0, 0x02, 0x01, 0x00, 0x14, 0x01, 0x00, 0x1E, 0x00, 0x02, 0x14, 0x02, 0x01, 0x0E, 0x02, 0x00, 0x07, 0x00,
                     0xA1, 0x00, 0x00, 0x05, 0x00, 0xFC, 0x01, 0x11, 0x00] + surface + [0x7F, 0x00, 0x00, 0x00, 0x00]
        default: reply = []
        }
        print("  get  type=\(type) id=\(String(format: "0x%02X", rid)) maxSize=\(maxSize) -> \(reply.count) bytes")
        return Data(reply.prefix(maxSize))
    }
}

private final class LockedData: @unchecked Sendable {
    private var value = Data()
    private let lock = NSLock()
    func get() -> Data { lock.lock(); defer { lock.unlock() }; return value }
    func set(_ v: Data) { lock.lock(); value = v; lock.unlock() }
}

private func hex(_ b: [UInt8]) -> String { b.map { String(format: "%02x", $0) }.joined(separator: " ") }

private struct Finger {
    var x: Int          // 0...mt2MaxX
    var y: Int          // 0...mt2MaxY, 顶部为 0
    var state: UInt32   // 3 开始接触, 4 接触中, 7 停止, 0 非活动
    var type: UInt32    // 2 食指, 3 中指
    var id: UInt8
}

/// Magic Trackpad 2 多点触控布局的报文 0x02: 12 字节头部, 每根手指 9 字节
private func mt2Report(fingers: [Finger], touching: Bool, millis: UInt32) -> Data {
    var r: [UInt8] = [0x02, 0x00, 0, 0, 0, 0, 0, touching ? 0x03 : 0x02, 0x31,
                      UInt8(truncatingIfNeeded: (millis << 3) | 0x4), UInt8(truncatingIfNeeded: millis >> 5), UInt8(truncatingIfNeeded: millis >> 13)]
    for f in fingers {
        let x = UInt32(bitPattern: Int32(f.x - mt2MaxX / 2)) & 0x1FFF
        let y = UInt32(bitPattern: Int32(-(f.y - mt2MaxY / 2))) & 0x1FFF
        let packed = x | (y << 13) | ((f.type & 7) << 26) | ((f.state & 7) << 29)
        let active = f.state != 7 && f.state != 0
        r += [UInt8(packed & 0xFF), UInt8((packed >> 8) & 0xFF), UInt8((packed >> 16) & 0xFF), UInt8(packed >> 24),
              active ? 20 : 0, active ? 20 : 0, active ? 10 : 0, active ? 5 : 0, (f.id & 0x0F) | (0x4 << 5)]
    }
    return Data(r)
}

enum MagicTrackpadProbe {
    static func run() async {
        var pid: UInt32 = 0x0281, transport: HIDDeviceTransport = .i2c, hold = 8.0
        var swipe: String? = nil, distance = 1800, frames = 30, intervalMs = 8
        var warp: CGPoint? = nil
        var it = CommandLine.arguments.dropFirst().makeIterator()
        while let a = it.next() {
            switch a {
            case "--pid": if let v = it.next() { pid = UInt32(v.replacingOccurrences(of: "0x", with: ""), radix: 16) ?? pid }
            case "--transport":
                switch it.next() {
                case "usb": transport = .usb
                case "bluetooth": transport = .bluetooth
                default: transport = .i2c
                }
            case "--hold": hold = Double(it.next() ?? "") ?? hold
            case "--swipe": swipe = it.next()
            case "--distance": distance = Int(it.next() ?? "") ?? distance
            case "--frames": frames = Int(it.next() ?? "") ?? frames
            case "--interval-ms": intervalMs = Int(it.next() ?? "") ?? intervalMs
            case "--warp":
                let p = (it.next() ?? "").split(separator: ",").compactMap { Double($0) }
                if p.count == 2 { warp = CGPoint(x: p[0], y: p[1]) }
            default: break
            }
        }

        let props = HIDVirtualDevice.Properties(
            descriptor: Data(mt2Descriptor), vendorID: 0x05AC, productID: pid, transport: transport,
            product: "Magic Trackpad 2", manufacturer: "Apple Inc.", versionNumber: 0x804,
            serialNumber: "Mos Lab MT2 Probe", locationID: 0x1440_0000)
        guard let device = HIDVirtualDevice(properties: props) else {
            print("✗ HIDVirtualDevice 返回 nil"); exit(2)
        }
        await device.activate(delegate: MT2Delegate())
        print("✓ 虚拟 MT2 已创建: \(device), pid=\(String(format: "0x%04X", pid)), transport=\(transport)")
        try? await Task.sleep(for: .seconds(2.5))   // 留时间给驱动匹配与特性报文握手

        if let swipe {
            if let warp { CGWarpMouseCursorPosition(warp) }
            let clock = SuspendingClock()
            let start = Date()
            func ms() -> UInt32 { UInt32(Date().timeIntervalSince(start) * 1000) + 100 }
            let sign = swipe == "up" ? -1 : 1
            let y0 = mt2MaxY / 2 - sign * distance / 2
            func send(_ fingers: [Finger], _ touching: Bool) async {
                do { try await device.dispatchInputReport(data: mt2Report(fingers: fingers, touching: touching, millis: ms()), timestamp: clock.now) }
                catch { print("  dispatch 失败: \(error)") }
            }
            for i in 0...frames {
                let t = Double(i) / Double(frames)
                let y = y0 + sign * Int(Double(distance) * t)
                let state: UInt32 = i == 0 ? 3 : 4
                await send([Finger(x: 3400, y: y, state: state, type: 2, id: 1), Finger(x: 4700, y: y, state: state, type: 3, id: 2)], true)
                try? await Task.sleep(for: .milliseconds(intervalMs))
            }
            let yEnd = y0 + sign * distance
            await send([Finger(x: 3400, y: yEnd, state: 7, type: 2, id: 1), Finger(x: 4700, y: yEnd, state: 7, type: 3, id: 2)], false)
            try? await Task.sleep(for: .milliseconds(10))
            await send([Finger(x: 3400, y: yEnd, state: 0, type: 0, id: 1)], false)
            try? await Task.sleep(for: .milliseconds(10))
            await send([], false)
            print("  swipe \(swipe) 已发送 \(frames) 帧")
        }
        try? await Task.sleep(for: .seconds(hold))
    }
}
