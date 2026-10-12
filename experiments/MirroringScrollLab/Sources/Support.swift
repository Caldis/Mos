// 共享运行时状态与小工具: 锁封装, 私有 CGEvent 字段编号, 统计计数, 事件监视缓冲,
// iPhone 镜像窗口定位, 以及 AppleMultitouch 设备的 sender 查询

import AppKit
import CoreGraphics
import IOKit

final class Locked<Value>: @unchecked Sendable {
    private var value: Value
    private let lock = NSLock()
    init(_ value: Value) { self.value = value }
    func get() -> Value { lock.lock(); defer { lock.unlock() }; return value }
    func set(_ newValue: Value) { lock.lock(); value = newValue; lock.unlock() }
    @discardableResult
    func mutate<R>(_ body: (inout Value) -> R) -> R { lock.lock(); defer { lock.unlock() }; return body(&value) }
}

/// 触控板相关的私有 CGEvent 字段编号 (取自 Mac Mouse Fix / mirroir-mcp 源码)
enum Field {
    static let sender = CGEventField(rawValue: 87)!
    static let gestureSubtype = CGEventField(rawValue: 110)!
    static let gesturePhase = CGEventField(rawValue: 132)!
    static let gestureDX = CGEventField(rawValue: 116)!
    static let gestureDY = CGEventField(rawValue: 119)!
    /// 系统在自然滚动翻转设备位移时置 1; 该值为 1 时镜像对 175-178 取反
    static let inverted = CGEventField(rawValue: 137)!
    /// kCGScrollWheelEventMomentumOptionPhase; 写 123 号字段会覆盖它, 0x10 位表示惯性被打断
    static let momentumOption = CGEventField(rawValue: 173)!
    /// kCGScrollWheelEventAcceleratedDeltaAxis1/2 与 RawDeltaAxis1/2 (SDK 名称; Axis1 为纵向)
    static let accelY = CGEventField(rawValue: 176)!
    static let accelX = CGEventField(rawValue: 175)!
    static let rawY = CGEventField(rawValue: 178)!
    static let rawX = CGEventField(rawValue: 177)!
}

/// 写入本工具发出事件的 kCGEventSourceUserData, 供 tap 识别并跳过自身事件
let ownEventMarker: Int64 = 0x4D6F_734C

struct LabStats {
    var captured = 0
    var consumed = 0
    var emitted = 0
    var ignoredOwn = 0
    var outOfScope = 0
    var tapReenabled = 0
    var dispatchErrors = 0
    var droppedTicks = 0
}

enum Lab {
    static let stats = Locked(LabStats())
    static let monitor = Locked<[String]>([])
    /// 本工具虚拟 HID 设备的 sender ID (87 号字段)
    static let ownSenders = Locked<Set<Int64>>([])
    static let lastTrackpadSender = Locked<Int64>(0)
    static let lastMouseSender = Locked<Int64>(0)
    static let clockSummary = Locked("未运行")

    private static let timeFormat: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss.SSS"; return f
    }()

    /// LabConfig.diagnostics 在热路径 (tap 回调, 引擎逐帧) 上的镜像。使用普通变量: 偶尔读到旧值
    /// 只影响一个事件, 而每个事件加一次锁正是这个开关要避免的开销
    static var diagnosticsEnabled = true

    static func log(_ line: String) {
        guard diagnosticsEnabled else { return }
        let stamped = timeFormat.string(from: Date()) + " " + line
        monitor.mutate {
            $0.append(stamped)
            if $0.count > 120 { $0.removeFirst($0.count - 120) }
        }
    }
}

struct MirroringState {
    var rect: CGRect?
    var pid: pid_t?
    var frontmost = false
}

/// 跟踪 iPhone 镜像窗口在全局坐标 (左上角为原点) 中的位置, 与 CGEvent 的坐标系一致
final class MirroringLocator {
    static let shared = MirroringLocator()
    let state = Locked(MirroringState())
    private var timer: Timer?

    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.refresh() }
    }

    private func refresh() {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.ScreenContinuity").first else {
            state.set(MirroringState()); return
        }
        let pid = app.processIdentifier
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        var rect: CGRect?
        for w in windows where (w[kCGWindowOwnerPID as String] as? pid_t) == pid && (w[kCGWindowLayer as String] as? Int) == 0 {
            if let bounds = w[kCGWindowBounds as String] as? NSDictionary,
               let r = CGRect(dictionaryRepresentation: bounds), r.width > 100 {
                rect = r; break
            }
        }
        state.set(MirroringState(rect: rect, pid: pid, frontmost: NSWorkspace.shared.frontmostApplication?.processIdentifier == pid))
    }
}

enum MultitouchSender {
    /// 第一个非虚拟 AppleMultitouchDevice 的注册表 ID (内置触控板或真实妙控板)
    /// AppleMultitouchDevice 就是真实触控板滚动事件在 87 号字段中标明的 IOHIDEventService
    static var id: Int64? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleMultitouchDevice"), &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }
        var result: Int64?
        var service = IOIteratorNext(iterator)
        while service != 0 {
            let transport = IORegistryEntryCreateCFProperty(service, "Transport" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String
            var entry: UInt64 = 0
            if result == nil, transport != "Virtual", IORegistryEntryGetRegistryEntryID(service, &entry) == KERN_SUCCESS {
                result = Int64(bitPattern: entry)
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        return result
    }
}

enum MosApp {
    static let bundleIDs = ["com.caldis.Mos", "com.caldis.Mos.debug"]
    static var running: [NSRunningApplication] {
        bundleIDs.flatMap { NSRunningApplication.runningApplications(withBundleIdentifier: $0) }
    }
}
