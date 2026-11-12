# Logitech CID Registry 统一设计

**日期**: 2026-03-21
**状态**: Review Round 2 修订, 待用户审核

## 背景

Mos 的按键模块中，Logitech HID++ 按钮的 CID（Control ID）到人类可读名称的映射存在三处独立的硬编码，且覆盖范围有限（仅 8~12 个 CID）。未匹配的 CID 在 UI 中显示为不友好的 `Logi(2253)` 格式。

HID++ REPROG_CONTROLS_V4 协议不返回按钮名称字符串，只返回 CID + TaskID + Flags 数值。所有按钮名称必须由客户端维护静态映射表。Solaar 开源项目维护了一份约 310 条的权威 CID→名称映射表，来源于 Logitech 官方 controls.xml 及社区补充。

### 当前问题

1. **名称覆盖不足**: 硬编码仅 8~12 个 CID，未知按钮显示 `Logi(N)` 格式
2. **三处重复映射，互不引用**:
   - `MosInputEvent.swift` → `LogitechCIDMap.displayName()` (8 条 MosCode→名称)
   - `KeyCode.swift` → `mouseMap` 中 1000+ 条目 (8 条，与上重复)
   - `LogitechHIDDebugPanel.swift` → `HIDPPInfo.cidNames` (12 条 CID→名称)
3. **Logi 逻辑分散**: `LogitechCIDMap` 定义在通用模块 `MosInputEvent.swift` 中，污染非 Logi 代码
4. **命名有误**: 如 CID 0x00FD 在 Mos 中标记为 "Battery LED"，Solaar 中为 "DPI Switch"

## 设计方案

### 核心原则

- **Single Source of Truth**: 一张 CID 表，Debug 面板和按键面板共用
- **Logi 模块内聚**: 所有 Logi 专属逻辑内聚在 `Mos/LogitechHID/` 目录
- **数据溯源**: 注释中标注 Solaar 项目来源引用，便于后续同步

### 1. 新建 `LogitechCIDRegistry.swift`

**位置**: `Mos/LogitechHID/LogitechCIDRegistry.swift`

**职责**: CID 信息的唯一数据源，整合名称查询和 MosCode 映射。

```swift
/// Logitech HID++ Control ID (CID) 注册表
///
/// 数据来源: Solaar 项目 (GPL-2.0)
/// https://github.com/pwr-Solaar/Solaar
/// 文件: lib/logitech_receiver/special_keys.py
/// 原始数据基于 Logitech 官方 controls.xml, 由 Solaar 社区维护和补充
struct LogitechCIDRegistry {

    // MARK: - CID 名称表 (来自 Solaar special_keys.py CONTROL 字典)

    /// CID → 人类可读名称
    /// 名称已格式化: 下划线替换为空格, 保持 Solaar 原始大小写
    private static let cidNames: [UInt16: String] = [
        0x0001: "Volume Up old",
        0x0002: "Volume Down old",
        0x0003: "Mute",
        // ... 完整约 310 条，从 Solaar special_keys.py 移植
        // 包含 G1~G32 (0x1001~0x1020), M1~M8 (0x1101~0x1108), MR (0x1200)
    ]

    // MARK: - CID → MosCode 特殊映射 (Mos 自有逻辑)

    /// 为常见鼠标按钮保留固定 MosCode (1000~1007)
    /// 其余 CID 使用公式: 2000 + CID
    private static let cidToCode: [UInt16: UInt16] = [
        0x0050: 1003,  // Left Click (diverted)
        0x0051: 1004,  // Right Click (diverted)
        0x0052: 1005,  // Middle Click (diverted)
        0x0053: 1006,  // Back (diverted)
        0x0056: 1007,  // Forward (diverted)
        0x00C3: 1000,  // Mouse Gesture Button
        0x00C4: 1001,  // Smart Shift
        0x00D7: 1002,  // Virtual Gesture Button
    ]

    // MARK: - 名称查询

    /// 通过 CID 查询名称 (Debug 面板 + 按键面板共用)
    /// 未知 CID 返回 "Unknown(0xXXXX)" 格式
    static func name(forCID cid: UInt16) -> String {
        return cidNames[cid] ?? String(format: "Unknown(0x%04X)", cid)
    }

    /// 通过 MosCode 查询名称 (按键面板使用)
    /// 先反查 CID, 再查名称
    static func name(forMosCode code: UInt16) -> String {
        guard let cid = toCID(code) else { return "Logi(\(code))" }
        return name(forCID: cid)
    }

    // MARK: - Code 转换

    // MARK: - 反向映射缓存 (预计算, 避免 O(n) 线性扫描)

    private static let codeToCID: [UInt16: UInt16] = {
        var reversed: [UInt16: UInt16] = [:]
        for (cid, code) in cidToCode { reversed[code] = cid }
        return reversed
    }()

    /// CID → MosCode
    /// 已知 CID 最大值约 0x1200, 加 2000 后 ≈ 6608, 远小于 UInt16.max (65535)
    /// 因此溢出分支在实践中不可达, 仅作防御性保留
    static func toMosCode(_ cid: UInt16) -> UInt16 {
        if let known = cidToCode[cid] { return known }
        let mapped = UInt32(2000) + UInt32(cid)
        return mapped <= UInt32(UInt16.max) ? UInt16(mapped) : UInt16(cid & 0x0FFF) + 2000
    }

    /// MosCode → CID (反向映射, O(1) 查表)
    static func toCID(_ mosCode: UInt16) -> UInt16? {
        if let cid = codeToCID[mosCode] { return cid }
        if mosCode >= 2000 { return mosCode - 2000 }
        return nil
    }

    /// 判断按钮码是否属于 Logitech HID++ 专有范围
    static func isLogitechCode(_ code: UInt16) -> Bool {
        return code >= 1000
    }
}
```

### 2. 迁移 `LogitechCIDMap`

- **删除** `MosInputEvent.swift` 中的整个 `LogitechCIDMap` 结构体
- 所有引用 `LogitechCIDMap.xxx` 的调用点改为 `LogitechCIDRegistry.xxx`
- 接口签名保持兼容 (`toMosCode`, `toCID`, `isLogitechCode`)，仅类型名变更

### 3. 清理重复映射

| 操作 | 文件 | 详情 |
|------|------|------|
| **删除** | `LogitechHIDDebugPanel.swift` | 删除 `HIDPPInfo.cidNames` 字典，改为调用 `LogitechCIDRegistry.name(forCID:)` |
| **删除** | `MosInputEvent.swift` | 删除整个 `LogitechCIDMap` 结构体 |
| **删除** | `KeyCode.swift` → `mouseMap` | 删除 1000+ 的 Logi 条目 (1000~1007 共 8 条) |

### 4. 更新消费者代码

以下为所有引用点的完整清单 (基于全局搜索确认, 无遗漏):

#### 4.1 `MosInputEvent.swift` (3 处)

```swift
// displayComponents - 改前:
if LogitechCIDMap.isLogitechCode(code) {
    components.append(LogitechCIDMap.displayName(forCode: code))
    components.append("[Logi]")
}
// 改后:
if LogitechCIDRegistry.isLogitechCode(code) {
    components.append(LogitechCIDRegistry.name(forMosCode: code))
    components.append("[Logi]")
}

// isRecordable - 改前:
if LogitechCIDMap.isLogitechCode(code) { return true }
// 改后:
if LogitechCIDRegistry.isLogitechCode(code) { return true }
```

#### 4.2 `BrandTag.swift` (1 处)

```swift
// isLogiCode - 改前:
return LogitechCIDMap.isLogitechCode(code)
// 改后:
return LogitechCIDRegistry.isLogitechCode(code)
```

#### 4.3 `ButtonTableCellView.swift` (1 处)

```swift
// 改前:
let isLogiTrigger = binding.triggerEvent.type == .mouse && LogitechCIDMap.isLogitechCode(binding.triggerEvent.code)
// 改后:
let isLogiTrigger = binding.triggerEvent.type == .mouse && LogitechCIDRegistry.isLogitechCode(binding.triggerEvent.code)
```

#### 4.4 `LogitechDeviceSession.swift` (7 处)

LogitechCIDMap 引用 (2 处):
```swift
// 改前:
let mosCode = LogitechCIDMap.toMosCode(c.cid)
code: LogitechCIDMap.toMosCode(cid),
// 改后:
let mosCode = LogitechCIDRegistry.toMosCode(c.cid)
code: LogitechCIDRegistry.toMosCode(cid),
```

HIDPPInfo.cidNames 引用 (5 处, 行 407/443/453/872/877):
```swift
// 改前:
let cidName = HIDPPInfo.cidNames[cid] ?? "?"
// 改后:
let cidName = LogitechCIDRegistry.name(forCID: cid)
```

#### 4.5 `LogitechHIDDebugPanel.swift` (1 处)

```swift
// refreshControls() - 改前:
let name = HIDPPInfo.cidNames[c.cid] ?? "Unknown"
// 改后:
let name = LogitechCIDRegistry.name(forCID: c.cid)
```

#### 4.6 `RecordedEvent.swift` → `ScrollHotkey.displayName` (需修改)

ScrollHotkey 除了 `init(from: CGEvent)` 外, 还有 `init(from: MosInputEvent)` (line 232),
且 KeyRecorder 录制时会接收 Logi HID++ 按钮事件。因此 ScrollHotkey 可以持有 Logi 码 (>= 1000)。

```swift
// 改前:
var displayName: String {
    switch type {
    case .keyboard: return KeyCode.keyMap[code] ?? "Key \(code)"
    case .mouse:    return KeyCode.mouseMap[code] ?? "🖱\(code)"
    }
}
// 改后:
var displayName: String {
    switch type {
    case .keyboard: return KeyCode.keyMap[code] ?? "Key \(code)"
    case .mouse:
        if LogitechCIDRegistry.isLogitechCode(code) {
            return LogitechCIDRegistry.name(forMosCode: code)
        }
        return KeyCode.mouseMap[code] ?? "🖱\(code)"
    }
}
```

#### 4.7 `PreferencesScrollingViewController.swift` → `getBaseDisplayName` (需修改)

```swift
// 改前:
case .mouse:
    return KeyCode.mouseMap[hotkey.code] ?? "🖱\(hotkey.code)"
// 改后:
case .mouse:
    if LogitechCIDRegistry.isLogitechCode(hotkey.code) {
        return LogitechCIDRegistry.name(forMosCode: hotkey.code)
    }
    return KeyCode.mouseMap[hotkey.code] ?? "🖱\(hotkey.code)"
```

#### 4.8 `CGEvent+Extensions.swift` (无需修改)

CGEventTap 产生的 mouseCode 范围为 0~31, 不会出现 Logi 码, 不受 mouseMap 清理影响。

#### 4.9 `tools/hidpp/full-test.swift` (不在 scope 内)

该文件是独立脚本 (`swift tools/hidpp/full-test.swift` 直接运行), 不属于 app target,
无法编译引用 app 源码中的 `LogitechCIDRegistry`。保留其本地 cidNames 副本。
后续如需统一, 需要将 Registry 提取为 shared Swift module 或将工具纳入 Xcode build target。

### 5. Solaar 名称格式化策略

- 在 `cidNames` 字典中**直接存储格式化后的名称**（编译期确定）
- 格式化规则: 下划线 → 空格, 保持原始大小写
- 示例: `"DPI_Switch"` → `"DPI Switch"`, `"Mouse_Gesture_Button"` → `"Mouse Gesture Button"`
- 对于双下划线表示的 `/` 分隔: `"Screen_Capture__Print_Screen"` → `"Screen Capture / Print Screen"`

### 6. 命名修正 (以 Solaar 为准)

| CID | Mos 当前 | Solaar (采用) |
|-----|---------|--------------|
| 0x00FD | Battery LED | DPI Switch |
| 0x00D7 | DPI Change | Virtual Gesture Button |
| 0x00D0 | Top Button | MultiPlatform Gesture Button |
| 0x00C3 | Gesture Button | Mouse Gesture Button |
| 0x00C4 | SmartShift | Smart Shift |
| 0x00E8 | Thumb Wheel Up | Volume Down |
| 0x00E9 | Thumb Wheel Down | Volume Up |

## 已持久化 displayComponents 的处理

`RecordedEvent.displayComponents` 是在录制时生成并通过 Codable 序列化到 UserDefaults 的。
现有绑定中的旧名称 (如 "Gesture", "SmartShift") 会保留, 新录制的绑定会使用 Solaar 的名称
(如 "Mouse Gesture Button", "Smart Shift")。

**处理策略**: 接受临时不一致, 不做数据迁移。
- 绑定的功能由 `code` (MosCode) 决定, 名称仅影响 UI 展示, 不影响功能
- 用户重新录制绑定时, displayComponents 会自然更新为新名称
- 数据迁移的复杂度和风险与收益不成正比

## 改动范围汇总

| 文件 | 操作 |
|------|------|
| `Mos/LogitechHID/LogitechCIDRegistry.swift` | **新建** - CID 注册表 (唯一数据源) |
| `Mos/InputEvent/MosInputEvent.swift` | **改** - 删除 LogitechCIDMap, 引用改为 LogitechCIDRegistry |
| `Mos/LogitechHID/LogitechHIDDebugPanel.swift` | **改** - 删除 HIDPPInfo.cidNames, 改用 Registry |
| `Mos/LogitechHID/LogitechDeviceSession.swift` | **改** - LogitechCIDMap → LogitechCIDRegistry (2处), HIDPPInfo.cidNames → Registry (5处) |
| `Mos/Keys/KeyCode.swift` | **改** - 删除 mouseMap 中 1000+ 条目 (8条) |
| `Mos/Components/BrandTag.swift` | **改** - isLogiCode 改为引用 Registry |
| `Mos/Windows/PreferencesWindow/ButtonsView/ButtonTableCellView.swift` | **改** - LogitechCIDMap → LogitechCIDRegistry |

| `Mos/Windows/PreferencesWindow/ButtonsView/RecordedEvent.swift` | **改** - ScrollHotkey.displayName 增加 Logi 码 fallback |
| `Mos/Windows/PreferencesWindow/ScrollingView/PreferencesScrollingViewController.swift` | **改** - getBaseDisplayName 增加 Logi 码 fallback |

**不涉及** (经确认无影响):
- `MosInputProcessor.swift` (无 LogitechCIDMap/HIDPPInfo.cidNames 引用)
- `CGEvent+Extensions.swift` (mouseCode 范围 0~31, 不涉及 Logi 码)
- `tools/hidpp/full-test.swift` (独立脚本, 不属于 app target, 无法引用 app 源码)

## 不变的部分

- `BrandTag` 的渲染逻辑、品牌标签视觉样式
- `KeyPreview` 的 `[Logi]` 标记识别和渲染
- `MosInputEvent` 的整体结构和 `displayComponents` 的输出格式
- `RecordedEvent` 的序列化格式和 `ButtonBinding` 的存储结构
- `KeyRecorder` 的录制流程
- `HIDPPInfo.featureNames` 及其他非 CID 字典保留在 `LogitechHIDDebugPanel.swift`

## 来源引用与许可

CID→名称映射数据的原始来源为 Logitech 官方 controls.xml。
Solaar 项目 (GPL-2.0) 将其整理为 Python 字典格式并持续维护。

**许可分析**:
- CID 编号是 Logitech 硬件协议的事实性标识符, 不构成版权保护对象
- 按钮功能名称 (如 "Left Button", "Smart Shift") 是对硬件功能的描述性标签,
  属于 Logitech 产品定义的事实性数据, 非 Solaar 的创意表达
- Solaar 的贡献在于整理和补充这些映射, 我们在注释中明确标注来源以示致谢
- 我们不复制 Solaar 的任何代码逻辑、算法或程序结构, 仅移植事实性的 CID→名称对照关系
- Mos 项目 (CC BY-NC 4.0) 与 GPL-2.0 在许可条款上存在差异,
  但对于事实性数据的引用不触发 GPL 的 copyleft 传播条款

**最终决定**: 由项目维护者 (Caldis) 确认此许可分析是否可接受。

文件头部注释需包含:
```
// Logitech HID++ Control ID (CID) 名称注册表
//
// 数据来源: Solaar 项目
// https://github.com/pwr-Solaar/Solaar
// 文件: lib/logitech_receiver/special_keys.py
// Commit: b9e0cf823543ba1dadc8eb188083b5c8db6280b0
// 原始数据基于 Logitech 官方 controls.xml, 由 Solaar 社区维护和补充
// Solaar 项目采用 GPL-2.0 许可证
```
