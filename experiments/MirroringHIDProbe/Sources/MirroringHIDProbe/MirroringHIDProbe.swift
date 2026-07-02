//
//  MirroringHIDProbe — CoreHID 虚拟 HID 设备验证原型
//
//  目的: 验证「用 CoreHID HIDVirtualDevice 注入滚轮 → iPhone 镜像是否响应、方向是否可控、
//        能否平滑」这一核心假设。本程序只创建一个虚拟鼠标并按参数持续发送滚轮报文,
//        观测靠肉眼看 iPhone 镜像窗口 + `hidutil list`。它不集成进 Mos,是一次性验证工具。
//
//  用法(需已签名带 com.apple.developer.hid.virtual.device, 见 README):
//    mirroring-hid-probe                     # 默认: 每 1.5s 交替上下滚一阵, 看方向
//    mirroring-hid-probe --mode smooth        # 高频小步长, 测平滑
//    mirroring-hid-probe --mode notch         # 低频大步长, 传统"格"滚动
//    mirroring-hid-probe --direction up       # 只往一个方向(up/down), 便于对照方向
//    mirroring-hid-probe --delta 5 --interval-ms 8 --burst 40
//

import Foundation
import CoreHID

// MARK: - HID Report Descriptor
// 标准相对定位鼠标: 3 键 + X + Y + Wheel(0x38) + AC Pan(0x0238, 水平)
// 输入报文 = 5 个有符号字节: [buttons, dX, dY, wheel, acPan]
private let mouseReportDescriptor: [UInt8] = [
    0x05, 0x01,        // Usage Page (Generic Desktop)
    0x09, 0x02,        // Usage (Mouse)
    0xA1, 0x01,        // Collection (Application)
    0x09, 0x01,        //   Usage (Pointer)
    0xA1, 0x00,        //   Collection (Physical)
    0x05, 0x09,        //     Usage Page (Button)
    0x19, 0x01,        //     Usage Minimum (1)
    0x29, 0x03,        //     Usage Maximum (3)
    0x15, 0x00,        //     Logical Minimum (0)
    0x25, 0x01,        //     Logical Maximum (1)
    0x95, 0x03,        //     Report Count (3)
    0x75, 0x01,        //     Report Size (1)
    0x81, 0x02,        //     Input (Data,Var,Abs)      ; 3 个按键位
    0x95, 0x01,        //     Report Count (1)
    0x75, 0x05,        //     Report Size (5)
    0x81, 0x03,        //     Input (Const,Var,Abs)     ; 5 位填充
    0x05, 0x01,        //     Usage Page (Generic Desktop)
    0x09, 0x30,        //     Usage (X)
    0x09, 0x31,        //     Usage (Y)
    0x09, 0x38,        //     Usage (Wheel)
    0x15, 0x81,        //     Logical Minimum (-127)
    0x25, 0x7F,        //     Logical Maximum (127)
    0x75, 0x08,        //     Report Size (8)
    0x95, 0x03,        //     Report Count (3)
    0x81, 0x06,        //     Input (Data,Var,Rel)      ; X, Y, Wheel
    0x05, 0x0C,        //     Usage Page (Consumer)
    0x0A, 0x38, 0x02,  //     Usage (AC Pan)
    0x15, 0x81,        //     Logical Minimum (-127)
    0x25, 0x7F,        //     Logical Maximum (127)
    0x75, 0x08,        //     Report Size (8)
    0x95, 0x01,        //     Report Count (1)
    0x81, 0x06,        //     Input (Data,Var,Rel)      ; AC Pan(水平)
    0xC0,              //   End Collection
    0xC0               // End Collection
]

private func scrollReport(wheel: Int8 = 0, pan: Int8 = 0) -> Data {
    Data([0, 0, 0, UInt8(bitPattern: wheel), UInt8(bitPattern: pan)])
}

// MARK: - Delegate (只发输入报文, get/set report 均无操作)
private final class ProbeDelegate: HIDVirtualDeviceDelegate {
    func hidVirtualDevice(_ device: HIDVirtualDevice,
                          receivedSetReportRequestOfType type: HIDReportType,
                          id: HIDReportID?, data: Data) async throws {}
    func hidVirtualDevice(_ device: HIDVirtualDevice,
                          receivedGetReportRequestOfType type: HIDReportType,
                          id: HIDReportID?, maxSize: Int) async throws -> Data { Data() }
}

// MARK: - 参数解析
private struct Options {
    enum Mode: String { case diagnostic, smooth, notch }
    var mode: Mode = .diagnostic
    var direction: String? = nil     // "up" / "down" / nil(交替)
    var delta: Int8 = 3              // 每个报文的滚轮步长
    var intervalMs: Int = 15         // 报文间隔
    var burst: Int = 20             // 每阵报文数
}

private func parseOptions() -> Options {
    var o = Options()
    var it = CommandLine.arguments.dropFirst().makeIterator()
    while let a = it.next() {
        switch a {
        case "--mode": if let v = it.next(), let m = Options.Mode(rawValue: v) { o.mode = m }
        case "--direction": o.direction = it.next()
        case "--delta": if let v = it.next(), let n = Int(v) { o.delta = Int8(clamping: n) }
        case "--interval-ms": if let v = it.next(), let n = Int(v) { o.intervalMs = max(1, n) }
        case "--burst": if let v = it.next(), let n = Int(v) { o.burst = max(1, n) }
        case "-h", "--help":
            print("""
            MirroringHIDProbe — CoreHID 虚拟 HID 滚轮验证
              --mode diagnostic|smooth|notch   验证模式(默认 diagnostic)
              --direction up|down              固定方向(默认交替)
              --delta N                        滚轮步长(默认 3)
              --interval-ms N                  报文间隔毫秒(默认 15)
              --burst N                        每阵报文数(默认 20)
            观测: 打开 iPhone 镜像并让其窗口在前台, 看列表是否滚动 / 方向 / 是否平滑。
            另开终端 `hidutil list | grep -i Mos` 确认虚拟设备已注册。
            """)
            exit(0)
        default: break
        }
    }
    // 各模式的默认调参
    switch o.mode {
    case .smooth: if o.delta == 3 { o.delta = 1 }; if o.intervalMs == 15 { o.intervalMs = 8 }; if o.burst == 20 { o.burst = 60 }
    case .notch:  if o.delta == 3 { o.delta = 10 }; if o.intervalMs == 15 { o.intervalMs = 120 }; if o.burst == 20 { o.burst = 6 }
    case .diagnostic: break
    }
    return o
}

// MARK: - 主流程
@main
struct MirroringHIDProbe {
    static func main() async {
        let opt = parseOptions()

        let props = HIDVirtualDevice.Properties(
            descriptor: Data(mouseReportDescriptor),
            vendorID: 0xBE_EF,
            productID: 0x0533,
            product: "Mos Mirroring HID Probe",
            manufacturer: "Mos"
        )

        guard let device = HIDVirtualDevice(properties: props) else {
            FileHandle.standardError.write(Data("""
            ✗ HIDVirtualDevice(properties:) 返回 nil。
              最可能原因: 未带 entitlement com.apple.developer.hid.virtual.device,
              或签名/描述文件不对。见 README「签名」一节。
              也可能是首次运行被系统隐私授权拦截(检查系统设置 > 隐私与安全性 > 输入监控)。

            """.utf8))
            exit(2)
        }

        let delegate = ProbeDelegate()
        await device.activate(delegate: delegate)

        print("✓ 虚拟 HID 鼠标已创建并激活: \(device)")
        print("  确认设备已注册:  hidutil list | grep -i 'Mos Mirroring'")
        print("  模式=\(opt.mode.rawValue)  步长=\(opt.delta)  间隔=\(opt.intervalMs)ms  每阵=\(opt.burst)")
        print("  现在打开 iPhone 镜像, 让其窗口在前台观察。Ctrl-C 结束。\n")

        let clock = SuspendingClock()
        var cycle = 0
        while true {
            cycle += 1
            // 决定方向: 固定 or 交替。HID Wheel 正=向上(远离用户), 负=向下。
            let up: Bool
            switch opt.direction {
            case "up": up = true
            case "down": up = false
            default: up = (cycle % 2 == 1)
            }
            let step: Int8 = up ? opt.delta : Int8(-Int(opt.delta))
            print("[\(cycle)] \(up ? "▲ up  " : "▼ down") 发送 \(opt.burst) 个报文 (wheel=\(step))")

            for _ in 0..<opt.burst {
                do {
                    try await device.dispatchInputReport(data: scrollReport(wheel: step), timestamp: clock.now)
                } catch {
                    FileHandle.standardError.write(Data("  dispatchInputReport 失败: \(error)\n".utf8))
                }
                try? await Task.sleep(for: .milliseconds(opt.intervalMs))
            }
            // 阵与阵之间停顿, 便于肉眼分辨方向
            try? await Task.sleep(for: .milliseconds(1200))
        }
    }
}
