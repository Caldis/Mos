import Foundation
import CoreHID
import IOKit

private final class ReportDelegate: HIDVirtualDeviceDelegate {
    let featureReports: [UInt8: Data]
    init(featureReports: [UInt8: Data] = [:]) { self.featureReports = featureReports }

    func hidVirtualDevice(_ device: HIDVirtualDevice, receivedSetReportRequestOfType type: HIDReportType,
                          id: HIDReportID?, data: Data) async throws {}

    func hidVirtualDevice(_ device: HIDVirtualDevice, receivedGetReportRequestOfType type: HIDReportType,
                          id: HIDReportID?, maxSize: Int) async throws -> Data {
        guard let raw = id?.rawValue else { return Data() }
        return featureReports[raw] ?? Data()
    }
}

/// 通过串行报文流驱动的 CoreHID 虚拟设备
///
/// `HIDVirtualDevice` (CoreHID, macOS 15+, 需要 com.apple.developer.hid.virtual.device 授权) 会在注册表中
/// 发布一个 IOHIDUserDevice。系统随后像对待真实硬件一样为它匹配驱动:
/// 普通鼠标描述符匹配 AppleUserHIDEventDriver, Apple Magic Trackpad 2 的 VendorID/ProductID 匹配
/// AppleMultitouchTrackpadHIDEventDriver。这里发出的输入报文在 CGEvent 之下进入 HID 事件系统,
/// 因此其结果与真实设备无法区分 (这也是 iPhone 镜像能收到它的原因)
///
/// `dispatchInputReport` 是异步方法; 报文经 AsyncStream 排队, 保证发送顺序
private final class VirtualDevice {
    let status = Locked("未创建")
    private let sink = Locked<AsyncStream<Data>.Continuation?>(nil)
    private let creating = Locked(false)
    private let properties: HIDVirtualDevice.Properties
    private let delegate: any HIDVirtualDeviceDelegate
    private let onReady: ((AsyncStream<Data>.Continuation) async -> String)?

    init(properties: HIDVirtualDevice.Properties, delegate: any HIDVirtualDeviceDelegate,
         onReady: ((AsyncStream<Data>.Continuation) async -> String)? = nil) {
        self.properties = properties
        self.delegate = delegate
        self.onReady = onReady
    }

    var isReady: Bool { sink.get() != nil }

    func ensure() {
        guard sink.get() == nil, creating.mutate({ let was = $0; $0 = true; return !was }) else { return }
        status.set("创建中")
        Task {
            guard let device = HIDVirtualDevice(properties: properties) else {
                status.set("创建失败: 签名缺少 HID Virtual Device")
                creating.set(false)
                return
            }
            await device.activate(delegate: delegate)
            let (stream, continuation) = AsyncStream.makeStream(of: Data.self)
            Task.detached(priority: .userInitiated) {
                let clock = SuspendingClock()
                for await report in stream {
                    do {
                        try await device.dispatchInputReport(data: report, timestamp: clock.now)
                    } catch {
                        Lab.stats.mutate { $0.dispatchErrors += 1 }
                        Trace.updateLatest { $0.dispatchErrors += 1 }
                        Lab.log("dispatchInputReport 失败: \(error)")
                    }
                }
                _ = device
            }
            sink.set(continuation)
            status.set(await onReady?(continuation) ?? "就绪")
        }
    }

    /// 丢弃当前设备: 报文流结束后发送任务退出, 设备随之释放并从注册表消失
    func destroy() {
        sink.mutate { $0?.finish(); $0 = nil }
        creating.set(false)
        status.set("已销毁")
    }

    /// 丢弃当前设备 (报文流结束, 设备被释放) 并创建新设备
    func recreate() {
        sink.mutate { $0?.finish(); $0 = nil }
        creating.set(false)
        ensure()
    }

    func send(_ report: Data) {
        guard let c = sink.get() else { ensure(); return }
        c.yield(report)
    }
}

// MARK: - 鼠标

private let mouseDescriptor: [UInt8] = [
    0x05, 0x01, 0x09, 0x02, 0xA1, 0x01, 0x09, 0x01, 0xA1, 0x00,
    0x05, 0x09, 0x19, 0x01, 0x29, 0x03, 0x15, 0x00, 0x25, 0x01, 0x95, 0x03, 0x75, 0x01, 0x81, 0x02,
    0x95, 0x01, 0x75, 0x05, 0x81, 0x03,
    0x05, 0x01, 0x09, 0x30, 0x09, 0x31, 0x09, 0x38, 0x15, 0x81, 0x25, 0x7F, 0x75, 0x08, 0x95, 0x03, 0x81, 0x06,
    0x05, 0x0C, 0x0A, 0x38, 0x02, 0x15, 0x81, 0x25, 0x7F, 0x75, 0x08, 0x95, 0x01, 0x81, 0x06,
    0xC0, 0xC0,
]

/// 报文布局: [按键, dX, dY, 滚轮, 横向滚动]
private func mouseReport(dx: Int8 = 0, wheel: Int8 = 0, pan: Int8 = 0) -> Data {
    Data([0, UInt8(bitPattern: dx), 0, UInt8(bitPattern: wheel), UInt8(bitPattern: pan)])
}

final class VirtualMouse {
    static let shared = VirtualMouse()

    private let device = VirtualDevice(
        properties: HIDVirtualDevice.Properties(descriptor: Data(mouseDescriptor), vendorID: 0xBEEF, productID: 0x0535,
                                                product: "Mirroring Scroll Lab Mouse", manufacturer: "Mos Lab"),
        delegate: ReportDelegate(),
        onReady: { _ in
            // CGEvent 的 87 号字段是产生该事件的 IOHIDEventService 的注册表 ID
            for _ in 0..<20 {
                let ids = hidEventServiceIDs(vendorID: 0xBEEF, productID: 0x0535)
                if !ids.isEmpty {
                    Lab.ownSenders.mutate { $0.formUnion(ids) }
                    return "就绪, sender=\(ids.sorted())"
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
            return "就绪, sender 未找到 (自身滚动可能被重复处理)"
        })

    var status: String { device.status.get() }
    func ensure() { device.ensure() }

    /// `y` / `x` 为 CGEvent 符号约定; 系统会对 HID 滚轮输入应用自然滚动, 因此这里预先抵消
    func wheel(y: Int, x: Int) {
        let flip = Self.naturalScrolling ? -1 : 1
        var vy = y * flip, vx = x * flip
        while vy != 0 || vx != 0 {
            let sy = max(-127, min(127, vy)), sx = max(-127, min(127, vx))
            device.send(mouseReport(wheel: Int8(sy), pan: Int8(sx)))
            vy -= sy; vx -= sx
        }
        Lab.stats.mutate { $0.emitted += 1 }
    }

    /// 往返移动 1 像素, 让光标下的窗口在第一个滚轮报文之前收到指针进入事件
    func nudge() {
        device.send(mouseReport(dx: 1))
        device.send(mouseReport(dx: -1))
    }

    static var naturalScrolling: Bool {
        (UserDefaults.standard.object(forKey: "com.apple.swipescrolldirection") as? Bool) ?? true
    }
}

// MARK: - 触控板 (Windows Precision Touchpad 描述符)

private let touchpadDescriptor: [UInt8] = {
    let finger: [UInt8] = [
        0x05, 0x0D, 0x09, 0x22, 0xA1, 0x02,
        0x15, 0x00, 0x25, 0x01, 0x75, 0x01, 0x95, 0x01, 0x09, 0x47, 0x81, 0x02, 0x09, 0x42, 0x81, 0x02,
        0x95, 0x06, 0x81, 0x03,
        0x75, 0x08, 0x95, 0x01, 0x25, 0x0F, 0x09, 0x51, 0x81, 0x02,
        0x05, 0x01, 0x15, 0x00, 0x26, 0xFF, 0x0F, 0x75, 0x10, 0x55, 0x0E, 0x65, 0x11, 0x35, 0x00,
        0x46, 0xE8, 0x03, 0x09, 0x30, 0x81, 0x02, 0x46, 0xBC, 0x02, 0x09, 0x31, 0x81, 0x02,
        0xC0,
    ]
    var d: [UInt8] = [0x05, 0x0D, 0x09, 0x05, 0xA1, 0x01, 0x85, 0x01]
    d += finger + finger
    d += [
        0x05, 0x0D, 0x65, 0x00, 0x55, 0x00, 0x35, 0x00, 0x45, 0x00, 0x15, 0x00, 0x25, 0x7F, 0x75, 0x08, 0x95, 0x01,
        0x09, 0x54, 0x81, 0x02,
        0x05, 0x09, 0x09, 0x01, 0x25, 0x01, 0x75, 0x01, 0x95, 0x01, 0x81, 0x02, 0x95, 0x07, 0x81, 0x03,
        0x05, 0x0D, 0x55, 0x0C, 0x66, 0x01, 0x10, 0x47, 0xFF, 0xFF, 0x00, 0x00, 0x27, 0xFF, 0xFF, 0x00, 0x00,
        0x75, 0x10, 0x95, 0x01, 0x09, 0x56, 0x81, 0x02,
        0x85, 0x02, 0x65, 0x00, 0x55, 0x00, 0x35, 0x00, 0x45, 0x00, 0x09, 0x55, 0x09, 0x59, 0x75, 0x04, 0x95, 0x02,
        0x25, 0x0F, 0xB1, 0x02,
        0xC0,
        0x05, 0x0D, 0x09, 0x0E, 0xA1, 0x01, 0x85, 0x03, 0x09, 0x22, 0xA1, 0x02, 0x09, 0x52, 0x15, 0x00, 0x25, 0x0A,
        0x75, 0x08, 0x95, 0x01, 0xB1, 0x02, 0xC0, 0xC0,
    ]
    return d
}()

final class VirtualTouchpad {
    static let shared = VirtualTouchpad()
    private var scanTime: UInt16 = 0
    private var down = false

    private let device = VirtualDevice(
        properties: HIDVirtualDevice.Properties(descriptor: Data(touchpadDescriptor), vendorID: 0xBEEF, productID: 0x0536,
                                                product: "Mirroring Scroll Lab Touchpad", manufacturer: "Mos Lab"),
        delegate: ReportDelegate(featureReports: [2: Data([0x02, 0x02]), 3: Data([0x03, 0x03])]))

    var status: String { device.status.get() }
    func ensure() { device.ensure() }

    /// 两根手指位于固定 X 位置, Y 都为逻辑坐标 `y` (0...4095)
    func touch(y: Double) {
        down = true
        send(tip: true, y: Int(y))
    }

    func lift() {
        guard down else { return }
        down = false
        send(tip: false, y: 2048)
        device.send(report(contacts: [], scan: nextScan()))
    }

    private func send(tip: Bool, y: Int) {
        let contacts = [(id: UInt8(0), x: 1500), (id: UInt8(1), x: 2400)].map { (tip: tip, id: $0.id, x: $0.x, y: y) }
        device.send(report(contacts: contacts, scan: nextScan()))
        Lab.stats.mutate { $0.emitted += 1 }
    }

    private func nextScan() -> UInt16 {
        scanTime &+= 80
        return scanTime
    }

    /// 报文 ID 1: 两个触点 [标志, id, xL, xH, yL, yH], 之后是触点数, 按键和扫描时间
    private func report(contacts: [(tip: Bool, id: UInt8, x: Int, y: Int)], scan: UInt16) -> Data {
        var r: [UInt8] = [0x01]
        for i in 0..<2 {
            if i < contacts.count {
                let c = contacts[i]
                let x = UInt16(clamping: c.x), y = UInt16(clamping: c.y)
                r += [c.tip ? 0x03 : 0x01, c.id, UInt8(x & 0xFF), UInt8(x >> 8), UInt8(y & 0xFF), UInt8(y >> 8)]
            } else {
                r += [0, 0, 0, 0, 0, 0]
            }
        }
        r += [UInt8(contacts.count), 0, UInt8(scan & 0xFF), UInt8(scan >> 8)]
        return Data(r)
    }
}

/// 查询指定 VendorID / ProductID 下 `className` 类服务的注册表 ID
///
/// 只用类名做 IOKit 匹配, VendorID / ProductID 逐个读取属性比较。并非所有类都支持在匹配字典里按这两个键过滤:
/// AppleMultitouchDevice 会忽略它们, 直接返回所有触控板 (包括内置触控板)
func hidEventServiceIDs(vendorID: Int, productID: Int, className: String = "IOHIDEventService") -> Set<Int64> {
    var iterator: io_iterator_t = 0
    guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(className), &iterator) == KERN_SUCCESS else { return [] }
    defer { IOObjectRelease(iterator) }
    func number(_ service: io_object_t, _ key: String) -> Int? {
        IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Int
    }
    var ids = Set<Int64>()
    var service = IOIteratorNext(iterator)
    while service != 0 {
        var entry: UInt64 = 0
        if number(service, "VendorID") == vendorID, number(service, "ProductID") == productID,
           IORegistryEntryGetRegistryEntryID(service, &entry) == KERN_SUCCESS {
            ids.insert(Int64(bitPattern: entry))
        }
        IOObjectRelease(service)
        service = IOIteratorNext(iterator)
    }
    return ids
}

// MARK: - 伪装 Magic Trackpad 2 (报文布局取自 acidanthera/VoodooInput 的 VoodooInputSimulatorDevice)
//
// 伪装的工作方式:
// 1. 设备以 Apple 的 VendorID 0x05AC, ProductID 0x0281 (VoodooInput 在 macOS 12+ 使用的 MT2 ID)
//    和 I2C 传输方式发布。AppleMultitouchTrackpadHIDEventDriver 据此匹配并接管设备,
//    hidutil 随后会列出对应的 AppleMultitouchDevice
// 2. 驱动执行特性报文握手: 先 SET 报文 1 写入查询字节 (0xDB, 0x7F, 0xD9 等), 再 GET 报文 1
//    (或查询 ID) 读取应答: 设备族 ID, 传感器行列数, 传感器表面尺寸等
//    MT2Delegate 按 VoodooInput 的固定值应答。最后驱动 SET 报文 2 = 02 01 (开启多点触控模式)
// 3. 触摸以 MT2 多点触控布局的输入报文 0x02 发送 (见 `report`)。之后由系统自己的
//    手势识别器生成带阶段、加速和惯性的滚动事件

private let mt2Descriptor: [UInt8] = [
    0x05, 0x01, 0x09, 0x02, 0xa1, 0x01, 0x09, 0x01, 0xa1, 0x00, 0x05, 0x09, 0x19, 0x01, 0x29, 0x03, 0x15, 0x00, 0x25, 0x01,
    0x85, 0x02, 0x95, 0x03, 0x75, 0x01, 0x81, 0x02, 0x95, 0x01, 0x75, 0x05, 0x81, 0x01, 0x05, 0x01, 0x09, 0x30, 0x09, 0x31,
    0x15, 0x81, 0x25, 0x7f, 0x75, 0x08, 0x95, 0x02, 0x81, 0x06, 0x95, 0x04, 0x75, 0x08, 0x81, 0x01, 0xc0, 0xc0, 0x05, 0x0d,
    0x09, 0x05, 0xa1, 0x01, 0x06, 0x00, 0xff, 0x09, 0x0c, 0x15, 0x00, 0x26, 0xff, 0x00, 0x75, 0x08, 0x95, 0x10, 0x85, 0x3f,
    0x81, 0x22, 0xc0, 0x06, 0x00, 0xff, 0x09, 0x0c, 0xa1, 0x01, 0x06, 0x00, 0xff, 0x09, 0x0c, 0x15, 0x00, 0x26, 0xff, 0x00,
    0x85, 0x44, 0x75, 0x08, 0x96, 0x6b, 0x05, 0x81, 0x00, 0xc0,
]

/// 传感器表面 156.00 x 110.40 mm, 单位 0.01 mm
private let mt2Surface: [UInt8] = [0xD9, 0xF0, 0x3C, 0x00, 0x00, 0x20, 0x2B, 0x00, 0x00, 0x44, 0xE3, 0x52, 0xFF, 0xBD, 0x1E, 0xE4, 0x26]

/// 应答 AppleMultitouch 的特性报文握手: SET 报文 1 选择查询项, GET 报文 1 返回应答
private final class MT2Delegate: HIDVirtualDeviceDelegate {
    private let pending = Locked(Data())

    func hidVirtualDevice(_ device: HIDVirtualDevice, receivedSetReportRequestOfType type: HIDReportType,
                          id: HIDReportID?, data: Data) async throws {
        let bytes = [UInt8](data)
        Lab.log("MT2 驱动 SET \(type) id=\(id.map { String(format: "0x%02X", $0.rawValue) } ?? "nil") \(bytes.map { String(format: "%02x", $0) }.joined(separator: " "))")
        guard id?.rawValue == 0x01 || bytes.first == 0x01 else { return }
        let command = bytes.first == 0x01 && bytes.count > 1 ? bytes[1] : (bytes.first ?? 0)
        let reply: [UInt8]
        switch command {
        case 0xDB: reply = [0x01, 0xDB, 0x00, 0x49, 0x00]
        case 0xD1: reply = [0x01, 0xD1, 0x00, 0x01, 0x00]
        case 0xD3: reply = [0x01, 0xD3, 0x00, 0x0C, 0x00]
        case 0xD0: reply = [0x01, 0xD0, 0x00, 0x0F, 0x00]
        case 0xA1: reply = [0x01, 0xA1, 0x00, 0x06, 0x00]
        case 0xD9: reply = mt2Surface
        case 0x7F: reply = [0x01, 0x7F, 0x00, 0x04, 0x00]
        case 0xC8: reply = [0x01, 0xC8, 0x00, 0x01, 0x00]
        default: reply = []
        }
        pending.set(Data(reply))
    }

    func hidVirtualDevice(_ device: HIDVirtualDevice, receivedGetReportRequestOfType type: HIDReportType,
                          id: HIDReportID?, maxSize: Int) async throws -> Data {
        let reply: [UInt8]
        Lab.log("MT2 驱动 GET \(type) id=\(String(format: "0x%02X", id?.rawValue ?? 0))")
        switch id?.rawValue ?? 0 {
        case 0x00: reply = [0x00, 0x01]
        case 0x01: reply = [UInt8](pending.get())
        case 0xD1: reply = [0xD1, 0x81]
        case 0xD3: reply = [0xD3, 0x01, 0x16, 0x1E, 0x03, 0x95, 0x00, 0x14, 0x1E, 0x62, 0x05, 0x00, 0x00]
        case 0xD0: reply = [0xD0, 0x02, 0x01, 0x00, 0x14, 0x01, 0x00, 0x1E, 0x00, 0x02, 0x14, 0x02, 0x01, 0x0E, 0x02, 0x00]
        case 0xA1: reply = [0xA1, 0x00, 0x00, 0x05, 0x00, 0xFC, 0x01]
        case 0xD9: reply = mt2Surface
        case 0x7F: reply = [0x7F, 0x00, 0x00, 0x00, 0x00]
        case 0xC8: reply = [0xC8, 0x08]
        case 0x02: reply = [0x02, 0x01]
        case 0xDB:
            reply = [0xDB, 0x01, 0x02, 0x00, 0xD1, 0x81, 0x0D, 0x00,
                     0xD3, 0x01, 0x16, 0x1E, 0x03, 0x95, 0x00, 0x14, 0x1E, 0x62, 0x05, 0x00, 0x00, 0x10, 0x00,
                     0xD0, 0x02, 0x01, 0x00, 0x14, 0x01, 0x00, 0x1E, 0x00, 0x02, 0x14, 0x02, 0x01, 0x0E, 0x02, 0x00, 0x07, 0x00,
                     0xA1, 0x00, 0x00, 0x05, 0x00, 0xFC, 0x01, 0x11, 0x00] + mt2Surface + [0x7F, 0x00, 0x00, 0x00, 0x00]
        default: reply = []
        }
        return Data(reply.prefix(maxSize))
    }
}

/// 伪装的 Magic Trackpad 2。引擎通过 `touch` (落指 / 移动) 和 `lift` (抬指) 驱动它
final class VirtualMagicTrackpad {
    static let shared = VirtualMagicTrackpad()
    static let maxX = 8134, maxY = 5206
    /// 虚拟妙控板的服务注册表 ID, phased 模式借用它作为 sender 身份
    static let serviceIDs = Locked<Set<Int64>>([])
    static var centerY: Int { maxY / 2 }
    private static let fingerX = [3400, 4700]
    /// 手指整体横向偏移的允许范围, 保证两根手指都离触控板左右边缘至少 300 单位
    static let offsetXRange = (300 - 3400)...(maxX - 300 - 4700)

    private let start = Date()
    private var down = false
    private var lastY = 2603
    private var lastX = 0
    /// 触点 ID (1...15) 每次落指递增, 与真实触控板为每个新触点分配新 ID 的做法一致
    private var nextID: UInt8 = 1
    private var ids: [UInt8] = [1, 2]

    private let device = VirtualDevice(
        properties: HIDVirtualDevice.Properties(descriptor: Data(mt2Descriptor), vendorID: 0x05AC, productID: 0x0281, transport: .i2c,
                                                product: "Magic Trackpad 2", manufacturer: "Apple Inc.", versionNumber: 0x804,
                                                serialNumber: "Mirroring Scroll Lab MT2", locationID: 0x1440_0000),
        delegate: MT2Delegate(),
        onReady: { _ in
            // 触控板滚动事件的 87 号字段标明的是 AppleMultitouchDevice, 不是其下层的 HID 事件驱动
            // 该对象在驱动完成握手后才出现, 因此需要等待
            for _ in 0..<50 {
                let device = hidEventServiceIDs(vendorID: 0x05AC, productID: 0x0281, className: "AppleMultitouchDevice")
                if !device.isEmpty {
                    let ids = device.union(hidEventServiceIDs(vendorID: 0x05AC, productID: 0x0281))
                    Lab.ownSenders.mutate { $0.formUnion(ids) }
                    VirtualMagicTrackpad.serviceIDs.set(device)
                    return "就绪, 原生驱动已接管, sender=\(device.sorted())"
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
            return "已创建, 但未见触控板事件服务 (驱动未接管)"
        })

    var status: String { device.status.get() }
    func ensure() { device.ensure() }
    func recreate() { device.recreate() }
    /// 销毁设备并清空借用的 sender, 用于验证不依赖虚拟设备的输出路径
    func destroy() {
        device.destroy()
        down = false
        VirtualMagicTrackpad.serviceIDs.set([])
    }

    /// 两根手指保持固定间距, 整体横向偏移 `x` (0 为初始位置), 纵向都位于 `y` (0 为触控板远端边缘)
    func touch(x: Double = 0, y: Double, first: Bool) {
        if first {
            ids = [nextID, nextID % 15 + 1]
            nextID = (nextID + 1) % 15 + 1
        }
        down = true
        let state: UInt32 = first ? 3 : 4
        let yy = Int(y.rounded()), xx = Int(x.rounded())
        lastY = yy
        lastX = xx
        device.send(report(fingers: Self.fingerX.enumerated().map { (x: $0.element + xx, y: yy, state: state, type: UInt32(2 + $0.offset), id: ids[$0.offset]) },
                           touching: true))
        Lab.stats.mutate { $0.emitted += 1 }
    }

    /// 依次发送停止, 非活动, 空帧, 这是多点触控驱动期望的抬指序列
    func lift() {
        guard down else { return }
        down = false
        let y = lastY, x = lastX
        device.send(report(fingers: Self.fingerX.enumerated().map { (x: $0.element + x, y: y, state: 7, type: UInt32(2 + $0.offset), id: ids[$0.offset]) },
                           touching: false))
        device.send(report(fingers: [(x: Self.fingerX[0] + x, y: y, state: 0, type: 0, id: ids[0])], touching: false))
        device.send(report(fingers: [], touching: false))
    }

    /// 报文 0x02: 12 字节头部, 每根手指 9 字节
    ///
    /// 头部: [0] 报文 ID 0x02, [1] 物理按键, [2...6] 未使用, [7] 触摸中为 0x03 否则为 0x02,
    /// [8] 多点触控报文 ID 0x31, [9...11] 毫秒时间戳, 按 (ms << 3 | 0x4) 打包为 24 位
    ///
    /// 手指数据为小端位域: x SInt13 (第 0-12 位, 以触控板中心为 0), y SInt13 (第 13-25 位, 以中心为 0, 向上为正),
    /// 手指类型 UInt3 (第 26-28 位: 1 拇指, 2 食指, 3 中指 ...), 状态 UInt3 (第 29-31 位: 3 开始接触, 4 接触中, 7 停止,
    /// 0 非活动), 之后依次为接触长轴, 接触短轴, 面积, 压力 (各 1 字节), 最后是触点 ID (第 0-3 位) 和
    /// 角度 (第 5-7 位, 4 = pi/2)
    private func report(fingers: [(x: Int, y: Int, state: UInt32, type: UInt32, id: UInt8)], touching: Bool) -> Data {
        let ms = UInt32(Date().timeIntervalSince(start) * 1000) + 100
        var r: [UInt8] = [0x02, 0x00, 0, 0, 0, 0, 0, touching ? 0x03 : 0x02, 0x31,
                          UInt8(truncatingIfNeeded: (ms << 3) | 0x4), UInt8(truncatingIfNeeded: ms >> 5), UInt8(truncatingIfNeeded: ms >> 13)]
        for f in fingers {
            let x = UInt32(bitPattern: Int32(f.x - Self.maxX / 2)) & 0x1FFF
            let y = UInt32(bitPattern: Int32(-(f.y - Self.maxY / 2))) & 0x1FFF
            let packed = x | (y << 13) | ((f.type & 7) << 26) | ((f.state & 7) << 29)
            let active: UInt8 = (f.state == 7 || f.state == 0) ? 0 : 1
            r += [UInt8(packed & 0xFF), UInt8((packed >> 8) & 0xFF), UInt8((packed >> 16) & 0xFF), UInt8(packed >> 24),
                  20 * active, 20 * active, 10 * active, 5 * active, (f.id & 0x0F) | (0x4 << 5)]
        }
        return Data(r)
    }
}
