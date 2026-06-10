# Options 订阅 + 脏组写入 & 无风险清理 — 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 删除死代码与 Timer 隐患；为 Options 引入按组变更订阅与脏组合并写入，央化 ButtonUtils 缓存失效与 Logi 用量刷新。

**Architecture:** 持久化触发点从 ~30 处分散 `saveOptions()` 收敛为 `Options.markChanged(group)` 单入口：同步通知订阅者、脏组集合 + 同 tick 合并异步写入。scroll/buttons 容器被全局与 per-app 复用，用 `===` 身份判定归属组。两个系统级订阅者（ButtonUtils、LogiUsageBootstrap）替代 6 处 VC 手动调用。

**Tech Stack:** Swift 5 / AppKit / XCTest。规格见 `docs/superpowers/specs/2026-06-11-options-subscription-cleanup-design.md`。

**约束提醒:**
- 最低 macOS 10.13，不可用 `@MainActor` / `String(localized:)`。
- 主 target 是文件夹同步模式（增删文件免改 pbxproj）；**MosTests 是显式引用模式**（新测试文件必须登记 pbxproj）。
- 不改任何 UserDefaults key 与数据格式。
- 构建/测试一律 `-scheme Debug`，禁止 `-target Mos`。

---

### Task 1: 删除 ButtonFilter 死代码

**Files:**
- Delete: `Mos/ButtonCore/ButtonFilter.swift`

- [ ] **Step 1: 确认零引用（删除前最后核验）**

Run: `grep -rn "ButtonFilter" Mos/ MosTests/ Mos.xcodeproj/project.pbxproj | grep -v "ButtonCore/ButtonFilter.swift:"`
Expected: 无输出（exit code 1）

- [ ] **Step 2: 删除文件**

Run: `rm Mos/ButtonCore/ButtonFilter.swift`

- [ ] **Step 3: 构建验证**

Run: `xcodebuild -scheme Debug -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add -A Mos/ButtonCore/ButtonFilter.swift
git commit -m "refactor(buttons): 删除零引用的 ButtonFilter 死代码

全仓库 grep 零引用 (架构评估 P2-3); 主 target 为文件夹同步模式, 无需改 pbxproj。

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: 权限轮询 Timer 统一持有

**Files:**
- Modify: `Mos/AppDelegate.swift:170-181`（startWithAccessibilityPermissionsChecker 的 else 分支）

无法单元测试的原因：该逻辑由 NSWorkspace session 通知与真实 Accessibility 权限驱动，XCTest 下 `AppRuntime.shouldRunAppStartupSideEffects` 直接短路。人工验证路径：移除辅助功能授权启动 app → 出现引导窗口；授权后 10s 内核心启动；期间合盖休眠再唤醒不产生重复引导窗口。

- [ ] **Step 1: 修改 else 分支，存储并复用 permissionRecoveryTimer**

将 `AppDelegate.swift` 中：

```swift
            } else {
                // 如果应用不在辅助权限列表内, 则弹出欢迎窗口
                WindowManager.shared.showWindow(withIdentifier: WINDOW_IDENTIFIER.introductionWindowController, withTitle: "")
                // 启动定时器检测权限, 当拥有授权时启动滚动处理
                Timer.scheduledTimer(
                    timeInterval: 10.0,
                    target: self,
                    selector: #selector(startWithAccessibilityPermissionsChecker(_:)),
                    userInfo: nil,
                    repeats: true
                )
            }
```

改为：

```swift
            } else {
                // 如果应用不在辅助权限列表内, 则弹出欢迎窗口
                WindowManager.shared.showWindow(withIdentifier: WINDOW_IDENTIFIER.introductionWindowController, withTitle: "")
                // 启动定时器检测权限, 当拥有授权时启动滚动处理
                // 统一由 permissionRecoveryTimer 持有, 使 sessionDidResign 可取消, 避免反复休眠/切换用户时叠加
                permissionRecoveryTimer?.invalidate()
                permissionRecoveryTimer = Timer.scheduledTimer(
                    timeInterval: 10.0,
                    target: self,
                    selector: #selector(startWithAccessibilityPermissionsChecker(_:)),
                    userInfo: nil,
                    repeats: true
                )
            }
```

- [ ] **Step 2: 构建验证**

Run: `xcodebuild -scheme Debug -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add Mos/AppDelegate.swift
git commit -m "fix(app): 权限轮询 Timer 统一由 permissionRecoveryTimer 持有

原 10s 轮询 Timer 未存引用, sessionDidResign 无法取消, 反复休眠/切换用户可叠加多个轮询器 (架构评估 P3-1)。

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: OptionsGroup 变更订阅 + 脏组合并写入（核心）

**Files:**
- Modify: `Mos/Options/Options.swift`（新增 OptionsGroup/observe/markChanged/flush，拆分 saveOptions）
- Modify: `Mos/Utils/Constants.swift:94-218`（~26 个字段 didSet 改 markChanged）
- Modify: `Mos/Windows/PreferencesWindow/ApplicationView/Application.swift:16-30`（4 个 didSet）
- Modify: `Mos/AppDelegate.swift`（applicationWillTerminate 兜底 flush）
- Create: `MosTests/OptionsChangePropagationTests.swift`
- Modify: `Mos.xcodeproj/project.pbxproj`（登记新测试文件）

- [ ] **Step 1: 写失败测试 — 创建 `MosTests/OptionsChangePropagationTests.swift`**

```swift
import XCTest
@testable import Mos_Debug

final class OptionsChangePropagationTests: XCTestCase {

    /// 订阅只对命中的组触发
    func testObserveFiresForMatchingGroupOnly() {
        let options = Options()
        var received: [OptionsGroup] = []
        options.observe([.scroll]) { received.append($0) }
        options.markChanged(.scroll)
        options.markChanged(.buttons)
        XCTAssertEqual(received, [.scroll])
    }

    /// scroll 容器身份路由: 自身的 scroll → .scroll, 其他实例 (per-app) → .application
    func testScrollContainerIdentityRouting() {
        let options = Options()
        var received: [OptionsGroup] = []
        options.observe([.scroll, .application]) { received.append($0) }
        options.markChanged(scrollContainer: options.scroll)
        options.markChanged(scrollContainer: OPTIONS_SCROLL_DEFAULT())
        XCTAssertEqual(received, [.scroll, .application])
    }

    /// buttons 容器身份路由
    func testButtonsContainerIdentityRouting() {
        let options = Options()
        var received: [OptionsGroup] = []
        options.observe([.buttons, .application]) { received.append($0) }
        options.markChanged(buttonsContainer: options.buttons)
        options.markChanged(buttonsContainer: OPTIONS_BUTTONS_DEFAULT())
        XCTAssertEqual(received, [.buttons, .application])
    }

    /// 读取期间 (readingOptionsLock) 抑制通知
    func testMarkChangedSuppressedDuringRead() {
        let options = Options()
        var fired = false
        options.observe([.scroll]) { _ in fired = true }
        options.withReadingLockForTests {
            options.markChanged(.scroll)
        }
        XCTAssertFalse(fired)
        options.markChanged(.scroll)
        XCTAssertTrue(fired)
    }

    /// 同一 runloop tick 内多次变更合并为一次 flush, 且只含脏组
    func testSameTickChangesCoalesceIntoSingleFlush() {
        let options = Options()
        let flushed = expectation(description: "flush")
        var flushedGroups: Set<OptionsGroup> = []
        var flushCount = 0
        options.onFlushForTests = { groups in
            flushedGroups = groups
            flushCount += 1
            flushed.fulfill()
        }
        options.markChanged(.scroll)
        options.markChanged(.scroll)
        options.markChanged(.buttons)
        wait(for: [flushed], timeout: 2.0)
        XCTAssertEqual(flushCount, 1)
        XCTAssertEqual(flushedGroups, [.scroll, .buttons])
    }
}
```

- [ ] **Step 2: 登记 pbxproj（MosTests 是显式引用模式）**

在 `Mos.xcodeproj/project.pbxproj` 中 grep `ScrollDispatchContextTests.swift`，会命中 3 处（PBXBuildFile、PBXFileReference、Sources build phase；PBXGroup 若有第 4 处也照做）。在每处旁边复制该行并替换文件名为 `OptionsChangePropagationTests.swift`、两个 UUID 替换为新值：

- BuildFile UUID: `C7A1B2C3D4E5F60718293A4B`
- FileReference UUID: `C7A1B2C3D4E5F60718293A4C`

例（PBXBuildFile 节）：
```
		C7A1B2C3D4E5F60718293A4B /* MosTests/OptionsChangePropagationTests.swift in Sources */ = {isa = PBXBuildFile; fileRef = C7A1B2C3D4E5F60718293A4C /* MosTests/OptionsChangePropagationTests.swift */; };
```

- [ ] **Step 3: 跑测试确认编译失败（OptionsGroup 未定义）**

Run: `xcodebuild -scheme Debug -destination 'platform=macOS' test -only-testing:MosTests/OptionsChangePropagationTests 2>&1 | tail -5`
Expected: 编译错误 `cannot find type 'OptionsGroup'`

- [ ] **Step 4: 实现 Options.swift 核心机制**

在 `Options.swift` 的 `class Options` 定义前插入：

```swift
/// 配置分组: 变更通知与脏组写入的粒度
enum OptionsGroup: CaseIterable {
    case general, update, scroll, buttons, application
}
```

`class Options` 内（`preservedUnknownBindings` 声明之后）新增：

```swift
    // 变更订阅 (append-only; 订阅者均为进程级单例, 无注销需求)
    private var observers: [(groups: Set<OptionsGroup>, handler: (OptionsGroup) -> Void)] = []
    // 待写入的脏组与调度标志
    private var pendingSaveGroups: Set<OptionsGroup> = []
    private var saveFlushScheduled = false
    #if DEBUG
    /// 测试钩子: flush 发生时回调脏组集合 (XCTest 下真实写入被跳过, 用它观测合并行为)
    var onFlushForTests: ((Set<OptionsGroup>) -> Void)?
    /// 测试钩子: 在读取锁内执行 body, 验证抑制语义
    func withReadingLockForTests(_ body: () -> Void) {
        readingOptionsLock = true
        defer { readingOptionsLock = false }
        body()
    }
    #endif
```

`extension Options`（读取和写入）内新增：

```swift
    // MARK: 变更订阅与脏组写入

    /// 订阅指定组的变更 (同步派发, 主线程)
    func observe(_ groups: Set<OptionsGroup>, handler: @escaping (OptionsGroup) -> Void) {
        observers.append((groups: groups, handler: handler))
    }

    /// 变更入口: 通知订阅者并调度该组的延迟写入 (同 tick 合并)
    func markChanged(_ group: OptionsGroup) {
        assert(Thread.isMainThread, "Options.markChanged is main-thread-only")
        // 读取期间 (readOptions) 抑制通知与保存
        guard !readingOptionsLock else { return }
        for observer in observers where observer.groups.contains(group) {
            observer.handler(group)
        }
        pendingSaveGroups.insert(group)
        scheduleSaveFlush()
    }

    /// 身份路由: scroll 容器被全局配置与 per-app (Application.scroll) 复用
    func markChanged(scrollContainer: OPTIONS_SCROLL_DEFAULT) {
        markChanged(scrollContainer === scroll ? .scroll : .application)
    }
    /// 身份路由: buttons 容器被全局配置与 per-app (Application.buttons) 复用
    func markChanged(buttonsContainer: OPTIONS_BUTTONS_DEFAULT) {
        markChanged(buttonsContainer === buttons ? .buttons : .application)
    }

    private func scheduleSaveFlush() {
        guard !saveFlushScheduled else { return }
        saveFlushScheduled = true
        DispatchQueue.main.async { [weak self] in
            self?.flushPendingSaves()
        }
    }

    /// 写入所有脏组 (应用退出前由 AppDelegate 兜底调用)
    func flushPendingSaves() {
        saveFlushScheduled = false
        guard !pendingSaveGroups.isEmpty else { return }
        let groups = pendingSaveGroups
        pendingSaveGroups = []
        #if DEBUG
        onFlushForTests?(groups)
        #endif
        guard !AppRuntime.isRunningXCTest else { return }
        UserDefaults.standard.set("optionsExist", forKey: OptionItem.General.OptionsExist)
        for group in groups { save(group: group) }
    }
```

把现有 `saveOptions()` 函数体替换为按组写入的同步全量版本，并新增 `save(group:)`（**键与今天逐一对应，零增减**）：

```swift
    // 同步写入全部配置 (首启播种与遗留路径; 常规变更走 markChanged 的脏组合并写入)
    func saveOptions() {
        guard !AppRuntime.isRunningXCTest else { return }
        if !readingOptionsLock {
            UserDefaults.standard.set("optionsExist", forKey: OptionItem.General.OptionsExist)
            for group in OptionsGroup.allCases { save(group: group) }
        }
    }

    // 按组写入 UserDefaults
    private func save(group: OptionsGroup) {
        switch group {
        case .general:
            UserDefaults.standard.set(general.hideStatusItem, forKey: OptionItem.General.HideStatusItem)
        case .update:
            UserDefaults.standard.set(update.checkOnAppStart, forKey: OptionItem.Update.CheckOnAppStart)
            UserDefaults.standard.set(update.includingBetaVersion, forKey: OptionItem.Update.IncludingBetaVersion)
        case .scroll:
            UserDefaults.standard.set(scroll.smooth, forKey: OptionItem.Scroll.Smooth)
            UserDefaults.standard.set(scroll.reverse, forKey: OptionItem.Scroll.Reverse)
            UserDefaults.standard.set(scroll.reverseVertical, forKey: OptionItem.Scroll.ReverseVertical)
            UserDefaults.standard.set(scroll.reverseHorizontal, forKey: OptionItem.Scroll.ReverseHorizontal)
            saveScrollHotkey(scroll.dash, forKey: OptionItem.Scroll.Dash)
            saveScrollHotkey(scroll.toggle, forKey: OptionItem.Scroll.Toggle)
            saveScrollHotkey(scroll.block, forKey: OptionItem.Scroll.Block)
            UserDefaults.standard.set(scroll.step, forKey: OptionItem.Scroll.Step)
            UserDefaults.standard.set(scroll.speed, forKey: OptionItem.Scroll.Speed)
            UserDefaults.standard.set(scroll.duration, forKey: OptionItem.Scroll.Duration)
            UserDefaults.standard.set(scroll.deadZone, forKey: OptionItem.Scroll.DeadZone)
            UserDefaults.standard.set(scroll.smoothSimTrackpad, forKey: OptionItem.Scroll.SmoothSimTrackpad)
            UserDefaults.standard.set(scroll.smoothVertical, forKey: OptionItem.Scroll.SmoothVertical)
            UserDefaults.standard.set(scroll.smoothHorizontal, forKey: OptionItem.Scroll.SmoothHorizontal)
        case .buttons:
            saveButtonBindingsData()
        case .application:
            UserDefaults.standard.set(application.allowlist, forKey: OptionItem.Application.Allowlist)
            if let applicationsData = application.applications.json() {
                UserDefaults.standard.set(applicationsData, forKey: OptionItem.Application.Applications)
            } else {
                NSLog("Failed to serialize applications data, skipping save")
            }
        }
    }
```

注意：现行 `saveOptions()` 中 `durationBeforeSimTrackpadLock` 等若有遗漏键，以**现行 saveOptions 实际写的键**为准逐行搬运（搬运前 diff 核对一遍，确保零增减）。

`Options` 的 5 个组属性 didSet 统一为（general/update 今天没有 didSet，补齐）：

```swift
    // 常规
    var general = OPTIONS_GENERAL_DEFAULT() {
        didSet { markChanged(.general) }
    }
    // 更新
    var update = OPTIONS_UPDATE_DEFAULT() {
        didSet { markChanged(.update) }
    }
    // 滚动
    var scroll = OPTIONS_SCROLL_DEFAULT() {
        didSet { markChanged(.scroll) }
    }
    // 按钮绑定
    var buttons = OPTIONS_BUTTONS_DEFAULT() {
        didSet { markChanged(.buttons) }
    }
    // 应用
    var application = OPTIONS_APPLICATION_DEFAULT() {
        didSet { markChanged(.application) }
    }
```

`loadApplicationsData()` 中两处 `forObserver:` 改为：

```swift
            forObserver: { Options.shared.markChanged(.application) }
```

- [ ] **Step 5: 改写 Constants.swift 字段级 didSet**

`OPTIONS_GENERAL_DEFAULT`（保留 willSet 副作用）：

```swift
class OPTIONS_GENERAL_DEFAULT {
    // 自启
    var autoLaunch = false {
        willSet {Utils.launchAtStartup(on: newValue)}
        didSet {Options.shared.markChanged(.general)}
    }
    // 隐藏
    var hideStatusItem = false {
        willSet {newValue ? StatusItemManager.hideStatusItem() : StatusItemManager.showStatusItem()}
        didSet {Options.shared.markChanged(.general)}
    }
}
```

`OPTIONS_UPDATE_DEFAULT`：两个 didSet 改为 `Options.shared.markChanged(.update)`。

`OPTIONS_BUTTONS_DEFAULT`：

```swift
class OPTIONS_BUTTONS_DEFAULT: Codable {
    var binding:[ButtonBinding] = [] {
        didSet { Options.shared.markChanged(buttonsContainer: self) }
    }
}
```

`OPTIONS_SCROLL_DEFAULT`：全部 15 个字段 didSet 改为 `Options.shared.markChanged(scrollContainer: self)`（durationTransition 是计算属性不动）。

`OPTIONS_APPLICATION_DEFAULT`：

```swift
class OPTIONS_APPLICATION_DEFAULT {
    var allowlist = false {
        didSet {Options.shared.markChanged(.application)}
    }
    var applications = EnhanceArray<Application>(
        matchKey: "path",
        forObserver: {() in Options.shared.markChanged(.application)}
    )
}
```

- [ ] **Step 6: 改写 Application.swift 的 4 个 didSet**

`displayName` / `inherit` / `scroll` / `buttons` 的 `didSet { Options.shared.saveOptions() }` 全部改为 `didSet { Options.shared.markChanged(.application) }`。

- [ ] **Step 7: AppDelegate 退出兜底**

`applicationWillTerminate` 中 `ButtonCore.shared.disable()` 之后追加：

```swift
        // 写入尚未 flush 的脏配置组
        Options.shared.flushPendingSaves()
```

- [ ] **Step 8: 跑新测试**

Run: `xcodebuild -scheme Debug -destination 'platform=macOS' test -only-testing:MosTests/OptionsChangePropagationTests 2>&1 | tail -5`
Expected: `** TEST SUCCEEDED **`（5 个用例全过）

- [ ] **Step 9: 跑配置相关回归**

Run: `xcodebuild -scheme Debug -destination 'platform=macOS' test -only-testing:MosTests/OptionsButtonsLoaderTests -only-testing:MosTests/ScrollHotkeyTests -only-testing:MosTests/ButtonUtilsCacheTests 2>&1 | tail -5`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 10: Commit**

```bash
git add Mos/Options/Options.swift Mos/Utils/Constants.swift Mos/Windows/PreferencesWindow/ApplicationView/Application.swift Mos/AppDelegate.swift MosTests/OptionsChangePropagationTests.swift Mos.xcodeproj/project.pbxproj
git commit -m "feat(options): OptionsGroup 变更订阅 + 脏组合并写入

~30 处分散 saveOptions() 收敛为 markChanged(group) 单入口: 同步通知订阅者,
脏组集合同 tick 合并后只写变更组的键 (原先任一字段变更全量重写所有键)。
scroll/buttons 容器全局/per-app 复用, 以引用身份判定归属组。
首启播种保留同步全量写; 退出前 AppDelegate 兜底 flush。键与数据格式零变更。

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: ButtonUtils 缓存失效订阅化

**Files:**
- Modify: `Mos/ButtonCore/ButtonUtils.swift:20`（init 订阅）
- Modify: `Mos/Windows/PreferencesWindow/ButtonsView/PreferencesButtonsViewController.swift:129`（删手动调用）
- Test: `MosTests/ButtonUtilsCacheTests.swift`（追加用例，免 pbxproj）

- [ ] **Step 1: 写失败测试 — 在 `ButtonUtilsCacheTests.swift` 追加**

```swift
    /// 绑定变更经 Options 订阅自动失效缓存 (无需手动 invalidateCache)
    func testBindingMutationInvalidatesCacheViaSubscription() {
        let saved = Options.shared.buttons.binding
        defer { Options.shared.buttons.binding = saved }

        _ = ButtonUtils.shared.getButtonBindings()   // 先填充缓存
        Options.shared.buttons.binding = []
        XCTAssertTrue(ButtonUtils.shared.getButtonBindings().isEmpty,
                      "binding 置空后缓存应经订阅自动失效")
        Options.shared.buttons.binding = saved
        XCTAssertEqual(ButtonUtils.shared.getButtonBindings().count, saved.count)
    }
```

- [ ] **Step 2: 跑测试确认失败**

Run: `xcodebuild -scheme Debug -destination 'platform=macOS' test -only-testing:MosTests/ButtonUtilsCacheTests 2>&1 | tail -5`
Expected: 新用例 FAIL（缓存未失效，旧数据仍在）。注意：若此用例意外通过，检查是否别处仍有手动 invalidate 干扰，不许跳过本步。

- [ ] **Step 3: ButtonUtils.init 订阅**

```swift
    init() {
        // 绑定组变更时自动失效缓存 (订阅者为进程级单例, 无需注销)
        Options.shared.observe([.buttons]) { [weak self] _ in
            self?.invalidateCache()
        }
    }
```

- [ ] **Step 4: 跑测试确认通过**

Run: `xcodebuild -scheme Debug -destination 'platform=macOS' test -only-testing:MosTests/ButtonUtilsCacheTests 2>&1 | tail -5`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: 删除 ButtonsVC 手动失效调用**

`PreferencesButtonsViewController.syncViewWithOptions()` 中删除 `ButtonUtils.shared.invalidateCache()` 一行（其余暂留，Task 5 处理 setUsage 部分）。

- [ ] **Step 6: 回归 + Commit**

Run: `xcodebuild -scheme Debug -destination 'platform=macOS' test -only-testing:MosTests/ButtonUtilsCacheTests -only-testing:MosTests/OptionsChangePropagationTests 2>&1 | tail -5`
Expected: `** TEST SUCCEEDED **`

```bash
git add Mos/ButtonCore/ButtonUtils.swift Mos/Windows/PreferencesWindow/ButtonsView/PreferencesButtonsViewController.swift MosTests/ButtonUtilsCacheTests.swift
git commit -m "refactor(buttons): ButtonUtils 缓存失效改为订阅驱动

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 5: Logi 用量刷新央化（订阅驱动 + 移除 5 处手动 setUsage）

**Files:**
- Modify: `Mos/Integration/LogiUsageBootstrap.swift`（直读 Options + installOptionsObservers + 失效 app 清理）
- Modify: `Mos/AppDelegate.swift:127`（安装订阅）
- Modify: `Mos/Windows/PreferencesWindow/ButtonsView/PreferencesButtonsViewController.swift`（删 setUsage + collectButtonBindingCodes）
- Modify: `Mos/Windows/PreferencesWindow/ScrollingView/PreferencesScrollingViewController.swift`（删 pushCurrentScopeUsage 及其调用与 collect* 辅助）
- Modify: `Mos/Windows/PreferencesWindow/ScrollingView/PreferencesScrollingWithApplicationViewController.swift:94,102`（删手动 setUsage）
- Modify: `Mos/Windows/PreferencesWindow/ApplicationView/PreferencesApplicationViewController.swift:104`（删移除应用时的手动清理）
- Test: `MosTests/LogiUsageBootstrapTests.swift`（追加用例）

- [ ] **Step 0: 前置核验 EnhanceArray.remove(from:) 对不存在 key 是否安全**

Read `Mos/Utils/EnhanceArray.swift` 的 `remove(from:)` 实现。若未对 `dictionary[key] == nil` 做 guard，测试中的 defer 双重清理改为先判 `get(by: key) != nil`。

- [ ] **Step 1: 写失败测试 — 在 `LogiUsageBootstrapTests.swift` 追加**

```swift
    /// app 从列表移除后, refreshAll 应推送空集清理其 appScroll 用量 (防注册表残留)
    func testRefreshAllClearsUsageForRemovedApp() {
        let key = "/tmp/MosUsageBootstrapTest.app"
        let code: UInt16 = 1006  // Logi Back 的 MosCode (与 LogiCenterDeviceIntegrationTests 一致)
        let app = Application(path: key)
        app.inherit = false
        app.scroll.dash = ScrollHotkey(type: .mouse, code: code)
        Options.shared.application.applications.append(app)
        defer {
            if Options.shared.application.applications.get(by: key) != nil {
                Options.shared.application.applications.remove(from: key)
            }
            LogiUsageBootstrap.refreshAll()
        }

        LogiUsageBootstrap.refreshAll()
        XCTAssertTrue(LogiCenter.shared.usages(of: code).contains(.appScroll(key: key, role: .dash)),
                      "注册后应能查询到 appScroll 用量")

        Options.shared.application.applications.remove(from: key)
        LogiUsageBootstrap.refreshAll()
        XCTAssertFalse(LogiCenter.shared.usages(of: code).contains(.appScroll(key: key, role: .dash)),
                       "app 移除后用量应被清理")
    }
```

- [ ] **Step 2: 跑测试确认失败**

Run: `xcodebuild -scheme Debug -destination 'platform=macOS' test -only-testing:MosTests/LogiUsageBootstrapTests 2>&1 | tail -5`
Expected: 第二个断言 FAIL（旧 refreshAll 不清理已消失的 app source）

- [ ] **Step 3: 改写 LogiUsageBootstrap.swift**

文件头注释 `Preference-panel save paths push their own slice afterward.` 改为 `Options 订阅驱动: 绑定/热键/应用列表变更时整体刷新 (installOptionsObservers).`，实现改为：

```swift
enum LogiUsageBootstrap {

    /// 上次推送过 appScroll 用量的 app path, 用于 app 移除后推送空集清理注册表残留
    private static var lastPushedAppPaths: Set<String> = []

    /// 订阅 Options 变更, 集中刷新 Logi 用量 (替代偏好面板各处手动 setUsage)
    static func installOptionsObservers() {
        Options.shared.observe([.buttons, .scroll, .application]) { _ in
            refreshAll()
        }
    }

    static func refreshAll() {
        // 1. Button bindings (直读 Options, 不依赖 ButtonUtils 缓存失效的订阅顺序)
        let buttonCodes: Set<UInt16> = Set(
            Options.shared.buttons.binding
                .filter { $0.isEnabled && $0.triggerEvent.type == .mouse }
                .map { $0.triggerEvent.code }
                .filter { LogiCenter.shared.isLogiCode($0) }
        )
        LogiCenter.shared.setUsage(source: .buttonBinding, codes: buttonCodes)

        // 2. Global scroll
        for role in ScrollRole.allCases {
            let codes = globalScrollCodes(role: role)
            LogiCenter.shared.setUsage(source: .globalScroll(role), codes: codes)
        }

        // 3. App scroll
        var currentPaths: Set<String> = []
        let apps = Options.shared.application.applications
        for i in 0..<apps.count {
            guard let app = apps.get(by: i) else { continue }
            currentPaths.insert(app.path)
            for role in ScrollRole.allCases {
                let codes = appScrollCodes(app: app, role: role)
                LogiCenter.shared.setUsage(source: .appScroll(key: app.path, role: role), codes: codes)
            }
        }
        // 3b. 已移除 app 的用量清理
        for stalePath in lastPushedAppPaths.subtracting(currentPaths) {
            for role in ScrollRole.allCases {
                LogiCenter.shared.setUsage(source: .appScroll(key: stalePath, role: role), codes: [])
            }
        }
        lastPushedAppPaths = currentPaths
    }
```

（`globalScrollCodes` / `appScrollCodes` 两个私有函数原样保留。）

- [ ] **Step 4: AppDelegate 安装订阅**

`applicationDidFinishLaunching` 中：

```swift
        LogiCenter.shared.installBridge(LogiIntegrationBridge.shared)
        LogiUsageBootstrap.installOptionsObservers()
        LogiUsageBootstrap.refreshAll()
```

- [ ] **Step 5: 跑测试确认通过**

Run: `xcodebuild -scheme Debug -destination 'platform=macOS' test -only-testing:MosTests/LogiUsageBootstrapTests 2>&1 | tail -5`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 6: 删除 5 处 VC 手动 setUsage（变更路径已被 didSet 订阅覆盖）**

1. `PreferencesButtonsViewController.syncViewWithOptions()`：删除 Logi 注释 + `collectButtonBindingCodes()` 调用 + `LogiCenter.shared.setUsage(...)` 两行，函数体只剩 `Options.shared.buttons.binding = buttonBindings`；同时删除整个 `collectButtonBindingCodes()` 私有函数（先 grep 确认无其他调用）。
2. `PreferencesScrollingViewController`：grep `pushCurrentScopeUsage` 找到全部调用点删除，再删除 `pushCurrentScopeUsage` / `collectGlobalScrollCodes` / `collectAppScrollCodes` 三个私有函数（先 grep 确认无其他调用）。
3. `PreferencesScrollingWithApplicationViewController.swift:94,102` 两处 `LogiCenter.shared.setUsage(...)`：删除（含所在的死代码化辅助函数，若删空）。
4. `PreferencesApplicationViewController.swift:104` 移除应用时的 setUsage 清理循环：删除（由 refreshAll 的 stale 差集清理接管）。

删除后每个文件 grep `LogiCenter` 确认仅剩与 usage 无关的引用（如 ButtonsVC 的 BLE 诊断 Toast 调用保留）。

- [ ] **Step 7: 构建 + 全量相关回归 + 边界 lint**

Run: `xcodebuild -scheme Debug -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`

Run: `xcodebuild -scheme Debug -destination 'platform=macOS' test 2>&1 | tail -5`
Expected: `** TEST SUCCEEDED **`（全部 39+ 测试文件）

Run: `scripts/qa/lint-logi-boundary.sh`
Expected: `Lint passed`

- [ ] **Step 8: Commit**

```bash
git add Mos/Integration/LogiUsageBootstrap.swift Mos/AppDelegate.swift Mos/Windows/PreferencesWindow MosTests/LogiUsageBootstrapTests.swift
git commit -m "refactor(logi): Logi 用量刷新央化为 Options 订阅驱动

5 处偏好面板手动 setUsage 收敛为 LogiUsageBootstrap 订阅 .buttons/.scroll/.application
统一 refreshAll: 直读 Options 消除缓存顺序依赖, 并对已移除 app 推送空集,
修复删除应用后 appScroll 用量在注册表残留的隐患。

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 6: 终验

- [ ] **Step 1: 全量测试**

Run: `xcodebuild -scheme Debug -destination 'platform=macOS' test 2>&1 | tail -5`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 2: 人工验证路径记录（不可自动化部分，报告给用户）**

- 偏好面板拖动滑杆：滚动行为即时生效（didSet 仍同步通知），落盘合并为 tick 级。
- 录制/删除绑定、改热键、增删例外应用后：Logi divert 状态正确（需真实设备，留给用户确认）。
- 权限撤销→恢复流程；休眠唤醒不叠加引导窗口。
