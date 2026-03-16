# Logitech HID++ 2.0 硬件按键集成设计

## 概述

为 Mos 新增 Logitech 鼠标硬件层面的按键识别能力。通过 IOKit HIDManager 实现 HID++ 2.0 协议通信,捕获 CGEventTap 无法感知的 Logitech 专有按键(手势按钮、DPI 按钮等),并以最小侵入方式整合到现有按键绑定系统中。

### 目标

- 识别并捕获 Logitech HID++ 鼠标上的专有硬件按键
- 用户可将这些按键绑定到系统快捷键(复用现有 ButtonBinding 机制)
- 兼容未来新增的 Logitech HID++ 设备
- 不影响现有滚动/按键/分应用/Remote 检测等全部功能
- 现有用户配置数据自动兼容,无需迁移

### 非目标

- 不替代 CGEventTap(两者互补)
- 不处理 Logitech 滚动数据(ScrollCore 保持不变)
- 不支持非 Logitech 的 HID 设备
- 不实现 DPI 控制、电池状态等非按键功能

---

## 背景知识

### HID++ 2.0 协议

HID++ 2.0 是 Logitech 的私有扩展协议,基于标准 USB HID 的 vendor-specific usage page 传输。跨平台(Windows/macOS/Linux),非 Apple 专有。

**关键概念:**
- **IRoot (Feature 0x0000)**: 所有 HID++ 2.0 设备必有的根特征,用于动态发现其他特征的 index
- **REPROG_CONTROLS_V4 (Feature 0x1B04)**: 按键重编程特征,支持按键 divert(将按键事件从标准 OS 路径转移到 HID++ 通道)
- **报文格式**: Short (7 bytes, Report ID 0x10), Long (20 bytes, Report ID 0x11)
- **Feature Discovery**: 通过 IRoot 的 GetFeature() 查询 Feature ID → Feature Index 映射

### 为什么需要 HID++

Logitech 鼠标上的某些按键(手势按钮、DPI 切换等)不会产生标准 CGEvent。这些按键的信号只在 HID++ 通道中可见。CGEventTap 对这类按键完全透明。

### macOS 访问路径

macOS 上通过 IOKit 框架的 `IOHIDManager` API 访问底层 HID 设备。无需第三方库(Mouser 项目用的 Python `hidapi` 底层也是 IOKit)。

---

## 架构设计

### 设计原则

1. **互补而非替代**: HID++ 是 CGEventTap 的补充事件源,不改变现有事件处理流程
2. **统一抽象**: 引入 MosInputEvent 统一两种来源的事件表示
3. **状态隔离**: 各模块只拥有自己的状态,单向依赖,无循环引用
4. **向后兼容**: 新增字段全部 optional,旧数据自动兼容

### 分层架构

```
+---------------------------------------------------------------+
|                     Event Source Layer                         |
|                  (互相完全不知道对方存在)                         |
|                                                               |
|  +-------------------------+  +-----------------------------+ |
|  | CGEventTap Adapter      |  | LogitechHIDManager          | |
|  | (现有 Interceptor)       |  | (新增, IOKit HIDManager)    | |
|  |                         |  |                             | |
|  | 职责:                    |  | 职责:                       | |
|  | - 拦截系统级事件          |  | - 枚举 Logitech HID 设备    | |
|  | - 转换为 MosInputEvent   |  | - HID++ 2.0 协议通信        | |
|  | - 处理 consume/pass      |  | - 按钮 divert 和事件监听    | |
|  |                         |  | - 设备连接/断开生命周期      | |
|  +------------+------------+  +-------------+---------------+ |
|               | MosInputEvent               | MosInputEvent   |
+---------------+-----------------------------+-----------------+
                |                             |
                v                             v
+---------------------------------------------------------------+
|                   Processing Layer                            |
|                                                               |
|  +----------------------------------------------------------+ |
|  | MosInputProcessor (单例, 无状态)                           | |
|  |                                                          | |
|  | 输入: MosInputEvent                                       | |
|  | 输出: MosInputResult (.consumed / .passthrough)           | |
|  |                                                          | |
|  | 逻辑:                                                     | |
|  | 1. ButtonUtils.shared.getButtonBindings()                 | |
|  | 2. 遍历匹配 triggerEvent.matches(mosEvent)                | |
|  | 3. 匹配成功: ShortcutExecutor.execute() -> .consumed      | |
|  | 4. 无匹配: .passthrough                                   | |
|  +----------------------------------------------------------+ |
+---------------------------------------------------------------+
                |
                v
+---------------------------------------------------------------+
|                   Action Layer (现有, 不变)                     |
|                                                               |
|  ShortcutExecutor -> 合成 CGEvent -> post 到系统               |
+---------------------------------------------------------------+
```

### 控制流详解

#### CGEventTap 路径 (同步,必须立即返回)

```swift
// ButtonCore.buttonEventCallBack 改造:
let buttonEventCallBack: CGEventTapCallBack = { (proxy, type, event, refcon) in
    let mosEvent = MosInputEvent(fromCGEvent: event)
    let result = MosInputProcessor.shared.process(mosEvent)
    switch result {
    case .consumed:    return nil
    case .passthrough: return Unmanaged.passUnretained(event)
    }
}
```

#### HID++ 路径 (同步,无 pass-through)

```swift
// LogitechHIDManager 内部:
func onHIDButtonEvent(cid: UInt16, isDown: Bool, device: MosInputDevice) {
    let mosEvent = MosInputEvent(
        type: .mouse,
        code: LogitechCIDMap.toMosCode(cid),
        modifiers: currentModifierFlags(),
        phase: isDown ? .down : .up,
        source: .hidPlusPlus,
        device: device
    )
    // 结果被忽略 -- HID++ 按键不存在 "pass-through" 语义
    // 因为这些按键本来就不会产生系统事件
    let _ = MosInputProcessor.shared.process(mosEvent)
}
```

---

## 数据模型

### MosInputEvent (新增)

**设计约束**: `MosInputEvent` 是纯运行时对象,不遵循 Codable。因为 `MosInputSource.cgEvent(CGEvent)` 中的 CGEvent 不可序列化。只有从中提取的 `RecordedEvent` 走持久化路径。

```swift
/// 事件阶段
enum MosInputPhase {
    case down
    case up
}

/// 事件来源
enum MosInputSource {
    /// 来自 CGEventTap, 携带原始 CGEvent 用于 pass-through/consume
    case cgEvent(CGEvent)
    /// 来自 Logitech HID++ 协议
    case hidPlusPlus
}

/// 设备信息 (可序列化, 用于 DeviceFilter 匹配和 UI 展示)
struct MosInputDevice: Codable, Equatable {
    let vendorId: UInt16      // USB Vendor ID (Logitech = 0x046D)
    let productId: UInt16     // USB Product ID
    let name: String          // 人类可读名称 (如 "MX Master 3S")
}

/// 统一输入事件 (运行时对象, 不可序列化)
struct MosInputEvent {
    let type: EventType           // .keyboard 或 .mouse (复用现有枚举)
    let code: UInt16              // 按键码 / 按钮码
    let modifiers: CGEventFlags   // 修饰键状态
    let phase: MosInputPhase      // 按下 / 抬起
    let source: MosInputSource    // 事件来源
    let device: MosInputDevice?   // 设备信息 (CGEventTap 来源为 nil)

    /// 从 CGEvent 构造
    init(fromCGEvent event: CGEvent) {
        if event.isKeyboardEvent {
            self.type = .keyboard
            self.code = event.keyCode
        } else {
            self.type = .mouse
            self.code = event.mouseCode
        }
        self.modifiers = event.flags
        self.phase = event.isKeyDown ? .down : .up
        self.source = .cgEvent(event)
        self.device = nil
    }

    /// 从 HID++ 数据构造
    init(type: EventType, code: UInt16, modifiers: CGEventFlags,
         phase: MosInputPhase, source: MosInputSource, device: MosInputDevice?) {
        self.type = type
        self.code = code
        self.modifiers = modifiers
        self.phase = phase
        self.source = source
        self.device = device
    }

    /// 构造展示用名称组件
    static func buildDisplayComponents(_ event: MosInputEvent) -> [String] {
        var components: [String] = []
        // 修饰键
        let flags = NSEvent.ModifierFlags(rawValue: UInt(event.modifiers.rawValue))
        if flags.contains(.control) { components.append(KeyCode.modifierMap[0x3B] ?? "^") }
        if flags.contains(.option) { components.append(KeyCode.modifierMap[0x3A] ?? "~") }
        if flags.contains(.shift) { components.append(KeyCode.modifierMap[0x38] ?? "$") }
        if flags.contains(.command) { components.append(KeyCode.modifierMap[0x37] ?? "@") }
        // 按键名称
        switch event.type {
        case .keyboard:
            components.append(KeyCode.keyMap[event.code] ?? "Key \(event.code)")
        case .mouse:
            if event.code >= 1000 {
                components.append(LogitechCIDMap.displayName(forCode: event.code))
            } else {
                components.append(KeyCode.mouseMap[event.code] ?? "Button \(event.code)")
            }
        }
        return components
    }
}
```

### MosInputProcessor (新增)

```swift
/// 处理结果
enum MosInputResult {
    case consumed     // 事件已处理,不再传递
    case passthrough  // 事件未匹配,继续传递
}

/// 统一事件处理器 (无状态单例)
class MosInputProcessor {
    static let shared = MosInputProcessor()

    func process(_ event: MosInputEvent) -> MosInputResult {
        let bindings = ButtonUtils.shared.getButtonBindings()
        guard let binding = bindings.first(where: {
            $0.triggerEvent.matchesMosInput(event) && $0.isEnabled
        }) else {
            return .passthrough
        }
        ShortcutExecutor.shared.execute(named: binding.systemShortcutName)
        return .consumed
    }
}
```

### RecordedEvent 扩展 (修改)

```swift
struct RecordedEvent: Codable, Equatable {
    // 现有字段 (不变)
    let type: EventType
    let code: UInt16
    let modifiers: UInt
    let displayComponents: [String]

    // 新增字段 (optional, 向后兼容)
    let deviceFilter: DeviceFilter?

    // 新增: 匹配 MosInputEvent
    func matchesMosInput(_ event: MosInputEvent) -> Bool {
        // 1. 修饰键匹配
        guard UInt(event.modifiers.rawValue) == modifiers else { return false }
        // 2. 类型匹配
        guard event.type == type else { return false }
        // 3. 按键码匹配
        switch type {
        case .keyboard:
            guard event.phase == .down else { return false }
            guard code == event.code else { return false }
        case .mouse:
            guard code == event.code else { return false }
        }
        // 4. 设备过滤 (可选)
        if let filter = deviceFilter {
            guard filter.matches(event.device) else { return false }
        }
        return true
    }

    // 保留: 旧的 CGEvent 匹配 (供 ScrollCore 热键使用, 不改)
    func matches(_ event: CGEvent) -> Bool {
        // 现有逻辑完全不变
    }

    // 新增: 从 MosInputEvent 构造
    init(from event: MosInputEvent, deviceFilter: DeviceFilter? = nil) {
        self.type = event.type
        self.code = event.code
        self.modifiers = UInt(event.modifiers.rawValue)
        self.deviceFilter = deviceFilter
        self.displayComponents = MosInputEvent.buildDisplayComponents(event)
    }
}

/// ScrollHotkey 扩展: 从 MosInputEvent 构造
extension ScrollHotkey {
    init(from event: MosInputEvent) {
        self.type = event.type
        self.code = event.code
    }
}
```

### DeviceFilter (新增)

```swift
struct DeviceFilter: Codable, Equatable {
    let vendorId: UInt16?     // nil = 不限厂商
    let productId: UInt16?    // nil = 不限型号

    func matches(_ device: MosInputDevice?) -> Bool {
        guard let device = device else { return false }
        if let vid = vendorId, vid != device.vendorId { return false }
        if let pid = productId, pid != device.productId { return false }
        return true
    }
}
```

### 按钮编号空间

```swift
// 标准 CGEvent 鼠标按钮: 0 ~ 31 (系统分配)
// 标准键盘虚拟键码:      0 ~ 127 (由 EventType 区分, 不冲突)
// Logitech HID++ 专有:   1000+   (我们分配)

/// Logitech CID -> Mos 按钮码映射
struct LogitechCIDMap {
    // CID 参考: Logitech HID++ 2.0 REPROG_CONTROLS_V4 规范
    private static let cidToCode: [UInt16: UInt16] = [
        0x00C3: 1000,  // Gesture Button
        0x00C4: 1001,  // SmartShift
        0x00D7: 1002,  // DPI Change Button
        // 后续设备新增 CID 在此追加, 从 1003 递增
    ]

    static func toMosCode(_ cid: UInt16) -> UInt16 {
        if let known = cidToCode[cid] { return known }
        // 未知 CID: 映射到 2000+ 区段, 但限制在 UInt16 范围内
        let mapped = UInt32(2000) + UInt32(cid)
        return mapped <= UInt32(UInt16.max) ? UInt16(mapped) : UInt16(cid & 0x0FFF) + 2000
    }

    static func displayName(forCode code: UInt16) -> String {
        switch code {
        case 1000: return "Gesture"
        case 1001: return "SmartShift"
        case 1002: return "DPI"
        default:   return "Logi \(code)"
        }
    }
}
```

---

## LogitechHIDManager 模块设计

### 职责

1. 通过 IOKit `IOHIDManager` 枚举和监控 Logitech HID 设备
2. 实现 HID++ 2.0 协议子集(IRoot feature discovery + REPROG_CONTROLS_V4 button divert)
3. 解析 HID++ 通知,将按键事件转换为 MosInputEvent
4. 管理设备连接/断开生命周期

### 设备发现

```swift
class LogitechHIDManager {
    static let shared = LogitechHIDManager()

    private var hidManager: IOHIDManager?
    private var connectedDevices: [IOHIDDevice: LogitechDeviceSession] = [:]

    /// Logitech USB Vendor ID
    private static let logitechVendorId: Int = 0x046D

    func start() {
        hidManager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        guard let manager = hidManager else { return }

        // 只匹配 Logitech 设备
        let matchDict: [String: Any] = [
            kIOHIDVendorIDKey as String: LogitechHIDManager.logitechVendorId
        ]
        IOHIDManagerSetDeviceMatching(manager, matchDict as CFDictionary)

        // 注册连接/断开回调
        IOHIDManagerRegisterDeviceMatchingCallback(manager, deviceConnected, nil)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, deviceDisconnected, nil)

        // Schedule 到 main RunLoop (低频事件, 避免线程同步)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    func stop() {
        guard let manager = hidManager else { return }
        // 清理所有设备会话
        for (_, session) in connectedDevices {
            session.teardown()
        }
        connectedDevices.removeAll()
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        hidManager = nil
    }
}
```

### 设备会话

每个已连接的 Logitech HID++ 设备维护一个独立会话:

```swift
/// 单个 Logitech 设备的 HID++ 会话
class LogitechDeviceSession {
    let hidDevice: IOHIDDevice
    let deviceInfo: MosInputDevice

    // HID++ 状态
    private var featureIndex: [UInt16: UInt8] = [:]   // Feature ID -> Feature Index
    private var divertedCIDs: Set<UInt16> = []         // 已 divert 的 CID 集合
    private var lastActiveCIDs: Set<UInt16> = []       // 上一帧活跃的 CID (用于差分检测)
    private var deviceIndex: UInt8 = 0x01              // HID++ device index (连接时探测)

    // Report buffer: 必须用堆分配指针, 保证在 IOKit 回调生命周期内地址稳定
    // Swift [UInt8] 是 value type, copy-on-write 时地址会变, 导致 IOKit 回调访问野指针
    private var reportBufferPtr: UnsafeMutablePointer<UInt8>?
    private static let reportBufferSize = 64  // 足够容纳 Long report (20 bytes) + 余量

    // HID++ 2.0 常量
    private static let featureIRoot: UInt16 = 0x0000
    private static let featureReprogV4: UInt16 = 0x1B04

    // 异步请求超时保护
    private var discoveryTimer: Timer?
    private var pendingDiscovery: [UInt16: (UInt8?) -> Void] = [:]
    private static let discoveryTimeout: TimeInterval = 5.0

    init(hidDevice: IOHIDDevice) {
        self.hidDevice = hidDevice
        self.deviceInfo = MosInputDevice(
            vendorId: UInt16(IOHIDDeviceGetProperty(hidDevice, kIOHIDVendorIDKey as CFString) as? Int ?? 0),
            productId: UInt16(IOHIDDeviceGetProperty(hidDevice, kIOHIDProductIDKey as CFString) as? Int ?? 0),
            name: IOHIDDeviceGetProperty(hidDevice, kIOHIDProductKey as CFString) as? String ?? "Unknown"
        )
    }

    deinit {
        reportBufferPtr?.deallocate()
    }

    /// 初始化 HID++ 通信: 探测 Device Index -> Feature Discovery -> Button Divert
    func setup() {
        // 1. 分配稳定的 report buffer
        reportBufferPtr = .allocate(capacity: Self.reportBufferSize)
        reportBufferPtr!.initialize(repeating: 0, count: Self.reportBufferSize)

        // 2. 注册 Input Report 回调 (使用堆指针)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(
            hidDevice,
            reportBufferPtr!,
            Self.reportBufferSize,
            Self.inputReportCallback,
            context
        )

        // 3. 探测 device index
        // 蓝牙直连通常是 0x01, Unifying Receiver 按配对槽位 0x01-0x06
        // 发送 ping (IRoot.GetFeature with dummy feature) 到候选 index, 看谁响应
        probeDeviceIndex { [weak self] index in
            guard let self = self, let index = index else {
                NSLog("[LogitechHID] Failed to probe device index, using default 0x01")
                return
            }
            self.deviceIndex = index

            // 4. Feature Discovery
            self.discoverFeature(featureId: Self.featureReprogV4) { [weak self] featureIdx in
                guard let self = self, let featureIdx = featureIdx else {
                    NSLog("[LogitechHID] Device does not support REPROG_CONTROLS_V4, skipping")
                    return
                }
                self.featureIndex[Self.featureReprogV4] = featureIdx
                // 5. Divert 可重编程的按键
                self.divertButtons(featureIndex: featureIdx)
            }
        }
    }

    func teardown() {
        // 取消超时定时器
        discoveryTimer?.invalidate()
        discoveryTimer = nil
        pendingDiscovery.removeAll()
        // 取消所有 divert
        for cid in divertedCIDs {
            undivertButton(cid: cid)
        }
        divertedCIDs.removeAll()
    }

    /// 探测正确的 HID++ device index
    /// 依次尝试 0x01 ~ 0x06, 发送 IRoot ping, 看哪个 index 收到有效响应
    private func probeDeviceIndex(completion: @escaping (UInt8?) -> Void) {
        // 简化策略: 先尝试 0x01 (蓝牙直连最常见)
        // 如果超时无响应, 尝试下一个 index
        // 最多尝试到 0x06
        // 完整实现在 LogitechDeviceSession.swift 中
        completion(0x01)  // 伪代码, 实际需要异步探测
    }
}
```
```

### HID++ 2.0 消息收发

```swift
extension LogitechDeviceSession {
    // 报文结构
    // Short: [ReportID(0x10), DeviceIndex, FeatureIndex, FuncID/SwID, Param0, Param1, Param2]
    // Long:  [ReportID(0x11), DeviceIndex, FeatureIndex, FuncID/SwID, Param0...Param15]

    /// 发送 HID++ 请求
    /// - 使用实例的 deviceIndex (连接时探测确定, 非硬编码)
    /// - 检查 IOReturn 返回值, 失败时记录日志
    private func sendRequest(featureIndex: UInt8, functionId: UInt8, params: [UInt8] = []) {
        var report = [UInt8](repeating: 0, count: 7)  // Short report
        report[0] = 0x10                               // Report ID
        report[1] = deviceIndex                        // 探测得到的 device index
        report[2] = featureIndex
        report[3] = (functionId << 4) | 0x01           // FuncID | SwID
        for (i, p) in params.prefix(3).enumerated() {
            report[4 + i] = p
        }
        let result = IOHIDDeviceSetReport(
            hidDevice,
            IOHIDReportType(kIOHIDReportTypeOutput),   // Swift 需要显式类型转换
            CFIndex(report[0]),
            report,
            report.count
        )
        if result != kIOReturnSuccess {
            NSLog("[LogitechHID] SetReport failed: 0x%08x", result)
        }
    }

    /// Feature Discovery: IRoot.GetFeature(featureId) -> featureIndex
    /// 带超时保护: discoveryTimeout 秒内无响应则回调 nil
    private func discoverFeature(featureId: UInt16, completion: @escaping (UInt8?) -> Void) {
        let params: [UInt8] = [UInt8(featureId >> 8), UInt8(featureId & 0xFF)]
        sendRequest(featureIndex: 0x00, functionId: 0, params: params)
        pendingDiscovery[featureId] = completion

        // 超时保护
        discoveryTimer = Timer.scheduledTimer(withTimeInterval: Self.discoveryTimeout, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            if let pending = self.pendingDiscovery.removeValue(forKey: featureId) {
                NSLog("[LogitechHID] Feature discovery timed out for 0x%04X", featureId)
                pending(nil)
            }
        }
    }

    /// Button Divert: REPROG_CONTROLS_V4.SetControlReporting(CID, divert=1)
    /// 动态发现始终优先; knownDevices 仅作为调试参考, 不影响 divert 决策
    private func divertButtons(featureIndex: UInt8) {
        queryControlList(featureIndex: featureIndex) { [weak self] controls in
            for control in controls where control.isDivertable {
                self?.divertButton(featureIndex: featureIndex, cid: control.cid)
            }
        }
    }
}
```

### 事件解析与分发

```swift
extension LogitechDeviceSession {
    // C 函数指针, 作为 IOHIDDeviceRegisterInputReportCallback 的 callback
    static let inputReportCallback: IOHIDReportCallback = { context, result, sender, type, reportID, report, reportLength in
        guard let context = context else { return }
        let session = Unmanaged<LogitechDeviceSession>.fromOpaque(context).takeUnretainedValue()
        let reportData = Array(UnsafeBufferPointer(start: report, count: reportLength))
        session.handleInputReport(reportData)
    }

    /// 处理 Input Report
    func handleInputReport(_ report: [UInt8]) {
        // 验证是 HID++ 报文
        guard report.count >= 7, (report[0] == 0x10 || report[0] == 0x11) else { return }

        let featureIdx = report[2]
        let funcAndSw = report[3]

        // HID++ Error Report 检测 (Feature Index = 0xFF)
        // 格式: [ReportID, DevIdx, 0xFF, ErrorFeatureIdx, ErrorFuncID, SoftwareID, ErrorCode]
        if featureIdx == 0xFF {
            let errorFeatureIdx = report[3]
            let errorCode = report.count > 6 ? report[6] : 0
            NSLog("[LogitechHID] Error report: featureIdx=0x%02X errorCode=0x%02X", errorFeatureIdx, errorCode)
            // 如果有 pending discovery 对应此 feature, 回调 nil
            handleErrorReport(report)
            return
        }

        // 检查是否为 pending feature discovery 的响应
        if featureIdx == 0x00 {
            handleDiscoveryResponse(report)
            return
        }

        // 检查是否为 REPROG_CONTROLS_V4 通知
        guard let reprogIdx = featureIndex[Self.featureReprogV4],
              featureIdx == reprogIdx else { return }

        // 解析按键事件
        // REPROG_CONTROLS_V4 divertedButtonsEvent 通知格式:
        // Params: [CID_MSB, CID_LSB, CID_MSB, CID_LSB, ...]  (成对 CID, 0x0000 结束)
        var activeCIDs: Set<UInt16> = []
        var offset = 4
        while offset + 1 < report.count {
            let cid = (UInt16(report[offset]) << 8) | UInt16(report[offset + 1])
            if cid == 0 { break }
            activeCIDs.insert(cid)
            offset += 2
        }

        // 差分检测: 按下/抬起
        let newlyPressed = activeCIDs.subtracting(lastActiveCIDs)
        let newlyReleased = lastActiveCIDs.subtracting(activeCIDs)
        lastActiveCIDs = activeCIDs

        for cid in newlyPressed {
            dispatchButtonEvent(cid: cid, isDown: true)
        }
        for cid in newlyReleased {
            dispatchButtonEvent(cid: cid, isDown: false)
        }
    }

    private func dispatchButtonEvent(cid: UInt16, isDown: Bool) {
        // 使用 CGEventSource.flagsState 获取修饰键 (比 NSEvent.current 更可靠)
        // NSEvent.current 只在 sendEvent 期间有效, IOKit 回调中可能为 nil
        // CGEventSource.flagsState(.combinedSessionState) 在 macOS 10.13+ 可用
        let currentFlags = CGEventSource.flagsState(.combinedSessionState)

        let mosEvent = MosInputEvent(
            type: .mouse,
            code: LogitechCIDMap.toMosCode(cid),
            modifiers: currentFlags,
            phase: isDown ? .down : .up,
            source: .hidPlusPlus,
            device: deviceInfo
        )

        // 处理结果: HID++ 事件无 pass-through 语义
        let _ = MosInputProcessor.shared.process(mosEvent)

        // 同时发送通知 (供 KeyRecorder 录制期间监听)
        NotificationCenter.default.post(
            name: LogitechHIDManager.buttonEventNotification,
            object: mosEvent
        )
    }
}
```

### 设备兼容性策略

```swift
/// 已知设备的按键定义 (可通过 plist/JSON 配置文件外置, 未来不用改代码)
struct LogitechDeviceProfile {
    let productId: UInt16
    let name: String
    let divertableCIDs: [UInt16]  // 需要 divert 的 CID 列表

    static let knownDevices: [UInt16: LogitechDeviceProfile] = [
        0xB034: LogitechDeviceProfile(
            productId: 0xB034,
            name: "MX Master 3S",
            divertableCIDs: [0x00C3, 0x00C4, 0x00D7]
        ),
        // 后续设备在此追加
    ]
}
```

**未知设备处理**: 对于 `knownDevices` 中没有的 Logitech 设备,使用动态发现:
1. 检查设备是否支持 REPROG_CONTROLS_V4 feature
2. 如果支持,查询其可 divert 的按键列表
3. 自动 divert 所有标记为 divertable 的按键

这意味着未来新 Logitech 设备只要支持 HID++ 2.0 和 REPROG_CONTROLS_V4,无需修改代码即可自动兼容。

**优先级**: 动态发现始终优先。`knownDevices` 仅作为调试参考和显示名称来源,不影响 divert 决策。如果动态发现返回的可 divert 按键多于 `knownDevices` 中定义的,按动态发现结果执行。

---

## 应用生命周期集成

```swift
// AppDelegate 或等效的启动入口
func applicationDidFinishLaunching() {
    // ... 现有初始化 ...
    ScrollCore.shared.enable()
    ButtonCore.shared.enable()
    LogitechHIDManager.shared.start()   // 在 ButtonCore 之后启动
}

func applicationWillTerminate() {
    LogitechHIDManager.shared.stop()    // 在 ButtonCore 之前停止
    ButtonCore.shared.disable()
    ScrollCore.shared.disable()
}
```

LogitechHIDManager 的启停独立于 ButtonCore,但顺序上:
- 启动时: ButtonCore 先启用 (确保 MosInputProcessor 的下游就绪), 然后启动 LogitechHID
- 停止时: 先停 LogitechHID (停止产生事件), 然后停 ButtonCore

---

## 状态隔离

### 状态归属矩阵

| 模块 | 拥有的状态 | 不知道的事 |
|------|-----------|----------|
| **CGEventTap Adapter** (ButtonCore) | Interceptor 实例、EventTap 生命周期 | LogitechHIDManager 存在 |
| **LogitechHIDManager** | IOHIDManager、已连接设备列表 | CGEventTap 存在、ButtonBinding 配置 |
| **LogitechDeviceSession** | HID++ 会话状态、feature index 缓存、divert 状态、lastActiveCIDs | 处理层如何消费事件 |
| **MosInputProcessor** | 无状态 | 事件来自哪里 |
| **Options / ButtonUtils** | ButtonBinding 持久化配置 | 事件如何产生 |
| **KeyRecorder** | 录制会话状态 | 设备协议实现 |
| **ShortcutExecutor** | 无状态 | 触发来源 |

### 依赖方向 (单向, 无环)

```
LogitechHIDManager --+
                     +--> MosInputProcessor --> ButtonUtils/Options --> ShortcutExecutor
CGEventTap Adapter --+
```

### 线程模型

```
Main RunLoop
  +-- CGEventTap 回调 (系统调度, 同步)
  +-- IOKit HIDManager 回调 (schedule 到 Main RunLoop, 同步)
  +-- MosInputProcessor.process() (被上述两者同步调用, 无锁竞争)
```

IOKit schedule 到 Main RunLoop 的理由:
- HID++ 按键事件极低频(用户按键级别, 每秒个位数)
- 避免跨线程同步复杂性
- ShortcutExecutor 内部的 CGEvent.post() 需要在 main thread

---

## KeyRecorder 适配

### 改动方案

KeyRecorder 需要同时捕获 CGEventTap 和 HID++ 两种事件源:

```swift
class KeyRecorder: NSObject {
    // 新增: HID++ 事件监听 (录制期间临时启用)
    private var hidEventObserver: NSObjectProtocol?

    func startRecording(from sourceView: NSView, mode: KeyRecordingMode = .combination) {
        // ... 现有 CGEventTap interceptor 启动逻辑不变 ...

        // 新增: 监听 HID++ 事件
        hidEventObserver = NotificationCenter.default.addObserver(
            forName: LogitechHIDManager.buttonEventNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let mosEvent = notification.object as? MosInputEvent else { return }
            // 复用现有的录制完成通知机制
            NotificationCenter.default.post(
                name: KeyRecorder.FINISH_NOTI_NAME,
                object: mosEvent  // 注意: 这里传的是 MosInputEvent 而非 CGEvent
            )
        }
    }

    func stopRecording() {
        // ... 现有清理逻辑 ...
        // 新增: 移除 HID++ 监听
        if let observer = hidEventObserver {
            NotificationCenter.default.removeObserver(observer)
            hidEventObserver = nil
        }
    }
}
```

### Delegate 协议变更

**问题**: 现有 `KeyRecorderDelegate` 是 `@objc protocol` (因为使用了 `@objc optional`)。但 `MosInputEvent` 是 struct,不能在 `@objc` 方法中使用。

**解决方案**: 去掉 `@objc`,用 protocol extension 提供默认实现替代 `@objc optional`:

```swift
// 改造前:
// @objc protocol KeyRecorderDelegate: AnyObject {
//     func onEventRecorded(_ recorder: KeyRecorder, didRecordEvent event: CGEvent, isDuplicate: Bool)
//     @objc optional func validateRecordedEvent(_ recorder: KeyRecorder, event: CGEvent) -> Bool
// }

// 改造后:
protocol KeyRecorderDelegate: AnyObject {
    func onEventRecorded(_ recorder: KeyRecorder, didRecordEvent event: MosInputEvent, isDuplicate: Bool)
    func validateRecordedEvent(_ recorder: KeyRecorder, event: MosInputEvent) -> Bool
}

// 默认实现 (替代 @objc optional 语义)
extension KeyRecorderDelegate {
    func validateRecordedEvent(_ recorder: KeyRecorder, event: MosInputEvent) -> Bool {
        return true  // 默认: 视为新录制
    }
}
```

### handleRecordedEvent 改造

现有代码第 208 行使用 `notification.object as! CGEvent` 强制转换。HID++ 事件作为 MosInputEvent 通过同一 notification 传入时会崩溃。改造后的完整逻辑:

```swift
@objc private func handleRecordedEvent(_ notification: NSNotification) {
    guard isRecording, !isRecorded else { return }

    // 统一转换为 MosInputEvent (兼容两种来源)
    let mosEvent: MosInputEvent
    if let cgEvent = notification.object as? CGEvent {
        mosEvent = MosInputEvent(fromCGEvent: cgEvent)
    } else if let hidEvent = notification.object as? MosInputEvent {
        mosEvent = hidEvent
    } else {
        NSLog("[EventRecorder] Unknown event type: \(type(of: notification.object))")
        return
    }

    // 验证有效性 (根据录制模式)
    let isValid = recordingMode == .singleKey
        ? isRecordableAsSingleKey(mosEvent)  // 需要新增 MosInputEvent 版本的验证
        : isRecordable(mosEvent)
    guard isValid else {
        keyPopover?.keyPreview.shakeWarning()
        invalidKeyPressCount += 1
        if invalidKeyPressCount >= invalidKeyThreshold {
            keyPopover?.showEscHint()
        }
        return
    }

    isRecorded = true
    let isNew = self.delegate?.validateRecordedEvent(self, event: mosEvent) ?? true
    let isDuplicate = !isNew
    let status: KeyPreview.Status = isNew ? .recorded : .duplicate

    keyPopover?.keyPreview
        .update(from: MosInputEvent.buildDisplayComponents(mosEvent), status: status)
    self.delegate?.onEventRecorded(self, didRecordEvent: mosEvent, isDuplicate: isDuplicate)

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
        self?.stopRecording()
    }
}
```

**注意**: `MosInputEvent` 是 struct (不继承 NSObject),通过 `NotificationCenter` 传递时需要注意: `notification.object` 会被 box 为 `Any?`。使用 `as?` 类型检查即可安全判断。如果 box 行为有问题,备选方案是将 MosInputEvent 包装在一个轻量 NSObject wrapper class 中。

---

## 现有功能兼容性

| 功能 | 影响 | 说明 |
|------|------|------|
| 滚动平滑 (ScrollCore) | 无 | 不改, 继续用 CGEventTap |
| 滚动翻转 | 无 | 同上 |
| 滚动热键 (dash/toggle/block) | 无 | 继续用 ScrollHotkey + CGEvent 匹配 |
| 按钮绑定 (ButtonCore) | 主要改动 | callback 内转为 MosInputProcessor |
| 分应用配置 | 无 | Application.buttons 数据结构已就绪 |
| Remote 检测 | 无 | 只作用于 scrollWheel CGEvent |
| Trackpad 过滤 | 无 | 只作用于 scrollWheel CGEvent |
| Monitor 窗口 | 无 | 只可视化滚动数据 |
| 快捷键执行 | 无 | ShortcutExecutor 接口不变 |
| KeyRecorder | 需适配 | delegate 参数类型变更 |
| 配置持久化 | 向后兼容 | RecordedEvent 新增 optional 字段 |

### ButtonFilter 与 HID++ 事件

当前 `ButtonFilter` 存在但未被 `ButtonCore.buttonEventCallBack` 调用(是预留接口)。`MosInputProcessor` 同样不集成 ButtonFilter。如果未来 ButtonFilter 被启用,需要同时将其应用于 HID++ 事件路径。目前两者保持一致: 都不经过 ButtonFilter。

### Phase 2: ScrollCore 热键统一

当前 ScrollCore 的热键系统 (dash/toggle/block) 使用 `ScrollHotkey.matches(_ event: CGEvent)` 直接匹配 CGEvent。如果未来用户需要将 Logitech 手势按钮用作滚动热键,需要在 LogitechHIDManager 和 ScrollCore 之间增加桥接层,将 HID++ 按键事件转化为 ScrollCore 的热键状态更新。这不在本次设计范围内。

### UserDefaults 数据兼容

RecordedEvent 新增 `deviceFilter: DeviceFilter?`:
- 旧数据反序列化时该字段缺失 -> `decodeIfPresent` 返回 nil -> 匹配任何设备 -> 行为与改动前完全一致
- 无需数据迁移逻辑

---

## 文件变更清单

### 新增文件 (4个)

| 文件 | 位置 | 职责 |
|------|------|------|
| `MosInputEvent.swift` | `Mos/InputEvent/` | MosInputEvent, MosInputPhase, MosInputSource, MosInputDevice, DeviceFilter |
| `MosInputProcessor.swift` | `Mos/InputEvent/` | MosInputProcessor, MosInputResult |
| `LogitechHIDManager.swift` | `Mos/LogitechHID/` | IOKit HIDManager 封装, 设备枚举, 生命周期 |
| `LogitechDeviceSession.swift` | `Mos/LogitechHID/` | HID++ 2.0 协议通信, Feature Discovery, Button Divert, 事件解析 |

### 修改文件 (6个)

| 文件 | 变更内容 |
|------|---------|
| `RecordedEvent.swift` | 新增 `deviceFilter` 字段 + `matchesMosInput()` + `init(from: MosInputEvent)` + `ScrollHotkey.init(from: MosInputEvent)` |
| `ButtonCore.swift` | callback 内部改为构造 MosInputEvent 并调用 MosInputProcessor |
| `KeyRecorder.swift` | delegate 从 `@objc protocol` 改为 Swift protocol + extension 默认实现; 参数类型改为 MosInputEvent; `handleRecordedEvent` 增加类型分支; 录制时增加 HID++ 监听 |
| `KeyCode.swift` | 新增 Logitech 按钮码显示名称映射 (1000+ 段) |
| `PreferencesButtonsViewController` | delegate 方法签名跟随变更, `RecordedEvent(from: MosInputEvent)` |
| `PreferencesScrollingViewController` | delegate 方法签名跟随变更, `ScrollHotkey(from: MosInputEvent)` |

### 不修改文件

ScrollCore, ScrollPoster, Interpolator, ScrollFilter, ScrollUtils, ScrollEvent, Interceptor, ShortcutExecutor, SystemShortcut, ButtonFilter, ButtonUtils, Application, Options, Monitor 窗口

---

## 风险与缓解

### 1. Logitech Options+ 冲突
**风险**: Logitech Options+ 也会访问 HID++ 设备,两者争夺 HID 句柄。
**缓解**: IOHIDManager 的 `kIOHIDOptionsTypeNone` 模式允许多个进程同时打开设备。但 divert 操作可能冲突 -- 需要在文档中告知用户: 如使用 Mos 的 Logitech 按键绑定功能,建议退出 Logitech Options+。

### 2. 设备兼容性
**风险**: 不同 Logitech 设备的 HID++ 实现细节可能不同。
**缓解**: 使用动态 Feature Discovery 而非硬编码 feature index。对于不支持 REPROG_CONTROLS_V4 的设备,graceful fallback -- 不 divert 任何按键,不影响 CGEventTap 路径。

### 3. 蓝牙 vs USB Receiver
**风险**: Unifying Receiver 和蓝牙连接的设备在 HID 层的表现不同。
**缓解**: Unifying Receiver 作为一个复合 HID 设备出现,需要正确处理 device index。初版优先支持蓝牙直连(更简单),USB Receiver 作为后续增强。

### 4. macOS 版本兼容
**风险**: IOKit API 在不同 macOS 版本上的行为。
**缓解**: IOHIDManager 从 macOS 10.5 就存在,API 稳定。项目最低支持 10.13,完全兼容。

### 5. 权限
**风险**: 访问 HID 设备可能需要额外权限。
**缓解**: Mos 已经要求 Accessibility 权限。IOHIDManager 访问 HID 设备在 macOS 上通常不需要额外权限(除了某些 kext 级别的操作)。需要实际测试确认。
