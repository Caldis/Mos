# STEP 03: ScrollActionPort 断环 + 线程断言 + 热路径配置快照 — 设计文档

- 日期: 2026-06-17
- 来源: docs/architecture.html (MOS-ARCH-2026-06) SHEET 06 ROADMAP STEP 03 (P1-2 / P2-1 / P1-3 第三步)
- 状态: 已获用户批准（按此设计执行）
- 基线: master @ 59ef650（已确认远端 31 个新提交全在 website/，未触碰 Mos/ Swift 代码）

## 背景与问题

架构评估 P1-2 指出核心三角循环：`ScrollCore → InputProcessor → ShortcutExecutor → ScrollCore`，三个单例互相直呼，无法独立实例化测试任何一角。实地核查（2026-06-17）确认依赖边：

- `ScrollCore.swift:76-77` → `InputProcessor.shared.markMosScrollActionSessionsUsedForScroll()` / `releaseMosScrollMouseSessionsIfPhysicalButtonsAreUp()`（热路径，主线程）
- `InputProcessor.swift:106-127` → `ShortcutExecutor.shared.resolveAction/execute`
- `ShortcutExecutor.swift:206` → `ScrollCore.shared.handleMosScrollAction(role:isDown:)` ← **闭合三角的回边，全 executor 仅此一处引用 ScrollCore**

P2-1：核心域（InputProcessor.activeBindings、ScrollCore 热键布尔、ButtonUtils 缓存）零断言零锁，当前拓扑安全（都在主 RunLoop）但属隐式约定。

P1-3 第三步：`ScrollPoster` 在 CVDisplayLink 线程读 `Options.shared.scroll.{smoothSimTrackpad,deadZone}` 与 `ScrollCore.shared.application`（`processing()` line 364；`stop()` line 211-216；`resolveSimTrackpadEnabled()` line 414-418），属跨线程读共享单例的潜在数据竞争。

## 目标

- **Part A**：引入 `ScrollActionPort` 协议，ShortcutExecutor 依赖协议而非 `ScrollCore` 具体类型，打破命名三角循环，使 ScrollCore 退出该 SCC、executor 的 mosScroll 派发可用 fake 端口独立测试。
- **Part B**：新增 `assertMainThread()` 辅助（DEBUG-only），固化核心域主线程约定。
- **Part C**：`ScrollPoster` 在主线程捕获 `{simTrackpadEnabled, deadZone}` 不可变快照，CVDisplayLink 线程只读快照，消除热路径跨线程读。

## 非目标（YAGNI / 范围纪律）

- **不切断 ShortcutExecutor ↔ InputProcessor**（`combinedModifierFlags`，executor.swift:388/488）。这是一条独立于"三角"的双向边：executor 合成事件时需要 InputProcessor 的虚拟修饰键状态，属真实领域查询、纯读、风险低，且不在用户批准的"三角断环"范围内。本次显式记录为已知残留耦合，留作后续同技术（`ModifierFlagsProviding` 端口）处理。切断后 executor 才完全无环；当前 STEP 03 只保证 ScrollCore 退出三角。
- 不改 ScrollPoster 既有 `stateLock` 锁模型，不动 `duration`（已是 update 时传入的快照值）。
- 不引入 `@MainActor`（最低 macOS 10.13 不可用）。
- 不改任何 UserDefaults key、动作标识符、持久化格式。

## 设计

### Part A：ScrollActionPort

新建 `Mos/Shortcut/ScrollActionPort.swift`（与消费者 ShortcutExecutor 同模块，依赖倒置）：

```swift
import Foundation

/// 滚动动作端口: ShortcutExecutor 通过此协议驱动 Mos 滚动热键 (dash/toggle/block) 状态,
/// 不直接依赖 ScrollCore, 从而打破 ScrollCore→InputProcessor→ShortcutExecutor→ScrollCore 三角循环。
/// ScrollCore 实现此协议并在启动期 (AppDelegate / 测试 setUp) 注入。
protocol ScrollActionPort: AnyObject {
    func handleMosScrollAction(role: ScrollRole, isDown: Bool)
}
```

ShortcutExecutor 改动：

```swift
/// Mos 滚动动作端口 (启动期注入 ScrollCore.shared)。weak: 端口是永生单例, 避免强引用环。
weak var scrollActionPort: ScrollActionPort?
```

line 206 由 `ScrollCore.shared.handleMosScrollAction(role:isDown:)` 改为 `scrollActionPort?.handleMosScrollAction(role:isDown:)`。executor 文件内不再出现 `ScrollCore`（line 297 仅注释，可保留）。

ScrollCore 改动：声明 `class ScrollCore: ScrollActionPort`（`handleMosScrollAction(role:isDown:)` 签名已匹配，无需改实现）。

接线（组合根，遵循 LogiCenter.installBridge 既有模式）：

- `AppDelegate.applicationDidFinishLaunching` 在 `LogiCenter.shared.installBridge(...)` 后加 `ShortcutExecutor.shared.scrollActionPort = ScrollCore.shared`（受 `shouldRunAppStartupSideEffects` 守卫，生产环境执行；XCTest 跳过）。
- `InputProcessorTests.setUp` 已触碰 `ScrollCore.shared`，加一行 `ShortcutExecutor.shared.scrollActionPort = ScrollCore.shared` 即可，对现有用例零破坏。

### Part B：assertMainThread

`Mos/Utils/Utils.swift` 顶层新增：

```swift
/// DEBUG 下断言当前在主线程; Release 零开销。
/// 核心事件域 (ScrollCore 热键状态 / InputProcessor 绑定表 / ButtonUtils 缓存) 约定主线程 only,
/// 当前所有 CGEventTap 与 IOHIDManager 回调均调度于主 RunLoop。此断言固化该隐式约定 (架构评估 P2-1)。
@inline(__always)
func assertMainThread(_ message: @autoclosure () -> String = "must run on main thread",
                      file: StaticString = #fileID, line: UInt = #line) {
    #if DEBUG
    assert(Thread.isMainThread, message(), file: file, line: line)
    #endif
}
```

插入点（仅外部进入的入口，内部 helper 经调用链覆盖；均不在 CVDisplayLink 线程）：

- `InputProcessor.process(_:)`
- `InputProcessor.clearActiveBindings()`
- `ScrollCore.handleScrollHotkey(code:isDown:)`（来自 Logi bridge，未来最可能挪离主线程，高价值）
- `ScrollCore.handleMosScrollAction(role:isDown:)`
- `ButtonUtils.invalidateCache()`

显式不插入 `ScrollPoster.processing` 及其调用链（CVDisplayLink 线程）。用 `assert`（DEBUG-only）而非 `precondition`，匹配"最低成本固化"。

### Part C：ScrollPoster 配置快照

`ScrollPoster` 新增（紧邻 `stateLock`）：

```swift
// 滚动配置快照: 主线程在 update 时捕获, CVDisplayLink 线程只读, 避免热路径跨线程读 Options/ScrollCore
private struct ConfigSnapshot {
    var simTrackpadEnabled: Bool
    var deadZone: Double
}
private var config = ConfigSnapshot(simTrackpadEnabled: false, deadZone: 1.0)
```

捕获函数（调用方持 `stateLock`）：

```swift
/// 主线程读取当前 (全局 / 例外应用) 配置存入快照。调用方须持有 stateLock。
private func captureConfigSnapshotLocked() {
    let simTrackpad: Bool
    if let application = ScrollCore.shared.application, !application.inherit {
        simTrackpad = application.scroll.smoothSimTrackpad
    } else {
        simTrackpad = Options.shared.scroll.smoothSimTrackpad
    }
    config = ConfigSnapshot(
        simTrackpadEnabled: simTrackpad,
        deadZone: Options.shared.scroll.deadZone
    )
}
```

在 `update()` 已持锁区间（line 59-60 之间）调用 `captureConfigSnapshotLocked()`。

替换 display-link 线程的跨线程读（全部已在 `stateLock` 临界区内，故读 `config` 一致）：

- `resolveSimTrackpadEnabled()` 整体改为 `return config.simTrackpadEnabled`（调用点 emitPhase line 325、post line 435 均在锁内）。
- `processing()` line 364 `let deadZone = Options.shared.scroll.deadZone` → `let deadZone = config.deadZone`（锁内）。
- `stop()` line 211-216 的 `enableSimTrackpad` 解析 → `let enableSimTrackpad = config.simTrackpadEnabled`（stop 持锁 line 208）。

正确性变化：`stop()`/`processing()` 不再读 live Options，而读最近一次 `update()`（手势开始/续滚）捕获的值。用户在亚秒级手势中途改偏好的极端情况下，该手势沿用开始时配置——比今天读半改状态的 live 值更一致，可接受。`update()` 始终在主线程、且 `ScrollCore.shared.application` 在 `update()` 前由 `scrollEventCallBack` 设好，故快照取到正确的应用上下文。

DEBUG 测试钩子：

```swift
#if DEBUG
func captureConfigSnapshotForTests() {
    os_unfair_lock_lock(&stateLock); defer { os_unfair_lock_unlock(&stateLock) }
    captureConfigSnapshotLocked()
}
var configSnapshotForTests: (simTrackpadEnabled: Bool, deadZone: Double) {
    os_unfair_lock_lock(&stateLock); defer { os_unfair_lock_unlock(&stateLock) }
    return (config.simTrackpadEnabled, config.deadZone)
}
#endif
```

## 测试计划

- **Part A**：扩展 `MosTests/InputProcessorTests.swift` setUp 接线端口；新增用例验证 executor 经 fake 端口驱动（证明脱钩）：
  - `MosTests/ScrollActionPortTests.swift`（显式引用模式，须登记 pbxproj）：定义 `FakeScrollActionPort` 记录 `(role,isDown)` 调用；`resolveAction("mosScrollDash")` → `execute(phase:.down/.up)` → 断言 fake 收到 `(.dash,true)`/`(.dash,false)`，且全程未触碰 ScrollCore。tearDown 还原 `scrollActionPort`。
  - 既有 `InputProcessorTests` mosScroll 用例（断言 `ScrollCore.shared.dashScroll` 等）在 setUp 接线后保持绿。
- **Part B**：无独立用例（DEBUG assert，测试在主线程运行天然满足）。回归确保不误触发。
- **Part C**：`MosTests/ScrollPosterConfigSnapshotTests.swift`（登记 pbxproj）：置 `Options.scroll.smoothSimTrackpad=true / deadZone=7.0`、`ScrollCore.shared.application=nil` → `captureConfigSnapshotForTests()` → 改 live Options 为 false/1.0 → 断言 `configSnapshotForTests == (true, 7.0)`，证明快照而非 live 读。tearDown 还原 Options 与 application。
- **既有回归**：`InputProcessorTests`、`ScrollCoreHotkeyTests`、`ButtonBindingTests`、`ScrollPosterStateTests`、`OptionsChangePropagationTests` 全绿。

## 验证

- 每个 Part 独立 `xcodebuild -scheme Debug -configuration Debug -destination 'platform=macOS' build`。
- `xcodebuild -scheme Debug -destination 'platform=macOS' test`（全量）。
- Part A 触及 executor/ScrollCore，不涉 `Mos/Integration/` 与 `Mos/Logi/`，无需 lint-logi-boundary；但 ScrollActionPort 引用 `ScrollRole`（Zone-A 白名单内），仍跑一次 `scripts/qa/lint-logi-boundary.sh` 确认未越界。
- 人工验证（不可自动化）：侧键绑定 Mos 滚动动作（dash/toggle/block）实际生效；simTrackpad 模式与非 simTrackpad 模式滚动收尾正常；改 deadZone 后滚动停止阈值符合预期。

## 风险与缓解

| 风险 | 缓解 |
| --- | --- |
| 端口未接线导致 mosScroll 静默失效 | 生产 AppDelegate 接线 + 测试 setUp 接线；新增 fake 端口用例锁定派发路径；端口 nil 时仅 mosScroll 动作 no-op（其余动作不受影响） |
| init 互相依赖死锁 | 接线在 AppDelegate/测试 setUp（非 init），executor.init 不触碰 ScrollCore，无单例 init 重入 |
| Part C 快照引入新竞争 | 不新增锁：所有 `config` 读写均已在既有 `stateLock` 内（update 写、processing/stop/emitPhase/post 读） |
| 中途改偏好的手势配置差一拍 | 手势内一致，亚秒级，记录为可接受语义变化 |
| 残留 IP↔SE 耦合被误认为已断 | 明确记录为非目标，executor 本次仅脱离 ScrollCore，未完全无环 |
