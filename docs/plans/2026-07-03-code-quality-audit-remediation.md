# 代码质量审查修复计划（2026-07-03）

> **执行方式**：本文档是可分批执行的修复 backlog。每批建议独立分支/PR，完成一项就把索引表中状态改为 `✅`。行号基于 master `238706e`，执行前如有偏移以符号搜索为准。

**来源**：对全部 8 个模块（约 3.2 万行 Swift）的系统性审查。6 路并行子系统审查 + 对全部高严重度项的人工二次核实（逐条读源码确认）。低严重度项经 grep 交叉验证调用方后收录。

**审查中确认健康、无需改动的部分**（避免后续重复怀疑）：

- `Options` 配置中心：五个配置组内存缓存，滚动热路径零 UserDefaults I/O，写侧脏组合并统一 flush（`Options.swift:69-87, 141-161`）。
- 主线程契约：CGEventTap / IOHIDManager 回调统一调度在主 RunLoop（`Utils.swift:269`、`LogiSessionManager.swift:58`），关键路径有 `assertMainThread` / DEBUG precondition 守护。本文的竞态项都是**绕过**此契约的例外路径。
- Logi 辅助文件（SessionManager、CIDDirectory、ConflictDetector、DivertPlanner、UsageRegistry、DeliveryPolicy/Mode、Bridge 等 14 个）职责单一、纯函数可测。
- 依赖均较新：Sparkle、DGCharts 5.1.0、LoginServiceKit 2.4.0。

---

## 调度策略

排序依据：**用户影响 × 回归风险 × 工作量 × 批次间依赖**。

| 批次 | 主题 | 为什么排这里 | 工作量 | 回归风险 |
|---|---|---|---|---|
| **P0** | 崩溃 / 数据竞争 / 无界增长（9 项） | 直接用户损害（崩溃、修饰键卡死、点击错位、内存失控），且全部是局部小改 | 小 | 低 |
| **P1** | 性能止血（13 项） | 热路径与 release 常驻开销，多数改动局部 | 小-中 | 低 |
| **P2** | 死代码清理（11 项） | 零风险纯删除（约 -600 行），先删掉可给 P3/P5 的重构减少噪音 | 小 | 极低 |
| **P3** | DRY 收敛（14 项) | 消重降低后续维护成本；部分项（P3-1）是 P5 拆分的前置铺垫 | 中 | 中 |
| **P4** | 最佳实践加固（15 项） | 潜伏缺陷（错误吞掉、observer 泄漏、竞态窗口），不紧急但应在大重构前修完，避免被拆分掩埋 | 中 | 低-中 |
| **P5** | 结构重构（8 项，立项级） | god class 拆分、循环耦合切断。工作量最大，必须在 P0-P4 落地、测试面稳定后进行 | 大 | 高 |

**批内 PR 切分建议**（同批内按模块分组，共享测试门槛）：

- P0 → 3 个 PR：`ScrollCore`（P0-1/2）、`Logi`（P0-5/7）、`Shortcut+Keys+Utils+Monitor`（P0-3/4/6/8/9）。
- P1 → 3 个 PR：`LogiDebugPanel 系`（P1-1~6）、`ScrollCore 系`（P1-7/8/12/13）、`偏好设置 UI 系`（P1-9/10/11）。
- P2 → 1 个 PR 一次删完。
- P3/P4 → 按模块拆 2-4 个 PR。
- P5 → 每项单独立项，先写 design doc（沿用 `docs/plans/*-design.md` 惯例）。

**验证门槛**（引自 `AGENTS.md` / `.agents/docs/testing.md`，每个 PR 至少）：

```bash
xcodebuild -scheme Debug -configuration Debug -destination 'platform=macOS' build
xcodebuild -scheme Debug -destination 'platform=macOS' test -only-testing:MosTests/<相关测试类>
scripts/qa/lint-logi-boundary.sh   # 涉及 Mos/Logi 或 Mos/Integration 时
```

模块 → 测试类映射：ScrollCore → `ScrollEventTests` `ScrollPhaseTests` `ScrollDispatchContextTests` `ScrollCoreHotkeyTests`；Logi → `LogiDivertReconciliationTests` `LogiButtonDeliveryModeTests` `LogiStandardMouseButtonAliasTests`；Shortcut/Keys/InputEvent → `ButtonBindingTests` `InputProcessorTests` `ScrollHotkeyTests` `MouseInteractionSessionControllerTests`；Options → `OptionsButtonsLoaderTests`。

**需要用户确认的高风险动作**（`AGENTS.md` 人类确认边界）：P4-4（HID 回调注销）与 P5-1（session 拆分）涉及 divert / 真实设备行为，合并前应跑 `LOGI_REAL_DEVICE=1` 真机测试，需用户确认设备已连接。

---

## 索引

| ID | 位置 | 分类 | 严重度 | 状态 |
|---|---|---|---|---|
| P0-1 | ScrollUtils.swift:41-54 | 并发 | 高 | ✅ 2026-07-03 |
| P0-2 | ScrollUtils.swift:92-104 | 崩溃/性能 | 高 | ✅ 2026-07-03 |
| P0-3 | Utils.swift:233 | 崩溃 | 高 | ✅ 2026-07-03 |
| P0-4 | MonitorViewController.swift:96 / MonitorLogStore.swift:21 | 性能 | 高 | ✅ 2026-07-03 |
| P0-5 | LogiDeviceSession.swift:2638,1074 | 并发 | 高 | ✅ 2026-07-03 |
| P0-6 | ShortcutExecutor.swift:367,529 | 正确性 | 高 | ✅ 2026-07-03 |
| P0-7 | LogiDeviceSession.swift:2568-2570 | 崩溃 | 高 | ✅ 2026-07-03 |
| P0-8 | KeyRecorder.swift:168-170 | 正确性 | 高 | ✅ 2026-07-03 |
| P0-9 | ShortcutExecutor.swift:152-163 | 正确性 | 高 | ✅ 2026-07-03 |
| P1-1 | LogiDebugPanel.swift:366-381 | 性能 | 中 | ✅ 2026-07-03 |
| P1-2 | LogiDebugPanel.swift:466 / CGEvent+Extensions.swift:234 | 性能 | 中 | ✅ 2026-07-03 |
| P1-3 | LogiDebugPanel.swift:1451-1453 | 性能 | 中 | ✅ 2026-07-03 |
| P1-4 | LogiDebugPanel.swift:1671-1687 | 性能 | 中 | ✅ 2026-07-03 |
| P1-5 | BrailleSpinner.swift:27-37 | 性能 | 中 | ✅ 2026-07-03 |
| P1-6 | LogiDebugPanel.swift:1721-1724 | 性能 | 中 | ✅ 2026-07-03 |
| P1-7 | ScrollFilter.swift:38-41 | 性能 | 中 | ✅ 2026-07-03 |
| P1-8 | ScrollEvent.swift:58-84 | 坏味道/性能 | 中 | ✅ 2026-07-03 |
| P1-9 | PreferencesButtonsViewController.swift:149 等 | 性能 | 中 | ✅ 2026-07-03 (菜单缓存部分并入 P5-5) |
| P1-10 | ActionDisplayResolver.swift:146-166 | 性能 | 中 | ✅ 2026-07-03 |
| P1-11 | LogiDeviceSession.swift:2695-2713 | 性能 | 低 | 待处理 (需真机验证, 建议与 P4-4 同批) |
| P1-12 | ScrollCore.swift:305-310,383-389 | 性能 | 低 | 待处理 (并入 P5-3) |
| P1-13 | ScrollUtils.swift:111-114 | 性能 | 低 | ✅ 2026-07-03 |
| P2-1 | Utils/Archieve.swift | 死代码 | 中 | ✅ 2026-07-04 |
| P2-2 | Utils.swift:250-265 | 死代码 | 低 | ✅ 2026-07-04 |
| P2-3 | ScrollUtils.swift:19-27 | 死代码 | 低 | ✅ 2026-07-04 |
| P2-4 | KeyCode.swift:40-41 | 死代码 | 低 | ✅ 2026-07-04 |
| P2-5 | SystemShortcut.swift:351-373 | 死代码 | 低 | ✅ 2026-07-04 |
| P2-6 | Logger.swift:101-137 | 死代码 | 低 | ✅ 2026-07-04 |
| P2-7 | Toast 组件 3 处 | 死代码 | 低 | ✅ 2026-07-04 |
| P2-8 | ButtonCore.swift:31,74-82 | 死代码 | 低 | ✅ 2026-07-04 |
| P2-9 | BrandTag.swift:88,120 | 死代码/架构 | 低 | ✅ 2026-07-04 (isLogiCode 耦合留 P5-8; brandForCode 有调用方保留) |
| P2-10 | LogiSelfTestWizard.swift:23 等 | 死代码 | 低 | ✅ 2026-07-04 |
| P2-11 | PreferencesApplicationViewController.swift:209,77-82 | 死代码 | 低 | ✅ 2026-07-04 |
| P3-1 | LogiDeviceSession.swift:1868-2051 | DRY | 中 | ✅ 2026-07-04 |
| P3-2 | LogiDeviceSession.swift:962-989 | DRY | 低 | ✅ 2026-07-04 |
| P3-3 | LogiDeviceSession 常量散落 | DRY | 低 | ✅ 2026-07-04 |
| P3-4 | LogiDeviceSession handshake 终点 ×3 | DRY | 低 | ⏸ 挂起 (三处通知语义刻意不同: receiver ping 完成不可清 peripheral spinner、divertBoundControls 刻意不 post; 机械统一有破坏 sidebar 状态风险, 并入 P5-1 状态机重构) |
| P3-5 | ShortcutExecutor.swift:316-353,358,478 | DRY | 中 | ✅ 2026-07-04 |
| P3-6 | ShortcutExecutor.swift:459-476 | DRY | 中 | ✅ 2026-07-04 |
| P3-7 | ShortcutManager.swift:70-118,195-246 | DRY | 低 | ✅ 2026-07-04 |
| P3-8 | SystemShortcut.swift:68-165,494-510 | 坏味道 | 低 | ✅ 2026-07-04 |
| P3-9 | ToastManager.swift:139-190 | DRY | 中 | ✅ 2026-07-04 |
| P3-10 | 两个偏好 VC 三方法重复 | DRY | 中 | ✅ 2026-07-04 (updateViewVisibility 共享化并修复隐藏动画顺序; toggleNoDataHint 各自保留) |
| P3-11 | Options.swift:184-215 | DRY | 中 | ✅ 2026-07-04 |
| P3-12 | AppDelegate.swift 停机序列 ×3 | DRY | 低 | ✅ 2026-07-04 |
| P3-13 | RecordedEvent.swift:56-66 等 | DRY/本地化 | 低 | ✅ 2026-07-04 (显示名收敛; 兜底文案为符号+数字, 本地化评估为低价值不改) |
| P3-14 | LogiDebugPanel 内部重复 ×3 组 | DRY | 低 | ✅ 2026-07-04 |
| P4-1 | 8 个 VC 生命周期缺 super | 最佳实践 | 中 | ✅ 2026-07-04 (9 处) |
| P4-2 | ScrollCore 系 4 个单例 init | 最佳实践 | 低 | ✅ 2026-07-04 (ScrollCore/ScrollUtils 改 private; ScrollPoster/ScrollPhase 保持可构造 — 测试以独立实例为 SUT) |
| P4-3 | LogiDebugPanel.swift:1075 / AppDelegate.swift:106 | 泄漏 | 中 | ✅ 2026-07-04 |
| P4-4 | LogiDeviceSession.swift:907-942 | 潜伏 UAF | 中 | ✅ 2026-07-04 代码完成 (teardown+deinit NULL 注销); ⚠️ 待真机插拔/休眠唤醒循环验证 |
| P4-5 | KeyRecorder.swift:234,243,533 | 错误处理/竞态 | 中 | ✅ 2026-07-04 (catch 统一走 stopRecording 回滚且 async 排序在 beginKeyRecording 后; 延迟复位改可取消 WorkItem) |
| P4-6 | LogiSelfTestWizard.swift:169-173 | 竞态 | 中 | ✅ 2026-07-04 |
| P4-7 | LogiDeviceSession.swift:2386,1514 | 错误处理 | 中 | ✅ 2026-07-04 (2.0 错误按 featureIdx==0x00 精确结算; 1.0 错误保持旧语义 — 报文不可靠回显失败请求身份) |
| P4-8 | LogiDebugPanel.swift:1416 | 错误处理 | 低 | ✅ 2026-07-04 (随 P3-14 重写导出函数一并修复) |
| P4-9 | SystemShortcut.swift:168-176 | 正确性 | 中 | ✅ 2026-07-04 (全仓核实 ==/hash 零直接调用方, Shortcut 不参与 Codable 持久化 — 零风险语义修正; 补 hasSameKeyCombination 显式组合等价 API) |
| P4-10 | Utils.swift:165-167 | 正确性 | 中 | ✅ 2026-07-04 |
| P4-11 | UI 层 force cast/unwrap 6 处 | 最佳实践 | 中 | ✅ 2026-07-04 |
| P4-12 | PreferencesTabViewController.swift:31-43 | 最佳实践 | 中 | ✅ 2026-07-04 (一次性守卫 + 显式等价约束; 审查建议的去 frame 方案会破坏背景, 已改用 width/height 常量约束) |
| P4-13 | PreferencesScrollingViewController.swift:226-228 | 坏味道 | 低 | ✅ 2026-07-04 (核实为旧数据一次性迁移兜底 — 写路径已有完整归一化, 删除会致旧数据显示/引擎不一致; 已注释固化语义) |
| P4-14 | Interceptor.swift:48,77,113 | 并发 | 低 | ✅ 2026-07-04 (owningRunLoop 创建时捕获) |
| P4-15 | 魔法数字 2 处 | 坏味道 | 低 | ✅ 2026-07-04 |
| P5-1 | LogiDeviceSession 拆分 | 结构 | 高 | 待处理 (2026-07-10 随 master handoff 合入刷新方案: 4105 行, 新增性能红线约束与双鼠标验证场景) |
| P5-2 | LogiDebugPanel 拆分 | 结构 | 中 | 待处理 (2026-07-10 刷新: 3047 行, 新增 3 个 feature context) |
| P5-3 | ScrollCore.swift:53-195 拆分 | 结构 | 中 | 待处理 |
| P5-4 | handleInputReport 拆分 | 结构 | 中 | 待处理 |
| P5-5 | ButtonTableCellView 减负 | 结构 | 中 | 待处理 |
| P5-6 | session↔manager↔center 循环耦合 | 结构 | 高 | ✅ 2026-07-11 (LogiSessionEnvironment 注入, session/manager 不再反向引用单例; 设计 docs/plans/2026-07-11-logi-session-environment-design.md; P5-1 前置已满足) |
| P5-7 | Options/Constants 耦合环 | 结构 | 中 | 待处理 |
| P5-8 | ScrollCore facade + WindowManager 耦合 | 结构 | 低 | 待处理 |

---

## P0 崩溃 / 数据竞争 / 无界增长

### P0-1 滚动热路径无锁数据竞争（ScrollUtils 共享缓存）

- **位置**：`Mos/ScrollCore/ScrollUtils.swift:41-54`；触发链 `Mos/ScrollCore/ScrollPoster.swift:242-243`（`stop()` 内调 `isEventTargetingChrome`）；`ScrollPoster.swift:222 vs 192-194`（`poster` 字段本身）。
- **上下文**：`getRunningApplication(from:)` 无锁读写 `lastEventTargetPID` / `currEventTargetPID` / `cachedRunningApplication` 三个实例字段。它有两类调用方：主线程的 CGEvent tap 回调（`ScrollCore.swift:91`），以及 **CVDisplayLink 线程**——`processing()` 末尾（`ScrollPoster.swift:422-423`）调 `stop()`，`stop()` 内经 `isEventTargetingChrome(snapshot.event)` 走到同一函数。`cachedRunningApplication` 是 ARC 对象指针，两线程撕裂写可直接崩溃；`NSRunningApplication.init` 也被在非主线程调用。`ScrollPoster.poster` 字段同样是主线程写（create/recreate）、DisplayLink 线程读（stop），而第 56 行注释声称"主线程访问, 无需锁"，与实际调用路径矛盾。
- **修复步骤**：
  1. 首选方案：让 `stop()` 中的 Chrome 判断不再实时查询——在主线程 tap 回调阶段（`captureConfigSnapshotLocked` 或 `preparePostingSnapshot`）就把 `isTargetChrome` 布尔存入 snapshot，DisplayLink 线程只读快照。这与现有 `ScrollDispatchContext` 快照模式一致。
  2. 若仍需跨线程访问 `poster` 字段，将其纳入已有的 `stateLock` 临界区，或把 `stop()` 的 DisplayLink 收尾改为 `DispatchQueue.main.async` 投递。
  3. 修正 `ScrollPoster.swift:56` 的过期注释，写明真实线程语义。
- **验证**：`ScrollPhaseTests` `ScrollDispatchContextTests` `ScrollEventTests` + Debug build；TSan 跑一次 `xcodebuild test -enableThreadSanitizer YES`（如 scheme 支持）；手动在 Chrome 中滚动确认 TrackingEnd 行为不变。

### P0-2 Launchpad 检测：热路径 force unwrap + 缺版本门控 + 缓存失效

- **位置**：`Mos/ScrollCore/ScrollUtils.swift:92-104`。
- **上下文**：`getLaunchpadActivity` 在滚动事件路径上执行 `CGWindowListCopyWindowInfo` 全量窗口扫描，随后 `windowInfoList!`、`windowInfo[kCGWindowName]!`、`as! String` 三连强解。问题有三层：(a) `CGWindowListCopyWindowInfo` 在锁屏/WindowServer 异常时可返回 nil → 崩溃直接击穿全局滚动；(b) 10.15+ 无录屏权限拿不到 `kCGWindowName`，这段扫描是无效开销，却只有 10.15 的 Dock 路径分支（84-89 行）而没有把老逻辑排除；(c) 96-99 行命中 `LPSpringboard` 的 true 分支 `return` 前不更新 `launchpadLastDetectTime`，命中期间"每秒一次"的节流失效，退化为每个滚动事件扫描一次。
- **修复步骤**：
  1. 给 windowList 扫描包上 `if #available(macOS 10.15, *) { } else { ... }` 反向门控——10.15+ 直接走 Dock executable 判断，老系统才扫描窗口名。
  2. 扫描分支改为 `guard let windowInfoList = ... as? [[CFString: Any]] else { return launchpadActiveCache }`，逐项用 `as? String` 安全取 `kCGWindowName`。
  3. true 分支 return 前同样更新 `launchpadLastDetectTime`。
- **验证**：Debug build + 在低版本可用时手动验证 Launchpad 平滑滚动不回归；主路径滚动无感知变化。

### P0-3 应用名解析 force unwrap 必崩溃路径

- **位置**：`Mos/Utils/Utils.swift:233`（`parseName(fromPath:)`）。
- **上下文**：`FileManager().displayName(atPath: path).removingPercentEncoding!`。该函数处理任意用户应用路径（偏好设置添加例外应用时调用）。应用显示名含无效百分号序列（如 "100% Orange Juice"，`%` 后不是合法十六进制）时 `removingPercentEncoding` 返回 nil → 必崩溃。
- **修复步骤**：
  1. 改为 `let raw = FileManager().displayName(atPath: path); let name = raw.removingPercentEncoding ?? raw`。
  2. 顺手确认：这里每次调用新建 `FileManager()` 实例，改用 `FileManager.default`。
- **验证**：新增单测：对含 `%` 的伪路径调用 `parseName` 不崩溃、返回原名。跑 `OptionsButtonsLoaderTests` + Debug build。
- **修复记录 (2026-07-03)**：已修复。回归测试额外发现并修复同函数的正则 bug：`pattern: ".app"` 的 `.` 是通配符且大小写不敏感, 会把 "WhatsApp" 截成 "What", 已改为锚定结尾的 `\.app$`（`UtilsParseNameTests` 覆盖）。

### P0-4 监视窗口内存/CPU 无界增长

- **位置**：`Mos/Windows/MonitorWindow/MonitorViewController.swift:96-99, 148`；`Mos/Windows/MonitorWindow/MonitorLogStore.swift:21-24`。
- **上下文**：监视窗口打开期间：(a) 图表 6 个 dataset 每个滚动事件都 append 且从不裁剪，`lineChartCount` 无限增长，同时每事件 `notifyDataSetChanged()` 触发全图重算；(b) `MonitorLogStore.append` 无上限累积字符串，而事件掩码含 `mouseMoved` 与三种 drag——**每次移动鼠标都永久累积一行**，仅 preview 读取时限 200 行，底层数组不裁剪；(c) 88-93 行还有每次 phase 变化的 `NSLog`。长会话内存与 CPU 双重失控。
- **修复步骤**：
  1. `MonitorLogStore.append` 加环形上限（如每 channel 2000 行，超出 `removeFirst` 批量裁剪；避免逐条 removeFirst 的 O(n) 抖动，可攒到 2200 再裁到 2000）。
  2. 图表 dataset 同样加滑动窗口（保留最近 N=600 个点，超出移除队首并调整 x 轴），或改为仅在可见时低频（如 30Hz 合批）刷新。
  3. 删除 88-93 行 phase 变化 NSLog（监视窗口自身已有展示）。
- **验证**：打开监视窗口持续滚动+晃动鼠标 5 分钟，Activity Monitor 观察内存稳定；图表交互正常。

### P0-5 Logi feature discovery 响应错配竞态

- **位置**：`Mos/Logi/Core/LogiDeviceSession.swift:2638`（`handleDiscoveryResponse` 用 `pendingDiscovery.first`）；`:1074-1075`（单实例 `discoveryTimer` 相互 invalidate）。
- **上下文**：IRoot.GetFeature 的响应报文不回显 featureId，代码用字典**任意序**的 `.first` 来匹配回调。当多个 discovery 并发时（真实路径：初始 0x1B04 REPROG discovery 未完成时，用户触发 SmartShift 快捷键 → `LogiSessionManager.primarySession`（`LogiSessionManager.swift:395` 兜底返回未初始化完成的 session）→ `executeSmartShiftToggle` → `discoverFeature(0x2110)`），可能把 REPROG 的 featureIndex 交给 SmartShift 的回调，错误 index 还会被写入 `featureIndex` 并**持久化到 UserDefaults 缓存**，重启后仍然错。同时 `discoveryTimer` 是单实例：后发的 discoverFeature 会 `invalidate()` 前一个的超时定时器，前者的 pending 条目永远悬挂。
- **修复步骤**：
  1. 将 `pendingDiscovery` 从"字典 + 任意序 .first"改为 **FIFO 队列串行化**：同一时刻只允许一个 in-flight GetFeature，响应到达即出队匹配，队列非空则发下一个。HID++ IRoot 本身是串行请求-响应协议，串行化是协议正确姿势。
  2. 超时改为随队列头一起管理：每次出队/入队重置一个针对**当前队头**的超时；超时触发时只 fail 队头并推进队列。
  3. 补一条防线：`LogiSessionManager.primarySession` 在 `handshakeComplete == false` 时返回 nil 或延迟执行外部快捷键动作（这会同时消除并发窗口）。
  4. 为错配场景补回归测试（用 `MosTests/LogiTestDoubles` 模拟两个并发 discovery + 乱序响应）。
- **验证**：`LogiDivertReconciliationTests` `LogiButtonDeliveryModeTests` + 新增回归测试 + `scripts/qa/lint-logi-boundary.sh`；建议真机（`LOGI_REAL_DEVICE=1`）验证 SmartShift/DPI 快捷键，**需用户确认设备连接**。
- **注意**：此项与 P5-1 的 HIDPPRequestPipeline 是同一根因的短期/长期解。P0 阶段先做最小串行化，不要顺手开始大拆分。

### P0-6 合成鼠标事件多显示器坐标错位

- **位置**：`Mos/Shortcut/ShortcutExecutor.swift:367`（`executeCustomMouseButton` 内联坐标翻转）；`:529-533`（`currentMouseLocationForCGEvent()`，同样问题）。
- **上下文**：NSEvent 坐标系原点在**主屏**（`NSScreen.screens[0]`）左下角，CGEvent 原点在主屏左上角。翻转公式应当用主屏高度，代码却用 `NSScreen.main`（**焦点窗口所在屏**）：`let screenHeight = NSScreen.main?.frame.height ?? 0`。多显示器且屏高不同时，合成点击/拖拽的 Y 坐标整体偏移、点错位置；`?? 0` 兜底还会产生负坐标。影响 executeCustomMouseButton 与 replay 两条路径。
- **修复步骤**：
  1. 两处统一改为 `NSScreen.screens.first?.frame.height`；更稳妥的等价写法是直接用 `CGEvent(source: nil)?.location` 取当前鼠标的 CG 坐标，完全绕开手工翻转。
  2. 消除 365-368 行对 529-533 的内联重复（与 P3-5 合并处理亦可，此处先让两处调用同一函数）。
- **验证**：`ButtonBindingTests` `MouseInteractionSessionControllerTests`；有条件时双显示器（不同分辨率、副屏在上/在左）手动验证自定义鼠标键动作点击位置。

### P0-7 设备报文不校验直接模运算（除零/溢出 trap）

- **位置**：`Mos/Logi/Core/LogiDeviceSession.swift:2568-2570`（ChangeHost 响应处理）。
- **上下文**：`let hostCount = report[4]; let currentHost = report[5]; let nextHost = (currentHost + 1) % hostCount`。HID 报文是外部输入：固件异常或伪造报文给出 `hostCount == 0` 时整数除零 trap；`currentHost == 255` 时 `+1` 溢出 trap。两者都是进程级崩溃。
- **修复步骤**：
  1. `guard hostCount > 0 else { log + return }`。
  2. 加法改 `let nextHost = (UInt16(currentHost) + 1) % UInt16(hostCount)` 或 `currentHost &+ 1`（配合 guard 后取模）。
  3. 顺检同函数邻近分支是否有同类未校验字节运算。
- **验证**：Logi 测试类全跑 + lint-logi-boundary.sh。

### P0-8 录制期间吞掉合成修饰键事件 → 系统修饰键卡死

- **位置**：`Mos/Keys/KeyRecorder.swift:168-170`；对照 `Mos/ButtonCore/ButtonCore.swift` 同 marker 分支（放行）。
- **上下文**：KeyRecorder 的录制 tap 是**主动过滤型**（`.defaultTap`，214 行）。对带 `MosEventMarker.syntheticCustom` 标记的事件，注释写"跳过"，实际 `return nil` ——在 defaultTap 语义下这是**删除事件**。录制期间若 `executeCustom` 正在释放虚拟修饰键（合成 flagsChanged），该事件被吞，系统修饰键状态卡死（用户表现：录完快捷键后 ⌘/⌥ 像被按住）。ButtonCore 对同一 marker 是 `return Unmanaged.passUnretained(event)` 放行，两处语义不一致。
- **修复步骤**：
  1. 将 `return nil` 改为 `return Unmanaged.passUnretained(event)`（跳过录制处理但放行事件），与 ButtonCore 语义对齐。
  2. 补回归测试：录制中注入带 syntheticCustom 标记的 flagsChanged，断言事件被放行且不进入录制结果。
- **验证**：`InputProcessorTests` + 新增测试；手动：绑定一个含修饰键的自定义动作，触发它的同时开始录制，确认修饰键不卡死。

### P0-9 系统快捷键合成事件缺 marker → 可能被二次匹配

- **位置**：`Mos/Shortcut/ShortcutExecutor.swift:152-163`（`execute(code:flags:)`）；对照 `:304, 311`（executeCustom 已打标）。
- **上下文**：系统快捷键路径合成的 keyDown/keyUp 未调用 `setIntegerValueField(.eventSourceUserData, ...)` 打 `syntheticCustom` 标记。这些事件 post 后重新进入 ButtonCore 的 keyDown tap，被 `InputProcessor.process` 当作真实输入参与绑定匹配——若用户恰好把该组合绑定了其他动作，会二次触发甚至构造递归链。executeCustom 路径已有 marker，仅此路径遗漏。
- **修复步骤**：
  1. 在 keyDown/keyUp 两个事件 post 前补 `event.setIntegerValueField(.eventSourceUserData, value: MosEventMarker.syntheticCustom)`（与 304 行写法一致）。
  2. 确认 ButtonCore/InputProcessor 对该 marker 的跳过分支覆盖 keyDown/flagsChanged 两类事件。
  3. 补回归测试：执行系统快捷键后，断言 InputProcessor 未收到可匹配输入。
- **验证**：`ButtonBindingTests` `InputProcessorTests` `ScrollHotkeyTests`。

---

## P1 性能止血

### P1-1 LogiDebugPanel 日志无 DEBUG 门控，release 常驻开销

- **位置**：`Mos/Logi/Debug/LogiDebugPanel.swift:366-381`（`appendToBuffer` 无条件 `NotificationCenter.post`）；调用侧 `LogiDeviceSession.swift:2332-2339, 996-999`（TX/RX 热路径上先做 hex 字符串格式化 + `decodeReport` 再传入）。
- **上下文**：release 构建、调试面板从未打开的情况下，每条 HID++ 报文（含每次物理按键）都执行：hex `String(format:)` 拼接 → `decodeReport`（含字典构造）→ 通知派发 → 无界 logBuffer 追加。
- **修复步骤**：
  1. 给 `LogiDebugPanel.log` 加惰性接口：`static func log(_ message: @autoclosure () -> String, ...)`，内部先判 `isLoggingEnabled`（DEBUG 或面板已打开）再求值——调用侧的 hex 格式化随之免费惰性化。
  2. 调用侧凡是"先拼字符串再 log"的（2332-2339 等），把拼接移进 autoclosure。
  3. logBuffer 加环形上限（与 P0-4 同法，如 5000 条）。
- **验证**：Logi 测试类 + release 构建冒烟（`-configuration Release` build）；打开面板确认日志功能不回归。

### P1-2 每条日志新建 DateFormatter（×2 处）

- **位置**：`Mos/Logi/Debug/LogiDebugPanel.swift:466-470`；`Mos/Extension/CGEvent+Extensions.swift:234-239`（被 `MonitorViewController.swift:175-187` 逐事件调用）。
- **上下文**：`DateFormatter` 创建成本毫秒级，两处都在逐事件路径上每次调用新建。
- **修复步骤**：两处各提取 `private static let timestampFormatter: DateFormatter = { ... }()` 复用。DateFormatter 非线程安全，但两处调用都在主线程（已验证），加注释固化该前提即可。
- **验证**：Debug build；监视窗口/调试面板时间戳显示正常。

### P1-3 日志表 O(N²) 过滤

- **位置**：`Mos/Logi/Debug/LogiDebugPanel.swift:1451-1453`（`filteredLogEntries()` 全量 `enumerated().filter`）；被 `:2238`（numberOfRows）、`:2267-2269`（heightOfRow）、`:2361`（logCell）逐行调用。
- **上下文**：500 行日志整表 reload 时约 50 万次元素扫描 + 上千次数组分配。
- **修复步骤**：
  1. 把过滤结果缓存为实例属性 `cachedFilteredEntries`，仅在 logBuffer 追加、过滤条件变化、clear 时失效重建。
  2. `numberOfRows/heightOfRow/cell` 统一读缓存。
- **验证**：调试面板开启后连续按键产生日志，滚动/过滤切换流畅无卡顿。

### P1-4 spinner 每 tick 递归遍历视图树

- **位置**：`Mos/Logi/Debug/LogiDebugPanel.swift:1671-1687`（手写 `find(in:)` 递归找 tag 100/101 的 header label，每 80ms 两次）。
- **修复步骤**：与其他 label 一致，在构建 UI 时把两个 header label 存为实例属性直接引用（或退而求其次用系统 `contentView.viewWithTag(_:)`）。
- **验证**：面板 loading 状态 spinner 动画正常。

### P1-5 BrailleSpinner 单例永久空转

- **位置**：`Mos/Logi/Debug/BrailleSpinner.swift:27-37`。
- **上下文**：单例 `init` 即启动 80ms 重复 Timer 且无任何 stop/invalidate API。首次访问后即使调试面板已关闭、无任何 loading，也永久以 12.5Hz 发通知空转，阻止 App Nap、增加功耗。
- **修复步骤**：
  1. 改为引用计数式生命周期：`beginSpinning()` / `endSpinning()`（或按订阅者数自动启停），无订阅者时 `timer.invalidate()`。
  2. 面板关闭路径（windowWillClose）确保调用 end。
- **验证**：打开→关闭调试面板后，用 Instruments/Activity Monitor 确认无 12.5Hz 定时唤醒。

### P1-6 每条按键日志触发整表 reloadData

- **位置**：`Mos/Logi/Debug/LogiDebugPanel.swift:1721-1724`。
- **上下文**：日志通知处理器对所有 `.buttonEvent` 类型日志都调 `refreshControls()`（整表 `reloadData()`），每次物理按键产生 2-3 条日志 → 2-3 次全量刷新；注释表明本意只想匹配 divert 状态变化。
- **修复步骤**：收窄条件为仅 `entry.message.contains(" divert=")`（或给 LogEntry 加显式 `divertStateChanged` 类型，避免字符串嗅探）；再叠加 100ms coalesce（`DispatchWorkItem` 去抖）。
- **验证**：面板打开时快速连击鼠标键，UI 无闪烁卡顿，divert 开关状态仍实时更新。

### P1-7 ScrollFilter 每帧数组分配 + 3/5 死计算

- **位置**：`Mos/ScrollCore/ScrollFilter.swift:38-41`。
- **上下文**：每个 CVDisplayLink 帧为两轴各堆分配一个 5 元素数组 `[first, first+0.23*diff, first+0.5*diff, first+0.77*diff, nextValue]`，但整个类只消费 `[0]`（`value()`）与 `[1]`（下次 `polish` 的 first），`[2][3][4]` 是纯死计算；初始窗口 `[0.0, 0.0]` 与返回值结构还不一致。
- **修复步骤**：把曲线窗口改为两个标量字段（`current` / `next`，即原 [0] 与 [1] 的语义），删除 5 元素插值数组；保留滤波数学不变（`0.23/0.5/0.77` 系数本就未被消费）。若担心语义，先补一个对 `value()` 输出序列的特征测试再改。
- **验证**：`ScrollEventTests` `ScrollPhaseTests` + 手动滚动手感对比（平滑度不应有任何变化，因为被删的是死值）。

### P1-8 isTrackpad 采样缓存机制完全失效（误导性死机制）

- **位置**：`Mos/ScrollCore/ScrollEvent.swift:58-84`。
- **上下文**："每 3 次采样一次"的缓存：82 行把计数重置为 `samplingRate - 1`（=2），下次调用 `+1` 后必然 `3 % 3 == 0`，于是**每个事件都全量重算**，采样变量沦为误导。且这套 static 可变状态跨设备共享——若采样真生效，鼠标/触控板交替时反而会误判 2/3 的事件。
- **修复步骤**：直接删除采样计数机制，每事件老实计算（现状本来就是每次都算，删掉只是去掉假缓存）；若确有优化需求，正确做法是按 `CGEvent` 的 source/subtype 判断而非跨事件缓存。
- **验证**：`ScrollEventTests`；鼠标/触控板交替使用滚动行为正确。

### P1-9 按键绑定任何变更全表 reload + cell 重建完整菜单

- **位置**：`Mos/Windows/PreferencesWindow/ButtonsView/PreferencesButtonsViewController.swift:149, 178, 241, 247`；`ButtonTableCellView.swift:591-609`（每次 configure 重建 `ShortcutManager.buildShortcutMenu` + 重注册 3 个通知观察者）。
- **上下文**：单条绑定增/删/改都 `tableView.reloadData()`，每个 cell 的 configure 重建完整 NSMenu、重注册观察者、触发异步冲突刷新——改一行动作全表付出 N 倍代价。
- **修复步骤**：
  1. 增/删改用 `insertRows/removeRows/reloadData(forRowIndexes:columnIndexes:)` 精准更新。
  2. NSMenu 构建结果按（绑定内容+Logi 状态）缓存于 cell 或共享 menu 工厂，绑定未变时复用。
  3. cell 的观察者注册移到 `viewDidMoveToWindow`/复用生命周期，configure 只更新数据（与 P5-5 联动，此处先做最小改）。
- **验证**：Debug build + 手动：多行绑定下修改单行，其他行无闪烁；`ButtonBindingTests`。

### P1-10 cell 渲染路径主线程磁盘 I/O

- **位置**：`Mos/Windows/PreferencesWindow/ButtonsView/ActionDisplayResolver.swift:146-166`（`openTargetPresentation`）。
- **上下文**：每次 cell 渲染同步执行 `FileManager.fileExists` + `Bundle(url:)` 读 Info.plist + `workspace.icon(forFile:)`，叠加 P1-9 的全表 reload，每次变更每行都触发一轮文件系统访问。
- **修复步骤**：以 URL 为 key 缓存 presentation 结果（名称+图标），失效时机：绑定的 openTarget 变更；首次未命中可回主线程前在 utility 队列预热，占位图标先行。
- **验证**：`ButtonBindingTests`（ActionDisplayResolver 有测试引用）+ 手动确认图标/名称显示正常。

### P1-11 reporting 状态全量串行刷新

- **位置**：`Mos/Logi/Core/LogiDeviceSession.swift:2695-2713`（`refreshReportingState` 重置全部 `reportingQueried` 后从 0 逐个 `sendGetControlReporting`）。
- **上下文**：MX 系设备 discoveredControls 可达数十个，每个失败各吃 1s 超时串行推进；而冲突 UI 实际只消费**已绑定 CID** 的状态。
- **修复步骤**：给 refresh 加 scope 参数（默认仅已绑定 + 有 divert 意图的 CID）；全量刷新仅在调试面板显式触发。
- **验证**：`LogiDivertReconciliationTests` + 真机冲突指示器行为（可与 P0-5 同批真机验证）。

### P1-12 每次击键全量绑定匹配（低）

- **位置**：`Mos/ScrollCore/ScrollCore.swift:305-310, 383-389`。
- **上下文**：系统级每次 keyDown/flagsChanged/otherMouseDown 都 `InputEvent(fromCGEvent:)` 分配 + `getBestMatchingBinding` 全量匹配。
- **修复步骤**：绑定配置变更时才重建的匹配索引（按 keyCode 分桶字典），命中桶内再精确匹配；`InputEvent` 若仅用于匹配可下沉为轻量 struct。低优先级，可与 P5-3 一起做。
- **验证**：`InputProcessorTests` `ScrollCoreHotkeyTests`。

### P1-13 每滚动事件两次 URL→path 转换（低）

- **位置**：`Mos/ScrollCore/ScrollUtils.swift:111-114`（`getTargetApplication`）。
- **修复步骤**：在 `getRunningApplication` 的 PID 缓存翻新处（52 行）一并缓存 `bundlePath` / `executablePath` 字符串，`getTargetApplication` 读缓存。与 P0-1 的重构同文件，建议同 PR。
- **验证**：`ScrollEventTests` + 例外应用规则命中行为不变。

---

## P2 死代码清理（一个 PR 内完成，先跑全量测试基线）

统一修复步骤：删除前 `grep -rn "<符号名>" Mos MosTests tools` 复核零引用 → 删除 → 从 `project.pbxproj` 移除文件引用（整文件删除时）→ Debug build + 全量 MosTests。

| ID | 位置 | 内容与上下文 |
|---|---|---|
| P2-1 | `Mos/Utils/Archieve.swift` | 整类死代码（全仓无引用），类名拼错（Archive），内部含 force unwrap（112-115 行 `windowInfoList!`）与空 TODO 分支（59 行）。**整文件删除 + pbxproj 移除。** |
| P2-2 | `Mos/Utils/Utils.swift:250-265` | `Utils.debounce` 无调用方（grep 命中的只是 Keys 注释里的字样）。 |
| P2-3 | `Mos/ScrollCore/ScrollUtils.swift:19-27` | `isTargetChanged` + `previousScrollTargetProcessID`/`currentScrollTargetProcessID`（用 `Double` 存 PID，类型语义也是错的）无调用方。 |
| P2-4 | `Mos/Keys/KeyCode.swift:40-41` | `modifierRKeys` 命名右侧修饰键、内容却是左侧键（复制粘贴错误），且 `modifierLKeys`/`modifierRKeys` 均无调用——错误内容的陷阱死代码，两个都删。 |
| P2-5 | `Mos/Shortcut/SystemShortcut.swift:351-373` | `findShortcut` / `isSystemShortcut` / `allShortcutNames` 无调用；findShortcut 还是线性扫描 + 重复组合下结果不确定。 |
| P2-6 | `Mos/Windows/MonitorWindow/Logger.swift:101-137` | `getTabletEventLog` / `getTabletProximityLog` / `printLog`（函数体只剩注释）无调用。 |
| P2-7 | Toast 组件 | `ToastPanel.swift:436` `fireToast()`（无控件绑定该 selector）+ 360-368 空占位块；`ToastWindow.swift:19` `currentStackDirection`（只写不读的假状态同步，同时删 `ToastManager.swift:212` 的赋值）；`ToastWindow.swift:70` `containerWidth` 无引用。 |
| P2-8 | `Mos/ButtonCore/ButtonCore.swift:31, 74-82` | `flagsChanged` 掩码定义后未参与任何组合；`primaryMouseObservationCallBack` 回调体零副作用却为每次左/右键点击安装 listen-only tap。**注意**：设计文档称该观察者为 "future diagnostics" 预留——删除 tap 安装（真实运行时开销）但在 commit message 注明出处；若要保留则包 `#if DEBUG`。 |
| P2-9 | `Mos/Components/BrandTag.swift:120, 88` | `brandForAction` 无调用（死的兼容包装）；顺带将 `isLogiCode` 对 `LogiCenter.shared` 的直接依赖改为注入/参数化（Components 层不应依赖业务单例，属 P5-8 同类，此处顺手最小化）。 |
| P2-10 | `Mos/Logi/Debug/LogiSelfTestWizard.swift:23`；`LogiDebugPanel.swift:234-235` | `lastOutcome` 只写不读；`L.topRatio` / `L.devInfoH` 未引用。 |
| P2-11 | `Mos/Windows/PreferencesWindow/ApplicationView/PreferencesApplicationViewController.swift:209, 77-82` | 209 行同一值冗余双重比较（`result.rawValue == OK.rawValue && result == .OK`，留一个）；77-82 行 sheet 弹出前的无效 `tableView.reloadData()`（真正 reload 在 `appendApplicationWith`）。 |

---

## P3 DRY 收敛

### P3-1 LogiDeviceSession"discover-then-execute"模板 ×8

- **位置**：`Mos/Logi/Core/LogiDeviceSession.swift:1868-2051`（SmartShift、DPI 列表、DPI 循环、ChangeHost、HostCycle、HiRes、ScrollInvert、ThumbWheel、PointerSpeed）；`changeHostFeatureId` 还在 1937/1953 重复声明。
- **上下文**："featureIndex 命中→直接执行 / 未命中→`discoverFeature` 回调里逐字重复同一 body" 的模板复制 8 次，两段仅 toast 文案和 pending 标志名不同（对照 1981-1997 与 2000-2015）。
- **修复步骤**：
  1. 抽 `private func withFeature(_ featureId: UInt16, then action: @escaping (UInt8) -> Void)`：内部封装缓存命中/发现/失败 toast。
  2. 8 个执行器改为 `withFeature(Self.featureSmartShift) { idx in ... }` 单行调用。
  3. 此项是 P5-1 FeatureActionExecutor 的直接铺垫，抽象命名保持一致。
- **验证**：Logi 测试类全跑 + lint-logi-boundary.sh + 真机快捷键抽查。

### P3-2 sendRequest 两个 case 体逐字节相同

- **位置**：`LogiDeviceSession.swift:962-989`（`.bleDirect` 与 `.receiver` 分支均为 20 字节 long report 构造 + SetReport，仅注释不同）。
- **修复步骤**：合并为同一代码路径，分支仅决定注释中提到的目标索引字节（如确实无差异则完全合并），保留一条注释说明两种传输的报文结构恰好一致。
- **验证**：Logi 测试类 + 真机收发。

### P3-3 Logi 常量/字典散落重复

- **位置**：feature ID 一半在 `LogiDeviceSession.swift:217-221` 类常量、一半函数体内联（1870 `0x2110`、1898 `0x2201`、1937 `0x1814`）；vendor usage page 判定 `0xFF00||0xFF43||0xFFC0` 在 `isHIDPPCandidate` 与 `setup()`（290+853）两份；HID++ 1.0 错误名字典在 1494-1499 与 1745-1749 两处且每次调用重建字面量。
- **修复步骤**：全部收敛为 `private static let` 常量/字典（feature ID 统一进 217-221 的常量区；错误名字典提为 static 存储属性）。
- **验证**：Logi 测试类；纯常量搬移，风险极低。

### P3-4 handshake 终点三件套 ×3 + 幂等 setter 被绕过

- **位置**：`LogiDeviceSession.swift:1009-1012, 2654-2657, 2742-2747`（markHandshakeComplete + post reportingDidComplete + recompute 三件套重复三次）；`:1576-1577, 2902`（绕过 `markHandshakeComplete()` 直接赋值 `handshakeComplete = true`，丢失防重复 post 保护，与 1025-1030 的幂等实现不一致）。
- **修复步骤**：抽 `private func completeHandshakePhase()` 统一三件套；两处直接赋值改走该入口。
- **验证**：Logi 测试类 + 真机重连场景（通知不重复、不丢失）。

### P3-5 ShortcutExecutor 三段鼠标事件构造流水线

- **位置**：`Mos/Shortcut/ShortcutExecutor.swift:316-353`（executeCustomMouseButton）、`:358-`（executeMouseButton）、`:478-`（replayMouseEvent）；365-368 内联重复 529-533 的坐标函数。
- **上下文**："建 source → 建 CGEvent → session 管理 → setButtonNumber → flags → marker → post" 近乎相同的流水线写了三遍。
- **修复步骤**：
  1. 抽 `private func postMouseEvent(spec: MouseEventSpec, location: CGPoint, flags: CGEventFlags?, marker: Int64?, sessionID: UUID?) -> UUID?` 为唯一构造+post 通道。
  2. 三个入口只负责各自的参数组装。
  3. 坐标获取统一走 `currentMouseLocationForCGEvent()`（P0-6 修复后的版本）。
- **验证**：`ButtonBindingTests` `MouseInteractionSessionControllerTests` `InputProcessorTests`。

### P3-6 Logi 虚拟键码映射跨模块重复

- **位置**：`ShortcutExecutor.swift:459-476`（`mouseButtonNumberForTapReplay` 硬编码 1003-1007）vs `Mos/Logi/Core/LogiCIDDirectory.swift:339-341`（1003-1007 的定义源头）。
- **上下文**：Logi 侧改码此处静默失效——映射知识在两个模块各写一份。
- **修复步骤**：在键码定义源头（LogiCIDDirectory 或 `LogiStandardMouseButtonAlias`）导出 `virtualCode → systemButtonNumber` 的公开映射，ShortcutExecutor 查表；`2...20` 的普通按钮段保留本地处理但加命名常量。注意 lint-logi-boundary 对跨界访问的 allowlist，必要时经 `LogiCenter`/Integration 暴露。
- **验证**：`LogiStandardMouseButtonAliasTests` `ButtonBindingTests` + lint-logi-boundary.sh。

### P3-7 ShortcutManager 菜单构建重复

- **位置**：`Mos/Shortcut/ShortcutManager.swift:70-118`（buildShortcutMenu 内联分类循环）vs `:195-246`（addCategoryToMenu，几乎逐行相同）。
- **修复步骤**：buildShortcutMenu 改为循环调用 addCategoryToMenu；对齐两者当前的细微差异（如有）并以 addCategoryToMenu 为准。
- **验证**：Debug build + 手动打开按键动作菜单，分类/图标/可用性过滤一致。

### P3-8 symbolName 巨型 switch（数据写成代码）

- **位置**：`Mos/Shortcut/SystemShortcut.swift:68-165`（约 95 case）与 `:494-510`（categorySymbolName 同模式）。
- **修复步骤**：下沉为 `private static let symbolByIdentifier: [String: String]`，getter 变 `symbolByIdentifier[identifier] ?? "questionmark.circle"`。新增快捷键从"两处改 switch"变为"一处加字典行"。
- **验证**：Debug build + 抽查菜单图标渲染。

### P3-9 Toast dismiss 双胞胎

- **位置**：`Mos/Components/Toast/ToastManager.swift:139-190`（`dismiss(id:)` 与 `dismissOldest` 完整重复：invalidate timer → isDismissing → 淡出 → orderOut → remove → reposition，仅时长 0.3/0.2 不同）。
- **修复步骤**：抽 `private func dismissToast(at index: Int, duration: TimeInterval)`，两个公开入口只负责定位 index 与选时长；顺手统一两处时长是否本应一致。
- **验证**：`tools/regression/toast-regression-tests.swift` harness + 手动多 toast 叠放场景。

### P3-10 两个偏好 VC 三方法逐字重复 + 隐藏动画失效

- **位置**：`PreferencesButtonsViewController.swift:277-287` vs `PreferencesApplicationViewController.swift:123-133`（`toggleNoDataHint` / `updateViewVisibility` / `updateDelButtonState` 逐字相同）。
- **上下文**：除重复外，`view.isHidden = !visible; view.animator().alphaValue = ...` 先立即隐藏再动画，隐藏路径动画不可见（顺序 bug）。
- **修复步骤**：
  1. 抽到共享基类或 `NSViewController` extension（如 `TableEditingViewController` 协议 + 默认实现）。
  2. 修正动画顺序：显示时先 `isHidden = false` 再动画到 1；隐藏时动画到 0、completion 里再 `isHidden = true`（用 `NSAnimationContext.runAnimationGroup`）。
- **验证**：手动：两个列表增删至空/非空，提示视图淡入淡出可见。

### P3-11 Options 读取样板 ×4 + 三处同步维护

- **位置**：`Mos/Options/Options.swift:184-215`（"object==nil 用默认值否则 bool(forKey:)" 重复 4 次）；每个配置键需在 OptionItem 定义、readOptions、save(group:) 三处手工同步。
- **修复步骤**：
  1. 抽 `private func readBool(_ key: String, default: Bool) -> Bool`（以及按需的 readDouble/readInt），readOptions 收敛为逐行声明。
  2. （可选，向 P5-7 过渡）定义 `OptionEntry<T>`（key + default + keyPath）表驱动 read/save，消灭三处同步。P3 阶段做到第 1 步即可。
- **验证**：`OptionsButtonsLoaderTests` + 升级兼容抽查：用旧版本写入的 defaults 启动，配置不丢失（涉及持久化，按 code-map 要求补 canary 测试）。

### P3-12 AppDelegate 停机序列 ×3

- **位置**：`Mos/AppDelegate.swift:149-151, 199-201, 208-210`（`LogiCenter.stop / ScrollCore.disable / ButtonCore.disable` 三行重复三次）。
- **修复步骤**：抽 `private func suspendAllEngines(reason: String)`，三处调用并把 reason 记日志（顺带提升可诊断性）。
- **验证**：Debug build + 手动：锁屏/权限丢失/退出三条路径行为不变。

### P3-13 鼠标键显示名重复 + 未本地化兜底

- **位置**：`Mos/Windows/PreferencesWindow/ButtonsView/RecordedEvent.swift:56-66` vs `PreferencesScrollingViewController.swift:290-303`（同为 "Logi 名 → KeyCode.mouseMap → 🖱code 兜底"）。
- **修复步骤**：收敛到一处（建议 `KeyCode` 或 RecordedEvent 的静态方法）；`"Key \(code)"` / `"🖱\(code)"` 兜底文案改 `NSLocalizedString`（遵守 `LOCALIZATION.md`，用 `NSLocalizedString(_:comment:)` 而非 `String(localized:)`）。
- **验证**：Debug build + 录制无名键位显示正常；`.xcstrings` 增补对应 key。

### P3-14 LogiDebugPanel 内部重复三组

- **位置**：TX 日志 + `IOHIDDeviceSetReport` + 错误处理块在 `:1441-1448` 与 `:1359-1366` 逐字重复；日志文本格式化在 `:442-452` 与 `:1407-1415` 两份；6s/1s/0.5s 魔法延时 `asyncAfter` 兜底刷新在 6 处复制（745, 1278, 1283, 1288, 1293, 1338）。
- **修复步骤**：
  1. 抽 `private func sendReportLogged(_ report: [UInt8], to session: LogiDeviceSession)`。
  2. 导出与展示共用 `formatLogEntry(_:)`。
  3. 6 处延时刷新收敛为一个 `scheduleRefresh(after:)`（内部 coalesce，后调覆盖前调），常量命名；刷新目标锁定调度时的 session id，规避"届时选中的会话"竞态。
- **验证**：面板手动冒烟（发包、导出、切 slot 时刷新正确）。

---

## P4 最佳实践加固

### P4-1 生命周期覆写系统性缺 super 调用

- **位置**：`PreferencesButtonsViewController.swift:68,79`、`PreferencesApplicationViewController.swift:31,45`、`PreferencesScrollingViewController.swift:48`、`PreferencesGeneralViewController.swift:17`、`PreferencesTabViewController.swift:31`、`MonitorViewController.swift:38,44`。
- **上下文**：AppKit 文档要求 `viewDidLoad/viewWillAppear/...` 覆写必须调 super；`NSTabViewController` 等中间类依赖 super 链完成状态维护。
- **修复步骤**：逐处补 `super.xxx()` 于函数首行；顺手检查全仓其余 VC（`grep -n "override func view" -r Mos/Windows`）。
- **验证**：Debug build + 偏好设置各 tab 切换、监视窗口开关冒烟。

### P4-2 单例 init 未 private

- **位置**：`ScrollCore.swift:14-15`、`ScrollPoster.swift:15-16`、`ScrollPhase.swift:100-101`、`ScrollUtils.swift:14-15`（对照同模块正确示范 `ScrollDispatchContext.swift:51`）。
- **修复步骤**：四处 `init` 加 `private`；编译错误处即暴露隐藏的二次实例化（若有，逐个改为 `.shared`）。
- **验证**：Debug build + ScrollCore 测试类。

### P4-3 block observer token 丢弃（泄漏）

- **位置**：`LogiDebugPanel.swift:1075-1081`（frameDidChange 闭包强持有 toolbar/3 按钮，token 未存，视图永不释放；1770-1771 注释还错误声称会自动移除——block 式观察者**不会**自动移除）；`AppDelegate.swift:106-114`（app 生命周期对象，影响小但同模式）。
- **修复步骤**：
  1. token 存入 `private var observerTokens: [NSObjectProtocol]`，窗口关闭/deinit 时 `forEach(removeObserver)`。
  2. 布局逻辑本身建议改为 Auto Layout 约束或 `layout()` 覆写，消除对通知的依赖。
  3. 修正 1770-1771 错误注释。
- **验证**：反复开关调试面板，用 Memory Graph 确认面板对象释放。

### P4-4 HID 输入回调注册后从不注销（潜伏 use-after-free）⚠️ 真机验证

- **位置**：`LogiDeviceSession.swift:907-914, 916-942`（`IOHIDDeviceRegisterInputReportCallback` 传 `Unmanaged.passUnretained(self)` + 裸 buffer 指针）；`:281-284`（deinit 直接 `reportBufferPtr?.deallocate()`，teardown 只 invalidate timer）。
- **上下文**：当前靠"全部在 main runloop 同步执行"的时序偶然性避免悬垂指针；任何异步化/后台队列改动都会变成 use-after-free。
- **修复步骤**：
  1. `teardown()` 中先 `IOHIDDeviceRegisterInputReportCallback(device, buffer, length, nil, nil)` 注销回调（Apple 认可的 NULL 注销方式），再关闭设备，最后再允许 buffer 释放。
  2. deinit 断言 teardown 已执行（DEBUG precondition）。
  3. 在类头注释固化"回调生命周期 ⊆ session 生命周期"的不变量。
- **验证**：Logi 测试类 + 真机插拔/休眠唤醒循环（**需用户确认设备连接**）。

### P4-5 KeyRecorder 三处健壮性

- **位置**：`Mos/Keys/KeyRecorder.swift:234-238, 243, 533-538`（对照 124 行 guard）。
- **上下文**：(a) Interceptor 创建失败的 catch 只重置 `isRecording`，不移除已注册的 3 个观察者（143-162 行）、不隐藏已显示的 keyPopover、不回滚已开始的 `LogiCenter.beginKeyRecording()`（Logi 按键保持 divert）、不通知 delegate；(b) 243 行 `notification.object as! CGEvent` 强转（同文件 449 行已示范 `CFGetTypeID` 安全检查）；(c) `stopRecording` 用 0.5s 延迟重置 `isRecording/isRecorded`，与 `startRecording` 的 guard 形成竞态窗口——ESC 取消后 0.5s 内点录制静默失败。
- **修复步骤**：
  1. 抽 `private func cleanupRecordingSession()` 统一回滚（观察者、popover、Logi divert、delegate 通知），catch 与正常 stop 共用。
  2. 243 行改用 `CFGetTypeID` 检查后转换（复制 449 行模式）。
  3. 0.5s 延迟语义改为"抑制随后的合成事件"专用标志（如 `suppressUntil: Date`），`isRecording` 立即复位，让重新录制不受影响。
- **验证**：`InputProcessorTests` + 手动：无辅助功能权限时点录制（触发 catch 路径）UI 状态正确；快速 ESC→立即重录成功。

### P4-6 自检向导 stale 超时误杀后续步骤

- **位置**：`Mos/Logi/Debug/LogiSelfTestWizard.swift:169-173`。
- **上下文**：`asyncAfter(30s)` 超时闭包只检查 `pendingObserver != nil`——前一步 Skip/通过后，observer 被下一步的 Run 重新赋值，旧定时器看到非 nil 即判 fail 并摘掉**新**步骤的 observer。
- **修复步骤**：加代际计数 `waitGeneration`，闭包捕获发起时的值，触发时 `guard generation == self.waitGeneration` 才生效（或改用可 cancel 的 `DispatchWorkItem`，每次 endWait 时 cancel）。
- **验证**：手动跑自检向导：快速 Skip 多步后等待 30s+，后续步骤不被误判失败。

### P4-7 HID++ 错误一刀切 fail 全部 pending

- **位置**：`LogiDeviceSession.swift:2386-2390`（HID++ 2.0 错误已解析出 `originalFeatureIdx` 却无差别清空全部 pendingDiscovery）；`:1514-1519`（1.0 错误同样处理）。
- **修复步骤**：按错误报文中的 feature index / sub id 精确定位对应 pending 条目，只 fail 它；无法定位时才降级全清（保留现行为作 fallback 并记日志）。**注意**：若 P0-5 已将 discovery 串行化，此项自然简化为"只 fail 队头"，建议排在 P0-5 之后做。
- **验证**：Logi 测试类 + 用测试替身模拟"GetControlReporting 报错时并发 SmartShift discovery 存活"。

### P4-8 导出失败静默吞掉

- **位置**：`LogiDebugPanel.swift:1416`（`try? output.write(...)`）。
- **修复步骤**：改 do/catch，失败时 toast/alert 反馈（含错误描述），成功时可顺带在 Finder 中显示。
- **验证**：手动：导出到只读目录，看到失败提示。

### P4-9 Shortcut 相等性忽略 identifier

- **位置**：`Mos/Shortcut/SystemShortcut.swift:168-176`；已知碰撞 `getInfo` vs `italic`（均 ⌘+34，249 行注释自认冲突）；`displayShortcut` 只能靠 `count == 1` 兜底（580 行）。
- **修复步骤**：
  1. Equatable/Hashable 纳入 `identifier`。
  2. 全仓审查依赖旧相等语义的调用点（菜单选中态、去重）：需要"按键组合等价"的场合显式提供 `hasSameKeyCombination(as:)`。
  3. **持久化兼容检查**：确认 identifier 不参与已存档编码路径的相等性判断（code-map 将 shortcut identifier 列为持久化敏感项），补 canary 测试。
- **验证**：`ButtonBindingTests` `ScrollHotkeyTests` + 旧配置加载兼容测试。

### P4-10 extractRegexMatches 参数被遮蔽

- **位置**：`Mos/Utils/Utils.swift:165-167`（函数体第一行 `let pattern = #"\/?.*\.app"#` 遮蔽同名参数，传什么都被忽略；现有调用点恰好都传同一 pattern 才未暴露）。
- **修复步骤**：删除遮蔽行，让参数生效；或若该函数本就只服务 .app 匹配，删掉 pattern 参数并改名 `extractAppPathMatch(from:)`，二选一（推荐后者，语义诚实）。
- **验证**：新增单测覆盖两个现有调用点的输入输出。

### P4-11 UI 层 force cast / force unwrap 清理

- **位置与修复**：
  - `PreferencesScrollingWithApplicationViewController.swift:34`：`prepare(for:)` 无差别 `as!` 且不检查 segue identifier → `guard segue.identifier == ..., let vc = segue.destinationController as? ... else { return }`；15 行 `private var parentTableRow: Int!` 评估改 `Int?` + 使用点 guard。
  - `PreferencesApplicationViewController.swift:163`：`cell.subviews[0] as! NSButton` → `as?` + guard；`:208` `view.window!` → `guard let window = view.window`。
  - `MonitorViewController.swift:63,162`：`notification.object as! CGEvent` → `as?` guard（任何第三方以同名通知 post 非 CGEvent 即崩溃）。
  - `AdaptivePopover.swift:28`：`subviews.first!` → guard 降级。
  - `Utils.swift:105-111`：`Bundle.main.bundleIdentifier!` → `??` 兜底；111 行 NSLog 格式串无占位符（`processIdentifier` 参数永远不输出）→ 补 `%d` 或删参数。
- **验证**：Debug build + 各窗口冒烟。

### P4-12 PreferencesTabViewController 重复 setup + 约束混用

- **位置**：`PreferencesTabViewController.swift:31-43`。
- **上下文**：一次性 setup 写在 `viewDidAppear`（每次窗口重新显示都执行）：清空根视图全部约束、重复 addSubview；`backgroundVisualEffectView` 未设 `translatesAutoresizingMaskIntoConstraints = false` 就同时用 frame + anchor，autoresizing 隐式约束与显式约束共存。
- **修复步骤**：
  1. setup 移到 `viewDidLoad` 或加 `didSetup` 一次性标志。
  2. 补 `translatesAutoresizingMaskIntoConstraints = false`，删除 frame 预设与 `view.removeConstraints(view.constraints)`（暴力清约束会连 storyboard 约束一起清）。
- **验证**：偏好设置窗口反复开关、切 tab，无布局跳动/约束冲突日志。

### P4-13 syncViewWithOptions 读路径隐藏写副作用

- **位置**：`PreferencesScrollingViewController.swift:226-228`（"同步界面"函数里 `scroll.duration = resolvedDuration` 写回模型，经 didSet 触发 `Options.markChanged` 落盘）。
- **修复步骤**：把 duration 归一化逻辑移到写路径（读取/迁移配置时一次性 resolve），sync 函数保持只读；若归一化必须留此处，重命名并注释说明副作用。
- **验证**：`OptionsButtonsLoaderTests` + 打开滚动设置页不产生 defaults 写入（可用 `defaults read` 对比）。

### P4-14 Interceptor deinit 的 run loop 假设

- **位置**：`Mos/Utils/Interceptor.swift:48, 77, 113`（添加/移除 source 全用 `CFRunLoopGetCurrent()`，deinit 所在线程决定移除目标）。
- **修复步骤**：创建时保存 `runLoop = CFRunLoopGetCurrent()`，stop/deinit 统一对保存的 runLoop 操作；DEBUG 下断言 deinit 线程==创建线程作为过渡观测。
- **验证**：`InputProcessorTests` + 开关滚动/录制功能（Interceptor 生命周期最频繁的路径）。

### P4-15 魔法数字命名

- **位置**：`ScrollCore.swift:229`（dash 增幅 `5.0`）；`ScrollUtils.swift:65`（`"com.google.Chrome"` 内联在工具方法，ScrollPoster.stop 的收尾行为依赖它）。
- **修复步骤**：提为命名常量 `dashAmplificationFactor`、`chromeBundleID`（后者随 P0-1 的快照重构一并处理）。
- **验证**：Debug build。

---

## P5 结构重构（每项先出 design doc 再动工）

### P5-1 LogiDeviceSession（4105 行）拆分 ⚠️ 立项级

> **2026-07-10 更新**：master 合入接收器多设备 handoff（c48937f，设计文档 `docs/plans/2026-07-08-logi-receiver-multi-device-handoff.md`）后本节已按合并后现实刷新。原方案基于 3191 行单目标模型，已失效的部分见下方标注。

- **上下文**：全仓最大 god class（合并后 4105 行）：状态模型已按 slot 拆进 `PerSlotState`（handoff Phase 1 完成，等于替本项做了状态聚合地基），但 session 仍聚合 10 类职责；`pending*` 引用 92 处；**timer/DispatchWorkItem 机制 15 处并存**（discoveryTimer 5s、controlInfoQueryTimer+retryCounts 1s、reportingQueryTimer 1s、SetControlReporting ACK TTL 2s、BLE guard TTL 2s、receiver 枚举 asyncAfter 5s、divertReassertion 0.05s、takeover debounce 等）——是 P0-5 竞态的结构性根因。新增横切义务：`pumpPendingDivertQueue` 必须在每个发现/上报查询终点调用（漏一处 = 热插拔 slot 被永久搁置，真机踩过坑）——这是被挂起的 P3-4"handshake 终点语义"的第 4 个变体，状态机化的又一论据。
- **硬约束（handoff 文档 §2 性能红线，重构全程不可违反）**：不得新增任何周期性/重复 HID++ 活动（无 watchdog/pulse/keepalive/轮询）；每设备 discovery+divert 连接时 one-shot；所有 retarget/收敛动作加"已完成"守卫防振荡。判定标准：随时间反复发 HID++ 请求即踩线；仅在连接/断开/用户操作等离散事件上各做一次为安全。
- **拆分方案**（按现有内聚边界，均保持 main-thread 约束不变，建议按序各自一个 PR）：
  1. **HIDPPReportDecoder**：纯 debug 字符串解码，零状态依赖，最容易先切。
  2. **HIDPPTransport**：报文编码 + `IOHIDDeviceSetReport` + 设备开关/回调注册，持有 buffer 与 device（P4-4 的注销逻辑归它）；出站 `report[1]` 的 slot 归属（巡检游标 vs 接管 slot）在此层显式化。
  3. **HIDPPRequestPipeline**：统一 request-response 关联 + 超时/重试，吸收全部 timer/TTL 与 `pending*` 标志（P0-5 的 `FeatureDiscoveryQueue` 演进为此组件；跨 slot 的发现串行约束——IRoot 响应不回显 featureId——是其核心不变量）。
  4. **ReceiverEnumerator + TakeoverCoordinator**（原"ReceiverEnumerator 含自动 retarget"边界已失效——retarget 语义被 handoff 删除）：前者管槽位 ping/枚举/0xB5 设备信息；后者管接管集合（`receiverManagedSlots`/`pendingDivertSlots`/sweep/pump/takeover-debounce）与巡检游标（`deviceIndex`）的双概念模型。handoff 已有纯函数 `chooseReceiverTargetSlot`/`receiverDivertSlots`/`receiverConnectionNotificationAction`（带单测），迁移时保持纯函数形态。
  5. **ReprogDiscoveryStateMachine**：GetControlCount→ControlInfo→Reporting 三阶段链，操作 `PerSlotState`（容器已就位），产出 per-slot `discoveredControls`；吸收 P3-4 的 4 处终点语义（含 pump 义务）为显式状态机出口。
  6. **DivertCoordinator**：applyUsage/recording plan/reassert/BLE guard；纯函数部分（`targetCIDsForUsage` 等 static）已具备抽离条件。
  7. **FeatureActionExecutor**：依托 P3-1 的 `withFeature`；haptic/scrollForce/forceSensing 三个巡检 context 按 handoff §4.3 保持单值（绑定巡检游标），不进多设备管线。
  8. `*ForTests` 转发随各自 static 纯函数迁走，用 `@testable` 消除。
- **前置**：P0-5、P0-7、P3-1~3、P4-4、P4-7 已落地；P5-6 至少完成接口化（否则拆出的组件仍被 `.shared` 反向引用缠住）。**design doc 必须以 handoff 设计文档为输入。**
- **验证**：每步 Logi 全测试类 + lint-logi-boundary.sh + 真机全功能回归（divert、SmartShift、DPI、多主机切换、休眠唤醒，**新增：双鼠标同接收器 handoff 场景**；BLE 直连 0xFF 与单设备 receiver 行为不得回归），**需用户确认设备**。

### P5-2 LogiDebugPanel（3047 行）拆分

- **上下文**（2026-07-10 刷新：handoff + HAPTIC/ForceSensing/ScrollForce 合入后 2392→3047 行）：窗口/视图构建、HID++ 协议字典、日志缓冲与文件持久化、直接向硬件发包（`sendDebugPacket` 内 `IOHIDDeviceSetReport`）混在一个类；新增 haptic/scrollForce/forceSensing 三个 bespoke context UI + 4 个 feature 观察者，context 区抽离价值上升。
- **修复步骤**：拆为 `LogiDebugLogStore`（缓冲/过滤/导出，吸收 P1-1/1-3 的缓存）、`LogiDebugPacketService`（发包，走 P5-1 的 Transport 而非直接 SetReport）、`LogiDebugPanelWindow`（纯 UI）、feature context 区（haptic/scrollForce/forceSensing 滑杆与观察者）独立成可复用 section 构建器。P1-1~6 完成后此项工作量已显著缩小。
- **验证**：面板全功能手动清单（日志、过滤、导出、发包、自检入口、slot 切换/轻量巡检、haptic/force 滑杆）。

### P5-3 ScrollCore.scrollEventCallBack（142 行闭包）拆分

- **位置**：`ScrollCore.swift:53-195`。
- **修复步骤**：按现有注释段落拆为具名私有方法：合成事件识别 → 设备分类 → 远程桌面判断 → 配置解析 → 方向/归一化 → 平滑分发决策，闭包体收敛为按序调用。**热路径纪律**：只拆函数不引入新分配；用 `@inline(__always)` 敏感处标注；拆分前后用监视窗口对比事件处理无回归。
- **验证**：ScrollCore 全测试类 + 手动滚动手感对比。

### P5-4 handleInputReport（306 行）拆分

- **位置**：`LogiDeviceSession.swift:2328-2633`。
- **修复步骤**：改为"解析报文头 → 路由表分发"结构：receiver 1.0 / 2.0 错误 / IRoot / REPROG / 各 feature 响应各成一个 handler 方法；与 P5-1 步骤 3/5/7 天然对齐，建议并入 P5-1 执行而非单独做。
- **验证**：同 P5-1。

### P5-5 ButtonTableCellView（861 行）减负

- **上下文**：cell 承担冲突诊断（订阅 3 个 LogiCenter 通知，550-575 行，且每次 configure 重注册）、popover 生命周期、KeyRecorder 录制、NSMenu 构建、绑定副本变更。
- **修复步骤**：冲突状态订阅上移到 ViewController 层（一处订阅、diff 后精准刷新受影响行）；菜单构建交给共享工厂（P1-9 已铺垫）；cell 退化为展示 + 事件转发。
- **验证**：`ButtonBindingTests` + 手动：冲突指示器、录制、菜单全流程。

### P5-6 session↔manager↔center 循环耦合切断

- **位置**：`LogiDeviceSession.swift:314, 368, 2843, 2887-2893, 3130`（底层 session 反向调用 `LogiSessionManager.shared` 的 deliveryMode/recordExternalClear/recompute 与 `LogiCenter.shared` 的 registry/isRecording/externalBridge）。
- **修复步骤**：为 session 需要的上行能力定义窄协议（如 `LogiSessionEnvironment`：`deliveryMode(for:)`、`isRecording`、`notifyActivityChanged()`），由 manager 注入；session 不再 import 单例。这是 P5-1 所有组件可测试化的前提。
- **验证**：Logi 全测试类（测试替身直接实现该协议，测试代码同步简化）+ lint-logi-boundary.sh。

### P5-7 Options/Constants 全局耦合环

- **位置**：`Constants.swift:97`（willSet 内嵌 LoginServiceKit I/O 与 StatusItem 操作，`readingOptionsLock` 只抑制 didSet 不抑制 willSet，启动读配置即触发系统副作用）；`:131-178`（25+ 属性 didSet 硬编码回调 `Options.shared.markChanged`，配置类无法脱离单例实例化）。
- **修复步骤**：
  1. 副作用出模型：`autoLaunch` 等改为纯存储，登录项/StatusItem 操作移到 Options 的写路径或专门的 applier（订阅变更后执行）。
  2. `markChanged` 回调改为构造注入 `onChange: (ScrollContainer) -> Void`，Options 组装时传入自身方法；测试可传空闭包。
  3. 与 P3-11 的表驱动读写合流。
- **验证**：`OptionsButtonsLoaderTests` + 升级兼容 canary + 手动：开机自启开关、状态栏显隐行为不变。

### P5-8 ScrollCore 方向 facade + WindowManager 隐式耦合

- **位置**：窗口层直触内部单例：`Logger.swift:15-17`、`MonitorViewController.swift:52`、`PreferencesApplicationViewController.swift:227`（`ScrollUtils.shared.getRunningApplication` / `ScrollCore.shared.scrollEventMask` 等）——与 Logi 侧 facade+lint 的纪律不对称；`WindowManager.swift:55-62` 的 `hideWindow` 名不副实（只隐藏 Dock 图标+可选移除引用），且 `Utils.hideDockIcon`（Utils.swift:151）反向依赖 `WindowManager.shared.refs.count == 1` 魔法条件，正确性依赖调用顺序。
- **修复步骤**：
  1. 为窗口层需要的 ScrollCore 能力开 facade（如 `ScrollCoreMonitoring` 协议：事件流订阅、目标应用查询），窗口层只依赖协议。
  2. 仿 `lint-logi-boundary.sh` 增加 ScrollCore 边界 lint（可并入同脚本）。
  3. `hideWindow` 重命名/重实现为语义诚实的 API；Dock 图标显隐决策集中到 WindowManager 一处。
- **验证**：Debug build + 窗口开关/Dock 图标行为冒烟；新 lint 脚本纳入 CI/质量门槛文档。

---

## 附：执行协议

1. 领取一批 → 建分支 `quality/p<N>-<主题>` → 逐项修复并勾选索引表状态。
2. 每个 PR 附：改动了哪些 ID、跑过的验证命令与结果、真实剩余风险（遵守 `AGENTS.md` 汇报要求）。
3. P0-5、P1-11、P4-4、P5-1 涉及真机验证的，合并前向用户确认设备状态。
4. 严禁在 P0-P2 的小修中"顺手"开始 P5 的拆分；反向依赖已在各项"前置"中注明。
