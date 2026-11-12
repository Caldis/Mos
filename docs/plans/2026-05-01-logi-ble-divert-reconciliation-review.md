# Review: Logi BLE Divert Reconciliation Plan

> 评审对象: `docs/plans/2026-05-01-logi-ble-divert-reconciliation.md`
> 评审基线: `Mos/Logi/Core/LogiDeviceSession.swift` 当前实现 (master, 2026-05-01)
> 评审视角: 协议正确性 / 状态机一致性 / 测试覆盖 / 命名与边界 / 真实设备行为可验证性

---

## TL;DR

整体修复方向 **正确且抓住了核心 bug**: `lastApplied` 被当作"设备状态的唯一真相"导致 BLE 设备 silent drop 后无法自愈。Plan 把它降级为"上次发出去的意图",再用 `GetControlReporting` 的真实回执做 reconcile,这条路径是对的,可以采纳。

但有 4 处需要 Codex 反馈/修订才能合入,按风险优先级:

1. **🔴 高 — Task 1 的 "BLE 自指 targetCID" 缺乏协议级证据**: Solaar (`_setCidReporting`) 在 BLE / Receiver 两种模式下都用 `remap=0`,Plan 提出的 `targetCID = self_cid` 修复**没有引用任何抓包、Solaar issue、Logi 官方文档**作为依据。如果实际 BLE silent drop 的根因是 reconcile 修复的"未重发",那么 self-target 这层改动可能是**多余甚至有害**(改变了对其它仍在线 BLE 设备的发包行为)。需要 Codex 补一份证据,否则建议先把 Task 1 退化为 `[cidH, cidL, flagsByte, 0x00, 0x00]`,只保留可测试包构造器的拆分价值。
2. **🟠 中 — Task 5 的 disconnect 重置未配套 reconnect 自动恢复**: `reprogInitComplete=false` 后,设备静默重连不会自动跑 reporting query,要等用户切回 Buttons 面板。binding 在中间的改动也都被 guard 静默丢弃,用户体感是"按键失灵且无提示"。Task 5 step 2 应在收到 `connected=true && devIdx==deviceIndex` 通知时主动 `rediscoverFeatures()` (或至少 `startReportingQuery()` 重启)。
3. **🟡 中 — `QueriedControlForTests` 命名作为生产函数参数是反模式**: `private static func reconciledAppliedSet(... queriedControls: [QueriedControlForTests])` 让 `*ForTests` 后缀渗入了生产 API。应拆为 `internal struct QueriedControlState { ... }` 在生产里使用,测试用 `internal static func reconciledAppliedSetForTests(...)` 包一层。
4. **🟡 中 — Task 4 的 reconcile 测试覆盖不完整**: 只验证了"丢失"和"未查询"两个分支,缺少 (a) `reportingFlags & 0x01 != 0` 时不应被移除 (Mos divert 仍生效),(b) 与 `divertedCIDs.subtract(lost)` 的一致性 (避免 conflict status 错为 .mosOwned/.coDivert)。

其余 5 处是 nit / 可改可不改,集中在最后。

---

## 1. 对 Plan 整体设计的肯定

下面这些设计判断是对的,Codex 不需要改:

- **架构选择保守**: 不引入"完整 HID++ 事务队列"是合理的范围控制 (Plan Notes 第一行已自我提示)。Mos 的体量不需要 TX/RX 严格 pairing,reconcile 已经足以兜住"丢回执"的场景。
- **`lastApplied` 重新定义为意图**: `lastApplied` 现在的语义是 "上一次 SetControlReporting 发出去的 CID 集合" (`/Mos/Logi/Core/LogiDeviceSession.swift:226`)。Plan Task 4 把它和 `discoveredControls[i].reportingFlags` 这个真实状态做差,这个二元区分非常正确,也是 fix 的核心。
- **Task 2 的 softwareId 区分**: 现状 `LogiDeviceSession.swift:1389` 在 `case 2` 不分 SW ID 直接路由,而设备物理按下/抬起会主动产生 `function=2, swID=0` 的 reporting state notification (Solaar `_getCidReporting` 文档行为)。当前代码会把这种 unsolicited notification 当成 query response,**确实**会错位推进 `reportingQueryIndex`,让某些 CID 的查询被跳过。Plan 的拆分 (`0x21 = query response`, `0x20 = notification`) 是协议级正确的。
- **Task 3 的 expected-CID guard**: 即使 SW ID 过滤掉了 notification,`reprogQueryTimeout=1.0s` (`LogiDeviceSession.swift:93`) 超时后 advance 到下一 CID,**迟到的 SW=0x01 响应仍会以 stale 身份到达**。Task 3 阻止 stale 响应推进 query index,是必要的二级防御。
- **Task 5 引入 `currentReceiverTargetIsConnected`**: 现状 `setControlReporting` 在 slot 已断时仍会发包,日志里出现 ConnectFailed 风暴 (Plan 的 supplied log 描述)。在 `applyUsage` / `refreshReportingState` / `temporarilyDivertAll` 三处加 guard 是对的。

---

## 2. 必须修的问题

### 2.1 🔴 Task 1: BLE 自指 targetCID 缺乏证据

**Plan 的主张**: BLE 直连用 `[cidH, cidL, flagsByte, cidH, cidL]`,Receiver 保持 `[cidH, cidL, flagsByte, 0x00, 0x00]`。

**反驳依据**:
- Solaar `lib/logitech_receiver/hidpp20.py` 的 `_setCidReporting` 在 BLE / Receiver 模式下统一使用 `struct.pack("!HBH", cid, bfield & 0xFF, remap)`,其中 `remap=0` 是默认值,只有显式 remap 时才填 target CID。Solaar 长期支持 LIFT / MX Anywhere 3S / MX Master 3S (BLE),没有针对 BLE 改 target。
- HID++ 协议约定: `remap=0` 意为 "保持现有 remap 不变";`remap=cid (self)` 意为 "remap 到自身,清除既有 remap"。Plan 没说明 BLE 设备需要 "清除 remap" 才能稳定 divert,这是一个**强假设**。
- Plan Task 6 step 1 的验证只能证明 reconcile 路径在 60-120s 后能恢复,**无法**单独证明 self-target 比 0x0000 更稳。两个变量耦合在一起改了。

**风险**:
- 如果 self-target 实际上在某些 BLE 设备 (LIFT, MX Master 3S BLE) 会触发"清掉用户在 Logi Options+ 里手动配的 remap"这种副作用,会造成回归。Mos 的同进程冲突检测 (`ConflictDetector.swift`) 此前一直预设"Mos 不动 remap target",这个边界一旦被打破,co-divert / foreign-divert 的语义会模糊。
- Plan 把这次提交描述为"BLE divert 修复",如果实际修好的是 reconcile 而非 self-target,日后排错会被这个改动误导。

**建议**:
- (A) 最简: **撤回 Task 1 的 BLE 分支差异**,两个模式都用 `[cidH, cidL, flagsByte, 0x00, 0x00]`。Task 1 仍保留把 setControlReporting 拆成可测试 packet builder 的工程价值,只是测试期望值改成 `[0x00, 0x53, 0x03, 0x00, 0x00]`。
- (B) 如果 Codex 坚持 self-target 必要,**必须**在 Plan 里附:
  - LIFT B BLE 抓包对比 (`remap=0` 与 `remap=self` 的实际 reporting state 差异),或
  - 一条 Logitech HID++ 官方文档/Solaar issue 链接说明 BLE 需要 self-target,或
  - 在 Task 6 增加对比验证 (用 `remap=0` 跑一次 60s soak,再用 `remap=self` 跑一次,记录两组 silent drop 频率)。

### 2.2 🟠 Task 5: disconnect 后无 reconnect 自动恢复

**Plan 的改动**: `handleDeviceConnectionNotification` 在 `connected=false && devIdx==deviceIndex` 时:
```
releaseAllActiveButtonState(reason: "receiver target disconnected")
lastApplied.removeAll()
divertedCIDs.removeAll()
reprogInitComplete = false
handshakeComplete = false
setDiscoveryInFlight(false)
```

**问题路径**:
1. Slot 短暂掉线 (Bolt receiver 遇到无线干扰是常见场景),Plan 的代码把 `reprogInitComplete=false`。
2. 用户在掉线期间改了 binding → `UsageRegistry.runRecompute()` → `applyUsage(set)`。当前代码就有 `guard reprogInitComplete else { return }` (`LogiDeviceSession.swift:241`),所以 binding 改动被静默吞掉。
3. 几秒后 slot 重连,设备发 `connected=true` 通知。**Plan 没在此处触发任何后续动作**。
4. 用户按键 → 设备没被 divert (因为 `lastApplied=空` 且 `applyUsage` 因 `reprogInitComplete=false` 不跑) → 用户体感"按键失灵"。
5. 修复路径只能是用户主动切回 Buttons 面板触发 `refreshReportingStates()` 节流过期(>=10s)再生效。

**建议**: Task 5 step 2 在 `connected=true && devIdx==deviceIndex` 分支也加上恢复逻辑,例如:
```swift
if connectionMode == .receiver,
   devIdx == deviceIndex,
   connected,
   featureIndex[Self.featureReprogV4] != nil,
   !discoveredControls.isEmpty {
    // 设备热回归: 直接重启 reporting query,会自然走 reconcile + primeFromRegistry
    setDiscoveryInFlight(true)
    startReportingQuery()
}
```
注意: 不需要 `rediscoverFeatures()` (那会清 `featureIndex` / `discoveredControls`,代价更大),只需重跑 query。如果 featureIndex 已被 setTargetSlot 等其他路径清掉,fallback 到完整 rediscover。

**额外提醒**: `LogiSessionManager.isRecording` 在 `temporarilyDivertAll()` 时被置 true,如果录制期间 slot 掉线,Task 5 的重置不会清 `isRecording`,而 `lastApplied` 已空。`restoreDivertToBindings()` → `primeFromRegistry()` → `applyUsage()` 此时 `reprogInitComplete=false`,binding divert 不会恢复。**录制流程的失败模式需要在 Task 5 显式 enumerate**,至少在 plan 里写一条注记。

### 2.3 🟡 Task 4: `QueriedControlForTests` 不应是生产 API

Plan 的代码里:
```swift
internal struct QueriedControlForTests { ... }

private static func reconciledAppliedSet(
    lastApplied: Set<UInt16>,
    queriedControls: [QueriedControlForTests]   // ← 生产函数签名
) -> Set<UInt16>
```

`*ForTests` 后缀渗到生产函数签名上,日后维护者会困惑"这个生产路径里为什么有测试类型"。请改为:

```swift
// 生产语义类型 (一次性快照,与 ControlInfo 解耦,纯值)
internal struct QueriedControlState {
    let cid: UInt16
    let reportingFlags: UInt8
    let reportingQueried: Bool
}

private static func reconciledAppliedSet(
    lastApplied: Set<UInt16>,
    queriedControls: [QueriedControlState]
) -> Set<UInt16> { ... }

#if DEBUG
internal static func reconciledAppliedSetForTests(
    lastApplied: Set<UInt16>,
    queriedControls: [QueriedControlState]
) -> Set<UInt16> {
    return reconciledAppliedSet(lastApplied: lastApplied, queriedControls: queriedControls)
}
#endif
```

(测试初始化 `.init(cid:..., reportingFlags:..., reportingQueried:...)` 完全不变,只是类型重命名。)

参考: 同仓库的 `LogiDevicSession.featureCacheKeyForTests` (`LogiDeviceSession.swift:155`) 已经用 `#if DEBUG` 包裹,延续这个模式即可。

### 2.4 🟡 Task 4: reconcile 测试覆盖不全

Plan 的 `LogiDivertReconciliationTests` 只有两条测试:
1. lost (reportingQueried=true 且 flags & 0x01 == 0) → 移除
2. unqueried → 不变

至少还需要补:

```swift
func testStillDivertedIsKept() {
    let result = LogiDeviceSession.reconciledAppliedSetForTests(
        lastApplied: [0x0053],
        queriedControls: [
            .init(cid: 0x0053, reportingFlags: 0x01, reportingQueried: true)
        ]
    )
    XCTAssertEqual(result, [0x0053])  // bit0=1 表示 Mos divert 仍生效, 不能误移除
}

func testStaleAppliedNotInQueriedControlsIsKept() {
    // lastApplied 中存在不在当前 discoveredControls 的 stale CID;
    // reconcile 不应该误删 (避免 setTargetSlot 等 race 路径下的 false-positive)
    let result = LogiDeviceSession.reconciledAppliedSetForTests(
        lastApplied: [0x0053, 0x9999],
        queriedControls: [
            .init(cid: 0x0053, reportingFlags: 0x01, reportingQueried: true)
        ]
    )
    XCTAssertEqual(result, [0x0053, 0x9999])
}
```

另外 Task 4 step 4 涉及到 `divertedCIDs.subtract(lost)`,这是为了避免 `LogiSessionManager.conflictStatus` 把 lost CID 误判为 `.mosOwned` (`LogiSessionManager.swift:219`)。**这个一致性最好有一个集成测试**,因为它跨越了 reconcile / divertedCIDs / ConflictDetector 三处。

---

## 3. 可改可不改的细节 (nit)

### 3.1 Task 2 的路由代码里 `case 2 where ...` 是 dead branch

Plan 改写后的 REPROG 分支:
```swift
if reportingQueryTimer != nil, Self.isGetControlReportingQueryResponse(report) {
    handleGetControlReportingResponse(report); return
}
if reprogInitComplete { ... }
else {
    switch functionId {
    case 0: handleGetControlCountResponse(report)
    case 1: handleGetControlInfoResponse(report)
    case 2 where Self.isGetControlReportingQueryResponse(report):
        handleGetControlReportingResponse(report)   // ← 永远走不到
    default: break
    }
}
```

`reportingQueryTimer` 在 `startReportingQuery` 之后到 `advanceReportingQuery` 终态之间一直 != nil,`case 2` 阶段必落入第一个 `if`。保留这个 case 当 fallback 没坏处,但加一行注释说明它是冗余 fallback,免得后续有人觉得是 dead code 删掉。

### 3.2 Task 3 stale 响应仍更新 reportingFlags 的语义

Plan 描述:
> Stores reportingFlags, targetCID, and reportingQueried.
> Advances only if reportingQueryIndex < discoveredControls.count and discoveredControls[reportingQueryIndex].cid == response.cid.

逻辑上,stale 响应仍然是设备真实状态的一份快照,更新 `reportingFlags`/`targetCID` 是合理的。但这意味着 `reportingQueried=true` 的语义微妙变了 — 从"本轮 query 已查到这个 CID"变成"曾经查到过这个 CID"。如果 `reconcileAppliedDivertsWithQueriedState` 在中途被触发 (例如 redivertAllControls 之后第一次 reporting query 还没跑完时),它会用上一轮的 stale flags 做 reconcile。

实际不会出 bug,因为 `reconcileAppliedDivertsWithQueriedState` 仅从 `divertBoundControls()` 调用,而 `divertBoundControls()` 只在 reporting query 完成 (advance 走完) 后被触发。但 plan 应该在注释里**明确这个不变量** ("reconcile 必须在 reporting query 完整一轮后调用"),否则未来有人把 reconcile 挪到 applyUsage 里会爆炸。

### 3.3 Task 4 reconcile 的位置

Plan 把 `reconcileAppliedDivertsWithQueriedState()` 放在 `divertBoundControls()` 顶部 (即 `primeFromRegistry()` 之前)。这是对的。但还有一个调用点值得考虑: `redivertAllControls()` (`LogiDeviceSession.swift:613`) 调 `divertBoundControls()` → reconcile 顺路跑。这条路径下 `discoveredControls.reportingQueried` 可能是上次 refresh 留下的真值,reconcile 仍能产生有效结果,不算问题,但 plan 应该提一句"redivert 路径也会 reconcile,行为一致"。

### 3.4 Task 1 packet builder 的 `case .unsupported` 返回空数组

```swift
case .unsupported:
    return []
```

`setControlReporting` 用 `guard !params.isEmpty else { return }` 兜底。逻辑没问题,但这条路径在生产里**不可达** (因为 `applyUsage` 已经被 `featureIndex[reprogV4]` guard 拦住,而 unsupported 不会有 reprog feature)。给 packet builder 写测试 `testUnsupportedReturnsEmptyArray()` 增加自信,但生产不会触发。可加可不加。

### 3.5 Plan Task 5 与 BLE direct 的 `currentReceiverTargetIsConnected` 关系

```swift
private var currentReceiverTargetIsConnected: Bool {
    guard connectionMode == .receiver else { return true }
    ...
}
```

BLE direct (deviceIndex=0xFF) 直接返回 `true`,这是对的。但 BLE 的 disconnect 路径目前**完全不走** `handleDeviceConnectionNotification` (那是 receiver-only HID++ 1.0 通知)。BLE 的 disconnect 由 `IOHIDManager` 的 `deviceRemovedCallback` 直接 teardown 整个 session (`LogiSessionManager.swift:124-131`),全套 state 都清掉了。所以 BLE silent drop 不是物理 disconnect,而是 link 还在但 reporting flag 被设备主动清。Plan 的整套 reconcile 路径就是为这个场景设计的,没毛病,只是建议在 plan notes 里把这个区分写清楚 ("Receiver disconnect = 通过 0x41 通知,我们要重置;BLE silent drop = 通过 reconcile 兜底,session 不变")。

---

## 4. 建议的修订动作

按优先级,Codex 反馈时建议:

| 优先级 | 改动 | 位置 |
|---|---|---|
| 🔴 必须 | 提供 BLE self-target 证据,否则撤回 Task 1 的 BLE/Receiver 包格式分支 | Task 1 |
| 🟠 必须 | 在 disconnect 通知 `connected=true` 分支主动恢复 reporting query | Task 5 step 2 |
| 🟡 强烈 | `QueriedControlForTests` → `QueriedControlState` + 单独 ForTests wrapper | Task 4 step 3 |
| 🟡 强烈 | 补 `testStillDivertedIsKept`、`testStaleAppliedNotInQueriedControlsIsKept`、reconcile + divertedCIDs 一致性集成测试 | Task 4 step 1 |
| 🟢 建议 | Task 4 reconcile 函数加注释 "must be called after a complete reporting query pass"  | Task 4 step 4 |
| 🟢 建议 | Task 2 的冗余 `case 2 where` 加注释 | Task 2 step 3 |
| 🟢 建议 | Task 6 step 1 拆成 "self-target 关闭" 和 "self-target 开启" 两组 soak 来证明 Task 1 的额外价值 | Task 6 step 1 |

---

## 5. 我没在这次 review 里覆盖的点 (留给 Codex 自检)

- `setControlReporting` 调用频率: reconcile 后会触发若干 SetControlReporting,如果 silent drop 是周期性的 (例如设备每 60s drop 一次),每次 refresh 都重发,长期是否会刷爆 BLE link。Plan Task 6 step 1 的 60-120s 验证不够长,建议跑 30 分钟 soak。
- `LogiBoundaryEnforcementTests` / `LogiCenterPublicSurfaceTests` 是否会因为新增 `internal` 类型而失败 (它们做模块边界检查),Plan 没列入回归测试清单。
- `Mos_Debug` scheme 是否包含 `LogiControlReportingPacketTests` 等新测试文件 (Xcode 项目文件需要手动加到 target membership)。Plan 提了 `xcodebuild test -only-testing:`,但没说这些文件需要手动加入 `MosTests` target,否则 Codex 跑测试会找不到。

---

## 6. 总评

| 维度 | 评价 |
|---|---|
| 问题诊断 | ✅ 准确抓住了"`lastApplied` 单一真相"的核心 bug |
| 修复架构 | ✅ "意图 vs 真相" 二元分离 + reconcile,设计干净 |
| 协议正确性 | ⚠️ softwareId / expected-CID 守卫正确;BLE self-target 缺证据 |
| 测试可见性 | ✅ `@testable import Mos_Debug` + internal-ForTests 包装,工程上可行 |
| 命名 | ⚠️ `QueriedControlForTests` 渗到生产,应拆 |
| 边界覆盖 | ⚠️ disconnect → reconnect 自动恢复缺失;reconcile 测试矩阵不全 |
| 文档/可追溯 | ⚠️ 没在 Plan Notes 区分 "receiver disconnect" vs "BLE silent drop" 两类故障域 |
| 回归风险 | 🟡 中等 — 主要风险在 Task 1 和 Task 5 的副作用,Task 2/3/4 自身风险低 |

**结论**: 当上面 4 处必须修复的问题被处理后,这个 plan 可以合入。修复路径本身是对的,只是边界没收齐。
