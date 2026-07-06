# Options 订阅机制 + 脏组写入 & 无风险清理 — 设计文档

- 日期: 2026-06-11
- 来源: docs/architecture.html (MOS-ARCH-2026-06) SHEET 06 ROADMAP STEP 01/02
- 状态: 已获用户批准（按此设计执行）

## 背景与问题

持久化触发点分散且全量写放大：

1. `Constants.swift` 中 `OPTIONS_*_DEFAULT`（均为 class）约 26 个字段级 `didSet` 各自调用 `Options.shared.saveOptions()`，每次写入**全部**配置键（含 buttons 绑定 JSON 编码与 applications JSON 编码）。拖动滑杆期间每 tick 全量落盘一次。
2. `Application` 的 4 个属性 didSet、`EnhanceArray` observer 也直调 `saveOptions()`。
3. 无变更订阅机制：`ButtonUtils` 缓存失效靠 ButtonsVC 手动调用；Logi 用量推送（`LogiCenter.setUsage`）分散在 5 处 VC 手动调用（ButtonsVC:131-132、ScrollingVC pushCurrentScopeUsage、ScrollingWithApplicationVC:94/102、ApplicationVC:104），新增编辑路径漏调会静默破坏 divert。
4. `readingOptionsLock` 是布尔重入标志（非锁），仅防读取期间触发保存。

另有两项无风险清理：`ButtonFilter.swift` 全仓库零引用（死代码）；AppDelegate 启动路径创建的 10s 权限轮询 Timer 未存引用，`sessionDidResign` 无法取消，极端睡眠/切换序列下可叠加。

## 目标

- STEP 01: 删除死代码；权限轮询 Timer 统一由 `permissionRecoveryTimer` 持有。
- STEP 02: 引入按组变更通知 + 脏组持久化；央化 ButtonUtils 失效与 Logi 用量刷新，删除 5 处 VC 手动 setUsage 与 1 处手动 invalidateCache。

## 非目标（YAGNI）

- 不迁移 VC 的 `syncViewWithOptions()` UI 手动刷新（行为正确，仅冗余）。
- 不做热路径配置快照（属 ROADMAP 后续项）。
- 不做订阅注销机制（订阅者均为进程级单例，append-only 即可）。
- 不改任何 UserDefaults key 与数据格式（持久化兼容面零变更）。

## 设计

### STEP 01

1. 删除 `Mos/ButtonCore/ButtonFilter.swift`。主 target 为 Xcode 16 文件夹同步模式（PBXFileSystemSynchronizedRootGroup），删文件无需改 pbxproj。
2. `AppDelegate.startWithAccessibilityPermissionsChecker`：10s 轮询 Timer 创建前 `permissionRecoveryTimer?.invalidate()`，并将新 Timer 存入 `permissionRecoveryTimer`；命中权限分支已有的 invalidate + 置 nil 逻辑保持。

### STEP 02

#### OptionsGroup 与变更入口

```swift
enum OptionsGroup: CaseIterable { case general, update, scroll, buttons, application }
```

`Options` 新增：

- `func markChanged(_ group: OptionsGroup)`：主线程断言；`readingOptionsLock` 期间直接返回（读取期抑制通知与保存）；否则同步通知订阅者，并将 group 加入 `pendingSaveGroups`，用一次性 `DispatchQueue.main.async` 调度 flush（同一 runloop tick 内多次变更合并为一次写入）。
- `func observe(_ groups: Set<OptionsGroup>, handler: @escaping (OptionsGroup) -> Void)`：append-only 订阅。
- `func flushPendingSaves()`：逐脏组写入对应键；`AppDelegate.applicationWillTerminate` 调用兜底。
- `saveOptions()` 拆分为 `save(group:)` 五个分支（general→HideStatusItem；update→2 键；scroll→14 键含热键；buttons→saveButtonBindingsData；application→Allowlist+applications JSON）。`OptionsExist` 标记每次 flush 时写入。
- 首次启动播种路径（readOptions 入口处无 OptionsExist 时）保留**同步全量写**（`saveAllNow()`），避免异步 flush 导致随后的读取读到空默认值。
- XCTest 守卫（`AppRuntime.isRunningXCTest`）保留在实际写入函数内；DEBUG 下提供 flush 测试钩子。

#### 归属路由（身份判定）

`OPTIONS_SCROLL_DEFAULT` / `OPTIONS_BUTTONS_DEFAULT` 同时被全局配置与 per-app（`Application.scroll` / `Application.buttons`）复用，字段 didSet 无法静态得知归属。字段 didSet 改调 `Options.shared.markChanged(scrollContainer: self)` / `markChanged(buttonsContainer: self)`，由 Options 用 `=== shared.scroll` / `=== shared.buttons` 身份判定路由到 `.scroll`/`.buttons`，否则 `.application`。临时副本被误路由到 `.application` 仅造成一组键的多余写入，无正确性影响。

- `OPTIONS_GENERAL_DEFAULT` 字段 → `.general`（保留 willSet 副作用：launchAtStartup / StatusItem 显隐）
- `OPTIONS_UPDATE_DEFAULT` 字段 → `.update`
- `OPTIONS_APPLICATION_DEFAULT.allowlist`、`EnhanceArray` observer、`Application` 4 个属性 didSet → `.application`
- `Options` 组级 didSet（整对象替换场景）→ 对应组；为 `general`/`update` 补齐组级 didSet 以保持一致

#### 订阅者（仅系统级，两个）

1. `ButtonUtils.init` 订阅 `.buttons` → `invalidateCache()`。删除 ButtonsVC:129 手动调用；`Options.readOptions` 末尾的显式 invalidate 保留（读取期通知被抑制）。懒加载安全：实例不存在时缓存天然 `isDirty=true`。
2. `LogiUsageBootstrap.installOptionsObservers()`（AppDelegate 在 installBridge 后调用）订阅 `.buttons/.scroll/.application` → `refreshAll()`。配套改造：
   - `refreshAll()` 改为直读 `Options.shared.buttons.binding`（不经 ButtonUtils 缓存），消除对通知顺序的依赖；
   - 维护 `lastPushedAppPaths: Set<String>`，对已消失的 app path 推送空集（`setUsage(source:.appScroll(...), codes: [])`），修复删除应用后 appScroll 用量残留；
   - 删除 5 处 VC 手动 setUsage 调用（其变更路径均已被字段/observer didSet 覆盖：绑定数组赋值、全局/per-app 热键赋值、inherit 切换、应用增删）。

通知为同步派发，`UsageRegistry` 自带同 tick recompute 合并与不变推送去重，突发变更代价可控。

## 测试计划

- 新增 `MosTests/OptionsChangePropagationTests.swift`（MosTests 为显式引用模式，需登记 pbxproj）：
  - 订阅按组触发、不跨组误触发；
  - 身份路由：shared.scroll 字段变更 → `.scroll`；Application.scroll 字段变更 → `.application`；
  - readOptions 期间抑制通知；
  - 同 tick 多次 markChanged 合并为一次 flush（DEBUG 钩子观测）。
- 扩展 `LogiUsageBootstrapTests`：含 Logi 热键的 app 经 refreshAll 注册用量后，从列表移除再 refreshAll，断言 `LogiCenter.usages` 清空（teardown 恢复现场）。
- 既有回归：`OptionsButtonsLoaderTests`、`ButtonUtilsCacheTests`、`ScrollHotkeyTests`、`UsageRegistry*Tests` 必须全绿。

## 验证

- 每步独立 `xcodebuild -scheme Debug -configuration Debug -destination 'platform=macOS' build`；
- `xcodebuild -scheme Debug -destination 'platform=macOS' test`（相关类全量）；
- 触及 `Mos/Integration/` → 跑 `scripts/qa/lint-logi-boundary.sh`；
- 人工验证路径（不可自动化部分）：偏好面板改绑定/热键/应用列表后 divert 行为、滑杆拖动流畅性、权限撤销恢复流程。

## 风险与缓解

| 风险 | 缓解 |
| --- | --- |
| 通知顺序导致 refreshAll 读到陈旧缓存 | refreshAll 直读 Options，不依赖 ButtonUtils 缓存 |
| 首启播种异步化破坏默认值读取 | 播种路径保留同步全量写 |
| 退出时丢失未 flush 的脏组 | applicationWillTerminate 兜底 flush（窗口为毫秒级） |
| 删除 VC 手动 setUsage 后某变更路径未被 didSet 覆盖 | 已逐路径核对（见订阅者一节）；测试覆盖增删改 |
| 身份判定误路由临时对象 | 仅多写一组键，无正确性影响 |
