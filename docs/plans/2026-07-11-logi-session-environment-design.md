# P5-6: session↔manager↔center 循环耦合切断 — 设计

日期: 2026-07-11 · 来源: `2026-07-03-code-quality-audit-remediation.md` P5-1 前置项

## 问题

`LogiDeviceSession`（依赖链最底层）反向调用两个上层单例，共 17 个行为调用点：

| 上行目标 | 能力 | 调用点 |
|---|---|---|
| `LogiSessionManager.shared` | `deliveryMode(for:)` | applyUsage 投影/决策 ×2 |
| | `recordExternalClear(for:)` | 外部清除 divert / 对账丢失 ×2 |
| | `recomputeAndNotifyActivityState()` | 活动状态终点 ×6 |
| `LogiCenter.shared` | `registry.primeSession(self)` | 发现完成 prime ×1 |
| | `registry.aggregatedCacheIsEmpty` | 接管集合过滤 ×2 |
| | `isRecording` | 录制分流 ×3 |
| | `externalBridge`（toast/dispatch/hotkey） | 按键事件出口 ×3 处 |

后果：session 及未来从它拆出的组件（P5-1）无法脱离单例图实例化，测试只能靠
`*ForTests` 静态纯函数旁路。

注：session 对 `LogiSessionManager.sessionChangedNotification` 等**静态通知名常量**
的引用不属于行为耦合（仅命名空间），不在本项范围。

## 方案

新协议 `LogiSessionEnvironment`（`Mos/Logi/Core/LogiSessionEnvironment.swift`）
承载上表全部上行能力，session 构造时注入，不再出现任何 `.shared`：

```swift
internal protocol LogiSessionEnvironment: AnyObject {
    func deliveryMode(for key: LogiOwnershipKey) -> LogiButtonDeliveryMode
    @discardableResult
    func recordExternalClear(for key: LogiOwnershipKey) -> LogiButtonDeliveryMode
    func notifyActivityChanged()
    var isRecording: Bool { get }
    var bindingsExist: Bool { get }
    func primeBindings(for session: LogiDeviceSession)
    func showToast(_ message: String, severity: LogiToastSeverity)
    @discardableResult
    func dispatchButtonEvent(_ event: InputEvent) -> LogiDispatchResult
    func handleScrollHotkey(code: UInt16, phase: InputPhase)
}
```

生产实现 `LogiSessionEnvironmentAdapter`（同文件）：持 manager（unowned，
manager 持有注入它的 sessions，避免环）+ `UsageRegistry`（强引用，无回指）+
`bridgeProvider` 闭包（`[weak center]` 读当前 bridge，兜底 NoOp——bridge 可被
`installBridge` 热替换，必须读现值不可快照）。

组装点 = 组合根 `LogiCenter.init`（生产 + DEBUG harness 两个 init 都要）：
`manager.sessionEnvironment = adapter`。`LogiSessionManager.deviceConnected`
把它传给 `LogiDeviceSession(hidDevice:environment:)`；未注入即断言失败
（生产不可能：session 只在 `center.start() → manager.start()` 后出现）。

顺带：manager 自身的 `showDeliveryContentionToast` 也改走 environment，
清除 manager→center 的最后一处直接引用。切断后 Logi 内部依赖成单向：
center → manager → session → (协议)。

## 不改什么

- 通知名常量引用（见上）。
- `LogiCenter` 对 manager/registry 的正向持有（facade 本职）。
- 行为零变化：adapter 各方法与原单例调用逐一等价。

## 验证

- 新增 `MosTests/LogiSessionEnvironmentTests.swift`（pbxproj 四处注册）：
  - DEBUG harness 组装后 adapter 各能力路由正确（bindingsExist 随 registry 翻转、
    toast/dispatch 落到 FakeLogiExternalBridge、isRecording 跟随 manager 录制态）
  - `LogiCenter.shared` 初始化后 manager.sessionEnvironment 已注入
- 全量 MosTests + `scripts/qa/lint-logi-boundary.sh` + Debug 构建。
- 真机行为不变（divert/录制/toast 路径逐一等价），无需专门真机批。
