# Toast 组件扩展设计

## 概述

将 Mos 项目中的 Toast 通知组件从单文件单 toast 架构演进为多 toast、可拖拽、可配置的产品级模块，并确保可独立解耦开源。

## 目标

1. 状态栏入口图标语义优化
2. Debug 面板全面重设计（面向用户的产品功能）
3. 支持多 toast 同时展示，堆叠方向自适应
4. 支持 toast 位置拖拽 + 独立持久化
5. 模块可独立插拔解耦，为独立开源做准备

## 架构方案：模块目录化

将现有单文件 `Toast.swift`（666 行）拆分为 Toast/ 目录下多个内聚文件，与项目现有模式（ScrollCore/、ButtonCore/）一致。对外仍只暴露 `Toast` struct 的 public 方法。

### 文件结构

```
Mos/Components/Toast/
├── Toast.swift            (~80 行)   公开 API 入口
├── ToastManager.swift     (~250 行)  多 toast 生命周期管理
├── ToastWindow.swift      (~200 行)  容器窗口 + 拖拽手势
├── ToastContentView.swift (~200 行)  视觉渲染层
├── ToastStorage.swift     (~60 行)   独立 UserDefaults 持久化
├── ToastPanel.swift       (~400 行)  产品级 Debug 面板
└── README.md                         组件文档
```

### 依赖关系

```
Toast (公开 API) → ToastManager → ToastWindow → ToastContentView
                                ↘ ToastStorage
Toast.showTestPanel() → ToastPanel → Toast (通过公开 API 测试)
```

所有内部类使用 `internal` 访问级别（同 module 内可见），对外只暴露 `Toast` struct 的 public 方法。

## §1 公开 API

```swift
public struct Toast {
    /// 显示通知
    static func show(
        _ message: String,
        style: Toast.Style = .info,
        duration: TimeInterval = 2.5,
        icon: NSImage? = nil
    )

    /// 关闭所有通知
    static func dismissAll()

    /// 打开 Debug 面板
    static func showTestPanel()

    /// 返回可直接加入菜单的 MenuItem
    static func debugMenuItem() -> NSMenuItem

    enum Style { case info, success, warning, error }
}
```

**变更说明：**
- `show()` — 签名不变，完全向后兼容
- `dismissAll()` — 新增，支持一键清除所有 toast
- `debugMenuItem()` — 新增，使用方一行 `menu.addItem(Toast.debugMenuItem())` 接入
- `showTestPanel()` — 保留，内部重写

## §2 多 Toast 管理（ToastManager）

### 容器窗口策略

采用**单容器窗口**方案：一个透明 NSPanel 作为容器，所有 ToastContentView 作为其子视图排列。

**选择理由：** 多独立 NSPanel 方案在拖拽时需要 N 个窗口同步 setFrame，高频 mouseDragged 下存在掉帧风险（尤其 macOS 10.13 + 旧硬件）。容器窗口方案从根本上消除此问题——拖拽永远只移动 1 个窗口。

**降级方案：** 如果实测容器窗口仍有性能问题，回退到"拖拽只移动被抓取的单个 toast，松手后其他 toast 动画归位"的简化方案。

### 堆叠算法

- **锚点**：第一个 toast 出现在用户记忆的位置（或默认的屏幕上方 1/5 居中处）
- **方向判定**：锚点在屏幕可见区域上半部 → 后续向下偏移；下半部 → 向上偏移
- **偏移量**：每个新 toast 在堆叠方向上偏移 `toastHeight + spacing(8px)`
- **溢出淘汰**：超出 maxCount 时，最旧的 toast 立即淡出消失
- **回收重排**：中间的 toast 消失后，后续 toast 动画滑动填补空位

### 多屏支持

根据鼠标当前位置自动选择目标屏幕（沿用现有逻辑）。

### 去重与防竞态

- 去重：同一消息在 0.5 秒内不重复显示（沿用现有逻辑）
- 防竞态：代际计数器，避免旧淡出 completion 影响新 toast（沿用现有逻辑）

## §3 拖拽交互（ToastWindow）

### 容器窗口设计

- `NSPanel` 子类，透明背景，`level: .floating`
- `.nonactivatingPanel` + `.fullScreenAuxiliary` 集合行为
- 窗口大小动态计算：`maxCount × (toastHeight + spacing)` 为最大尺寸

### 事件穿透

重写 `hitTest(_:)` 方法：在 ToastContentView 区域内返回 self（响应拖拽），在透明区域返回 nil（事件穿透到下层窗口）。macOS 10.13 完全支持。

### 拖拽行为

- 拖拽任意一个 toast 内容区域时，整个容器窗口跟随移动（所有 toast 保持堆叠间距）
- 松开后，新的锚点位置写入 ToastStorage
- 堆叠方向根据新位置实时重新计算
- 跨越屏幕中线时方向即时翻转，子视图动画重排

### 动画

- 淡入：250ms，easeOut（沿用）
- 淡出：300ms，easeIn（沿用）
- 回收重排滑动：200ms，easeInOut
- 方向翻转重排：250ms，easeInOut

## §4 独立持久化（ToastStorage）

```swift
// 独立 UserDefaults suite，不与应用的 Options/UserDefaults 混合
UserDefaults(suiteName: "com.caldis.toast")
```

| Key | Type | Default | 说明 |
|-----|------|---------|------|
| positionX | CGFloat? | nil (屏幕居中) | 锚点 X 坐标 |
| positionY | CGFloat? | nil (上 1/5) | 锚点 Y 坐标 |
| maxCount | Int | 4 | 最大同时显示数 |

- `nil` 值表示使用默认位置（屏幕可见区域水平居中，垂直上 1/5 处）
- Debug 面板中的 Reset 按钮清除 positionX/positionY 回到默认

## §5 产品级 Debug 面板（ToastPanel）

### 设计原则

Debug 面板是**面向用户的产品功能**，不只是开发调试工具。视觉品质要求与应用其他界面一致。

### 视觉风格

- 整体使用 `NSVisualEffectView` 毛玻璃背景
- Header 与内容融为一体，不做分隔线，统一材质
- 深色 HUD 风格，与 toast 本身的视觉风格统一
- 窗口尺寸约 420×520

### 三段式布局

**Configuration（全局配置）：**
- Max Simultaneous：滑块控件，范围 1-8，默认 4，实时写入 ToastStorage
- Position：显示当前状态（Saved/Default），Reset 按钮清除记忆位置

**Send Toast（自定义发送）：**
- Message：文本输入框
- Style：按钮组（非下拉），选中态高亮，颜色+图标直观表达（Info / Success / Warning / Error）
- Duration：滑块 0.5-10s，默认 2.5s
- Custom Icon：复选框
- Show Toast：主操作按钮

**Quick Tests（一键场景测试）：**
2×3 网格布局：

| 测试 | 说明 |
|------|------|
| All Styles | 逐个显示 4 种样式 |
| Stack Test | 连续发送至 maxCount，验证堆叠 |
| Overflow | 超出上限，验证淘汰 |
| Dedup | 连续发送相同消息，验证去重 |
| Long Text | 超长文本，验证截断 |
| Dismiss All | 一键清除所有 toast |

## §6 状态栏图标

**变更：** `bubble.left.fill` → `text.bubble`

- macOS 11+：使用 `text.bubble` SF Symbol，语义从"聊天"改为"通知/消息"
- macOS 10.13-10.15：保持现有 imageLiteral fallback

**集成方式变化：**
```swift
// 之前 (StatusItemManager 中硬编码)
Utils.addMenuItem(to: menu, title: " Toast Test",
                 icon: #imageLiteral(resourceName: "SF.bubble.left.fill"),
                 action: #selector(toastTestClick))

// 之后 (一行接入)
menu.addItem(Toast.debugMenuItem())
```

## §7 兼容性

所有实现必须兼容 macOS 10.13+：
- SF Symbols（macOS 11+）有 imageLiteral fallback
- NSVisualEffectView：10.14+ 用 `.hudWindow` + `.vibrantDark`，10.13 用 `.dark`
- hitTest 重写：全版本可靠
- UserDefaults suiteName：全版本可靠
- NSAnimationContext：全版本可靠

## §8 模块解耦清单

确保 Toast 模块可独立插拔：
- [ ] 零外部依赖（不依赖 Options、Application、ScrollCore 等）
- [ ] 独立持久化（UserDefaults suite，不混用应用 UserDefaults）
- [ ] 公开 API 完整（show / dismissAll / showTestPanel / debugMenuItem）
- [ ] StatusItemManager 中通过 `Toast.debugMenuItem()` 接入，无硬编码
- [ ] README.md 包含独立使用文档
- [ ] 所有字符串可本地化（使用 NSLocalizedString）
