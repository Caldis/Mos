# Logitech 按键冲突提示器 — 设计

## 背景

Mos 的 Logi HID++ 按键绑定可能与 Logitech Options+ 同时劫持同一按键。`LogitechDivertPlanner` 已经保证 Mos 不会无差别扫除第三方 divert,但当用户绑定的按键正好被 Options+ 占用时,按键依然会"双方打架"。需要在 UI 上**提前告知用户**,让用户做决策。

## 目标

- 在 `偏好设置 > 按键` 面板每一行的虚线分隔符中部,当该行绑定的 Logi 按键当前已被第三方(如 Options+)divert / remap 时,叠加一个 branch 图标。
- hover 图标时弹出 NSPopover,中文说明"该按键可能被其他应用接管,双方可能冲突"。
- 非 Logi 按键行 / 未检测到冲突 / 未查询完成 → 不显示图标(沉默)。
- 设备连接/断开、reporting 查询完成 → 自动刷新图标状态。

## 非目标

- 不自动放弃绑定、不修改 Planner 行为。用户始终拥有最终决策权。
- 不区分"是谁"在 divert(前一轮已经明确)——启发式只输出"是/否有第三方占用"。
- 不新增任何 HID++ 通信路径 —— 完全复用 init 阶段已有的 `GetControlReporting` 结果。

## 数据与判定(纯函数)

### 信号来源

- **每个 `ControlInfo`**:`reportingFlags`(bit0=tmpDivert, bit1=persistDivert, bit2=tmpRemap, bit3=persistRemap)+ `reportingQueried` 标志(查询是否完成)+ `targetCID`(remap 目标)。
- **`divertedCIDs`**:Mos 本进程当前 set 为 tmpDivert 的 CID 集合(已存在于 `LogitechDeviceSession`)。

### 判定规则

```
conflict(cid) =
    reportingQueried == true
    && (
         (reportingFlags & 0b0010) != 0       // persistDivert: Mos 从不写
      || (reportingFlags & 0b1100) != 0       // tmpRemap / persistRemap: Mos 从不写
      || ((reportingFlags & 0b0001) != 0      // tmpDivert 且 CID 不在 Mos 的集合
          && !divertedCIDs.contains(cid))
    )
```

Mos 运行时会把自己的绑定 set 为 tmpDivert → `reportingFlags.bit0 = 1` 但 CID ∈ `divertedCIDs` → 不算冲突。第三方做的 persist/remap/其它 CID 的 tmpDivert → 命中冲突。

## 模块划分

### 新增:`Mos/LogitechHID/LogitechConflictDetector.swift`

纯函数 / 轻量 struct。

```swift
struct LogitechConflictDetector {
    enum Status { case unknown, clear, conflict }

    static func status(
        reportingFlags: UInt8,
        reportingQueried: Bool,
        cid: UInt16,
        mosDivertedCIDs: Set<UInt16>
    ) -> Status
}
```

- `unknown`:`reportingQueried == false`(设备未连接 / init 未完成 / 非 divertable)→ UI 不显示图标。
- `clear` / `conflict`:按上面的规则输出。

可单测。

### 新增:`LogitechHIDManager.conflictStatus(forMosCode:) -> Status`

提供给 UI 层的唯一查询入口。实现:

1. 把 MosCode → CID(`LogitechCIDRegistry.toCID`)。
2. 遍历 `sessions`,找到持有该 CID 的 session(同一设备同时只会由一个 session 持有 HID++ 候选接口)。
3. 找到 `ControlInfo` → 调 `LogitechConflictDetector.status(...)`。
4. 所有找不到的情况返回 `.unknown`。

### 新增通知:`LogitechHIDManager.reportingQueryDidComplete`

在 `LogitechDeviceSession.handleGetControlReportingResponse` 的"查询完成"分支(`LogitechDeviceSession.swift:1420`)中 post,通知 UI 刷新。现有的 `sessionChangedNotification` 保留,处理设备连接/断开。

### 修改:`ButtonTableCellView`

**虚线层结构**保持 `CAShapeLayer` 不变,新增:

- 一个 `NSImageView`(branch 图标)作为 `contentView` 的子视图,绝对定位到虚线中点。
- `NSTrackingArea`(`mouseEnteredAndExited + activeInKeyWindow`)附加到该 ImageView。
- 一个 `NSPopover`(content 为简单 NSViewController + NSTextField,本地化文案)。

**时机**:

- `configure(with:)` 末尾:如按键为 Logi → 调 `LogitechHIDManager.shared.conflictStatus(forMosCode:)`,据此显示/隐藏图标。
- `viewWillAppear` 时订阅通知、`viewWillDisappear` 时取消订阅(可通过弱引用 observer)。
- 收到 `sessionChangedNotification` 或 `reportingQueryDidComplete` → 重新 resolve 状态。

**图标资源**:

- macOS 11+:`NSImage(systemSymbolName: "arrow.triangle.branch", accessibilityDescription: ...)`,`contentTintColor` 设为警告色(可用 `NSColor.systemOrange` 或已有的 `mainBlue`)。
- macOS 10.13~10.15 fallback:bundled PNG 资源 `Mos/Assets.xcassets/Preferences/ConflictBranch.imageset/`(与现有 `Preferences/` 资产并列)。若资产缺失则整行不显示图标(不影响核心功能)。

**虚线位置**:现有 `setupDashedLine` 在 `startX..endX` 中绘制。branch 图标居中于 `(startX+endX)/2`,图标周围可预留 6~8pt "间隙"(把虚线路径拆成 `start→gapStart` 和 `gapEnd→end` 两段),避免图标压在虚线上。

### 本地化

`Localizable.xcstrings` 新增两 key:

- `button_conflict_title` → 中文:"按键可能被其他应用接管";英文:"Button may be captured by another app"
- `button_conflict_detail` → 中文:"该按键当前已被其他应用(例如 Logitech Options+)自定义,两个应用同时劫持同一按键可能无法按预期工作。建议在该应用中释放该按键,或退出该应用。";英文版同义。

## 文件级改动清单

| 动作 | 文件 | 内容 |
|---|---|---|
| 新增 | `Mos/LogitechHID/LogitechConflictDetector.swift` | `Status` enum + `status(...)` 纯函数 |
| 修改 | `Mos/LogitechHID/LogitechHIDManager.swift` | 新增 `conflictStatus(forMosCode:)` + 新 `reportingQueryDidComplete` notification name |
| 修改 | `Mos/LogitechHID/LogitechDeviceSession.swift` | 在 reporting 查询完成后 post 新 notification;暴露 `control(for cid:) -> ControlInfo?` 读取接口(或复用现有 `debugDiscoveredControls`)|
| 修改 | `Mos/Windows/PreferencesWindow/ButtonsView/ButtonTableCellView.swift` | 新增 branch icon 子视图、tracking area、popover、通知订阅、在 `configure` / 通知回调时刷新可见性;修改 `setupDashedLine` 在图标处留 gap |
| 新增 | `Mos/Assets.xcassets/Preferences/ConflictBranch.imageset/` | 10.13~10.15 fallback 图标(template PNG) |
| 修改 | `Mos/Localizable.xcstrings` | 新增两 key |
| 新增 | `MosTests/LogitechConflictDetectorTests.swift` | 纯函数单测 |

## 测试计划

### 单测 (TDD 驱动)

`LogitechConflictDetectorTests`:

- `status_notQueried_returnsUnknown`
- `status_allZero_returnsClear`
- `status_persistDivertSet_returnsConflict`
- `status_tmpRemapSet_returnsConflict`
- `status_persistRemapSet_returnsConflict`
- `status_tmpDivert_cidInMosSet_returnsClear` — Mos 自己 divert 的不算冲突
- `status_tmpDivert_cidNotInMosSet_returnsConflict` — 第三方 tmpDivert
- `status_multipleBitsSet_returnsConflict`

### 手测

- 用 Logitech Options+ 给某按键分配手势 → 打开 Mos 按键面板 → 添加该按键的绑定 → 虚线中部应出现 branch → hover 出 popover。
- 退出 Options+ → 断开/重连设备触发 reporting 重查 → 图标消失。
- 切换到非 Logi 按键 → 图标不显示。

## 风险与取舍

1. **查询时效**:reporting 只在 init 时查一次。如果用户在 Mos 运行期间临时启动 Options+ 占用按键,不会再查 → 图标可能不更新。缓解:可后续加"打开按键面板时主动触发一次增量查询",但本版先不做(避免扩大范围)。
2. **Mos 自动刷新的边界**:`setControlReporting` 内部已经在本地更新 `reportingFlags.bit0`。所以运行时 Mos 自己的 divert 会体现在 `reportingFlags`,但判定依赖 `divertedCIDs` 抵消 → 判定正确。已经在单测覆盖。
3. **图标资源 / 布局**:branch 图标尺寸建议 12×12 pt,保证在窄行也不溢出。布局走 Auto Layout,避免与虚线绘制在布局变化时出现错位。
4. **10.13~10.15 用户**:没有 SF Symbol → 用 fallback 资产。如果懒得准备资产,可以先做 macOS 11+ only(加 `@available` gate,低版本安静失败)—— 与现有 `ShortcutManager` 风格一致。

## 分阶段实现建议

1. **Phase 1 — 纯函数 + 通知**:新增 `LogitechConflictDetector`,写单测;`LogitechHIDManager` 暴露 `conflictStatus(forMosCode:)` + `reportingQueryDidComplete`。不动 UI,TDD 先绿。
2. **Phase 2 — UI**:`ButtonTableCellView` 加 branch icon + hover popover;本地化;图标资产。
3. **Phase 3 — 可选扩展**:面板打开时主动重查(如果实测发现 init 查询不够实时),可以延后。

## 复用盘点

- HID++ 通信:零新增,完全用已有 `sendRequest/handleInputReport`。
- reporting 查询:已有 `startReportingQuery` + `handleGetControlReportingResponse`,只新加一行 `NotificationCenter.default.post` 即可。
- 事件驱动 UI:沿用 `sessionChangedNotification` 风格。
- UI 基础设施:`NSPopover`、`NSTrackingArea`、`CAShapeLayer` 均为 AppKit 标准。项目里 Toast 模块也有 NSPopover-like 用法可参考。
- 本地化:沿用 `NSLocalizedString` + `Localizable.xcstrings`。

总改动约:新增 ~120 行、修改 ~60 行,单测 ~80 行。无架构变更。
