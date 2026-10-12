//
//  TouchpadProbe — 虚拟 HID 触控板(Windows Precision Touchpad 形态的数字化仪描述符)
//
//  目的: 验证 macOS 是否把 CoreHID 虚拟触控板的双指滑动识别为带 phase 的触控板滚动 / 手势,
//        以及 iPhone 镜像是否把它当作触控板输入(原生平移 + 惯性)。
//
//  用法:
//    mirroring-hid-probe --touchpad [--direction up|down] [--distance N] [--duration-ms N]
//                        [--interval-ms N] [--cycles N] [--warp X,Y] [--fingers 1|2]
//

import Foundation
import CoreHID
import CoreGraphics

private let touchpadReportDescriptor: [UInt8] = {
    func finger() -> [UInt8] {
        [
            0x05, 0x0D,             // Usage Page (Digitizer)
            0x09, 0x22,             // Usage (Finger)
            0xA1, 0x02,             // Collection (Logical)
            0x15, 0x00,             //   Logical Minimum (0)
            0x25, 0x01,             //   Logical Maximum (1)
            0x75, 0x01,             //   Report Size (1)
            0x95, 0x01,             //   Report Count (1)
            0x09, 0x47,             //   Usage (Confidence)
            0x81, 0x02,             //   Input (Data,Var,Abs)
            0x09, 0x42,             //   Usage (Tip Switch)
            0x81, 0x02,             //   Input (Data,Var,Abs)
            0x95, 0x06,             //   Report Count (6)
            0x81, 0x03,             //   Input (Const)
            0x75, 0x08,             //   Report Size (8)
            0x95, 0x01,             //   Report Count (1)
            0x25, 0x0F,             //   Logical Maximum (15)
            0x09, 0x51,             //   Usage (Contact Identifier)
            0x81, 0x02,             //   Input (Data,Var,Abs)
            0x05, 0x01,             //   Usage Page (Generic Desktop)
            0x15, 0x00,             //   Logical Minimum (0)
            0x26, 0xFF, 0x0F,       //   Logical Maximum (4095)
            0x75, 0x10,             //   Report Size (16)
            0x55, 0x0E,             //   Unit Exponent (-2)
            0x65, 0x11,             //   Unit (SI Linear, cm)
            0x35, 0x00,             //   Physical Minimum (0)
            0x46, 0xE8, 0x03,       //   Physical Maximum (1000 -> 10.00 cm)
            0x09, 0x30,             //   Usage (X)
            0x81, 0x02,             //   Input (Data,Var,Abs)
            0x46, 0xBC, 0x02,       //   Physical Maximum (700 -> 7.00 cm)
            0x09, 0x31,             //   Usage (Y)
            0x81, 0x02,             //   Input (Data,Var,Abs)
            0xC0,                   // End Collection
        ]
    }
    var d: [UInt8] = [
        0x05, 0x0D,                 // Usage Page (Digitizer)
        0x09, 0x05,                 // Usage (Touch Pad)
        0xA1, 0x01,                 // Collection (Application)
        0x85, 0x01,                 //   Report ID (1)
    ]
    d += finger() + finger()
    d += [
        0x05, 0x0D,                 //   Usage Page (Digitizer)
        0x65, 0x00,                 //   Unit (None)
        0x55, 0x00,                 //   Unit Exponent (0)
        0x35, 0x00,                 //   Physical Minimum (0)
        0x45, 0x00,                 //   Physical Maximum (0)
        0x15, 0x00,                 //   Logical Minimum (0)
        0x25, 0x7F,                 //   Logical Maximum (127)
        0x75, 0x08,                 //   Report Size (8)
        0x95, 0x01,                 //   Report Count (1)
        0x09, 0x54,                 //   Usage (Contact Count)
        0x81, 0x02,                 //   Input (Data,Var,Abs)
        0x05, 0x09,                 //   Usage Page (Button)
        0x09, 0x01,                 //   Usage (Button 1)
        0x25, 0x01,                 //   Logical Maximum (1)
        0x75, 0x01,                 //   Report Size (1)
        0x95, 0x01,                 //   Report Count (1)
        0x81, 0x02,                 //   Input (Data,Var,Abs)
        0x95, 0x07,                 //   Report Count (7)
        0x81, 0x03,                 //   Input (Const)
        0x05, 0x0D,                 //   Usage Page (Digitizer)
        0x55, 0x0C,                 //   Unit Exponent (-4)
        0x66, 0x01, 0x10,           //   Unit (Seconds)
        0x47, 0xFF, 0xFF, 0x00, 0x00, // Physical Maximum (65535)
        0x27, 0xFF, 0xFF, 0x00, 0x00, // Logical Maximum (65535)
        0x75, 0x10,                 //   Report Size (16)
        0x95, 0x01,                 //   Report Count (1)
        0x09, 0x56,                 //   Usage (Scan Time)
        0x81, 0x02,                 //   Input (Data,Var,Abs)
        0x85, 0x02,                 //   Report ID (2)
        0x65, 0x00,                 //   Unit (None)
        0x55, 0x00,                 //   Unit Exponent (0)
        0x35, 0x00,                 //   Physical Minimum (0)
        0x45, 0x00,                 //   Physical Maximum (0)
        0x09, 0x55,                 //   Usage (Contact Count Maximum)
        0x09, 0x59,                 //   Usage (Pad Type)
        0x75, 0x04,                 //   Report Size (4)
        0x95, 0x02,                 //   Report Count (2)
        0x25, 0x0F,                 //   Logical Maximum (15)
        0xB1, 0x02,                 //   Feature (Data,Var,Abs)
        0xC0,                       // End Collection
        0x05, 0x0D,                 // Usage Page (Digitizer)
        0x09, 0x0E,                 // Usage (Device Configuration)
        0xA1, 0x01,                 // Collection (Application)
        0x85, 0x03,                 //   Report ID (3)
        0x09, 0x22,                 //   Usage (Finger)
        0xA1, 0x02,                 //   Collection (Logical)
        0x09, 0x52,                 //     Usage (Input Mode)
        0x15, 0x00,                 //     Logical Minimum (0)
        0x25, 0x0A,                 //     Logical Maximum (10)
        0x75, 0x08,                 //     Report Size (8)
        0x95, 0x01,                 //     Report Count (1)
        0xB1, 0x02,                 //     Feature (Data,Var,Abs)
        0xC0,                       //   End Collection
        0xC0,                       // End Collection
    ]
    return d
}()

private struct Contact {
    var tip: Bool
    var id: UInt8
    var x: Int
    var y: Int
}

/// 输入报文: [ID=1, f1(flags,id,xL,xH,yL,yH), f2(...), contactCount, buttons, scanL, scanH]
private func touchReport(_ contacts: [Contact], scanTime: UInt16) -> Data {
    var r: [UInt8] = [0x01]
    for i in 0..<2 {
        if i < contacts.count {
            let c = contacts[i]
            let x = UInt16(clamping: c.x), y = UInt16(clamping: c.y)
            let flags: UInt8 = c.tip ? 0x03 : 0x01   // 第 0 位置信, 第 1 位接触
            r += [flags, c.id, UInt8(x & 0xFF), UInt8(x >> 8), UInt8(y & 0xFF), UInt8(y >> 8)]
        } else {
            r += [0, 0, 0, 0, 0, 0]
        }
    }
    r += [UInt8(contacts.count), 0, UInt8(scanTime & 0xFF), UInt8(scanTime >> 8)]
    return Data(r)
}

private final class TouchpadDelegate: HIDVirtualDeviceDelegate {
    func hidVirtualDevice(_ device: HIDVirtualDevice, receivedSetReportRequestOfType type: HIDReportType,
                          id: HIDReportID?, data: Data) async throws {
        print("  set report type=\(type) id=\(String(describing: id)) data=\(data.map { String(format: "%02x", $0) }.joined(separator: " "))")
    }
    func hidVirtualDevice(_ device: HIDVirtualDevice, receivedGetReportRequestOfType type: HIDReportType,
                          id: HIDReportID?, maxSize: Int) async throws -> Data {
        print("  get report type=\(type) id=\(String(describing: id)) maxSize=\(maxSize)")
        switch id?.rawValue {
        case 2: return Data([0x02, 0x02])   // 最大触点数 2, 触控板类型 0 (可按压)
        case 3: return Data([0x03, 0x03])   // 输入模式 = 触控板
        default: return Data()
        }
    }
}

enum TouchpadProbe {
    static func run() async {
        var direction = "up", distance = 1600, durationMs = 320, intervalMs = 8, cycles = 1, fingers = 2
        var warp: CGPoint? = nil
        var it = CommandLine.arguments.dropFirst().makeIterator()
        while let a = it.next() {
            switch a {
            case "--direction": direction = it.next() ?? direction
            case "--distance": distance = Int(it.next() ?? "") ?? distance
            case "--duration-ms": durationMs = Int(it.next() ?? "") ?? durationMs
            case "--interval-ms": intervalMs = max(1, Int(it.next() ?? "") ?? intervalMs)
            case "--cycles": cycles = max(1, Int(it.next() ?? "") ?? cycles)
            case "--fingers": fingers = min(2, max(1, Int(it.next() ?? "") ?? fingers))
            case "--warp":
                let p = (it.next() ?? "").split(separator: ",").compactMap { Double($0) }
                if p.count == 2 { warp = CGPoint(x: p[0], y: p[1]) }
            default: break
            }
        }

        let props = HIDVirtualDevice.Properties(
            descriptor: Data(touchpadReportDescriptor),
            vendorID: 0xBE_EF,
            productID: 0x0534,
            product: "Mos Mirroring Touchpad Probe",
            manufacturer: "Mos"
        )
        guard let device = HIDVirtualDevice(properties: props) else {
            FileHandle.standardError.write(Data("✗ HIDVirtualDevice(properties:) 返回 nil\n".utf8))
            exit(2)
        }
        await device.activate(delegate: TouchpadDelegate())
        print("✓ 虚拟触控板已创建: \(device)")
        print("  方向=\(direction) 距离=\(distance) 时长=\(durationMs)ms 间隔=\(intervalMs)ms 指数=\(fingers)")
        try? await Task.sleep(for: .milliseconds(400))   // 给系统时间完成驱动匹配

        let clock = SuspendingClock()
        let originalCursor = CGEvent(source: nil)?.location
        var scan: UInt16 = 0
        func send(_ contacts: [Contact]) async {
            scan &+= UInt16(intervalMs * 10)                // 100 µs 单位
            do { try await device.dispatchInputReport(data: touchReport(contacts, scanTime: scan), timestamp: clock.now) }
            catch { FileHandle.standardError.write(Data("  dispatch 失败: \(error)\n".utf8)) }
        }

        for cycle in 1...cycles {
            if let point = warp { CGWarpMouseCursorPosition(point) }
            let sign = direction == "up" ? -1 : 1           // up = 手指朝远离用户方向(y 减小)
            let startY = sign < 0 ? 2048 + distance / 2 : 2048 - distance / 2
            let steps = max(1, durationMs / intervalMs)
            let xs = fingers == 2 ? [1500, 2400] : [2000]
            print("[\(cycle)] \(direction) swipe: \(steps) 帧")
            for step in 0...steps {
                // ease-in-out 位移曲线, 近似人手滑动的速度变化
                let t = Double(step) / Double(steps)
                let eased = t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
                let y = startY + sign * Int(Double(distance) * eased)
                await send(xs.enumerated().map { Contact(tip: true, id: UInt8($0.offset), x: $0.element, y: y) })
                try? await Task.sleep(for: .milliseconds(intervalMs))
            }
            let endY = startY + sign * distance
            await send(xs.enumerated().map { Contact(tip: false, id: UInt8($0.offset), x: $0.element, y: endY) })
            try? await Task.sleep(for: .milliseconds(intervalMs))
            await send([])
            try? await Task.sleep(for: .milliseconds(1200))
        }
        if warp != nil, let point = originalCursor { CGWarpMouseCursorPosition(point) }
    }
}
