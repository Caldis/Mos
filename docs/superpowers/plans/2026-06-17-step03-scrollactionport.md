# STEP 03: ScrollActionPort 断环 + 线程断言 + 热路径快照 — 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 引入 ScrollActionPort 协议打破 ScrollCore→InputProcessor→ShortcutExecutor→ScrollCore 三角循环；为核心域加主线程断言；ScrollPoster 热路径改读主线程捕获的配置快照。

**Architecture:** ShortcutExecutor 改依赖 `ScrollActionPort` 协议而非 `ScrollCore` 具体类型，ScrollCore 实现该协议并在启动期注入。`assertMainThread()` DEBUG 断言固化核心域主线程约定。ScrollPoster 在 `update()`（主线程、持 stateLock）捕获 `{simTrackpadEnabled, deadZone}` 快照，CVDisplayLink 线程在既有锁内只读快照。

**Tech Stack:** Swift 5 / AppKit / XCTest。规格见 `docs/superpowers/specs/2026-06-17-step03-scrollactionport-design.md`。

**约束提醒:**
- 最低 macOS 10.13，不可用 `@MainActor` / `String(localized:)`。
- 主 target 文件夹同步模式（增删文件免改 pbxproj）；**MosTests 显式引用模式（新测试文件必须登记 pbxproj，4 处）**。
- 不改任何 UserDefaults key / 动作标识符 / 持久化格式。
- 构建测试一律 `-scheme Debug`，禁止 `-target Mos`。
- 基线 master @ 59ef650。

---

### Task 1: ScrollActionPort 协议 + executor 脱钩 ScrollCore（TDD）

**Files:**
- Create: `Mos/Shortcut/ScrollActionPort.swift`
- Modify: `Mos/Shortcut/ShortcutExecutor.swift`（新增 weak 端口属性；line 206 改用端口）
- Modify: `Mos/ScrollCore/ScrollCore.swift`（conform 协议）
- Modify: `Mos/AppDelegate.swift`（启动期接线）
- Modify: `MosTests/InputProcessorTests.swift`（setUp 接线）
- Create: `MosTests/ScrollActionPortTests.swift`
- Modify: `Mos.xcodeproj/project.pbxproj`（登记新测试文件）

- [ ] **Step 1: 写失败测试 — 创建 `MosTests/ScrollActionPortTests.swift`**

```swift
import XCTest
@testable import Mos_Debug

/// 记录端口调用的测试替身, 证明 ShortcutExecutor 经协议派发, 不依赖 ScrollCore 具体类型。
private final class FakeScrollActionPort: ScrollActionPort {
    struct Call: Equatable { let role: ScrollRole; let isDown: Bool }
    var calls: [Call] = []
    func handleMosScrollAction(role: ScrollRole, isDown: Bool) {
        calls.append(Call(role: role, isDown: isDown))
    }
}

final class ScrollActionPortTests: XCTestCase {

    private var saved: ScrollActionPort?

    override func setUp() {
        super.setUp()
        saved = ShortcutExecutor.shared.scrollActionPort
    }

    override func tearDown() {
        ShortcutExecutor.shared.scrollActionPort = saved
        super.tearDown()
    }

    func testMosScrollAction_dispatchesToInjectedPort() {
        let fake = FakeScrollActionPort()
        ShortcutExecutor.shared.scrollActionPort = fake

        guard let action = ShortcutExecutor.shared.resolveAction(named: "mosScrollDash") else {
            return XCTFail("mosScrollDash 应可解析")
        }
        _ = ShortcutExecutor.shared.execute(action: action, phase: .down)
        _ = ShortcutExecutor.shared.execute(action: action, phase: .up)

        XCTAssertEqual(fake.calls, [
            .init(role: .dash, isDown: true),
            .init(role: .dash, isDown: false)
        ])
    }
}
```

- [ ] **Step 2: 登记 pbxproj（镜像 ScrollDispatchContextTests 的 4 处）**

`grep -n "ScrollDispatchContextTests.swift" Mos.xcodeproj/project.pbxproj` 得 4 行（PBXBuildFile / PBXFileReference / PBXGroup children / Sources）。每处旁复制一行，文件名替换为 `ScrollActionPortTests.swift`，UUID 用：
- BuildFile UUID: `D3A1B2C3D4E5F60718293A50`
- FileReference UUID: `D3A1B2C3D4E5F60718293A51`

PBXBuildFile 节示例：
```
		D3A1B2C3D4E5F60718293A50 /* MosTests/ScrollActionPortTests.swift in Sources */ = {isa = PBXBuildFile; fileRef = D3A1B2C3D4E5F60718293A51 /* MosTests/ScrollActionPortTests.swift */; };
```
PBXFileReference 节示例：
```
		D3A1B2C3D4E5F60718293A51 /* MosTests/ScrollActionPortTests.swift */ = {isa = PBXFileReference; includeInIndex = 1; lastKnownFileType = sourcecode.swift; path = MosTests/ScrollActionPortTests.swift; sourceTree = SOURCE_ROOT; };
```
PBXGroup children 与 Sources build phase 节各加对应的 `D3A1.../D3A1...` 行。

先 `grep -c "D3A1B2C3D4E5F60718293A5" Mos.xcodeproj/project.pbxproj` 确认为 0（无碰撞）。

- [ ] **Step 3: 跑测试确认编译失败（端口类型/属性未定义）**

Run: `xcodebuild -scheme Debug -destination 'platform=macOS' test -only-testing:MosTests/ScrollActionPortTests 2>&1 | grep -E "error:|cannot find" | head`
Expected: `cannot find type 'ScrollActionPort'` 及 `value of type 'ShortcutExecutor' has no member 'scrollActionPort'`

- [ ] **Step 4: 创建 `Mos/Shortcut/ScrollActionPort.swift`**

```swift
//
//  ScrollActionPort.swift
//  Mos
//  滚动动作端口: 解耦 ShortcutExecutor 对 ScrollCore 的具体依赖
//

import Foundation

/// ShortcutExecutor 通过此协议驱动 Mos 滚动热键 (dash/toggle/block) 状态,
/// 不直接依赖 ScrollCore, 从而打破
/// ScrollCore → InputProcessor → ShortcutExecutor → ScrollCore 三角循环。
/// ScrollCore 实现此协议, 由启动期 (AppDelegate / 测试 setUp) 注入。
protocol ScrollActionPort: AnyObject {
    func handleMosScrollAction(role: ScrollRole, isDown: Bool)
}
```

- [ ] **Step 5: ShortcutExecutor 新增端口属性 + 改 line 206**

`ShortcutExecutor` 类内 `init()` 之后新增：
```swift
    /// Mos 滚动动作端口 (启动期注入 ScrollCore.shared)。weak: 端口为永生单例, 避免强引用环。
    weak var scrollActionPort: ScrollActionPort?
```

line 206 `case .mosScroll(let role):` 分支：
```swift
        case .mosScroll(let role):
            scrollActionPort?.handleMosScrollAction(role: role, isDown: phase == .down)
            return .none
```

- [ ] **Step 6: ScrollCore conform 协议**

`Mos/ScrollCore/ScrollCore.swift` 类声明：
```swift
class ScrollCore: ScrollActionPort {
```
（`handleMosScrollAction(role:isDown:)` 已存在且签名匹配，无需改实现。）

- [ ] **Step 7: AppDelegate 启动期接线**

`applicationDidFinishLaunching` 中 `LogiCenter.shared.installBridge(LogiIntegrationBridge.shared)` 之后加：
```swift
        ShortcutExecutor.shared.scrollActionPort = ScrollCore.shared
```

- [ ] **Step 8: InputProcessorTests.setUp 接线**

`MosTests/InputProcessorTests.swift` setUp 末尾（line 20 之后、`}` 之前）加：
```swift
        ShortcutExecutor.shared.scrollActionPort = ScrollCore.shared
```

- [ ] **Step 9: 跑新测试 + mosScroll 回归确认通过**

Run: `xcodebuild -scheme Debug -destination 'platform=macOS' test -only-testing:MosTests/ScrollActionPortTests -only-testing:MosTests/InputProcessorTests 2>&1 | grep -E "Test Suite.*(passed|failed)|error:|TEST" | tail -8`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 10: 确认 executor 不再引用 ScrollCore 具体类型**

Run: `grep -n "ScrollCore" Mos/Shortcut/ShortcutExecutor.swift`
Expected: 仅 line 297 注释（无 `ScrollCore.shared` 调用）

- [ ] **Step 11: 构建 + Commit**

Run: `xcodebuild -scheme Debug -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`

```bash
git add Mos/Shortcut/ScrollActionPort.swift Mos/Shortcut/ShortcutExecutor.swift Mos/ScrollCore/ScrollCore.swift Mos/AppDelegate.swift MosTests/InputProcessorTests.swift MosTests/ScrollActionPortTests.swift Mos.xcodeproj/project.pbxproj
git commit -m "refactor(shortcut): ScrollActionPort 打破核心三角循环

ShortcutExecutor 改依赖 ScrollActionPort 协议而非 ScrollCore 具体类型,
ScrollCore 实现该协议并由启动期注入。打破
ScrollCore→InputProcessor→ShortcutExecutor→ScrollCore 三角 (架构评估 P1-2),
executor 的 mosScroll 派发现可用 fake 端口独立测试。

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: assertMainThread 核心域断言

**Files:**
- Modify: `Mos/Utils/Utils.swift`（新增顶层 `assertMainThread`）
- Modify: `Mos/InputEvent/InputProcessor.swift`（process / clearActiveBindings）
- Modify: `Mos/ScrollCore/ScrollCore.swift`（handleScrollHotkey / handleMosScrollAction）
- Modify: `Mos/ButtonCore/ButtonUtils.swift`（invalidateCache）

无独立单测（DEBUG assert，测试在主线程运行天然满足）；以全量回归不误触发为验证。

- [ ] **Step 1: Utils.swift 新增辅助函数**

`Mos/Utils/Utils.swift` 文件末尾（最后一个顶层声明之后）追加：
```swift
/// DEBUG 下断言当前在主线程; Release 零开销。
/// 核心事件域 (ScrollCore 热键状态 / InputProcessor 绑定表 / ButtonUtils 缓存) 约定主线程 only,
/// 当前所有 CGEventTap 与 IOHIDManager 回调均调度于主 RunLoop。固化该隐式约定 (架构评估 P2-1)。
@inline(__always)
func assertMainThread(_ message: @autoclosure () -> String = "must run on main thread",
                      file: StaticString = #fileID, line: UInt = #line) {
    #if DEBUG
    assert(Thread.isMainThread, message(), file: file, line: line)
    #endif
}
```

- [ ] **Step 2: InputProcessor 入口断言**

`func process(_ event: InputEvent) -> InputResult {` 首行加：
```swift
        assertMainThread()
```
`func clearActiveBindings() {` 首行加：
```swift
        assertMainThread()
```

- [ ] **Step 3: ScrollCore 入口断言**

`func handleMosScrollAction(role: ScrollRole, isDown: Bool) {` 首行加 `assertMainThread()`。
`func handleScrollHotkey(code: UInt16, isDown: Bool) -> Bool {` 首行加 `assertMainThread()`。

- [ ] **Step 4: ButtonUtils 入口断言**

`func invalidateCache() {` 首行加 `assertMainThread()`。

- [ ] **Step 5: 构建 + 全量测试确认不误触发**

Run: `xcodebuild -scheme Debug -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`

Run: `xcodebuild -scheme Debug -destination 'platform=macOS' test 2>&1 | grep -E "Test Suite 'MosTests.xctest'|error:|TEST " | tail -5`
Expected: `** TEST SUCCEEDED **`（无 assert 崩溃）

- [ ] **Step 6: Commit**

```bash
git add Mos/Utils/Utils.swift Mos/InputEvent/InputProcessor.swift Mos/ScrollCore/ScrollCore.swift Mos/ButtonCore/ButtonUtils.swift
git commit -m "refactor(core): assertMainThread 固化核心域主线程约定

InputProcessor.process/clearActiveBindings、ScrollCore.handleScrollHotkey/
handleMosScrollAction、ButtonUtils.invalidateCache 入口加 DEBUG-only 主线程断言,
固化当前隐式约定 (架构评估 P2-1); Release 零开销。

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: ScrollPoster 配置快照（TDD）

**Files:**
- Modify: `Mos/ScrollCore/ScrollPoster.swift`（ConfigSnapshot + 捕获 + 替换跨线程读 + DEBUG 钩子）
- Create: `MosTests/ScrollPosterConfigSnapshotTests.swift`
- Modify: `Mos.xcodeproj/project.pbxproj`（登记新测试文件）

- [ ] **Step 1: 写失败测试 — 创建 `MosTests/ScrollPosterConfigSnapshotTests.swift`**

```swift
import XCTest
@testable import Mos_Debug

final class ScrollPosterConfigSnapshotTests: XCTestCase {

    private var savedSim = false
    private var savedDead = 1.0
    private var savedApp: Application?

    override func setUp() {
        super.setUp()
        savedSim = Options.shared.scroll.smoothSimTrackpad
        savedDead = Options.shared.scroll.deadZone
        savedApp = ScrollCore.shared.application
    }

    override func tearDown() {
        Options.shared.scroll.smoothSimTrackpad = savedSim
        Options.shared.scroll.deadZone = savedDead
        ScrollCore.shared.application = savedApp
        super.tearDown()
    }

    /// 快照捕获后改动 live Options 不应影响已捕获的值 (证明快照而非实时读)
    func testConfigSnapshot_capturesValuesNotLiveReads() {
        ScrollCore.shared.application = nil
        Options.shared.scroll.smoothSimTrackpad = true
        Options.shared.scroll.deadZone = 7.0

        ScrollPoster.shared.captureConfigSnapshotForTests()

        // 改 live 值, 快照不应跟随
        Options.shared.scroll.smoothSimTrackpad = false
        Options.shared.scroll.deadZone = 1.0

        let snap = ScrollPoster.shared.configSnapshotForTests
        XCTAssertTrue(snap.simTrackpadEnabled, "simTrackpadEnabled 应为捕获时的 true")
        XCTAssertEqual(snap.deadZone, 7.0, "deadZone 应为捕获时的 7.0")
    }
}
```

- [ ] **Step 2: 登记 pbxproj（镜像 4 处）**

UUID：
- BuildFile UUID: `D3A1B2C3D4E5F60718293A60`
- FileReference UUID: `D3A1B2C3D4E5F60718293A61`

先 `grep -c "D3A1B2C3D4E5F60718293A6" Mos.xcodeproj/project.pbxproj` 确认为 0。按 Task 1 Step 2 同法镜像 `ScrollPosterConfigSnapshotTests.swift`。

- [ ] **Step 3: 跑测试确认编译失败**

Run: `xcodebuild -scheme Debug -destination 'platform=macOS' test -only-testing:MosTests/ScrollPosterConfigSnapshotTests 2>&1 | grep -E "error:|cannot find|has no member" | head`
Expected: `has no member 'captureConfigSnapshotForTests'` / `'configSnapshotForTests'`

- [ ] **Step 4: ScrollPoster 新增 ConfigSnapshot 与捕获**

`Mos/ScrollCore/ScrollPoster.swift` 在 `private var stateLock = os_unfair_lock_s()` 之后新增：
```swift
    // 滚动配置快照: 主线程在 update 时捕获, CVDisplayLink 线程只读, 避免热路径跨线程读 Options/ScrollCore
    private struct ConfigSnapshot {
        var simTrackpadEnabled: Bool
        var deadZone: Double
    }
    private var config = ConfigSnapshot(simTrackpadEnabled: false, deadZone: 1.0)
```

`update()` 内 `os_unfair_lock_lock(&stateLock)` + `defer { ... }` 之后、`self.duration = duration` 之前插入：
```swift
        // 捕获本次手势的配置快照 (主线程读 Options/ScrollCore, CVDisplayLink 线程只读)
        captureConfigSnapshotLocked()
```

在 `private extension ScrollPoster`（"数据处理及发送"）内新增（紧邻 resolveSimTrackpadEnabled 即可）：
```swift
    /// 主线程读取当前 (全局 / 例外应用) 配置存入快照。调用方须持有 stateLock。
    func captureConfigSnapshotLocked() {
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

- [ ] **Step 5: 替换 display-link 线程的跨线程读**

(a) `resolveSimTrackpadEnabled()` 整体改为：
```swift
    func resolveSimTrackpadEnabled() -> Bool {
        return config.simTrackpadEnabled
    }
```

(b) `processing()` 内 `let deadZone = Options.shared.scroll.deadZone` 改为：
```swift
        let deadZone = config.deadZone
```

(c) `stop()` 内 line 211-216 的：
```swift
        var enableSimTrackpad = Options.shared.scroll.smoothSimTrackpad
        if let application = ScrollCore.shared.application {
            enableSimTrackpad = application.inherit
                ? Options.shared.scroll.smoothSimTrackpad
                : application.scroll.smoothSimTrackpad
        }
```
改为：
```swift
        let enableSimTrackpad = config.simTrackpadEnabled
```

- [ ] **Step 6: 新增 DEBUG 测试钩子**

`ScrollPoster.swift` 既有 `#if DEBUG` 块（recordSkippedSyntheticEvent / diagnosticsSnapshot 所在，"滚动数据更新控制" extension 内）追加：
```swift
    func captureConfigSnapshotForTests() {
        os_unfair_lock_lock(&stateLock)
        captureConfigSnapshotLocked()
        os_unfair_lock_unlock(&stateLock)
    }
    var configSnapshotForTests: (simTrackpadEnabled: Bool, deadZone: Double) {
        os_unfair_lock_lock(&stateLock)
        defer { os_unfair_lock_unlock(&stateLock) }
        return (config.simTrackpadEnabled, config.deadZone)
    }
```
注意：`captureConfigSnapshotLocked` 定义在 `private extension`，与上述 DEBUG 钩子同文件同类型可访问（`private` 对同文件 extension 可见）。若编译报不可见，将 `captureConfigSnapshotLocked` 的 `private extension` 改为 `extension`（去 private），保持函数本身无显式修饰符（internal），同文件可调用。

- [ ] **Step 7: 跑新测试确认通过**

Run: `xcodebuild -scheme Debug -destination 'platform=macOS' test -only-testing:MosTests/ScrollPosterConfigSnapshotTests 2>&1 | grep -E "Test Case.*(passed|failed)|error:|TEST" | tail -5`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 8: 确认 ScrollPoster 非 DEBUG 路径不再跨线程读 Options/ScrollCore 配置**

Run: `grep -n "Options.shared.scroll\|ScrollCore.shared.application" Mos/ScrollCore/ScrollPoster.swift`
Expected: 仅剩 line 28 `duration` 初值（`Options.shared.scroll.durationTransition`）与 `captureConfigSnapshotLocked()` 内的主线程读；`processing()`/`stop()`/`resolveSimTrackpadEnabled()` 内不再出现

- [ ] **Step 9: ScrollPoster 回归 + Commit**

Run: `xcodebuild -scheme Debug -destination 'platform=macOS' test -only-testing:MosTests/ScrollPosterStateTests -only-testing:MosTests/ScrollPosterConfigSnapshotTests 2>&1 | grep -E "Test Suite.*(passed|failed)|TEST " | tail -5`
Expected: `** TEST SUCCEEDED **`

```bash
git add Mos/ScrollCore/ScrollPoster.swift MosTests/ScrollPosterConfigSnapshotTests.swift Mos.xcodeproj/project.pbxproj
git commit -m "refactor(scroll): ScrollPoster 热路径改读主线程配置快照

CVDisplayLink 线程原直接读 Options.scroll.{smoothSimTrackpad,deadZone} 与
ScrollCore.application (跨线程读共享单例, 架构评估 P1-3)。改为 update() 在主线程、
持 stateLock 捕获 {simTrackpadEnabled, deadZone} 快照, display-link 线程在既有锁内只读。
不新增锁; 手势内配置一致。

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: 终验与推送

- [ ] **Step 1: 全量测试**

Run: `xcodebuild -scheme Debug -destination 'platform=macOS' test 2>&1 | grep -E "Test Suite 'MosTests.xctest'|TEST " | tail -3`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 2: Logi 边界 lint（确认 ScrollRole 引用未越界）**

Run: `scripts/qa/lint-logi-boundary.sh`
Expected: `Lint passed`

- [ ] **Step 3: 推送**

```bash
git push origin master
```

- [ ] **Step 4: 人工验证路径记录（报告给用户，不可自动化）**

- 侧键/快捷键绑定 Mos 滚动动作（dash/toggle/block）实际触发滚动行为正确。
- simTrackpad 模式与普通模式下滚动收尾（动量结束/TrackingEnd）正常。
- 调整 deadZone 后滚动停止阈值符合预期。
