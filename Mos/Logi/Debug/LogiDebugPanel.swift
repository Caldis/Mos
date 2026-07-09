//
//  LogiDebugPanel.swift
//  Mos
//  Logitech HID++ 综合调试面板
//  Created by Mos on 2026/3/16.
//  Copyright © 2026 Caldis. All rights reserved.
//

import Cocoa
import IOKit
import IOKit.hid

// MARK: - Log Entry

enum LogEntryType: String, CaseIterable {
    case info = "Info"
    case tx = "TX"
    case rx = "RX"
    case error = "Error"
    case buttonEvent = "Button"
    case warning = "Warning"
}

struct LogEntry {
    let timestamp: String
    let deviceName: String
    let type: LogEntryType
    let message: String
    let decoded: String?
    let rawBytes: [UInt8]?
    var isExpanded: Bool = false
}

#if DEBUG
enum LogiTrace {
    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: "LogiVerboseTraceEnabled")
    }

    static func log(
        _ message: @autoclosure () -> String,
        device: String = "Trace",
        type: LogEntryType = .buttonEvent
    ) {
        guard isEnabled else { return }
        LogiDebugPanel.log(device: device, type: type, message: "[Trace] \(message())")
    }

    static func event(_ event: InputEvent) -> String {
        let source: String
        switch event.source {
        case .hidPP:
            source = "hidPP"
        case .cgEvent(let cgEvent):
            source = "cgEvent(\(cgEvent.eventTypeName), nativeButton=\(cgEvent.mouseCode))"
        }
        return "source=\(source) type=\(event.type) code=\(event.code) phase=\(event.phase) modifiers=\(String(format: "0x%llX", event.modifiers.rawValue)) display=\(event.displayComponents.joined(separator: "+")) device=\(event.device?.name ?? "nil")"
    }

    static func recordedEvent(_ event: RecordedEvent) -> String {
        "type=\(event.type) code=\(event.code) modifiers=\(String(format: "0x%llX", UInt64(event.modifiers))) display=\(event.displayComponents.joined(separator: "+")) deviceFilter=\(String(describing: event.deviceFilter))"
    }

    static func codes(_ codes: Set<UInt16>) -> String {
        guard !codes.isEmpty else { return "[]" }
        return "[" + codes.sorted().map { code in
            if LogiCIDDirectory.isLogitechCode(code) {
                return "\(code)(\(LogiCIDDirectory.name(forMosCode: code)))"
            }
            return "\(code)(\(KeyCode.mouseMap[code] ?? "Mouse(\(code))"))"
        }.joined(separator: ",") + "]"
    }

    static func cids(_ cids: Set<UInt16>) -> String {
        guard !cids.isEmpty else { return "[]" }
        return "[" + cids.sorted().map { cid in
            "\(String(format: "0x%04X", cid))(\(LogiCIDDirectory.name(forCID: cid)))"
        }.joined(separator: ",") + "]"
    }
}
#endif

// MARK: - HID++ Protocol Dictionaries

struct HIDPPInfo {
    static let featureNames: [UInt16: (String, String)] = [
        0x0000: ("IRoot", "Feature discovery root"),
        0x0001: ("IFeatureSet", "Enumerate all features"),
        0x0003: ("DeviceFWVersion", "Firmware version info"),
        0x0005: ("DeviceNameType", "Device name and type"),
        0x0020: ("ConfigChange", "Config change notification"),
        0x1000: ("BatteryStatus", "Battery level and status"),
        0x1001: ("BatteryVoltage", "Battery voltage reading"),
        0x1004: ("UnifiedBattery", "Unified battery reporting"),
        0x1814: ("ChangeHost", "Multi-host switching"),
        0x1815: ("HostsInfo", "Connected host info"),
        0x19B0: ("Haptic", "Haptic feedback control"),
        0x1B04: ("ReprogControlsV4", "Button reprog and divert"),
        0x1D4B: ("WirelessStatus", "Wireless connection status"),
        0x2110: ("SmartShift", "Scroll wheel mode"),
        0x2111: ("SmartShiftV2", "Scroll force / ratchet torque"),
        0x2121: ("HiResWheel", "Hi-res scroll wheel"),
        0x2150: ("ThumbWheel", "Thumb wheel control"),
        0x2200: ("MouseButtonSpy", "Mouse button spy"),
        0x2201: ("AdjustableDPI", "DPI adjustment"),
        0x2205: ("PointerSpeed", "Pointer speed control"),
        0x4521: ("HiResWheel", "Hi-res scroll wheel"),
        // 扩展可选功能 (MX Master 4 等); 由串行探测填充到 FEATURES 表
        0x1010: ("ChargingControl", "Charging behavior control"),
        0x1802: ("DeviceReset", "Reset device to factory"),
        0x19C0: ("ForceSensing", "Force-sensing button threshold"),
        0x1C00: ("PersistentRemap", "Persistent button mapping"),
        0x2001: ("LeftRightSwap", "Swap left/right buttons"),
        0x2006: ("AxisOrientation", "Pointer axis orientation"),
        0x2130: ("LowResWheel", "Low-res wheel / diversion"),
        0x2202: ("ExtendedDPI", "Extended DPI (per-axis, high)"),
        0x2230: ("AngleSnapping", "Angle snapping"),
        0x2240: ("SurfaceTuning", "Surface calibration"),
        0x2250: ("XYStats", "XY movement stats"),
        0x2251: ("WheelStats", "Wheel usage stats"),
        0x8060: ("ReportRate", "Report / polling rate"),
        0x8061: ("ExtReportRate", "Extended report rate"),
        0x8100: ("OnboardProfiles", "Onboard profiles"),
    ]

    static let controlFlagBits: [(bit: Int, short: String, desc: String)] = [
        (0, "Mouse", "Mouse button group"),
        (1, "FKey", "F-key group"),
        (2, "HotKey", "Hotkey"),
        (3, "FnToggle", "Fn toggle affected"),
        (4, "Reprog", "Reprogrammable"),
        (5, "Divert", "Divertable to SW"),
        (6, "Persist", "Persistent divert"),
        (7, "Virtual", "Virtual button"),
        (8, "RawXY", "Raw XY capable"),
        (9, "ForceXY", "Force raw XY"),
    ]

    static func flagsDescription(_ flags: UInt16) -> String {
        return controlFlagBits
            .filter { (flags >> $0.bit) & 1 != 0 }
            .map { $0.short }
            .joined(separator: ",")
    }

    static let errorNames: [UInt8: String] = [
        0x00: "NoError", 0x01: "Unknown", 0x02: "InvalidArgument",
        0x03: "OutOfRange", 0x04: "HWError", 0x05: "LogitechInternal",
        0x06: "InvalidFeatureIndex", 0x07: "InvalidFunctionID",
        0x08: "Busy", 0x09: "Unsupported",
    ]

    /// HAPTIC (0x19B0) 固件预置波形 (对齐 Solaar HapticWaveForms).
    /// ID 稀疏: 0x0F~0x1A 无定义, 0x1B 是有意跳跃. 实际支持范围以 GetCapabilities 位掩码为准.
    static let hapticWaveforms: [(id: UInt8, name: String)] = [
        (0x00, "Sharp State Change"),
        (0x01, "Damp State Change"),
        (0x02, "Sharp Collision"),
        (0x03, "Damp Collision"),
        (0x04, "Subtle Collision"),
        (0x05, "Happy Alert"),
        (0x06, "Angry Alert"),
        (0x07, "Completed"),
        (0x08, "Square"),
        (0x09, "Wave"),
        (0x0A, "Firework"),
        (0x0B, "Mad"),
        (0x0C, "Knock"),
        (0x0D, "Jingle"),
        (0x0E, "Ringing"),
        (0x1B, "Whisper Collision"),
    ]
}

// MARK: - Feature Action Definitions

struct HIDPPFeatureAction {
    let name: String
    let functionId: UInt8
    enum ParamType { case none, index, hex }
    let paramType: ParamType
    let defaultParams: [UInt8]
}

struct HIDPPFeatureActions {
    static let knownActions: [UInt16: [HIDPPFeatureAction]] = [
        0x0000: [
            HIDPPFeatureAction(name: "Ping", functionId: 0x01, paramType: .none, defaultParams: []),
            HIDPPFeatureAction(name: "GetFeature", functionId: 0x00, paramType: .hex, defaultParams: [0x00, 0x01]),
        ],
        0x0001: [
            HIDPPFeatureAction(name: "GetCount", functionId: 0x00, paramType: .none, defaultParams: []),
            HIDPPFeatureAction(name: "GetFeatureID", functionId: 0x01, paramType: .index, defaultParams: []),
        ],
        0x0003: [
            HIDPPFeatureAction(name: "GetEntityCount", functionId: 0x00, paramType: .none, defaultParams: []),
            HIDPPFeatureAction(name: "GetFWVersion", functionId: 0x01, paramType: .index, defaultParams: []),
        ],
        0x0005: [
            HIDPPFeatureAction(name: "GetCount", functionId: 0x00, paramType: .none, defaultParams: []),
            HIDPPFeatureAction(name: "GetName", functionId: 0x01, paramType: .index, defaultParams: []),
            HIDPPFeatureAction(name: "GetType", functionId: 0x02, paramType: .none, defaultParams: []),
        ],
        0x1000: [
            HIDPPFeatureAction(name: "GetLevel", functionId: 0x00, paramType: .none, defaultParams: []),
        ],
        0x1004: [
            HIDPPFeatureAction(name: "GetStatus", functionId: 0x00, paramType: .none, defaultParams: []),
        ],
        0x1B04: [
            HIDPPFeatureAction(name: "GetCount", functionId: 0x00, paramType: .none, defaultParams: []),
            HIDPPFeatureAction(name: "GetInfo", functionId: 0x01, paramType: .index, defaultParams: []),
            HIDPPFeatureAction(name: "GetReporting", functionId: 0x02, paramType: .hex, defaultParams: [0x00, 0x50]),
            HIDPPFeatureAction(name: "SetReporting", functionId: 0x03, paramType: .hex, defaultParams: [0x00, 0x50, 0x03]),
        ],
        0x2110: [
            HIDPPFeatureAction(name: "GetStatus", functionId: 0x00, paramType: .none, defaultParams: []),
            HIDPPFeatureAction(name: "SetStatus", functionId: 0x01, paramType: .hex, defaultParams: [0x02]),
        ],
        0x2121: [
            HIDPPFeatureAction(name: "GetCapability", functionId: 0x00, paramType: .none, defaultParams: []),
            HIDPPFeatureAction(name: "GetMode", functionId: 0x01, paramType: .none, defaultParams: []),
            HIDPPFeatureAction(name: "SetMode", functionId: 0x02, paramType: .hex, defaultParams: [0x00]),
        ],
        0x2201: [
            HIDPPFeatureAction(name: "GetSensorCount", functionId: 0x00, paramType: .none, defaultParams: []),
            HIDPPFeatureAction(name: "GetDPI", functionId: 0x01, paramType: .index, defaultParams: []),
            HIDPPFeatureAction(name: "SetDPI", functionId: 0x02, paramType: .hex, defaultParams: [0x00, 0x00, 0x03, 0x20]),
            HIDPPFeatureAction(name: "GetDPIList", functionId: 0x03, paramType: .index, defaultParams: []),
        ],
        // Report Rate (0x8060): fn0 档位位图, fn1 读当前, fn2 写 (值=ms 1-8)
        0x8060: [
            HIDPPFeatureAction(name: "GetRateList", functionId: 0x00, paramType: .none, defaultParams: []),
            HIDPPFeatureAction(name: "GetRate", functionId: 0x01, paramType: .none, defaultParams: []),
            HIDPPFeatureAction(name: "SetRate", functionId: 0x02, paramType: .hex, defaultParams: [0x01]),
        ],
        // Extended Report Rate (0x8061): fn1 caps 位图, fn2 读, fn3 写 (值=档位 index 0-6)
        0x8061: [
            HIDPPFeatureAction(name: "GetCapabilities", functionId: 0x01, paramType: .none, defaultParams: []),
            HIDPPFeatureAction(name: "GetRate", functionId: 0x02, paramType: .none, defaultParams: []),
            HIDPPFeatureAction(name: "SetRate", functionId: 0x03, paramType: .hex, defaultParams: [0x00]),
        ],
        // Extended Adjustable DPI (0x2202): 只放安全的读操作; 写 (fn6) 参数因传感器而异, 用 hex 手动发
        0x2202: [
            HIDPPFeatureAction(name: "GetSensorCount", functionId: 0x00, paramType: .none, defaultParams: []),
            HIDPPFeatureAction(name: "GetSensorDPI", functionId: 0x05, paramType: .index, defaultParams: []),
        ],
    ]

    static func actions(for featureId: UInt16) -> [HIDPPFeatureAction] {
        if let known = knownActions[featureId] { return known }
        return (0...15).map { funcId in
            HIDPPFeatureAction(name: "Func \(funcId)", functionId: UInt8(funcId), paramType: .hex, defaultParams: [])
        }
    }
}

// MARK: - Debug Panel

class LogiDebugPanel: NSObject {

    #if DEBUG
    internal static var autosaveNamesSnapshotForTests: [String] {
        // List of all NSSplitView.autosaveName literals used in this file.
        // If you add a new autosaveName, you MUST update LogiPersistenceCanaryTests
        // golden list to match.
        return ["HIDDebug.FeaturesControls.v3"]
    }
    #endif

    static let shared = LogiDebugPanel()
    static let logNotification = NSNotification.Name("LogiDebugLog")

    // MARK: - Layout Constants

    private struct L {
        static let defaultWidth: CGFloat = 1200
        static let defaultHeight: CGFloat = 750
        static let minWidth: CGFloat = 1200
        static let minHeight: CGFloat = 600
        static let sidebarWidth: CGFloat = 180
        static let actionsWidth: CGFloat = 160
        static let gap: CGFloat = 8
        static let pad: CGFloat = 8
        static let btnH: CGFloat = 24
        static let btnGap: CGFloat = 4
        // Min height for Actions panel context area. Fits worst-known feature (ReprogControlsV4: 4 action buttons + params field + index stepper ≈ 168pt) with slack.
        static let ctxMinH: CGFloat = 180
        static let logToolbarH: CGFloat = 28
        static let rawInputH: CGFloat = 30
        static let sectionHdrH: CGFloat = 20
    }

    // MARK: - Window

    private var window: NSPanel?

    // MARK: - Sidebar

    private var outlineView: NSOutlineView!
    private var deviceInfoLabels: [(key: NSTextField, value: NSTextField)] = []
    private var moreInfoLabels: [(key: NSTextField, value: NSTextField)] = []

    // MARK: - Tables

    private var featureTableView: NSTableView!
    private var controlsTableView: NSTableView!

    // MARK: - Actions Panel

    private var contextActionsContainer: NSView!
    private var paramInputField: NSTextField?
    private var indexParamValue: Int = 0
    private var indexStepperLabel: NSTextField?
    private weak var featuresControlsSplit: NSSplitView?

    // MARK: - Haptic Context (0x19B0)

    private var hapticWaveformPopup: NSPopUpButton?
    private var hapticLevelSlider: NSSlider?
    private var hapticLevelValueLabel: NSTextField?
    /// 跨重建保留的波形选择 (context 区随通知整体 rebuild)
    private var hapticSelectedWaveformId: UInt8 = 0x00
    /// 自动 state/capabilities 查询节流: 响应驱动的 rebuild 不应放大成查询风暴.
    /// 按 session 记录, 快速切换设备时不误吞新设备的首次查询.
    private var hapticAutoQueryStamp: (session: ObjectIdentifier, at: Date)?

    // MARK: - Scroll Force Context (0x2111)

    private var scrollForceSlider: NSSlider?
    private var scrollForceValueLabel: NSTextField?
    /// 与 haptic 同构的自动查询节流戳
    private var scrollForceAutoQueryStamp: (session: ObjectIdentifier, at: Date)?
    /// torque 写入的 trailing 去抖: 拖动/键盘连发只在静止后发最后一次值, 防止 HID 洪泛打崩鼠标
    private var scrollForceSendWork: DispatchWorkItem?
    private var scrollForcePendingTorque: UInt8?
    private var scrollForceLastSentTorque: UInt8?

    // MARK: - Force Sensing Context (0x19C0)

    private var forceSensingSlider: NSSlider?
    private var forceSensingValueLabel: NSTextField?
    private var forceSensingAutoQueryStamp: (session: ObjectIdentifier, at: Date)?
    /// 阈值写入 trailing 去抖, 与 scroll force 同构
    private var forceSensingSendWork: DispatchWorkItem?
    private var forceSensingPendingValue: UInt16?
    private var forceSensingLastSentValue: UInt16?

    // MARK: - Log

    private var logTableView: NSTableView!
    private var filterButtons: [LogEntryType: NSButton] = [:]
    private var rawInputField: NSTextField!
    private var reportTypeControl: NSSegmentedControl!

    // MARK: - State

    /// Single source of truth: the outline view's currently selected row.
    /// Derives the active session from whichever DeviceNode / SlotNode is
    /// highlighted in the sidebar. Mutations go through `selectRowIndexes` —
    /// never assign here.
    private var currentSession: LogiDeviceSession? {
        guard let outlineView = outlineView, outlineView.selectedRow >= 0 else { return nil }
        let item = outlineView.item(atRow: outlineView.selectedRow)
        if let node = item as? DeviceNode { return node.session }
        if let node = item as? SlotNode   { return node.session }
        return nil
    }
    private var logTypeFilter: Set<LogEntryType> = Set(LogEntryType.allCases)
    /// 记录上次已渲染的 filteredLog 行数, 用于 logNotification 走增量 insertRows 而非整表 reload.
    /// 断点条件 (过滤变化 / 清空 / buffer 到达 maxLogLines 触发前置裁剪) 时回落 reloadData.
    private var lastFilteredLogCount: Int = 0
    static var logBuffer: [LogEntry] = []
    static let maxLogLines = 500
    private var logObserver: NSObjectProtocol?
    private var sessionObserver: NSObjectProtocol?
    private var reportingCompleteObserver: NSObjectProtocol?
    private var discoveryStateObserver: NSObjectProtocol?
    private var spinnerObserver: NSObjectProtocol?
    private var hapticStateObserver: NSObjectProtocol?
    private var scrollForceStateObserver: NSObjectProtocol?
    private var forceSensingStateObserver: NSObjectProtocol?
    private var auxiliaryFeaturesObserver: NSObjectProtocol?
    private var windowCloseObserver: NSObjectProtocol?

    // Header 文本基座 (不含 spinner 后缀); spinner tick 时与当前帧拼接.
    private var featuresHeaderBase: String = "FEATURES (0)"
    private var controlsHeaderBase: String = "CONTROLS (0)"

    // MARK: - Sidebar Data

    private class DeviceNode {
        let session: LogiDeviceSession
        var isReceiver: Bool { session.connectionMode == .receiver }
        init(session: LogiDeviceSession) { self.session = session }
    }

    private class SlotNode {
        let session: LogiDeviceSession
        let slot: UInt8
        init(session: LogiDeviceSession, slot: UInt8) { self.session = session; self.slot = slot }
    }

    private enum SidebarSelection: Equatable {
        case device(sessionID: ObjectIdentifier)
        case slot(sessionID: ObjectIdentifier, slot: UInt8)
    }

    private var deviceNodes: [DeviceNode] = []

    // MARK: - Feature/Control Data

    private var featureRows: [(index: String, featureId: UInt16, featureIdHex: String, name: String)] = []
    private var controlRows: [LogiDeviceSession.ControlInfo] = []
    private var selectedFeatureId: UInt16?
    private var selectedControlCID: UInt16?

    // MARK: - Logging API

    #if DEBUG
    private static let autoLogQueue = DispatchQueue(label: "me.caldis.Mos.LogiDebugPanel.autoLog")
    private static let autoLogLatestFileName = "hidpp-debug-latest.log"
    private static var autoLogInitialized = false
    private static var autoLogSessionURL: URL?
    private static var autoLogDirectoryOverride: URL?

    internal static var currentAutoLogURLForTests: URL? {
        autoLogQueue.sync { autoLogSessionURL }
    }

    internal class func setTestingAutoLogDirectory(_ directory: URL) {
        autoLogQueue.sync {
            autoLogDirectoryOverride = directory
            resetAutoLogStateLocked()
        }
    }

    internal class func resetAutoLogForTests() {
        autoLogQueue.sync {
            autoLogDirectoryOverride = nil
            resetAutoLogStateLocked()
        }
    }

    internal class func flushAutoLogForTests() {
        autoLogQueue.sync {}
    }
    #endif

    /// release 下面板从未打开时跳过全部日志开销 (@autoclosure 令字符串插值一并惰性化);
    /// DEBUG 始终记录 (autoLog 落盘依赖)。一旦打开保持开启, buffer 有 maxLogLines 上限。
    static var isLoggingEnabled: Bool {
        #if DEBUG
        return true
        #else
        return panelHasBeenShown
        #endif
    }
    private(set) static var panelHasBeenShown = false

    /// 日志条目的统一文本格式 (DEBUG autoLog 落盘与手动导出共用)
    class func formatLogEntry(_ entry: LogEntry) -> String {
        let device = entry.deviceName.isEmpty ? "" : "[\(entry.deviceName)] "
        var output = "[\(entry.timestamp)] \(device)[\(entry.type.rawValue)] \(entry.message)\n"
        if let decoded = entry.decoded {
            output += "  > \(decoded)\n"
        }
        if let rawBytes = entry.rawBytes {
            output += "  HEX: \(rawBytes.map { String(format: "%02X", $0) }.joined(separator: " "))\n"
        }
        return output
    }

    class func log(_ message: @autoclosure () -> String) {
        guard isLoggingEnabled else { return }
        let entry = LogEntry(timestamp: timestamp(), deviceName: "", type: .info, message: message(), decoded: nil, rawBytes: nil)
        appendToBuffer(entry)
    }

    class func log(device: String, type: LogEntryType, message: @autoclosure () -> String, decoded: @autoclosure () -> String? = nil, rawBytes: @autoclosure () -> [UInt8]? = nil) {
        guard isLoggingEnabled else { return }
        let entry = LogEntry(timestamp: timestamp(), deviceName: device, type: type, message: message(), decoded: decoded(), rawBytes: rawBytes())
        appendToBuffer(entry)
    }

    // Note: existing callers that pass (device:type:message:decoded:) without rawBytes
    // will use the default rawBytes: nil from the method above.

    private class func appendToBuffer(_ entry: LogEntry) {
        logBuffer.append(entry)
        if logBuffer.count > maxLogLines { logBuffer.removeFirst(logBuffer.count - maxLogLines) }
        #if DEBUG
        appendToAutoLog(entry)
        #endif
        NotificationCenter.default.post(name: logNotification, object: entry)
    }

    #if DEBUG
    private class func appendToAutoLog(_ entry: LogEntry) {
        autoLogQueue.async {
            do {
                try ensureAutoLogInitializedLocked()
                let line = formatLogEntry(entry)
                let directory = autoLogDirectoryLocked()
                let latestURL = directory.appendingPathComponent(autoLogLatestFileName)
                try append(line, to: latestURL)
                if let sessionURL = autoLogSessionURL {
                    try append(line, to: sessionURL)
                }
            } catch {
                NSLog("LogiDebugPanel: failed to write auto log: \(error)")
            }
        }
    }

    private class func ensureAutoLogInitializedLocked() throws {
        guard !autoLogInitialized else { return }

        let directory = autoLogDirectoryLocked()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let sessionURL = directory.appendingPathComponent("hidpp-debug-\(fileTimestamp()).log")
        autoLogSessionURL = sessionURL

        let header = autoLogHeader()
        try header.write(to: directory.appendingPathComponent(autoLogLatestFileName), atomically: true, encoding: .utf8)
        try header.write(to: sessionURL, atomically: true, encoding: .utf8)

        autoLogInitialized = true
    }

    private class func resetAutoLogStateLocked() {
        autoLogInitialized = false
        autoLogSessionURL = nil
    }

    private class func autoLogDirectoryLocked() -> URL {
        if let override = autoLogDirectoryOverride {
            return override
        }
        let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library", isDirectory: true)
        return library
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("Mos", isDirectory: true)
    }

    private class func autoLogHeader() -> String {
        return [
            "# Mos HID++ debug log",
            "# Session started: \(fullTimestamp())",
            "# Latest file: \(autoLogLatestFileName)",
            "",
        ].joined(separator: "\n")
    }

    private class func append(_ text: String, to url: URL) throws {
        let data = Data(text.utf8)
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: url)
        defer { handle.closeFile() }
        handle.seekToEndOfFile()
        handle.write(data)
    }
    #endif

    // DateFormatter 创建成本毫秒级, 缓存复用; 仅主线程调用 (HID 回调与 UI 均在主 RunLoop)
    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()
    private static func timestamp() -> String {
        return timestampFormatter.string(from: Date())
    }

    #if DEBUG
    private static func fullTimestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS ZZZZZ"
        return f.string(from: Date())
    }

    private static func fileTimestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd-HHmmss"
        return f.string(from: Date())
    }
    #endif

    // MARK: - Show / Hide

    func show() {
        LogiDebugPanel.panelHasBeenShown = true
        if let w = window {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            refreshAll()
            startObserving()
            return
        }
        let w = buildWindow()
        window = w
        refreshAll()
        startObserving()
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Build Window

    private func buildWindow() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: L.defaultWidth, height: L.defaultHeight),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "Logitech HID++ Debug"
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.minSize = NSSize(width: L.minWidth, height: L.minHeight)
        panel.center()
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        // 关闭时停止观察 (spinner 定时器/日志观察者随之释放), show() 会重新注册
        panel.delegate = self
        panel.hasShadow = true
        panel.hidesOnDeactivate = false

        let effectView = NSVisualEffectView(frame: NSRect(origin: .zero, size: panel.frame.size))
        effectView.autoresizingMask = [.width, .height]
        effectView.state = .active
        effectView.blendingMode = .behindWindow
        panel.appearance = NSAppearance(named: .vibrantDark)
        if #available(macOS 10.14, *) {
            effectView.material = .hudWindow
        } else {
            effectView.material = .dark
        }
        panel.contentView = effectView

        let topInset = resolvedTopInset(for: panel)
        buildContent(in: effectView, topInset: topInset)

        windowCloseObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: panel, queue: .main
        ) { [weak self] _ in self?.stopObserving() }

        return panel
    }

    private func resolvedTopInset(for panel: NSPanel) -> CGFloat {
        let titlebarH = panel.frame.height - panel.contentLayoutRect.height
        return max(L.pad, titlebarH + 4)
    }

    // Flipped view for containers with manually-positioned dynamic content
    private final class FlippedView: NSView {
        override var isFlipped: Bool { return true }
    }
    // Flipped NSSplitView so first subview = top
    private final class TopFirstSplitView: NSSplitView {
        override var isFlipped: Bool { return true }
        override var dividerThickness: CGFloat { return 8 }
        override func drawDivider(in rect: NSRect) {
            // Draw nothing — gap between rounded-corner sections is the visual divider
        }
    }

    // Horizontal NSSplitView (isVertical = true → children arranged left/right).
    // Invisible divider to match the rounded-section aesthetic; the gap itself is the visual cue.
    private final class HorizontalSplitView: NSSplitView {
        override var dividerThickness: CGFloat { return 8 }
        override func drawDivider(in rect: NSRect) { /* no-op */ }
    }

    // Table header cell that skips the default gradient chrome and renders only its attributed text.
    private final class DarkHeaderCell: NSTableHeaderCell {
        override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
            drawInterior(withFrame: cellFrame, in: controlView)
        }
    }

    // Table header view with transparent bg + subtle bottom divider.
    private final class DarkHeaderView: NSTableHeaderView {
        override func draw(_ dirtyRect: NSRect) {
            NSColor.clear.setFill()
            dirtyRect.fill()
            let border = NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1)
            NSColor(calibratedWhite: 1.0, alpha: 0.08).setFill()
            border.fill()
            if let table = tableView {
                for i in 0..<table.numberOfColumns {
                    let cellRect = headerRect(ofColumn: i)
                    guard dirtyRect.intersects(cellRect) else { continue }
                    table.tableColumns[i].headerCell.draw(withFrame: cellRect, in: self)
                }
            }
        }
    }

    // MARK: - Build Content (Auto Layout)

    private func buildContent(in container: NSView, topInset: CGFloat) {
        // --- Sidebar ---
        let sidebar = NSView()
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(sidebar)
        buildSidebar(in: sidebar)

        // --- Main split: top area / log area ---
        let split = TopFirstSplitView()
        split.isVertical = false
        split.dividerStyle = .thin
        split.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(split)

        NSLayoutConstraint.activate([
            sidebar.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            sidebar.topAnchor.constraint(equalTo: container.topAnchor, constant: topInset),
            sidebar.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8),
            sidebar.widthAnchor.constraint(equalToConstant: L.sidebarWidth),

            split.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: L.gap),
            split.topAnchor.constraint(equalTo: container.topAnchor, constant: topInset),
            split.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            split.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8),
        ])

        // NSSplitView subviews — managed by split, NOT by constraints
        let topContainer = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 280))
        buildTopArea(in: topContainer)
        split.addSubview(topContainer)

        let logContainer = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 420))
        buildLogArea(in: logContainer)
        split.addSubview(logContainer)
    }

    // MARK: - Build Sidebar (Auto Layout + NSSplitView for draggable device info)

    private func buildSidebar(in sidebar: NSView) {
        // Draggable split between device tree and device info
        let sidebarSplit = TopFirstSplitView()
        sidebarSplit.isVertical = false
        sidebarSplit.dividerStyle = .thin
        sidebarSplit.translatesAutoresizingMaskIntoConstraints = false
        sidebar.addSubview(sidebarSplit)

        NSLayoutConstraint.activate([
            sidebarSplit.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor),
            sidebarSplit.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            sidebarSplit.topAnchor.constraint(equalTo: sidebar.topAnchor),
            sidebarSplit.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor),
        ])

        // Top section: device tree with header inside the rounded block
        let treeContainer = FlippedView(frame: NSRect(x: 0, y: 0, width: L.sidebarWidth, height: 200))
        let treeBg = makeSectionBg()
        treeBg.autoresizingMask = [.width, .height]
        treeBg.frame = treeContainer.bounds
        treeContainer.addSubview(treeBg)

        let header = makeSectionHeader("DEVICES")
        header.frame = NSRect(x: L.pad, y: 4, width: L.sidebarWidth - L.pad * 2, height: 16)
        header.autoresizingMask = [.width]
        treeContainer.addSubview(header)

        let treeScroll = NSScrollView()
        treeScroll.frame = NSRect(x: 4, y: L.sectionHdrH, width: L.sidebarWidth - 8, height: 200 - L.sectionHdrH - 4)
        treeScroll.autoresizingMask = [.width, .height]
        configureDarkScroll(treeScroll)

        let outline = NSOutlineView()
        outline.headerView = nil
        outline.backgroundColor = .clear
        outline.selectionHighlightStyle = .regular
        outline.indentationPerLevel = 14
        outline.rowHeight = 22
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("device"))
        col.resizingMask = .autoresizingMask
        outline.addTableColumn(col)
        outline.outlineTableColumn = col
        outline.delegate = self
        outline.dataSource = self
        outline.target = self
        outline.action = #selector(outlineViewClicked(_:))
        treeScroll.documentView = outline
        self.outlineView = outline
        treeContainer.addSubview(treeScroll)
        sidebarSplit.addSubview(treeContainer)

        // Bottom section: device info with its own rounded bg
        let infoContainer = NSView(frame: NSRect(x: 0, y: 0, width: L.sidebarWidth, height: 250))
        let infoBg = makeSectionBg()
        infoBg.autoresizingMask = [.width, .height]
        infoBg.frame = infoContainer.bounds
        infoContainer.addSubview(infoBg)

        let infoScroll = NSScrollView()
        infoScroll.autoresizingMask = [.width, .height]
        infoScroll.frame = infoContainer.bounds
        configureDarkScroll(infoScroll)

        let allKeys = ["VID", "PID", "Protocol", "Transport", "Dev Index", "Conn Mode", "Opened",
                        "UsagePage", "Usage", "HID++ Cand", "Init Done", "Dvrt CIDs", "Target"]
        let contentH: CGFloat = CGFloat(allKeys.count) * 16 + L.pad
        let infoDoc = FlippedView(frame: NSRect(x: 0, y: 0, width: L.sidebarWidth, height: contentH))
        var iy: CGFloat = L.pad
        let keyW: CGFloat = 65
        let valX: CGFloat = keyW + 4
        deviceInfoLabels.removeAll()
        moreInfoLabels.removeAll()
        for (i, keyText) in allKeys.enumerated() {
            let kl = makeLabel(text: keyText, fontSize: 9, weight: .medium, color: .tertiaryLabelColor)
            kl.font = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium)
            kl.frame = NSRect(x: L.pad, y: iy, width: keyW, height: 14)
            infoDoc.addSubview(kl)
            let vl = makeLabel(text: "--", fontSize: 9, color: .secondaryLabelColor)
            vl.font = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular)
            vl.frame = NSRect(x: valX, y: iy, width: L.sidebarWidth - valX - L.pad, height: 14)
            infoDoc.addSubview(vl)
            if i < 7 { deviceInfoLabels.append((key: kl, value: vl)) }
            else { moreInfoLabels.append((key: kl, value: vl)) }
            iy += 16
        }
        infoScroll.documentView = infoDoc
        infoContainer.addSubview(infoScroll)
        sidebarSplit.addSubview(infoContainer)
    }

    @objc private func outlineViewClicked(_ sender: Any?) {
        // 点接收器父行(不可选)不做任何事: 否则会带着"仍停在上一个 slot"的 selectedRow
        // 误触发那个 slot 的 rediscover. 展开/收起由 disclosure 三角自行处理.
        if outlineView.clickedRow >= 0,
           let clicked = outlineView.item(atRow: outlineView.clickedRow) as? DeviceNode,
           clicked.isReceiver {
            return
        }
        let row = outlineView.selectedRow
        guard row >= 0 else { return }
        let item = outlineView.item(atRow: row)

        if item is DeviceNode {
            // currentSession is computed from outlineView.selectedRow — already reflects this click.
            selectedFeatureId = nil
            selectedControlCID = nil
            refreshRightPanels()
        } else if let slot = item as? SlotNode {
            // Validate slot is online
            let paired = slot.session.debugReceiverPairedDevices
            let idx = Int(slot.slot) - 1
            guard idx >= 0, idx < paired.count, paired[idx].isConnected else { return }
            // 轻量巡检切换: 已发现的 slot 只切游标读缓存, 不重跑 REPROG 发现(接管已常驻);
            // 未发现的 slot inspectSlot 内部回退到完整重发现.
            slot.session.inspectSlot(slot.slot)
            refreshRightPanels()
            // 兜底刷一次(可选功能探测异步 / 回退重发现时防 UI 卡 loading).
            scheduleFallbackRefresh(after: FallbackRefreshDelay.afterDiscovery)
        }
    }

    // MARK: - Build Top Area (Auto Layout)

    private func buildTopArea(in parent: NSView) {
        let aCol = NSView()
        aCol.translatesAutoresizingMaskIntoConstraints = false
        parent.addSubview(aCol)

        let fcSplit = HorizontalSplitView()
        fcSplit.isVertical = true
        fcSplit.dividerStyle = .thin
        // v3: 提高 Controls 默认宽度以放下 CID(60) + Name(150) + Flags(200) + Status(50) = 460pt
        //     而不依赖 uniform autoresize 把余量分给弹性列. 换 name 让旧 v2 位置作废.
        fcSplit.autosaveName = "HIDDebug.FeaturesControls.v3"
        fcSplit.delegate = self
        fcSplit.translatesAutoresizingMaskIntoConstraints = false
        parent.addSubview(fcSplit)
        self.featuresControlsSplit = fcSplit

        NSLayoutConstraint.activate([
            fcSplit.leadingAnchor.constraint(equalTo: parent.leadingAnchor),
            fcSplit.topAnchor.constraint(equalTo: parent.topAnchor),
            fcSplit.bottomAnchor.constraint(equalTo: parent.bottomAnchor),
            fcSplit.trailingAnchor.constraint(equalTo: aCol.leadingAnchor, constant: -L.gap),

            aCol.topAnchor.constraint(equalTo: parent.topAnchor),
            aCol.bottomAnchor.constraint(equalTo: parent.bottomAnchor),
            aCol.trailingAnchor.constraint(equalTo: parent.trailingAnchor),
            aCol.widthAnchor.constraint(equalToConstant: L.actionsWidth),
        ])

        // Default split ratio ~36:64 (Features:Controls). Features only has 3 narrow
        // columns (Idx/ID/Name) so a smaller default leaves room for Controls' 4 columns
        // to show worst-case strings ("Mouse,Reprog,Divert,RawXY", "3rd-DVRT") without
        // truncation. autosaveName preserves any user-chosen position over this default.
        let fCol = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 280))
        let cCol = NSView(frame: NSRect(x: 0, y: 0, width: 520, height: 280))
        fcSplit.addSubview(fCol)
        fcSplit.addSubview(cCol)

        buildTableColumn(in: fCol, headerTag: 100, headerText: "FEATURES (0)", tableTag: 200,
                          columns: [("fIdx", "Idx", 36, 36, false),
                                    ("fId", "ID", 50, 50, false),
                                    ("fName", "Name", 160, 120, true)],
                          action: #selector(featureTableClicked(_:)), isFeature: true)
        buildTableColumn(in: cCol, headerTag: 101, headerText: "CONTROLS (0)", tableTag: 201,
                          columns: [("cCid", "CID", 60, 60, false),
                                    ("cName", "Name", 140, 120, true),
                                    ("cFlags", "Flags", 190, 170, true),
                                    ("cStatus", "Status", 68, 68, false)],
                          action: #selector(controlsTableClicked(_:)), isFeature: false)
        buildActionsPanel(in: aCol)
    }

    /// Build a table column section: bg + section header + dark column headers + scrollView/table
    private func buildTableColumn(in parent: NSView, headerTag: Int, headerText: String,
                                   tableTag: Int,
                                   columns: [(id: String, title: String, width: CGFloat, minWidth: CGFloat, isFlex: Bool)],
                                   action: Selector, isFeature: Bool) {
        let bg = makeSectionBg()
        bg.translatesAutoresizingMaskIntoConstraints = false
        parent.addSubview(bg)

        let header = makeSectionHeader(headerText)
        header.translatesAutoresizingMaskIntoConstraints = false
        header.tag = headerTag
        parent.addSubview(header)

        let sv = NSScrollView()
        sv.translatesAutoresizingMaskIntoConstraints = false
        configureDarkScroll(sv)
        parent.addSubview(sv)

        NSLayoutConstraint.activate([
            bg.leadingAnchor.constraint(equalTo: parent.leadingAnchor),
            bg.trailingAnchor.constraint(equalTo: parent.trailingAnchor),
            bg.topAnchor.constraint(equalTo: parent.topAnchor),
            bg.bottomAnchor.constraint(equalTo: parent.bottomAnchor),

            header.leadingAnchor.constraint(equalTo: parent.leadingAnchor, constant: L.pad),
            header.trailingAnchor.constraint(equalTo: parent.trailingAnchor, constant: -L.pad),
            header.topAnchor.constraint(equalTo: parent.topAnchor, constant: 4),
            header.heightAnchor.constraint(equalToConstant: 16),

            sv.leadingAnchor.constraint(equalTo: parent.leadingAnchor, constant: 4),
            sv.trailingAnchor.constraint(equalTo: parent.trailingAnchor, constant: -4),
            sv.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 2),
            sv.bottomAnchor.constraint(equalTo: parent.bottomAnchor, constant: -4),
        ])

        let table = NSTableView()
        table.backgroundColor = .clear
        table.headerView = DarkHeaderView()
        table.selectionHighlightStyle = .regular
        table.rowHeight = 20
        table.tag = tableTag
        table.delegate = self
        table.dataSource = self
        table.target = self
        table.action = action
        table.columnAutoresizingStyle = isFeature ? .lastColumnOnlyAutoresizingStyle : .uniformColumnAutoresizingStyle

        let headerAttrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.secondaryLabelColor,
            .font: NSFont.systemFont(ofSize: 10, weight: .medium),
        ]
        for (id, title, w, minW, isFlex) in columns {
            let c = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            let headerCell = DarkHeaderCell(textCell: title)
            headerCell.attributedStringValue = NSAttributedString(string: title, attributes: headerAttrs)
            c.headerCell = headerCell
            c.minWidth = minW > 0 ? minW : 40
            c.width = w > 0 ? w : 100
            c.resizingMask = isFlex ? .autoresizingMask : []
            table.addTableColumn(c)
        }
        sv.documentView = table
        // Features 只有一列弹性(Name)且在最后位, sizeLastColumnToFit 合适.
        // Controls 的最后列是 Status(固定 50pt, 不该被拉大), 跳过这个调用避免覆盖.
        if isFeature {
            table.sizeLastColumnToFit()
        }

        if isFeature { self.featureTableView = table }
        else { self.controlsTableView = table }
    }

    // MARK: - Actions Panel (Auto Layout)

    private func buildActionsPanel(in parent: NSView) {
        let bg = makeSectionBg()
        bg.translatesAutoresizingMaskIntoConstraints = false
        parent.addSubview(bg)

        let header = makeSectionHeader("ACTIONS")
        header.translatesAutoresizingMaskIntoConstraints = false
        parent.addSubview(header)

        let ctxC = FlippedView()
        ctxC.translatesAutoresizingMaskIntoConstraints = false
        parent.addSubview(ctxC)
        self.contextActionsContainer = ctxC

        let placeholder = makeLabel(text: "Select a feature\nor control", fontSize: 10, color: .tertiaryLabelColor)
        placeholder.translatesAutoresizingMaskIntoConstraints = false
        placeholder.alignment = .center
        placeholder.maximumNumberOfLines = 2
        ctxC.addSubview(placeholder)
        NSLayoutConstraint.activate([
            placeholder.leadingAnchor.constraint(equalTo: ctxC.leadingAnchor, constant: L.pad),
            placeholder.trailingAnchor.constraint(equalTo: ctxC.trailingAnchor, constant: -L.pad),
            placeholder.topAnchor.constraint(equalTo: ctxC.topAnchor, constant: L.pad),
        ])

        let sep = makeSep()
        sep.translatesAutoresizingMaskIntoConstraints = false
        parent.addSubview(sep)

        let globalC = FlippedView()
        globalC.translatesAutoresizingMaskIntoConstraints = false
        parent.addSubview(globalC)

        let globalH: CGFloat = CGFloat(5) * L.btnH + CGFloat(4) * L.btnGap + L.pad

        NSLayoutConstraint.activate([
            bg.leadingAnchor.constraint(equalTo: parent.leadingAnchor),
            bg.trailingAnchor.constraint(equalTo: parent.trailingAnchor),
            bg.topAnchor.constraint(equalTo: parent.topAnchor),
            bg.bottomAnchor.constraint(equalTo: parent.bottomAnchor),

            header.leadingAnchor.constraint(equalTo: parent.leadingAnchor, constant: L.pad),
            header.trailingAnchor.constraint(equalTo: parent.trailingAnchor, constant: -L.pad),
            header.topAnchor.constraint(equalTo: parent.topAnchor, constant: 4),
            header.heightAnchor.constraint(equalToConstant: 16),

            ctxC.leadingAnchor.constraint(equalTo: parent.leadingAnchor),
            ctxC.trailingAnchor.constraint(equalTo: parent.trailingAnchor),
            ctxC.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 2),
            ctxC.bottomAnchor.constraint(equalTo: sep.topAnchor),
            ctxC.heightAnchor.constraint(greaterThanOrEqualToConstant: L.ctxMinH),

            sep.leadingAnchor.constraint(equalTo: parent.leadingAnchor, constant: L.pad),
            sep.trailingAnchor.constraint(equalTo: parent.trailingAnchor, constant: -L.pad),
            sep.heightAnchor.constraint(equalToConstant: 1),

            globalC.leadingAnchor.constraint(equalTo: parent.leadingAnchor),
            globalC.trailingAnchor.constraint(equalTo: parent.trailingAnchor),
            globalC.topAnchor.constraint(equalTo: sep.bottomAnchor, constant: L.pad),
            globalC.bottomAnchor.constraint(equalTo: parent.bottomAnchor),
            globalC.heightAnchor.constraint(equalToConstant: globalH),
        ])

        let btnW = L.actionsWidth - L.pad * 2
        var by: CGFloat = 0
        for (title, action) in [("Re-Discover", #selector(rediscoverClicked)),
                                 ("Re-Divert", #selector(redivertClicked)),
                                 ("Undivert All", #selector(undivertClicked)),
                                 ("Enumerate", #selector(enumerateClicked)),
                                 ("Clear Log", #selector(clearLogClicked))] {
            let btn = makeActionBtn(title: title, action: action)
            btn.frame = NSRect(x: L.pad, y: by, width: btnW, height: L.btnH)
            globalC.addSubview(btn)
            by += L.btnH + L.btnGap
        }
    }

    // MARK: - Build Log Area (Auto Layout)

    private func buildLogArea(in parent: NSView) {
        let bg = makeLogBg()
        bg.translatesAutoresizingMaskIntoConstraints = false
        parent.addSubview(bg)

        let toolbar = NSView()
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        parent.addSubview(toolbar)
        buildLogToolbar(in: toolbar)

        let sv = NSScrollView()
        sv.translatesAutoresizingMaskIntoConstraints = false
        configureDarkScroll(sv)
        parent.addSubview(sv)

        let table = NSTableView()
        table.backgroundColor = .clear
        table.headerView = nil
        table.selectionHighlightStyle = .none
        table.rowHeight = 18
        table.tag = 300
        table.delegate = self
        table.dataSource = self
        table.target = self
        table.action = #selector(logRowClicked(_:))
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        let logCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("log"))
        logCol.resizingMask = .autoresizingMask
        table.addTableColumn(logCol)
        sv.documentView = table
        table.sizeLastColumnToFit()
        self.logTableView = table

        let rawBar = NSView()
        rawBar.translatesAutoresizingMaskIntoConstraints = false
        parent.addSubview(rawBar)
        buildRawInputBar(in: rawBar)

        NSLayoutConstraint.activate([
            bg.leadingAnchor.constraint(equalTo: parent.leadingAnchor),
            bg.trailingAnchor.constraint(equalTo: parent.trailingAnchor),
            bg.topAnchor.constraint(equalTo: parent.topAnchor),
            bg.bottomAnchor.constraint(equalTo: parent.bottomAnchor),

            toolbar.leadingAnchor.constraint(equalTo: parent.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: parent.trailingAnchor),
            toolbar.topAnchor.constraint(equalTo: parent.topAnchor, constant: 4),
            toolbar.heightAnchor.constraint(equalToConstant: L.logToolbarH),

            sv.leadingAnchor.constraint(equalTo: parent.leadingAnchor),
            sv.trailingAnchor.constraint(equalTo: parent.trailingAnchor),
            sv.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            sv.bottomAnchor.constraint(equalTo: rawBar.topAnchor, constant: -4),

            rawBar.leadingAnchor.constraint(equalTo: parent.leadingAnchor),
            rawBar.trailingAnchor.constraint(equalTo: parent.trailingAnchor),
            rawBar.bottomAnchor.constraint(equalTo: parent.bottomAnchor),
            rawBar.heightAnchor.constraint(equalToConstant: L.rawInputH),
        ])
    }

    private func buildLogToolbar(in toolbar: NSView) {
        let logLabel = makeSectionHeader("PROTOCOL LOG")
        logLabel.frame = NSRect(x: L.pad, y: 6, width: 100, height: 16)
        logLabel.autoresizingMask = []
        toolbar.addSubview(logLabel)

        let chipColors: [(LogEntryType, String, NSColor)] = [
            (.tx, "TX", NSColor(calibratedRed: 0.4, green: 0.6, blue: 1.0, alpha: 1.0)),
            (.rx, "RX", NSColor(calibratedRed: 0.3, green: 0.8, blue: 0.4, alpha: 1.0)),
            (.error, "ERR", NSColor(calibratedRed: 1.0, green: 0.3, blue: 0.3, alpha: 1.0)),
            (.buttonEvent, "BTN", NSColor(calibratedRed: 1.0, green: 0.8, blue: 0.2, alpha: 1.0)),
            (.warning, "WARN", NSColor(calibratedRed: 1.0, green: 0.6, blue: 0.2, alpha: 1.0)),
            (.info, "INFO", NSColor(calibratedWhite: 0.75, alpha: 1.0)),
        ]
        var fx: CGFloat = 110
        for (i, (entryType, label, color)) in chipColors.enumerated() {
            let btn = NSButton(title: label, target: self, action: #selector(filterChipClicked(_:)))
            btn.isBordered = false
            btn.wantsLayer = true
            btn.layer?.backgroundColor = color.withAlphaComponent(0.3).cgColor
            btn.layer?.cornerRadius = 3
            btn.font = NSFont.systemFont(ofSize: 9, weight: .medium)
            if #available(macOS 10.14, *) { btn.contentTintColor = color }
            btn.tag = i
            btn.frame = NSRect(x: fx, y: 4, width: 38, height: 20)
            btn.autoresizingMask = []
            toolbar.addSubview(btn)
            filterButtons[entryType] = btn
            fx += 42
        }

        let clearBtn = makeActionBtn(title: "Clear", action: #selector(clearLogClicked))
        clearBtn.frame = NSRect(x: 0, y: 4, width: 42, height: 20)
        clearBtn.font = NSFont.systemFont(ofSize: 9, weight: .medium)
        clearBtn.autoresizingMask = [.minXMargin]
        toolbar.addSubview(clearBtn)
        // Pin to right with constraints
        clearBtn.translatesAutoresizingMaskIntoConstraints = true
        clearBtn.autoresizingMask = [.minXMargin]

        let exportBtn = makeActionBtn(title: "Export", action: #selector(exportLogClicked))
        exportBtn.frame = NSRect(x: 0, y: 4, width: 46, height: 20)
        exportBtn.font = NSFont.systemFont(ofSize: 9, weight: .medium)
        exportBtn.autoresizingMask = [.minXMargin]
        toolbar.addSubview(exportBtn)

        let selfTestBtn = makeActionBtn(title: "Self-Test\u{2026}", action: #selector(selfTestClicked))
        selfTestBtn.frame = NSRect(x: 0, y: 4, width: 70, height: 20)
        selfTestBtn.font = NSFont.systemFont(ofSize: 9, weight: .medium)
        selfTestBtn.autoresizingMask = [.minXMargin]
        toolbar.addSubview(selfTestBtn)

        // Position clear/export/self-test from right using frame + autoresizingMask
        // Will be repositioned after layout
        toolbar.postsFrameChangedNotifications = true
        // token 必须持有: block 式观察者不会随视图释放自动移除, 丢弃 token 意味着
        // NotificationCenter 永久强持有闭包及其捕获的按钮。生命周期与窗口一致
        // (窗口只构建一次且 isReleasedWhenClosed=false), deinit 时统一移除。
        let token = NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: toolbar, queue: .main) { _ in
            let w = toolbar.bounds.width
            clearBtn.frame.origin.x = w - 50
            exportBtn.frame.origin.x = w - 100
            // exportBtn.x (w-100) - selfTest width (70) - gap (4) = w - 174
            selfTestBtn.frame.origin.x = w - 174
        }
        layoutObserverTokens.append(token)
    }

    @objc private func selfTestClicked() {
        #if DEBUG
        LogiSelfTestWizard.shared.show()
        #endif
    }

    private func buildRawInputBar(in container: NSView) {
        let sep = makeSep()
        sep.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(sep)

        let rawLabel = makeLabel(text: "RAW:", fontSize: 10, weight: .medium, color: .tertiaryLabelColor)
        rawLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(rawLabel)

        let segCtrl = NSSegmentedControl(labels: ["Short 7B", "Long 20B"], trackingMode: .selectOne, target: nil, action: nil)
        segCtrl.selectedSegment = 1
        segCtrl.translatesAutoresizingMaskIntoConstraints = false
        segCtrl.font = NSFont.systemFont(ofSize: 9)
        container.addSubview(segCtrl)
        self.reportTypeControl = segCtrl

        let inputField = NSTextField()
        inputField.font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        inputField.placeholderString = "11 FF 00 01 1B 04 00 ..."
        inputField.translatesAutoresizingMaskIntoConstraints = false
        inputField.wantsLayer = true
        inputField.layer?.cornerRadius = 3
        inputField.textColor = .labelColor
        inputField.backgroundColor = NSColor(calibratedWhite: 1.0, alpha: 0.06)
        inputField.isBezeled = false
        container.addSubview(inputField)
        self.rawInputField = inputField

        let sendBtn = makeActionBtn(title: "Send", action: #selector(sendRawClicked),
                                    color: NSColor(calibratedRed: 0.3, green: 0.8, blue: 0.4, alpha: 1.0))
        sendBtn.translatesAutoresizingMaskIntoConstraints = false
        sendBtn.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        container.addSubview(sendBtn)

        NSLayoutConstraint.activate([
            sep.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: L.pad),
            sep.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -L.pad),
            sep.topAnchor.constraint(equalTo: container.topAnchor),
            sep.heightAnchor.constraint(equalToConstant: 1),

            rawLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: L.pad),
            rawLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            rawLabel.widthAnchor.constraint(equalToConstant: 35),

            segCtrl.leadingAnchor.constraint(equalTo: rawLabel.trailingAnchor, constant: 4),
            segCtrl.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            segCtrl.widthAnchor.constraint(equalToConstant: 120),

            inputField.leadingAnchor.constraint(equalTo: segCtrl.trailingAnchor, constant: 8),
            inputField.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            inputField.trailingAnchor.constraint(equalTo: sendBtn.leadingAnchor, constant: -8),
            inputField.heightAnchor.constraint(equalToConstant: 20),

            sendBtn.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -L.pad),
            sendBtn.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            sendBtn.widthAnchor.constraint(equalToConstant: 42),
            sendBtn.heightAnchor.constraint(equalToConstant: 20),
        ])
    }

    // MARK: - Table Click Handlers

    @objc private func featureTableClicked(_ sender: Any?) {
        let row = featureTableView.selectedRow
        controlsTableView?.deselectAll(nil)
        selectedControlCID = nil
        guard row >= 0, row < featureRows.count else { selectedFeatureId = nil; updateContextActions(); return }
        selectedFeatureId = featureRows[row].featureId
        updateContextActions()
    }

    @objc private func controlsTableClicked(_ sender: Any?) {
        let row = controlsTableView.selectedRow
        featureTableView?.deselectAll(nil)
        selectedFeatureId = nil
        guard row >= 0, row < controlRows.count else { selectedControlCID = nil; updateContextActions(); return }
        selectedControlCID = controlRows[row].cid
        updateContextActions()
    }

    private func updateContextActions() {
        guard let container = contextActionsContainer else { return }
        container.subviews.forEach { $0.removeFromSuperview() }
        let w = container.bounds.width - L.pad * 2
        var by: CGFloat = 0

        if let featureId = selectedFeatureId {
            if featureId == LogiDeviceSession.featureHaptic, let session = currentSession {
                buildHapticContext(in: container, session: session, width: w)
                return
            }
            if featureId == LogiDeviceSession.featureSmartShiftEnhanced, let session = currentSession {
                buildScrollForceContext(in: container, session: session, width: w)
                return
            }
            if featureId == LogiDeviceSession.featureForceSensing, let session = currentSession {
                buildForceSensingContext(in: container, session: session, width: w)
                return
            }
            let actions = HIDPPFeatureActions.actions(for: featureId)
            for action in actions {
                let btn = makeActionBtn(title: action.name, action: #selector(featureActionClicked(_:)))
                btn.tag = Int(action.functionId)
                btn.frame = NSRect(x: L.pad, y: by, width: w, height: L.btnH)
                container.addSubview(btn)
                by += L.btnH + L.btnGap
            }
            by += 4
            let pf = makeInputField(placeholder: "params (hex)")
            pf.frame = NSRect(x: L.pad, y: by, width: w, height: L.btnH)
            container.addSubview(pf)
            self.paramInputField = pf
            by += L.btnH + L.btnGap

            // Reset index on each feature switch (matches prior behavior — stepper used to
            // be re-created at 0 every rebuild).
            indexParamValue = 0

            let stepW: CGFloat = 22
            let stepGap: CGFloat = 2
            let indexRow = FlippedView(frame: NSRect(x: L.pad, y: by, width: w, height: L.btnH))
            let labelW = w - (stepW * 2 + stepGap)

            let sl = makeLabel(text: "Index: 0", fontSize: 11, color: .secondaryLabelColor)
            sl.alignment = .left
            sl.frame = NSRect(x: 0, y: 0, width: labelW, height: L.btnH)
            sl.cell?.lineBreakMode = .byTruncatingTail
            indexRow.addSubview(sl)
            self.indexStepperLabel = sl

            let minusBtn = makeStepBtn(title: "−", action: #selector(indexMinusClicked))
            minusBtn.frame = NSRect(x: labelW, y: 1, width: stepW, height: stepW)
            indexRow.addSubview(minusBtn)

            let plusBtn = makeStepBtn(title: "+", action: #selector(indexPlusClicked))
            plusBtn.frame = NSRect(x: labelW + stepW + stepGap, y: 1, width: stepW, height: stepW)
            indexRow.addSubview(plusBtn)

            container.addSubview(indexRow)
            by += L.btnH + L.btnGap

        } else if let cid = selectedControlCID {
            let isDiverted = currentSession?.debugDivertedCIDs.contains(cid) ?? false
            let divertBtn = makeActionBtn(title: isDiverted ? "Undivert" : "Divert", action: #selector(toggleDivertClicked))
            divertBtn.frame = NSRect(x: L.pad, y: by, width: w, height: L.btnH)
            container.addSubview(divertBtn)
            by += L.btnH + L.btnGap

            let queryBtn = makeActionBtn(title: "Query Reporting", action: #selector(queryReportingClicked))
            queryBtn.frame = NSRect(x: L.pad, y: by, width: w, height: L.btnH)
            container.addSubview(queryBtn)
            by += L.btnH + L.btnGap + 4

            // Show current flags and target CID
            if let ctrl = controlRows.first(where: { $0.cid == cid }) {
                let flagsText = "Flags: \(HIDPPInfo.flagsDescription(ctrl.flags))"
                let fl = makeLabel(text: flagsText, fontSize: 9, color: .secondaryLabelColor)
                fl.frame = NSRect(x: L.pad, y: by, width: w, height: 14)
                container.addSubview(fl)
                by += 16

                if ctrl.targetCID != 0 && ctrl.targetCID != ctrl.cid {
                    let targetText = "Target: \(String(format: "0x%04X", ctrl.targetCID))"
                    let tl = makeLabel(text: targetText, fontSize: 9, color: .secondaryLabelColor)
                    tl.frame = NSRect(x: L.pad, y: by, width: w, height: 14)
                    container.addSubview(tl)
                }
            }
        } else {
            let ph = makeLabel(text: "Select a feature\nor control", fontSize: 10, color: .tertiaryLabelColor)
            ph.translatesAutoresizingMaskIntoConstraints = false
            ph.alignment = .center
            ph.maximumNumberOfLines = 2
            container.addSubview(ph)
            NSLayoutConstraint.activate([
                ph.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: L.pad),
                ph.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -L.pad),
                ph.topAnchor.constraint(equalTo: container.topAnchor, constant: L.pad),
            ])
        }
    }

    // MARK: - Haptic Context UI

    /// HAPTIC feature 选中时的专属操作区: 波形选择 + 播放, 强度滑杆, 状态回读.
    /// 布局语言与通用 context 一致 (手排 frame + FlippedView 坐标系).
    private func buildHapticContext(in container: NSView, session: LogiDeviceSession, width w: CGFloat) {
        let state = session.debugHapticState
        let mask = session.debugHapticWaveformMask
        var by: CGFloat = 0

        // 首次选中 (或设备未应答过) 时自动拉取 capabilities + state; 同一 session 1s 节流防响应驱动的查询风暴
        if state == nil || mask == nil {
            let sid = ObjectIdentifier(session)
            let throttled = hapticAutoQueryStamp.map {
                $0.session == sid && Date().timeIntervalSince($0.at) < 1.0
            } ?? false
            if !throttled {
                hapticAutoQueryStamp = (sid, Date())
                session.hapticRefreshInfo()
            }
        }

        // 波形选择
        let popup = NSPopUpButton(frame: NSRect(x: L.pad, y: by, width: w, height: L.btnH), pullsDown: false)
        stylePopupButton(popup)
        let menu = NSMenu()
        menu.autoenablesItems = false
        for wf in HIDPPInfo.hapticWaveforms {
            let item = NSMenuItem(title: wf.name, action: nil, keyEquivalent: "")
            item.tag = Int(wf.id)
            if let mask = mask { item.isEnabled = (mask >> UInt32(wf.id)) & 1 != 0 }
            menu.addItem(item)
        }
        popup.menu = menu
        popup.target = self
        popup.action = #selector(hapticWaveformChanged(_:))
        // 恢复上次选择; 若该波形被设备能力位掩码禁用则回落到第一个可用项
        let restoreIdx = menu.items.firstIndex { $0.tag == Int(hapticSelectedWaveformId) && $0.isEnabled }
            ?? menu.items.firstIndex { $0.isEnabled } ?? 0
        popup.selectItem(at: restoreIdx)
        hapticSelectedWaveformId = UInt8(menu.items[restoreIdx].tag)
        container.addSubview(popup)
        self.hapticWaveformPopup = popup
        by += L.btnH + L.btnGap

        let playBtn = makeActionBtn(title: "Play Waveform", action: #selector(hapticPlayClicked))
        playBtn.frame = NSRect(x: L.pad, y: by, width: w, height: L.btnH)
        container.addSubview(playBtn)
        by += L.btnH + L.btnGap + 4

        let sep = makeSep()
        sep.frame = NSRect(x: L.pad, y: by, width: w, height: 1)
        container.addSubview(sep)
        by += 1 + 6

        // 强度: 设备全局状态, 非单次播放参数
        let hdr = makeSectionHeader("INTENSITY")
        hdr.frame = NSRect(x: L.pad, y: by, width: w - 40, height: 14)
        container.addSubview(hdr)

        let valueText: String
        if let state = state {
            valueText = state.enabled ? "\(state.level)" : "Off"
        } else {
            valueText = "—"
        }
        let valueLabel = makeLabel(text: valueText, fontSize: 10, weight: .medium, color: .secondaryLabelColor)
        valueLabel.alignment = .right
        valueLabel.frame = NSRect(x: L.pad + w - 40, y: by, width: 40, height: 14)
        container.addSubview(valueLabel)
        self.hapticLevelValueLabel = valueLabel
        by += 16

        let level = (state?.enabled ?? false) ? Double(state?.level ?? 0) : 0
        let slider = NSSlider(value: level, minValue: 0, maxValue: 100,
                              target: self, action: #selector(hapticLevelChanged(_:)))
        slider.controlSize = .small
        slider.isContinuous = true
        slider.isEnabled = state != nil
        if state?.fourLevelsOnly == true {
            slider.numberOfTickMarks = 5
            slider.allowsTickMarkValuesOnly = true
        }
        slider.frame = NSRect(x: L.pad, y: by, width: w, height: 18)
        container.addSubview(slider)
        self.hapticLevelSlider = slider
        by += 18 + L.btnGap + 2

        let readBtn = makeActionBtn(title: "Read State", action: #selector(hapticReadStateClicked))
        readBtn.frame = NSRect(x: L.pad, y: by, width: w, height: L.btnH)
        container.addSubview(readBtn)
        by += L.btnH + 6

        // 协议边界说明: 波形时长/频率由固件内置, 不可参数化
        let note = makeLabel(text: "Firmware preset waveforms", fontSize: 9, color: .tertiaryLabelColor)
        note.frame = NSRect(x: L.pad, y: by, width: w, height: 12)
        note.cell?.lineBreakMode = .byTruncatingTail
        container.addSubview(note)
    }

    @objc private func hapticWaveformChanged(_ sender: NSPopUpButton) {
        hapticSelectedWaveformId = UInt8(clamping: sender.selectedTag())
    }

    @objc private func hapticPlayClicked() {
        currentSession?.hapticPlay(waveformId: hapticSelectedWaveformId)
    }

    @objc private func hapticLevelChanged(_ sender: NSSlider) {
        let v = UInt8(clamping: sender.integerValue)
        hapticLevelValueLabel?.stringValue = v == 0 ? "Off" : "\(v)"
        // 拖动过程中只联动数字; 松手 / 点击 / 键盘调整时才真正下发
        let eventType = NSApp.currentEvent?.type
        if eventType != .leftMouseDragged && eventType != .leftMouseDown {
            currentSession?.hapticSetLevel(v)
        }
    }

    @objc private func hapticReadStateClicked() {
        currentSession?.hapticRefreshInfo()
    }

    // MARK: - Scroll Force Context UI

    /// 0x2111 (SmartShift v2) 选中时的专属操作区: 齿感力度滑杆 (即 Logi Options+ 的 Scroll force).
    /// 布局语言与 Haptic context / 通用 context 完全一致 (手排 frame + FlippedView 坐标系).
    private func buildScrollForceContext(in container: NSView, session: LogiDeviceSession, width w: CGFloat) {
        let tunable = session.debugScrollForceTunableTorque
        let status = session.debugScrollForceStatus
        var by: CGFloat = 0

        // 首次选中 (或设备未应答过) 时自动拉取 capabilities + status; 同一 session 1s 节流防查询风暴
        if tunable == nil || status == nil {
            let sid = ObjectIdentifier(session)
            let throttled = scrollForceAutoQueryStamp.map {
                $0.session == sid && Date().timeIntervalSince($0.at) < 1.0
            } ?? false
            if !throttled {
                scrollForceAutoQueryStamp = (sid, Date())
                session.scrollForceRefreshInfo()
            }
        }

        // capabilities 未回来前先不禁用 (乐观); 明确 false 才锁死滑杆
        let torqueSupported = tunable ?? true

        let hdr = makeSectionHeader("SCROLL FORCE")
        hdr.frame = NSRect(x: L.pad, y: by, width: w - 40, height: 14)
        container.addSubview(hdr)

        let valueText: String
        if tunable == false {
            valueText = "N/A"
        } else if let status = status {
            valueText = "\(status.torque)"
        } else {
            valueText = "—"
        }
        let valueLabel = makeLabel(text: valueText, fontSize: 10, weight: .medium, color: .secondaryLabelColor)
        valueLabel.alignment = .right
        valueLabel.frame = NSRect(x: L.pad + w - 40, y: by, width: 40, height: 14)
        container.addSubview(valueLabel)
        self.scrollForceValueLabel = valueLabel
        by += 16

        // 齿感力度: 设备级状态, 1(最轻/最顺滑) - 100(最硬/最精确)
        let torque = Double(status?.torque ?? 1)
        let slider = NSSlider(value: max(1, torque), minValue: 1, maxValue: 100,
                              target: self, action: #selector(scrollForceChanged(_:)))
        slider.controlSize = .small
        slider.isContinuous = true
        // 支持且已读到当前值才可拖动; 值到达前拖动会写入陈旧默认
        slider.isEnabled = torqueSupported && status != nil
        slider.frame = NSRect(x: L.pad, y: by, width: w, height: 18)
        container.addSubview(slider)
        self.scrollForceSlider = slider
        by += 18 + L.btnGap + 2

        let readBtn = makeActionBtn(title: "Read State", action: #selector(scrollForceReadStateClicked))
        readBtn.frame = NSRect(x: L.pad, y: by, width: w, height: L.btnH)
        container.addSubview(readBtn)
        by += L.btnH + 6

        // 设备/协议边界说明
        let noteText = tunable == false ? "Tunable torque not supported" : "Ratchet detent strength"
        let note = makeLabel(text: noteText, fontSize: 9, color: .tertiaryLabelColor)
        note.frame = NSRect(x: L.pad, y: by, width: w, height: 12)
        note.cell?.lineBreakMode = .byTruncatingTail
        container.addSubview(note)
    }

    @objc private func scrollForceChanged(_ sender: NSSlider) {
        let v = UInt8(clamping: sender.integerValue)
        scrollForceValueLabel?.stringValue = "\(v)"
        // 第一道: 拖动 / 按下过程中只联动数字, 不下发 (连续 drag 一个事件都不发给设备)
        let eventType = NSApp.currentEvent?.type
        guard eventType != .leftMouseDragged && eventType != .leftMouseDown else { return }
        // 第二道: 松手 / 键盘调整走 trailing 去抖, 静止 80ms 后只发最后一次值, 键盘连发不会洪泛
        scheduleScrollForceSend(v)
    }

    /// torque 写入去抖: 去掉重复值 + 80ms trailing, 保证一串快速变更只落一次 HID 写.
    /// 始终发送最终值 (trailing 而非 leading), 不会丢用户停下时的目标力度.
    private func scheduleScrollForceSend(_ torque: UInt8) {
        guard torque != scrollForceLastSentTorque else { return }
        scrollForcePendingTorque = torque
        scrollForceSendWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self, let t = self.scrollForcePendingTorque else { return }
            self.scrollForceLastSentTorque = t
            self.currentSession?.scrollForceSetTorque(t)
        }
        scrollForceSendWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: work)
    }

    @objc private func scrollForceReadStateClicked() {
        currentSession?.scrollForceRefreshInfo()
    }

    // MARK: - Force Sensing Context UI

    /// 0x19C0 (Force Sensing Button) 选中时的操作区: 按压激活阈值滑杆 (即 Logi Options+ 的力度感应).
    /// 布局语言与 Haptic / Scroll Force 一致; 滑杆量程用设备上报的 min/max.
    private func buildForceSensingContext(in container: NSView, session: LogiDeviceSession, width w: CGFloat) {
        let info = session.debugForceSensingInfo
        let current = session.debugForceSensingCurrent
        var by: CGFloat = 0

        // 首次选中自动拉取按钮能力 (fn1) + 当前力度 (fn2); 同一 session 1s 节流
        if info == nil || current == nil {
            let sid = ObjectIdentifier(session)
            let throttled = forceSensingAutoQueryStamp.map {
                $0.session == sid && Date().timeIntervalSince($0.at) < 1.0
            } ?? false
            if !throttled {
                forceSensingAutoQueryStamp = (sid, Date())
                session.forceSensingRefreshInfo()
            }
        }

        let changeable = info?.changeable ?? true  // 能力未知前不禁用 (乐观)
        let hasData = info != nil && current != nil

        let hdr = makeSectionHeader("FORCE SENSING")
        hdr.frame = NSRect(x: L.pad, y: by, width: w - 50, height: 14)
        container.addSubview(hdr)

        let valueText: String
        if info?.changeable == false {
            valueText = "Locked"
        } else if let current = current {
            valueText = "\(current)"
        } else {
            valueText = "—"
        }
        let valueLabel = makeLabel(text: valueText, fontSize: 10, weight: .medium, color: .secondaryLabelColor)
        valueLabel.alignment = .right
        valueLabel.frame = NSRect(x: L.pad + w - 50, y: by, width: 50, height: 14)
        container.addSubview(valueLabel)
        self.forceSensingValueLabel = valueLabel
        by += 16

        // 量程用设备上报的 min/max; 未知时给个安全占位 0-100, maxValue 至少比 min 大 1 防非法 range
        let minV = Double(info?.minValue ?? 0)
        let maxV = max(minV + 1, Double(info?.maxValue ?? 100))
        let cur = min(max(Double(current ?? UInt16(minV)), minV), maxV)
        let slider = NSSlider(value: cur, minValue: minV, maxValue: maxV,
                              target: self, action: #selector(forceSensingChanged(_:)))
        slider.controlSize = .small
        slider.isContinuous = true
        slider.isEnabled = changeable && hasData
        slider.frame = NSRect(x: L.pad, y: by, width: w, height: 18)
        container.addSubview(slider)
        self.forceSensingSlider = slider
        by += 18 + L.btnGap + 2

        let readBtn = makeActionBtn(title: "Read State", action: #selector(forceSensingReadStateClicked))
        readBtn.frame = NSRect(x: L.pad, y: by, width: w, height: L.btnH)
        container.addSubview(readBtn)
        by += L.btnH + 6

        let noteText: String
        if info?.changeable == false {
            noteText = "Force not changeable on this device"
        } else if let info = info {
            noteText = "Press-activation force (\(info.minValue)-\(info.maxValue))"
        } else {
            noteText = "Press-activation force threshold"
        }
        let note = makeLabel(text: noteText, fontSize: 9, color: .tertiaryLabelColor)
        note.frame = NSRect(x: L.pad, y: by, width: w, height: 12)
        note.cell?.lineBreakMode = .byTruncatingTail
        container.addSubview(note)
    }

    @objc private func forceSensingChanged(_ sender: NSSlider) {
        let v = UInt16(clamping: sender.integerValue)
        forceSensingValueLabel?.stringValue = "\(v)"
        // 拖动 / 按下过程只联动数字, 不下发
        let eventType = NSApp.currentEvent?.type
        guard eventType != .leftMouseDragged && eventType != .leftMouseDown else { return }
        scheduleForceSensingSend(v)
    }

    /// 阈值写入去抖: 去重 + 80ms trailing, 与 scroll force 同构, 防 HID 洪泛
    private func scheduleForceSensingSend(_ value: UInt16) {
        guard value != forceSensingLastSentValue else { return }
        forceSensingPendingValue = value
        forceSensingSendWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self, let v = self.forceSensingPendingValue else { return }
            self.forceSensingLastSentValue = v
            self.currentSession?.forceSensingSetCurrent(v)
        }
        forceSensingSendWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: work)
    }

    @objc private func forceSensingReadStateClicked() {
        currentSession?.forceSensingRefreshInfo()
    }

    @objc private func indexMinusClicked() {
        setIndexParamValue(max(0, indexParamValue - 1))
    }

    @objc private func indexPlusClicked() {
        setIndexParamValue(min(255, indexParamValue + 1))
    }

    private func setIndexParamValue(_ v: Int) {
        indexParamValue = v
        indexStepperLabel?.stringValue = "Index: \(v)"
    }

    // MARK: - Global Actions

    /// 延时兜底刷新: 防止 Bolt 响应丢包等场景 UI 卡在 stale 状态。
    /// 合批语义 (后调覆盖前调) 也顺带规避 "定时器触发时刷的是届时选中的会话" 的旧竞态。
    /// 刷新统一为 sidebar + 右侧面板超集 —— 均为幂等读取, 超集无副作用。
    private enum FallbackRefreshDelay {
        static let afterDiscovery: TimeInterval = 6   // discovery/枚举链路最长耗时
        static let afterDivert: TimeInterval = 1     // SetControlReporting ACK 周期
        static let afterToggle: TimeInterval = 0.5   // 单个 divert toggle 响应
    }
    private var fallbackRefreshWorkItem: DispatchWorkItem?
    private func scheduleFallbackRefresh(after delay: TimeInterval) {
        fallbackRefreshWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.refreshSidebar()
            self.refreshRightPanels()
        }
        fallbackRefreshWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    @objc private func rediscoverClicked() {
        currentSession?.rediscoverFeatures()
        refreshRightPanelsLoading()
        scheduleFallbackRefresh(after: FallbackRefreshDelay.afterDiscovery)
    }

    @objc private func redivertClicked() {
        currentSession?.redivertAllControls()
        scheduleFallbackRefresh(after: FallbackRefreshDelay.afterDivert)
    }

    @objc private func undivertClicked() {
        currentSession?.undivertAllControls()
        scheduleFallbackRefresh(after: FallbackRefreshDelay.afterDivert)
    }

    @objc private func enumerateClicked() {
        currentSession?.enumerateReceiverDevices()
        scheduleFallbackRefresh(after: FallbackRefreshDelay.afterDiscovery)
    }

    @objc private func clearLogClicked() {
        LogiDebugPanel.logBuffer.removeAll()
        invalidateFilteredLogCache()
        lastFilteredLogCount = 0
        logTableView?.reloadData()
    }

    // MARK: - Feature Actions

    @objc private func featureActionClicked(_ sender: NSButton) {
        guard let session = currentSession, let featureId = selectedFeatureId else { return }
        guard let featureIdx = session.debugFeatureIndex[featureId] else {
            LogiDebugPanel.log(device: session.deviceInfo.name, type: .warning,
                                      message: "Feature 0x\(String(format: "%04X", featureId)) not indexed")
            return
        }
        let functionId = UInt8(sender.tag)
        var params = [UInt8](repeating: 0, count: 16)

        let actions = HIDPPFeatureActions.actions(for: featureId)
        if let action = actions.first(where: { $0.functionId == functionId }) {
            switch action.paramType {
            case .none: break
            case .index:
                params[0] = UInt8(indexParamValue)
            case .hex:
                if let hexStr = paramInputField?.stringValue, !hexStr.isEmpty {
                    let bytes = hexStr.split(separator: " ").compactMap { UInt8($0, radix: 16) }
                    for (i, b) in bytes.prefix(16).enumerated() { params[i] = b }
                } else {
                    for (i, b) in action.defaultParams.prefix(16).enumerated() { params[i] = b }
                }
            }
        }
        sendDebugPacket(session: session, featureIndex: featureIdx, functionId: functionId, params: params)
    }

    @objc private func toggleDivertClicked() {
        guard let session = currentSession, let cid = selectedControlCID else { return }
        session.toggleDivert(cid: cid)
        scheduleFallbackRefresh(after: FallbackRefreshDelay.afterToggle)
    }

    @objc private func queryReportingClicked() {
        guard let session = currentSession, let cid = selectedControlCID else { return }
        guard let reprogIdx = session.debugFeatureIndex[0x1B04] else { return }
        let params: [UInt8] = [UInt8(cid >> 8), UInt8(cid & 0xFF)] + [UInt8](repeating: 0, count: 14)
        sendDebugPacket(session: session, featureIndex: reprogIdx, functionId: 2, params: params)
    }

    private func sendDebugPacket(session: LogiDeviceSession, featureIndex: UInt8, functionId: UInt8, params: [UInt8]) {
        var report = [UInt8](repeating: 0, count: 20)
        report[0] = 0x11
        report[1] = session.debugDeviceIndex
        report[2] = featureIndex
        report[3] = (functionId << 4) | 0x01
        for (i, p) in params.prefix(16).enumerated() { report[4 + i] = p }
        sendReportLogged(report, to: session)
    }

    /// TX 日志 + IOHIDDeviceSetReport + 失败日志的统一发送通道 (面板内发包共用)
    private func sendReportLogged(_ report: [UInt8], to session: LogiDeviceSession) {
        let hex = report.map { String(format: "%02X", $0) }.joined(separator: " ")
        LogiDebugPanel.log(device: session.deviceInfo.name, type: .tx, message: "TX: \(hex)", rawBytes: report)

        let result = IOHIDDeviceSetReport(session.hidDevice, kIOHIDReportTypeOutput, CFIndex(report[0]), report, report.count)
        if result != kIOReturnSuccess {
            LogiDebugPanel.log(device: session.deviceInfo.name, type: .error,
                                      message: "IOHIDDeviceSetReport failed: \(String(format: "0x%08X", result))")
        }
    }

    // MARK: - Log Actions

    @objc private func filterChipClicked(_ sender: NSButton) {
        let chipOrder: [LogEntryType] = [.tx, .rx, .error, .buttonEvent, .warning, .info]
        guard sender.tag >= 0, sender.tag < chipOrder.count else { return }
        let type = chipOrder[sender.tag]
        if logTypeFilter.contains(type) {
            logTypeFilter.remove(type)
            sender.layer?.opacity = 0.3
        } else {
            logTypeFilter.insert(type)
            sender.layer?.opacity = 1.0
        }
        invalidateFilteredLogCache()
        lastFilteredLogCount = filteredLogEntries().count
        logTableView?.reloadData()
    }

    @objc private func logRowClicked(_ sender: Any?) {
        let row = logTableView.clickedRow
        let filtered = filteredLogEntries()
        guard row >= 0, row < filtered.count else { return }
        let bufferIdx = filtered[row].0
        LogiDebugPanel.logBuffer[bufferIdx].isExpanded.toggle()
        invalidateFilteredLogCache()
        logTableView.noteHeightOfRows(withIndexesChanged: IndexSet(integer: row))
        logTableView.reloadData(forRowIndexes: IndexSet(integer: row), columnIndexes: IndexSet(integer: 0))
    }

    @objc private func exportLogClicked() {
        guard let win = window else { return }
        let panel = NSSavePanel()
        let dateStr: String = {
            let fmt = DateFormatter()
            fmt.dateFormat = "yyyy-MM-dd-HHmmss"
            return fmt.string(from: Date())
        }()
        panel.nameFieldStringValue = "hidpp-debug-\(dateStr).log"
        panel.beginSheetModal(for: win) { response in
            guard response == .OK, let url = panel.url else { return }
            let output = LogiDebugPanel.logBuffer.map { LogiDebugPanel.formatLogEntry($0) }.joined()
            do {
                try output.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                // 导出失败给出可见反馈 (调试面板为开发者界面, 文案不本地化)
                LogiDebugPanel.log("Export failed: \(error.localizedDescription)")
                let alert = NSAlert()
                alert.alertStyle = .warning
                alert.messageText = "Export Failed"
                alert.informativeText = error.localizedDescription
                alert.runModal()
            }
        }
    }

    @objc private func sendRawClicked() {
        guard let session = currentSession else { return }
        guard session.debugDeviceOpened else {
            LogiDebugPanel.log(device: session.deviceInfo.name, type: .warning, message: "Device not opened")
            return
        }
        let hexStr = rawInputField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !hexStr.isEmpty else { return }
        let bytes = hexStr.split(separator: " ").compactMap { UInt8($0, radix: 16) }
        guard !bytes.isEmpty else {
            LogiDebugPanel.log(device: session.deviceInfo.name, type: .warning, message: "Invalid hex input")
            return
        }

        let isLong = reportTypeControl.selectedSegment == 1
        let reportLen = isLong ? 20 : 7
        var report = [UInt8](repeating: 0, count: reportLen)
        report[0] = isLong ? 0x11 : 0x10
        let srcBytes: [UInt8] = (bytes.first == 0x10 || bytes.first == 0x11) ? Array(bytes.dropFirst()) : bytes
        for (i, b) in srcBytes.prefix(reportLen - 1).enumerated() { report[1 + i] = b }

        sendReportLogged(report, to: session)
    }

    /// 过滤结果缓存: heightOfRow/logCell 逐行调用本方法, 无缓存时整表 reload 为 O(N²)。
    /// 失效点: 新日志追加 / 过滤条件变化 / 清空 / 行展开切换 / refreshAll。
    private var cachedFilteredLogEntries: [(Int, LogEntry)]?
    private func invalidateFilteredLogCache() {
        cachedFilteredLogEntries = nil
    }
    private func filteredLogEntries() -> [(Int, LogEntry)] {
        if let cached = cachedFilteredLogEntries { return cached }
        let computed = LogiDebugPanel.logBuffer.enumerated()
            .filter { logTypeFilter.contains($0.element.type) }
            .map { ($0.offset, $0.element) }
        cachedFilteredLogEntries = computed
        return computed
    }

    // MARK: - Refresh

    private func refreshAll() {
        refreshSidebar()
        refreshDeviceInfo()
        refreshFeatureTable()
        refreshControls()
        updateContextActions()
        invalidateFilteredLogCache()
        logTableView?.reloadData()
    }

    private func refreshRightPanels() {
        refreshDeviceInfo()
        refreshFeatureTable()
        refreshControls()
        updateContextActions()
    }

    private func refreshRightPanelsLoading() {
        featureRows.removeAll()
        controlRows.removeAll()
        featureTableView?.reloadData()
        controlsTableView?.reloadData()
        // Stale UI 一起清: selection / device info 都会在握手完成后重建.
        selectedFeatureId = nil
        selectedControlCID = nil
        featuresHeaderBase = "FEATURES (...)"
        controlsHeaderBase = "CONTROLS (...)"
        renderRightPanelHeaders()
        refreshDeviceInfo()
        updateContextActions()
    }

    private func currentSidebarSelection() -> SidebarSelection? {
        guard let outlineView = outlineView else { return nil }
        let row = outlineView.selectedRow
        guard row >= 0 else { return nil }
        if let node = outlineView.item(atRow: row) as? DeviceNode {
            return .device(sessionID: ObjectIdentifier(node.session))
        }
        if let node = outlineView.item(atRow: row) as? SlotNode {
            return .slot(sessionID: ObjectIdentifier(node.session), slot: node.slot)
        }
        return nil
    }

    private func row(for selection: SidebarSelection, in outlineView: NSOutlineView) -> Int? {
        for row in 0..<outlineView.numberOfRows {
            if let node = outlineView.item(atRow: row) as? DeviceNode {
                if case let .device(sessionID) = selection, ObjectIdentifier(node.session) == sessionID {
                    return row
                }
                continue
            }
            if let node = outlineView.item(atRow: row) as? SlotNode,
               case let .slot(sessionID, slot) = selection,
               ObjectIdentifier(node.session) == sessionID,
               node.slot == slot {
                return row
            }
        }
        return nil
    }

    private func refreshSidebar() {
        let sessions = LogiSessionManager.shared.activeSessions
        let previousSessionIDs = Set(deviceNodes.map { ObjectIdentifier($0.session) })
        let expandedSessionIDs: Set<ObjectIdentifier>
        let selectedItem = currentSidebarSelection()
        if let outlineView = outlineView {
            expandedSessionIDs = Set(deviceNodes.compactMap { node in
                outlineView.isItemExpanded(node) ? ObjectIdentifier(node.session) : nil
            })
        } else {
            expandedSessionIDs = []
        }
        deviceNodes = sessions
            .filter { $0.connectionMode != .unsupported }
            .map { DeviceNode(session: $0) }
        outlineView?.reloadData()
        for node in deviceNodes where node.isReceiver {
            let sessionID = ObjectIdentifier(node.session)
            if expandedSessionIDs.contains(sessionID) || !previousSessionIDs.contains(sessionID) {
                outlineView?.expandItem(node)
            }
        }
        // Selection IS the source of truth for currentSession. Decide the target
        // row deterministically and let the outlineView's selection drive the
        // right pane on the next refresh.
        guard let outlineView = outlineView else { return }
        let target = chooseSelectionTarget(prior: selectedItem, sessions: sessions, in: outlineView)
        if let target = target, let row = row(for: target, in: outlineView) {
            outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        } else {
            outlineView.deselectAll(nil)
        }
        if target != selectedItem {
            // Selection moved (first open, prior session disconnected, or slot row vanished).
            // Drop stale feature/control highlights so the right pane recomputes cleanly.
            selectedFeatureId = nil
            selectedControlCID = nil
        }
    }

    /// Pick the next sidebar selection after a `reloadData`.
    /// 1. Restore the prior selection if its row still exists.
    /// 2. If the prior was a slot row that vanished but the parent device is still
    ///    around, fall back to that device row (preserves session context rather
    ///    than dropping the user back to "nothing selected").
    /// 3. Otherwise (first open, prior session gone, etc.): pick the first device.
    /// 4. No devices reachable → no selection.
    private func chooseSelectionTarget(prior: SidebarSelection?,
                                       sessions: [LogiDeviceSession],
                                       in outlineView: NSOutlineView) -> SidebarSelection? {
        // 保留上次选择, 但 receiver header 不可选 -> 降级到其默认 slot.
        if let prior = prior, row(for: prior, in: outlineView) != nil {
            if case let .device(sessionID) = prior,
               let session = sessions.first(where: { ObjectIdentifier($0) == sessionID }),
               session.connectionMode == .receiver {
                return defaultSelection(for: session)
            }
            return prior
        }
        // 上次选的 slot 所在 session 还在 -> 回该 session 的默认(某个在线 slot).
        if case let .slot(sessionID, _)? = prior,
           let session = sessions.first(where: { ObjectIdentifier($0) == sessionID }) {
            return defaultSelection(for: session)
        }
        // 首个设备的默认.
        if let first = deviceNodes.first {
            return defaultSelection(for: first.session)
        }
        return nil
    }

    /// 某 session 默认应选中的 sidebar 项. 接收器: 选真实 slot(优先当前路由游标那台 ——
    /// Phase 3 已让它落在鼠标上 —— 否则首个在线 slot); 无在线 slot 返回 nil(父行不可选).
    /// BLE 直连: 设备本身即可选.
    private func defaultSelection(for session: LogiDeviceSession) -> SidebarSelection? {
        let sessionID = ObjectIdentifier(session)
        guard session.connectionMode == .receiver else {
            return .device(sessionID: sessionID)
        }
        let paired = session.debugReceiverPairedDevices
        let cursor = session.debugDeviceIndex
        if paired.first(where: { $0.slot == cursor })?.isConnected == true {
            return .slot(sessionID: sessionID, slot: cursor)
        }
        if let firstConnected = paired.first(where: { $0.isConnected }) {
            return .slot(sessionID: sessionID, slot: firstConnected.slot)
        }
        return nil
    }

    private func refreshDeviceInfo() {
        guard let s = currentSession else {
            for pair in deviceInfoLabels { pair.value.stringValue = "--" }
            for pair in moreInfoLabels { pair.value.stringValue = "--" }
            return
        }
        let vals: [String] = [
            String(format: "0x%04X", s.deviceInfo.vendorId),
            String(format: "0x%04X", s.deviceInfo.productId),
            s.debugFeatureIndex.isEmpty ? "--" : "4.x",
            s.transport,
            String(format: "0x%02X", s.debugDeviceIndex),
            s.debugConnectionMode,
            s.debugDeviceOpened ? "\u{2713}" : "\u{2717}",
        ]
        for (i, val) in vals.enumerated() where i < deviceInfoLabels.count {
            deviceInfoLabels[i].value.stringValue = val
        }
        let moreVals: [String] = [
            String(format: "0x%04X", s.usagePage),
            String(format: "0x%04X", s.usage),
            s.isHIDPPCandidate ? "Yes" : "No",
            s.debugReprogInitComplete ? "Yes" : "No",
            "\(s.debugDivertedCIDs.count)",
            targetDisplay(for: s),
        ]
        for (i, val) in moreVals.enumerated() where i < moreInfoLabels.count {
            moreInfoLabels[i].value.stringValue = val
        }
    }

    /// Receiver session 在指向某个 slot peripheral 时, 返回 "<peripheral name> (0xWPID)";
    /// 否则返回 "--".
    private func targetDisplay(for session: LogiDeviceSession) -> String {
        guard session.connectionMode == .receiver,
              session.debugDeviceIndex >= 1, session.debugDeviceIndex <= 6 else {
            return "--"
        }
        let idx = Int(session.debugDeviceIndex) - 1
        let paired = session.debugReceiverPairedDevices
        guard idx < paired.count, paired[idx].isConnected else { return "--" }
        let dev = paired[idx]
        let nameSegment = dev.name.isEmpty ? "Slot \(dev.slot)" : dev.name
        return dev.wirelessPID == 0
            ? nameSegment
            : String(format: "%@ (0x%04X)", nameSegment, dev.wirelessPID)
    }

    /// Receiver 的 device 标头被选中时, features/controls 语义上属于被 target 的某个 slot,
    /// 不应挂在 receiver 名下显示. 用 sidebar 当前选择来判断, 保证所有刷新入口
    /// (click / sessionChanged / reportingQueryDidComplete 等) 一致清空, 避免残留上轮 slot 数据.
    private func isReceiverHeaderSelected() -> Bool {
        guard let s = currentSession, s.connectionMode == .receiver else { return false }
        if case .device? = currentSidebarSelection() { return true }
        return false
    }

    private func refreshFeatureTable() {
        guard let s = currentSession, !isReceiverHeaderSelected() else {
            featureRows.removeAll()
            featureTableView?.reloadData()
            featuresHeaderBase = "FEATURES (0)"
            renderRightPanelHeaders()
            return
        }
        featureRows = s.debugFeatureIndex.sorted(by: { $0.value < $1.value }).map { (featureId, index) in
            let name = HIDPPInfo.featureNames[featureId]?.0 ?? "Unknown"
            return (index: String(format: "0x%02X", index), featureId: featureId,
                    featureIdHex: String(format: "0x%04X", featureId), name: name)
        }
        featureTableView?.reloadData()
        featuresHeaderBase = "FEATURES (\(featureRows.count))"
        renderRightPanelHeaders()
    }

    private func refreshControls() {
        guard let s = currentSession, !isReceiverHeaderSelected() else {
            controlRows.removeAll()
            controlsTableView?.reloadData()
            controlsHeaderBase = "CONTROLS (0)"
            renderRightPanelHeaders()
            return
        }
        controlRows = s.debugDiscoveredControls
        controlsTableView?.reloadData()
        controlsHeaderBase = "CONTROLS (\(controlRows.count))"
        renderRightPanelHeaders()
    }

    // header label 引用缓存: spinner 每 80ms 刷新两个 header, 每次递归遍历视图树代价过高
    private var headerLabelCache: [Int: NSTextField] = [:]
    private func applyHeaderLabel(tag: Int, text: String) {
        if let cached = headerLabelCache[tag], cached.window != nil {
            cached.stringValue = text
            return
        }
        func find(in view: NSView) -> NSTextField? {
            if let tf = view as? NSTextField, tf.tag == tag { return tf }
            for sub in view.subviews { if let f = find(in: sub) { return f } }
            return nil
        }
        if let cv = window?.contentView, let lbl = find(in: cv) {
            headerLabelCache[tag] = lbl
            lbl.stringValue = text
        }
    }

    /// Refresh FEATURES/CONTROLS headers with current base text, appending the
    /// Braille spinner glyph when the active session is still in discovery flight.
    private func renderRightPanelHeaders() {
        let inflight = currentSession?.debugDiscoveryInFlight ?? false
        let suffix = inflight ? "  \(BrailleSpinner.shared.currentFrame)" : ""
        applyHeaderLabel(tag: 100, text: featuresHeaderBase + suffix)
        applyHeaderLabel(tag: 101, text: controlsHeaderBase + suffix)
    }

    // MARK: - Observers

    private func startObserving() {
        stopObserving()
        lastFilteredLogCount = filteredLogEntries().count
        logObserver = NotificationCenter.default.addObserver(
            forName: LogiDebugPanel.logNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let self = self, let table = self.logTableView else { return }
            // 增量更新: 单条追加走 insertRows (O(1) 视图工作); 过滤掉的条目静默跳过;
            // 其它异常 (buffer 前置裁剪导致行数倒退) 回落 reloadData.
            self.invalidateFilteredLogCache()
            let newCount = self.filteredLogEntries().count
            let previousCount = self.lastFilteredLogCount
            if newCount == previousCount + 1 {
                table.insertRows(at: IndexSet(integer: newCount - 1), withAnimation: [])
            } else if newCount != previousCount {
                table.reloadData()
            }
            self.lastFilteredLogCount = newCount
            // Auto-scroll only if user is near the bottom
            if let sv = table.enclosingScrollView {
                let visibleH = sv.contentView.bounds.height
                let contentH = table.frame.height
                let scrollY = sv.contentView.bounds.origin.y
                let isNearBottom = (contentH - scrollY - visibleH) < 40
                if isNearBottom && newCount > 0 {
                    table.scrollRowToVisible(newCount - 1)
                }
            }
            // 只匹配 setControlReporting 的 "... divert=ON/OFF" 明确 toggle 日志.
            // 排除 RX flags 里的 "tmpDivert/persistDivert" 等被动描述 —— 那类状态变化由
            // reportingQueryDidCompleteNotification 在 discovery 结束时统一 refresh.
            // 合批: 每次物理按键产生 2-3 条日志, 逐条整表 reload 浪费, 100ms 内合并为一次
            if let entry = notification.object as? LogEntry,
               entry.type == .buttonEvent || entry.message.contains(" divert=") {
                self.scheduleControlsRefresh()
            }
        }
        sessionObserver = NotificationCenter.default.addObserver(
            forName: LogiSessionManager.sessionChangedNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.refreshAll() }
        reportingCompleteObserver = NotificationCenter.default.addObserver(
            forName: LogiSessionManager.reportingQueryDidCompleteNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            // Sidebar 状态圆点会从 Initializing 切到 Ready, 需要跟随 reprog init 完成一起刷新.
            self?.refreshSidebar()
            self?.refreshRightPanels()
        }
        discoveryStateObserver = NotificationCenter.default.addObserver(
            forName: LogiSessionManager.discoveryStateDidChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            // Discovery 进/出 flight: 刷 header (spinner 显隐) + sidebar (slot 行 spinner).
            self?.renderRightPanelHeaders()
            self?.refreshSidebar()
        }
        spinnerObserver = NotificationCenter.default.addObserver(
            forName: BrailleSpinner.didTickNotification, object: nil, queue: .main
        ) { [weak self] _ in
            // Spinner tick: 只在仍在 flight 时更新, 否则空跑浪费.
            guard self?.currentSession?.debugDiscoveryInFlight == true else { return }
            self?.renderRightPanelHeaders()
            self?.refreshSpinningSlotRow()
        }
        hapticStateObserver = NotificationCenter.default.addObserver(
            forName: LogiDeviceSession.hapticStateDidChangeNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let self = self,
                  let session = notification.object as? LogiDeviceSession,
                  session === self.currentSession else { return }
            // Haptic feature 刚被发现: FEATURES 表补行, 并还原之前的行选中 (reload 会清选中)
            if !self.featureRows.contains(where: { $0.featureId == LogiDeviceSession.featureHaptic }) {
                let prior = self.selectedFeatureId
                self.refreshFeatureTable()
                if let fid = prior,
                   let row = self.featureRows.firstIndex(where: { $0.featureId == fid }) {
                    self.featureTableView?.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                }
            }
            // 正在展示 haptic 操作区: 用最新 state / capabilities 重建 (滑杆位置, 波形可用性)
            if self.selectedFeatureId == LogiDeviceSession.featureHaptic {
                self.updateContextActions()
            }
        }
        scrollForceStateObserver = NotificationCenter.default.addObserver(
            forName: LogiDeviceSession.scrollForceStateDidChangeNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let self = self,
                  let session = notification.object as? LogiDeviceSession,
                  session === self.currentSession else { return }
            // 0x2111 刚被发现: FEATURES 表补行, 并还原之前的行选中 (reload 会清选中)
            if !self.featureRows.contains(where: { $0.featureId == LogiDeviceSession.featureSmartShiftEnhanced }) {
                let prior = self.selectedFeatureId
                self.refreshFeatureTable()
                if let fid = prior,
                   let row = self.featureRows.firstIndex(where: { $0.featureId == fid }) {
                    self.featureTableView?.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                }
            }
            // 正在展示 scroll force 操作区: 用最新 capabilities / status 重建 (滑杆位置与可用性)
            if self.selectedFeatureId == LogiDeviceSession.featureSmartShiftEnhanced {
                self.updateContextActions()
            }
        }
        forceSensingStateObserver = NotificationCenter.default.addObserver(
            forName: LogiDeviceSession.forceSensingStateDidChangeNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let self = self,
                  let session = notification.object as? LogiDeviceSession,
                  session === self.currentSession else { return }
            // 0x19C0 刚被发现: FEATURES 表补行, 还原之前的行选中 (reload 会清选中)
            if !self.featureRows.contains(where: { $0.featureId == LogiDeviceSession.featureForceSensing }) {
                let prior = self.selectedFeatureId
                self.refreshFeatureTable()
                if let fid = prior,
                   let row = self.featureRows.firstIndex(where: { $0.featureId == fid }) {
                    self.featureTableView?.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                }
            }
            // 正在展示 force sensing 操作区: 用最新 info / current 重建 (滑杆量程与位置)
            if self.selectedFeatureId == LogiDeviceSession.featureForceSensing {
                self.updateContextActions()
            }
        }
        auxiliaryFeaturesObserver = NotificationCenter.default.addObserver(
            forName: LogiDeviceSession.auxiliaryFeaturesDidChangeNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let self = self,
                  let session = notification.object as? LogiDeviceSession,
                  session === self.currentSession else { return }
            // 无专属 context 的可选 feature 被发现: 只补 FEATURES 表, 保留当前行选中
            let prior = self.selectedFeatureId
            self.refreshFeatureTable()
            if let fid = prior,
               let row = self.featureRows.firstIndex(where: { $0.featureId == fid }) {
                self.featureTableView?.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            }
        }
        BrailleSpinner.shared.beginTicking()
    }

    private var controlsRefreshScheduled = false
    private func scheduleControlsRefresh() {
        guard !controlsRefreshScheduled else { return }
        controlsRefreshScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self = self else { return }
            self.controlsRefreshScheduled = false
            self.refreshControls()
        }
    }

    private func stopObserving() {
        if let o = logObserver { NotificationCenter.default.removeObserver(o); logObserver = nil }
        if let o = sessionObserver { NotificationCenter.default.removeObserver(o); sessionObserver = nil }
        if let o = reportingCompleteObserver {
            NotificationCenter.default.removeObserver(o)
            reportingCompleteObserver = nil
        }
        if let o = discoveryStateObserver {
            NotificationCenter.default.removeObserver(o)
            discoveryStateObserver = nil
        }
        if let o = spinnerObserver {
            NotificationCenter.default.removeObserver(o)
            spinnerObserver = nil
            BrailleSpinner.shared.endTicking()
        }
        if let o = hapticStateObserver {
            NotificationCenter.default.removeObserver(o)
            hapticStateObserver = nil
        }
        if let o = scrollForceStateObserver {
            NotificationCenter.default.removeObserver(o)
            scrollForceStateObserver = nil
        }
        if let o = forceSensingStateObserver {
            NotificationCenter.default.removeObserver(o)
            forceSensingStateObserver = nil
        }
        if let o = auxiliaryFeaturesObserver {
            NotificationCenter.default.removeObserver(o)
            auxiliaryFeaturesObserver = nil
        }
        // 布局观察者 (frame change) 的生命周期与窗口一致, token 存于
        // layoutObserverTokens, 在 deinit 统一移除 (不随 show/hide 反复注册)。
    }

    private var layoutObserverTokens: [NSObjectProtocol] = []

    deinit {
        layoutObserverTokens.forEach { NotificationCenter.default.removeObserver($0) }
    }

    // MARK: - Helpers

    private func makeLabel(text: String, fontSize: CGFloat, weight: NSFont.Weight = .regular, color: NSColor = .labelColor) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = NSFont.systemFont(ofSize: fontSize, weight: weight)
        l.textColor = color
        l.backgroundColor = .clear
        l.isBezeled = false
        l.isEditable = false
        l.isSelectable = false
        return l
    }

    private func makeCenteredTableCell(in tableView: NSTableView,
                                       identifier: NSUserInterfaceItemIdentifier,
                                       font: NSFont) -> NSTableCellView {
        let cell = tableView.makeView(withIdentifier: identifier, owner: nil) as? NSTableCellView ?? {
            let view = NSTableCellView()
            view.identifier = identifier

            let label = NSTextField(labelWithString: "")
            label.translatesAutoresizingMaskIntoConstraints = false
            label.backgroundColor = .clear
            label.isBezeled = false
            label.isEditable = false
            label.isSelectable = false
            view.textField = label
            view.addSubview(label)

            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 2),
                label.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -2),
                label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            ])

            return view
        }()

        let label = cell.textField ?? NSTextField(labelWithString: "")
        label.font = font
        return cell
    }

    private func makeSectionHeader(_ title: String) -> NSTextField {
        return makeLabel(text: title, fontSize: 10, weight: .medium, color: .tertiaryLabelColor)
    }

    private func makeActionBtn(title: String, action: Selector,
                               color: NSColor = NSColor(calibratedRed: 0.4, green: 0.6, blue: 1.0, alpha: 1.0)) -> NSButton {
        let btn = NSButton(title: title, target: self, action: action)
        btn.isBordered = false
        btn.wantsLayer = true
        btn.layer?.backgroundColor = color.withAlphaComponent(0.15).cgColor
        btn.layer?.borderColor = color.withAlphaComponent(0.3).cgColor
        btn.layer?.borderWidth = 1
        btn.layer?.cornerRadius = 4
        btn.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        if #available(macOS 10.14, *) { btn.contentTintColor = .labelColor }
        return btn
    }

    private func makeInputField(placeholder: String) -> NSTextField {
        let tf = NSTextField()
        tf.placeholderString = placeholder
        tf.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        tf.textColor = .labelColor
        tf.backgroundColor = NSColor(calibratedWhite: 0.0, alpha: 0.18)
        tf.isBezeled = false
        tf.drawsBackground = true
        tf.focusRingType = .none
        tf.wantsLayer = true
        tf.layer?.cornerRadius = 4
        tf.layer?.borderColor = NSColor(calibratedWhite: 1.0, alpha: 0.18).cgColor
        tf.layer?.borderWidth = 1
        return tf
    }

    private func makeStepBtn(title: String, action: Selector) -> NSButton {
        let btn = NSButton(title: title, target: self, action: action)
        btn.isBordered = false
        btn.wantsLayer = true
        btn.layer?.backgroundColor = NSColor(calibratedWhite: 1.0, alpha: 0.06).cgColor
        btn.layer?.borderColor = NSColor(calibratedWhite: 1.0, alpha: 0.18).cgColor
        btn.layer?.borderWidth = 1
        btn.layer?.cornerRadius = 4
        btn.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        if #available(macOS 10.14, *) { btn.contentTintColor = .labelColor }
        return btn
    }

    private func stylePopupButton(_ p: NSPopUpButton) {
        p.isBordered = false
        p.wantsLayer = true
        p.layer?.backgroundColor = NSColor(calibratedWhite: 1.0, alpha: 0.06).cgColor
        p.layer?.borderColor = NSColor(calibratedWhite: 1.0, alpha: 0.18).cgColor
        p.layer?.borderWidth = 1
        p.layer?.cornerRadius = 4
        p.font = NSFont.systemFont(ofSize: 11)
        if #available(macOS 10.14, *) { p.contentTintColor = .labelColor }
    }

    private func configureDarkScroll(_ sv: NSScrollView) {
        sv.scrollerStyle = .overlay
        sv.scrollerKnobStyle = .light
        sv.hasVerticalScroller = true
        sv.borderType = .noBorder
        sv.drawsBackground = false
    }

    private func makeSep() -> NSView {
        let v = NSView()
        v.wantsLayer = true
        v.layer?.backgroundColor = NSColor(calibratedWhite: 1.0, alpha: 0.1).cgColor
        return v
    }

    private var blockCornerRadius: CGFloat {
        if #available(macOS 26.0, *) { return 10 }
        return 5
    }

    private func makeSectionBg() -> NSView {
        let v = NSView()
        v.wantsLayer = true
        v.layer?.backgroundColor = NSColor(calibratedWhite: 1.0, alpha: 0.05).cgColor
        v.layer?.cornerRadius = blockCornerRadius
        v.layer?.borderWidth = 1
        v.layer?.borderColor = NSColor(calibratedWhite: 1.0, alpha: 0.08).cgColor
        return v
    }

    private func makeLogBg() -> NSView {
        let v = NSView()
        v.wantsLayer = true
        v.layer?.backgroundColor = NSColor(calibratedRed: 0, green: 0, blue: 0, alpha: 0.4).cgColor
        v.layer?.cornerRadius = blockCornerRadius
        v.layer?.borderWidth = 1
        v.layer?.borderColor = NSColor(calibratedWhite: 1.0, alpha: 0.08).cgColor
        return v
    }

    private func logColor(for type: LogEntryType) -> NSColor {
        switch type {
        case .tx: return NSColor(calibratedRed: 0.4, green: 0.6, blue: 1.0, alpha: 1.0)
        case .rx: return NSColor(calibratedRed: 0.3, green: 0.8, blue: 0.4, alpha: 1.0)
        case .error: return NSColor(calibratedRed: 1.0, green: 0.3, blue: 0.3, alpha: 1.0)
        case .buttonEvent: return NSColor(calibratedRed: 1.0, green: 0.8, blue: 0.2, alpha: 1.0)
        case .warning: return NSColor(calibratedRed: 1.0, green: 0.6, blue: 0.2, alpha: 1.0)
        case .info: return NSColor(calibratedWhite: 0.75, alpha: 1.0)
        }
    }
}

// MARK: - NSOutlineViewDataSource & Delegate

extension LogiDebugPanel: NSOutlineViewDataSource {
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if item == nil { return deviceNodes.count }
        if let node = item as? DeviceNode, node.isReceiver {
            return node.session.debugReceiverPairedDevices.count
        }
        return 0
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if item == nil { return deviceNodes[index] }
        if let node = item as? DeviceNode, node.isReceiver {
            let paired = node.session.debugReceiverPairedDevices[index]
            return SlotNode(session: node.session, slot: paired.slot)
        }
        return NSNull()
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        return (item as? DeviceNode)?.isReceiver ?? false
    }
}

extension LogiDebugPanel: NSOutlineViewDelegate {
    func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
        // Device 行两行布局, slot 行保持单行.
        return (item is DeviceNode) ? Self.deviceRowHeight : 22
    }

    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        // 接收器父行只是容器, 只有其下的 slot 才代表真实设备; 禁止选中父行.
        // (BLE 直连 DeviceNode 无子 slot, 本身即设备, 仍可选中.)
        if let node = item as? DeviceNode, node.isReceiver {
            return false
        }
        // 空 slot 不可选中: 视觉已经降级, 再阻止 selection 避免 highlight 落在空行.
        if let slot = item as? SlotNode {
            let paired = slot.session.debugReceiverPairedDevices
            let idx = Int(slot.slot) - 1
            guard idx >= 0, idx < paired.count, paired[idx].isConnected else { return false }
        }
        return true
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        if let node = item as? DeviceNode {
            let cell = makeDeviceRowCell(in: outlineView)
            cell.textField?.attributedStringValue = renderDeviceRowPrimary(node: node)

            if let secondary = cell.viewWithTag(Self.secondaryTextTag) as? NSTextField {
                secondary.attributedStringValue = renderDeviceRowSecondary(node: node)
            }

            let status = sidebarStatus(for: node.session)
            if let dot = cell.viewWithTag(Self.statusDotTag) as? NSTextField {
                dot.stringValue = status.glyph
                dot.textColor = status.color
                dot.toolTip = status.accessibilityLabel
                dot.setAccessibilityLabel(status.accessibilityLabel)
            }
            return cell
        }

        let cellId = NSUserInterfaceItemIdentifier("DeviceCell")
        let cell = makeCenteredTableCell(in: outlineView, identifier: cellId, font: NSFont.systemFont(ofSize: 11))
        guard let label = cell.textField else { return cell }

        if let slot = item as? SlotNode {
            let paired = slot.session.debugReceiverPairedDevices
            let idx = Int(slot.slot) - 1
            guard idx >= 0, idx < paired.count else {
                label.stringValue = "Slot \(slot.slot): --"
                label.textColor = .quaternaryLabelColor
                return cell
            }
            let dev = paired[idx]
            let baseText: String
            if dev.isConnected {
                let base = dev.name.isEmpty ? "Slot \(dev.slot)" : dev.name
                // 权威类型(feature 0x0005)已知则附上; 首次巡检该 slot 时查得(见 requestDeviceTypeIfNeeded).
                if let type = dev.hidppDeviceTypeName {
                    baseText = "\(base) · \(type)"
                } else {
                    baseText = base
                }
                label.textColor = .labelColor
            } else {
                // 空 slot: 视觉显式降级, 暗示不可点击.
                baseText = "Slot \(dev.slot): empty"
                label.textColor = .quaternaryLabelColor
            }
            // 当前正 target 这个 slot 且 discovery 在 flight 时, 末尾追加 spinner.
            if isSlotSpinning(slot) {
                label.stringValue = "\(baseText)  \(BrailleSpinner.shared.currentFrame)"
            } else {
                label.stringValue = baseText
            }
        }
        return cell
    }

    /// 当前 slot 是否正处于 discovery flight (用于决定是否显示 spinner 字符).
    private func isSlotSpinning(_ slot: SlotNode) -> Bool {
        let session = slot.session
        return session.debugIsReceiver
            && session.debugDiscoveryInFlight
            && session.debugDeviceIndex == slot.slot
    }

    /// 增量刷新正在 spinning 的 slot 行 (避免整表 reload 引发滚动/选择抖动).
    fileprivate func refreshSpinningSlotRow() {
        guard let outline = outlineView else { return }
        for row in 0..<outline.numberOfRows {
            if let slotNode = outline.item(atRow: row) as? SlotNode,
               isSlotSpinning(slotNode) {
                outline.reloadItem(slotNode)
            }
        }
    }

    // MARK: - Sidebar Row Rendering

    fileprivate static let statusDotTag = 920501
    fileprivate static let secondaryTextTag = 920502
    fileprivate static let statusDotWidth: CGFloat = 14
    fileprivate static let deviceRowHeight: CGFloat = 40
    fileprivate static let rowInsetH: CGFloat = 6

    /// 为 DeviceNode 行构建两行 cell:
    ///   [primary: 设备名]                                  [● status dot]
    ///   [secondary: Bluetooth · Mouse · HID++]
    /// status dot 垂直居中对齐主文本, 固定 trailing 不被压缩.
    private func makeDeviceRowCell(in outlineView: NSOutlineView) -> NSTableCellView {
        let identifier = NSUserInterfaceItemIdentifier("DeviceRowCell")
        if let existing = outlineView.makeView(withIdentifier: identifier, owner: nil) as? NSTableCellView {
            return existing
        }
        let view = NSTableCellView()
        view.identifier = identifier

        let primary = NSTextField(labelWithString: "")
        primary.translatesAutoresizingMaskIntoConstraints = false
        primary.backgroundColor = .clear
        primary.isBezeled = false
        primary.isEditable = false
        primary.isSelectable = false
        // 必须显式设置和 attributedString 一致的字号, 否则 intrinsic size
        // 会按 label 默认 13pt 计算, 字形在 frame 内偏下导致视觉上下不对称.
        primary.font = NSFont.systemFont(ofSize: 11)
        primary.maximumNumberOfLines = 1
        primary.cell?.usesSingleLineMode = true
        primary.lineBreakMode = .byTruncatingTail
        primary.cell?.truncatesLastVisibleLine = true
        primary.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.textField = primary
        view.addSubview(primary)

        let secondary = NSTextField(labelWithString: "")
        secondary.tag = Self.secondaryTextTag
        secondary.translatesAutoresizingMaskIntoConstraints = false
        secondary.backgroundColor = .clear
        secondary.isBezeled = false
        secondary.isEditable = false
        secondary.isSelectable = false
        secondary.font = NSFont.systemFont(ofSize: 10)
        secondary.maximumNumberOfLines = 1
        secondary.cell?.usesSingleLineMode = true
        secondary.lineBreakMode = .byTruncatingTail
        secondary.cell?.truncatesLastVisibleLine = true
        secondary.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.addSubview(secondary)

        let dot = NSTextField(labelWithString: "")
        dot.tag = Self.statusDotTag
        dot.translatesAutoresizingMaskIntoConstraints = false
        dot.backgroundColor = .clear
        dot.isBezeled = false
        dot.isEditable = false
        dot.isSelectable = false
        dot.alignment = .right
        dot.font = NSFont.systemFont(ofSize: 9)
        dot.setContentHuggingPriority(.required, for: .horizontal)
        dot.setContentCompressionResistancePriority(.required, for: .horizontal)
        view.addSubview(dot)

        // 两行文本用一个 invisible container 包裹后在 view 中垂直居中,
        // 避免直接把 top/bottom 等额 padding 加到 view 上后因字体 metric 不均
        // 导致视觉不对称 (primary 上方留白远大于 secondary 下方).
        let textStack = NSView()
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.addSubview(primary)
        textStack.addSubview(secondary)
        view.addSubview(textStack)

        NSLayoutConstraint.activate([
            // Stack: centered vertically within row, horizontally between leading inset and dot
            textStack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            textStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Self.rowInsetH),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: dot.leadingAnchor, constant: -6),

            // Primary fills stack top
            primary.topAnchor.constraint(equalTo: textStack.topAnchor),
            primary.leadingAnchor.constraint(equalTo: textStack.leadingAnchor),
            primary.trailingAnchor.constraint(lessThanOrEqualTo: textStack.trailingAnchor),

            // Secondary directly below primary; its bottom pins stack bottom
            secondary.topAnchor.constraint(equalTo: primary.bottomAnchor, constant: 2),
            secondary.leadingAnchor.constraint(equalTo: textStack.leadingAnchor),
            secondary.trailingAnchor.constraint(lessThanOrEqualTo: textStack.trailingAnchor),
            secondary.bottomAnchor.constraint(equalTo: textStack.bottomAnchor),

            // Status dot aligned to primary (not view center) so it sits with the primary name
            dot.widthAnchor.constraint(equalToConstant: Self.statusDotWidth),
            dot.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Self.rowInsetH),
            dot.centerYAnchor.constraint(equalTo: primary.centerYAnchor),
        ])
        return view
    }

    /// Sidebar 行状态 (影响右侧圆点的颜色 + 形状).
    /// 颜色 + 形状双编码, 避免纯色盲场景下 ready/initializing 难以区分.
    private enum SidebarRowStatus {
        case ready        // 握手完成, 可通信或已完成枚举
        case initializing // 已打开接口, 握手进行中
        case observer     // 非 HID++ 候选接口; 仅监听广播, 不主动通信

        var color: NSColor {
            switch self {
            case .ready:        return NSColor(calibratedRed: 0.30, green: 0.78, blue: 0.36, alpha: 1.0)
            case .initializing: return NSColor(calibratedRed: 1.00, green: 0.75, blue: 0.00, alpha: 0.9)
            case .observer:     return NSColor.tertiaryLabelColor
            }
        }
        /// ● 实心圆 = 通道已就绪; ◐ 半圆 = 握手进行中; ○ 空心圆 = 仅观察
        var glyph: String {
            switch self {
            case .ready:        return "\u{25CF}"
            case .initializing: return "\u{25D0}"
            case .observer:     return "\u{25CB}"
            }
        }
        var accessibilityLabel: String {
            switch self {
            case .ready:        return "Ready"
            case .initializing: return "Initializing"
            case .observer:     return "Observer"
            }
        }
    }

    private func sidebarStatus(for session: LogiDeviceSession) -> SidebarRowStatus {
        // 非候选接口一律记为 Observer (OS 看得到, Mos 不通信).
        if !session.isHIDPPCandidate { return .observer }
        // handshakeComplete 覆盖所有终态 (receiver: ping 完成; direct: discovery 走到终点).
        return session.debugHandshakeComplete ? .ready : .initializing
    }

    /// HID 接口的"角色" (同一设备暴露多条 HID 接口时用于区分).
    /// Mouse / Keyboard / Consumer Control / Pointer / System Control / Vendor-specific
    private func interfaceRole(for session: LogiDeviceSession) -> String {
        switch (session.usagePage, session.usage) {
        case (0x0001, 0x0002): return "Mouse"
        case (0x0001, 0x0006): return "Keyboard"
        case (0x0001, 0x0001): return "Pointer"
        case (0x0001, 0x0080): return "System Control"
        case (0x000C, _):      return "Consumer Control"
        case (0xFF00, _), (0xFF43, _), (0xFFC0, _): return "Vendor"
        default: return String(format: "Usage %04X/%02X", session.usagePage, session.usage)
        }
    }

    /// 主行: 设备名 (接收器用 Registry 型号名, 直连用产品名).
    private func renderDeviceRowPrimary(node: DeviceNode) -> NSAttributedString {
        let session = node.session
        let primaryName: String = node.isReceiver
            ? LogiReceiverCatalog.displayName(forPID: session.deviceInfo.productId)
            : session.deviceInfo.name
        return NSAttributedString(
            string: primaryName,
            attributes: [
                .foregroundColor: NSColor.labelColor,
                .font: NSFont.systemFont(ofSize: 11),
            ]
        )
    }

    /// 副行:
    ///   - 直连设备: 传输方式 · 接口角色 (HID++ 标记冗余, FEATURES 面板已表达;
    ///     侧栏宽度 ~148px, 多一项会截断 'BLE · Mouse · HID++').
    ///   - 接收器:   HID++ 标记 (接收器名本身含类型, 不重复 transport/role).
    private func renderDeviceRowSecondary(node: DeviceNode) -> NSAttributedString {
        let session = node.session
        let meta     = NSFont.systemFont(ofSize: 10)
        let metaBold = NSFont.systemFont(ofSize: 10, weight: .medium)

        var segments: [String] = []
        if !node.isReceiver {
            segments.append(session.debugIsBLE ? "BLE" : "USB")
            segments.append(interfaceRole(for: session))
        } else if session.isHIDPPCandidate {
            segments.append("HID++")
        }

        let line = NSMutableAttributedString()
        for (index, segment) in segments.enumerated() {
            if index > 0 {
                line.append(NSAttributedString(
                    string: " · ",
                    attributes: [.foregroundColor: NSColor.quaternaryLabelColor, .font: meta]
                ))
            }
            let isHIDPP = segment == "HID++"
            line.append(NSAttributedString(
                string: segment,
                attributes: [
                    .foregroundColor: NSColor.tertiaryLabelColor,
                    .font: isHIDPP ? metaBold : meta,
                ]
            ))
        }
        return line
    }
}

// MARK: - NSTableViewDataSource & Delegate

extension LogiDebugPanel: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        switch tableView.tag {
        case 200: return featureRows.count
        case 201: return controlRows.count
        case 300: return filteredLogEntries().count
        default: return 0
        }
    }
}

extension LogiDebugPanel: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        stopObserving()
    }
}

extension LogiDebugPanel: NSSplitViewDelegate {
    func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        // Features column min width
        return 180
    }

    func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        // Controls column min width — leave at least 200pt on the right
        return max(180, splitView.bounds.width - 200)
    }
}

extension LogiDebugPanel: NSTableViewDelegate {
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        switch tableView.tag {
        case 200: return featureCell(tableColumn: tableColumn, row: row)
        case 201: return controlCell(tableColumn: tableColumn, row: row)
        case 300: return logCell(row: row)
        default: return nil
        }
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        if tableView.tag == 300 {
            let filtered = filteredLogEntries()
            guard row < filtered.count else { return 18 }
            let entry = filtered[row].1
            if entry.isExpanded {
                var lines = 1
                if entry.rawBytes != nil { lines += 1 }
                if entry.decoded != nil { lines += 1 }
                return CGFloat(lines) * 16 + 4
            }
        }
        return tableView.tag == 300 ? 18 : 20
    }

    private func featureCell(tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < featureRows.count else { return nil }
        let item = featureRows[row]
        let cellId = NSUserInterfaceItemIdentifier("fCell")
        let cell = makeCenteredTableCell(
            in: featureTableView,
            identifier: cellId,
            font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        )
        guard let label = cell.textField else { return cell }
        label.textColor = .labelColor

        switch tableColumn?.identifier.rawValue {
        case "fIdx": label.stringValue = item.index
        case "fId": label.stringValue = item.featureIdHex
        case "fName":
            label.stringValue = item.name
            label.textColor = NSColor(calibratedRed: 0.5, green: 0.7, blue: 1.0, alpha: 1.0)
        default: break
        }
        return cell
    }

    private func controlCell(tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < controlRows.count else { return nil }
        let ctrl = controlRows[row]
        let cellId = NSUserInterfaceItemIdentifier("cCell")
        let cell = makeCenteredTableCell(
            in: controlsTableView,
            identifier: cellId,
            font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        )
        guard let label = cell.textField else { return cell }
        label.textColor = .labelColor

        // reportingFlags 来自 GetControlReporting 的设备真实响应. 方案 B 让 Mos 不在本地改写它,
        // 但任何一次后续回读 (Query Reporting / Re-Discover / 面板重入) 都会把 Mos 自己通过
        // setControlReporting 置位的 bit 读回来 —— 所以 "reportingFlags != 0" 不能单独判为第三方.
        // 真正的第三方冲突 = 设备侧非零 且 不在 Mos 的 divertedCIDs 集合里.
        // 同一 CID 若被 Mos 与第三方同时 divert, 此处偏向 Mos 语义: ACTIONS 显示 Undivert 时
        // Status 也显示 DVRT, 不会再出现 "按钮是 Undivert 但标签却是 3rd-DVRT" 的隐藏矛盾.
        let mosOwns = currentSession?.debugDivertedCIDs.contains(ctrl.cid) ?? false
        let status = LogiConflictDetector.status(
            reportingFlags: ctrl.reportingFlags,
            targetCID: ctrl.targetCID,
            cid: ctrl.cid,
            reportingQueried: ctrl.reportingQueried,
            mosOwnsDivert: mosOwns
        )

        switch tableColumn?.identifier.rawValue {
        case "cCid": label.stringValue = String(format: "0x%04X", ctrl.cid)
        case "cName": label.stringValue = LogiCIDDirectory.name(forCID: ctrl.cid)
        case "cFlags":
            label.stringValue = HIDPPInfo.flagsDescription(ctrl.flags)
            label.textColor = .secondaryLabelColor
        case "cStatus":
            switch status {
            case .foreignDivert:
                label.stringValue = "3rd-DVRT"
                label.textColor = NSColor(calibratedRed: 1.0, green: 0.3, blue: 0.3, alpha: 0.9)
            case .remapped:
                label.stringValue = "REMAP"
                label.textColor = NSColor(calibratedRed: 1.0, green: 0.8, blue: 0.2, alpha: 0.8)
            case .mosOwned:
                label.stringValue = "DVRT"
                label.textColor = NSColor(calibratedRed: 1.0, green: 0.6, blue: 0.0, alpha: 0.8)
            case .clear:
                label.stringValue = "\u{25CF}"
                label.textColor = NSColor(calibratedRed: 0.3, green: 0.8, blue: 0.4, alpha: 1.0)
            case .unknown:
                label.stringValue = "?"
                label.textColor = .tertiaryLabelColor
            }
        default: break
        }
        return cell
    }

    private func logCell(row: Int) -> NSView? {
        let filtered = filteredLogEntries()
        guard row < filtered.count else { return nil }
        let entry = filtered[row].1

        let cellId = NSUserInterfaceItemIdentifier("logCell")
        let cell = logTableView.makeView(withIdentifier: cellId, owner: nil) as? NSTextField
            ?? NSTextField(labelWithString: "")
        cell.identifier = cellId
        cell.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        cell.backgroundColor = .clear
        cell.isBezeled = false
        cell.isEditable = false
        cell.isSelectable = true
        cell.maximumNumberOfLines = 0
        cell.cell?.wraps = true

        let color = logColor(for: entry.type)
        let arrow = entry.isExpanded ? "\u{25BE}" : "\u{25B8}"
        var text = "\(arrow) [\(entry.timestamp)] \(entry.message)"
        if entry.isExpanded {
            if let raw = entry.rawBytes {
                text += "\n  HEX: \(raw.map { String(format: "%02X", $0) }.joined(separator: " "))"
            }
            if let decoded = entry.decoded { text += "\n  \(decoded)" }
        }
        cell.attributedStringValue = NSAttributedString(string: text, attributes: [
            .foregroundColor: color,
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular),
        ])
        return cell
    }
}
