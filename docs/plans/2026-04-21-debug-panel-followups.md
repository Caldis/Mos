# HID++ DEBUG 面板遗留优化 · Follow-ups

## 背景

本次 (2026-04-21) 围绕"Logi 按键冲突指示器"完成了:
- `LogitechConflictDetector` + UI branch 图标 + hover popover(按键面板)
- `setControlReporting` 不再污染 `reportingFlags`(方案 B)
- self-remap (targetCID == cid) 排除
- DEBUG 面板 `cStatus` 列区分 **3rd-DVRT / REMAP / Mos-DVRT / 绿点**
- DEBUG 面板 `DEVICES` 列表新增接口角色 (`mouse/kbd/vendor/...`) + `HID++` 橘色徽标
- 修复 `LogitechHIDDebugPanel` 两处字符串比较 bug:
  - `isReceiver` 用 `connectionMode == .receiver`(原来比 "receiver" 字面量,实际返回 "Receiver (Unifying/Bolt)")
  - `refreshSidebar` filter 用 `connectionMode != .unsupported`(原来比 "unsupported" 字面量,实际返回 "Unsupported")

## 遗留问题

### FU-1 · 主行文本被截断 (P1)

**现象**:DEVICES 侧栏里,receiver 行期望显示

```
[R] USB Receiver  vendor · HID++  ●
```

实际只显示 `[R] USB`,"Receiver" 及之后全被 NSTextField `.byTruncatingTail` 裁掉,连 `…` 都没画(字体宽度/换行策略的表现差异)。

**根因**:侧栏宽度 `L.sidebarWidth` 有限,主行文本过长装不下。

**推荐方案 A**(最省心):简化文案,砍掉 "USB Receiver" 这个冗余产品名。所有 Bolt / Unifying receiver 在 macOS 报的都是这个名字,对用户零区分价值,真正区分靠 role + HID++ 角标。

示例:
```
[R]  vendor · HID++  ●
[M]  mouse           ●
[M]  kbd             ●
```

**替代方案**:
- B. 加宽 `L.sidebarWidth`。
- C. 双行 row(row 高度 36,主行产品名,副行 role/HID++)。

改动点:`LogitechHIDDebugPanel.swift:1449-1452` 的 `NSMutableAttributedString` 初始 string。

### FU-2 · Slot 点击无蓝色高亮 (P2)

**现象**:outlineView 展开 receiver 后,点击 `Slot 3` 文字变白(说明 selection 逻辑生效),但 **没有 sourceList 风格的蓝色圆角背景**。

**根因推测**:
- `outline.backgroundColor = .clear`(`LogitechHIDDebugPanel.swift:416`)
- 外层 scrollView + visual effect / vibrancy 可能吞掉了 sourceList 自绘的 selection layer。

**候选修法**:
- A. `outline.selectionHighlightStyle = .regular`(改用系统默认反向高亮,不依赖 sourceList 图层)。
- B. 给 `outline.backgroundColor` 设非 clear 值(例如 `.windowBackgroundColor.withAlphaComponent(0.01)`),让 sourceList 图层有基底。
- C. 自定义 `NSTableRowView` 重写 `drawSelection(in:)`。

简单起见推荐 A。

改动点:`LogitechHIDDebugPanel.swift:417` `outline.selectionHighlightStyle`。

### FU-3 · Bolt 按键响应结果不一致 (P3)

**现象**:用户按同一个按键多次,Mos DEBUG 面板的 log 里响应时而完整时而有丢失 / 错位。

**已有缓解**:
- error 推进:`handleInputReport` 识别 REPROG_V4 function 1/2 的 HID++ 2.0 error 响应,推进对应 query index。
- timeout 兜底:`controlInfoQueryTimer` / `reportingQueryTimer`,1s 无响应自动跳过(`LogitechDeviceSession.swift` 的 `reprogQueryTimeout`)。
- teardown 清理 timer。

**未解决**:底层 Bolt wireless link 抖动 / HID++ 1.0 `ConnectFailed` 瞬断(日志里 `subId=0x09 err=ConnectFailed`)。这超出 Mos 软件可控范围,属于协议层 / receiver 固件层问题。

**下一步若要深挖**:需要用户描述**具体**的"不一致"表现,例如:
- button event 时灵时不灵?
- 同一 CID 的 GetControlReporting 多次查到的 flags 值不同?
- Controls 列表里某个控件反复变色?

目前无 clear actionable。等复现信息再说。

## 非 DEBUG 面板的相关遗留

无。按键面板的 branch 图标 / hover popover 工作正常。

## 建议优先级

| ID | 优先级 | 工作量 | 用户体感影响 |
|---|---|---|---|
| FU-1 | P1 | 10 分钟 | 中(主功能可用但观感差)|
| FU-2 | P2 | 10 分钟 | 低(只是 debug 工具的视觉)|
| FU-3 | P3 | — | 低(已有兜底,极端情况少)|
