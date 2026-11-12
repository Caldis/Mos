# STEP 03 收尾: DGCharts 迁移 + ModifierFlagsProviding 端口 + 文档刷新 — 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans。checkbox 追踪。

**Goal:** ①Charts 4.1.0→DGCharts 5.1.0（保留调试图表功能，移除 swift-algorithms/swift-numerics 两个传递依赖）；②引入 ModifierFlagsProviding 端口切断 ShortcutExecutor↔InputProcessor 最后一条边（executor 完全无环）；③刷新 architecture.html SHEET 06 使其反映已完成项。

**Tech Stack:** Swift 5 / AppKit / XCTest / SwiftPM。基线 master @ 79e267c。

**调研结论（已验证）:**
- DGCharts 5.1.0 `Package.swift`：macOS 最低 `.v10_12`（兼容 10.13 硬约束）、**依赖数组为空**（5.x 移除 swift-algorithms，连带不再引入 swift-numerics）、模块/产品名 `DGCharts`（同仓库 danielgindi/Charts）。
- 仓库无任何 `import Algorithms/Numerics`（纯传递依赖，移除安全）。
- Monitor 仅用 `LineChartView/ChartDataEntry/LineChartDataSet/LineChartData`，4.x→5.x 这些 API 未变（5.0 仅改名 + 去依赖，无 API 破坏）。
- Charts 产品在 pbxproj 靠 UUID 链接，只需改 version 与 productName 两处功能值。

**约束:** macOS 10.13 最低；不可 `@MainActor`；MosTests 显式引用模式；构建测试用 `-scheme Debug`；用户明确要求**保留调试窗口图表功能**，本次只换底层依赖不改图表行为。

---

### Task A: Charts 4.1.0 → DGCharts 5.1.0 迁移

**Files:**
- Modify: `Mos.xcodeproj/project.pbxproj`（version + productName）
- Modify: `Mos/Windows/MonitorWindow/MonitorViewController.swift`（import）
- Regenerate: `Mos.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`（由 SPM 重解析）

- [ ] **Step 1: pbxproj 改版本要求 4.1.0 → 5.1.0**

`XCRemoteSwiftPackageReference "Charts"` 的 requirement：
```
			requirement = {
				kind = exactVersion;
				version = 4.1.0;
			};
```
→ `version = 5.1.0;`（保持 exactVersion，确定性，与原风格一致）

- [ ] **Step 2: pbxproj 改产品名 Charts → DGCharts**

`XCSwiftPackageProductDependency`：
```
		0BE5A295253A119C006D61C0 /* Charts */ = {
			isa = XCSwiftPackageProductDependency;
			package = 0BE5A294253A119C006D61C0 /* XCRemoteSwiftPackageReference "Charts" */;
			productName = Charts;
		};
```
仅将 `productName = Charts;` 改为 `productName = DGCharts;`（UUID 与注释 label 不动，Xcode 下次打开自动修正 label）。

- [ ] **Step 3: MonitorViewController import 改名**

`Mos/Windows/MonitorWindow/MonitorViewController.swift:10` `import Charts` → `import DGCharts`。

- [ ] **Step 4: 重解析 SPM 依赖并核验 Package.resolved**

Run: `xcodebuild -scheme Debug -destination 'platform=macOS' -resolvePackageDependencies 2>&1 | tail -5`
Expected: 成功解析。

Run: `grep -E "charts|algorithms|numerics" Mos.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`
Expected: charts 版本为 `5.1.0`；**swift-algorithms 与 swift-numerics 两项消失**。

- [ ] **Step 5: 构建（确认 DGCharts API 兼容）**

Run: `xcodebuild -scheme Debug -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`（若 API 报错，说明 5.x 有破坏点，需逐一适配——预期无）

- [ ] **Step 6: 全量测试 + Commit**

Run: `xcodebuild -scheme Debug -destination 'platform=macOS' test 2>&1 | grep -E "Test Suite 'MosTests.xctest'|TEST (SUCC|FAIL)" | tail -2`
Expected: `** TEST SUCCEEDED **`

```bash
git add Mos.xcodeproj/project.pbxproj Mos.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved Mos/Windows/MonitorWindow/MonitorViewController.swift
git commit -m "chore(deps): Charts 4.1.0 → DGCharts 5.1.0, 移除两个传递依赖

调试窗口图表功能保留 (用户反馈收集用)。DGCharts 5.x 依赖数组为空,
移除传递依赖 swift-algorithms + swift-numerics; 最低系统 macOS 10.12 仍兼容
10.13 约束; 模块改名 Charts → DGCharts, API 无破坏。

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

- [ ] **Step 7: 人工验证记录（不可自动化）**：Monitor 调试窗口（托盘 Option+点击 / DEBUG）折线图 6 条数据集正常绘制与刷新。

---

### Task B: ModifierFlagsProviding 端口（TDD）

**Files:**
- Create: `Mos/Shortcut/ModifierFlagsProviding.swift`
- Modify: `Mos/Shortcut/ShortcutExecutor.swift`（weak 属性 + 391/491 改端口）
- Modify: `Mos/InputEvent/InputProcessor.swift`（conform）
- Modify: `Mos/AppDelegate.swift`（接线）
- Modify: `MosTests/InputProcessorTests.swift`（setUp 接线）
- Modify: `MosTests/ScrollActionPortTests.swift`（追加 fake provider + 用例，免 pbxproj）

- [ ] **Step 1: 写失败测试 — 在 `MosTests/ScrollActionPortTests.swift` 追加**

文件顶部 FakeScrollActionPort 之后加：
```swift
/// 记录调用并返回固定 flags 的修饰键 provider 替身。
private final class FakeModifierFlagsProvider: ModifierFlagsProviding {
    let returnFlags: CGEventFlags
    var called = false
    init(returnFlags: CGEventFlags) { self.returnFlags = returnFlags }
    func combinedModifierFlags(physicalModifiers: CGEventFlags?) -> CGEventFlags {
        called = true
        return returnFlags
    }
}
```
`ScrollActionPortTests` 类内追加用例：
```swift
    func testCustomMouseButton_usesInjectedModifierFlagsProvider() {
        let fake = FakeModifierFlagsProvider(returnFlags: .maskShift)
        let savedProvider = ShortcutExecutor.shared.modifierFlagsProvider
        ShortcutExecutor.shared.modifierFlagsProvider = fake
        var capturedFlags: CGEventFlags?
        ShortcutExecutor.shared.setTestingMouseEventObserver { event in
            capturedFlags = event.flags
        }
        defer {
            ShortcutExecutor.shared.modifierFlagsProvider = savedProvider
            ShortcutExecutor.shared.clearTestingMouseEventObserver()
        }

        guard let action = ShortcutExecutor.shared.resolveAction(named: "custom::mouse:5:0") else {
            return XCTFail("custom::mouse:5:0 应解析为 customMouseButton")
        }
        _ = ShortcutExecutor.shared.execute(action: action, phase: .down)

        XCTAssertTrue(fake.called, "executor 应调用注入的 modifierFlagsProvider")
        XCTAssertEqual(capturedFlags, .maskShift, "合成事件 flags 应取自注入 provider 的返回值")
    }
```

- [ ] **Step 2: 跑测试确认编译失败**

Run: `xcodebuild -scheme Debug -destination 'platform=macOS' test -only-testing:MosTests/ScrollActionPortTests 2>&1 | grep -E "error:|cannot find|has no member" | head`
Expected: `cannot find type 'ModifierFlagsProviding'` / `has no member 'modifierFlagsProvider'`

- [ ] **Step 3: 创建 `Mos/Shortcut/ModifierFlagsProviding.swift`**

```swift
//
//  ModifierFlagsProviding.swift
//  Mos
//  修饰键端口: 解耦 ShortcutExecutor 对 InputProcessor 的具体依赖
//

import Cocoa

/// ShortcutExecutor 合成键鼠事件时, 通过此协议获取 (物理 + 虚拟) 合并修饰键,
/// 不直接依赖 InputProcessor, 从而切断 ShortcutExecutor↔InputProcessor 双向边,
/// 使 executor 仅依赖协议 (配合 ScrollActionPort) 完全无环。
/// InputProcessor 实现此协议, 由启动期 (AppDelegate / 测试 setUp) 注入。
protocol ModifierFlagsProviding: AnyObject {
    func combinedModifierFlags(physicalModifiers: CGEventFlags?) -> CGEventFlags
}
```

- [ ] **Step 4: ShortcutExecutor 新增 weak 属性 + 替换 391/491**

`scrollActionPort` 声明之后新增：
```swift
    /// 修饰键 provider (启动期注入 InputProcessor.shared)。weak: provider 为永生单例。
    weak var modifierFlagsProvider: ModifierFlagsProviding?
```
391 与 491 两处 `event.flags = InputProcessor.shared.combinedModifierFlags(physicalModifiers: X)` 改为（X 分别为 `inputModifiers` / `context.modifiers`）：
```swift
        event.flags = modifierFlagsProvider?.combinedModifierFlags(physicalModifiers: X)
            ?? X
            ?? CGEventSource.flagsState(.combinedSessionState)
```
（fallback: provider 未接线时退化为物理修饰键, 不崩不静默错位。）

- [ ] **Step 5: InputProcessor conform**

`class InputProcessor {` → `class InputProcessor: ModifierFlagsProviding {`（已有 `combinedModifierFlags(physicalModifiers:)` 方法，签名匹配，无需改实现）。

- [ ] **Step 6: AppDelegate 接线**

`ShortcutExecutor.shared.scrollActionPort = ScrollCore.shared` 之后加：
```swift
        ShortcutExecutor.shared.modifierFlagsProvider = InputProcessor.shared
```

- [ ] **Step 7: InputProcessorTests.setUp 接线**

`ShortcutExecutor.shared.scrollActionPort = ScrollCore.shared` 之后加：
```swift
        ShortcutExecutor.shared.modifierFlagsProvider = InputProcessor.shared
```

- [ ] **Step 8: 跑测试确认通过**

Run: `xcodebuild -scheme Debug -destination 'platform=macOS' test -only-testing:MosTests/ScrollActionPortTests -only-testing:MosTests/InputProcessorTests 2>&1 | grep -E "Test Suite.*(passed|failed)|error:|TEST (SUCC|FAIL)" | tail -8`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 9: 确认 executor 不再引用 InputProcessor**

Run: `grep -n "InputProcessor" Mos/Shortcut/ShortcutExecutor.swift`
Expected: 仅注释（如 552 行调用栈说明）；无 `InputProcessor.shared` 调用

- [ ] **Step 10: 构建 + Commit**

Run: `xcodebuild -scheme Debug -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`

```bash
git add Mos/Shortcut/ModifierFlagsProviding.swift Mos/Shortcut/ShortcutExecutor.swift Mos/InputEvent/InputProcessor.swift Mos/AppDelegate.swift MosTests/InputProcessorTests.swift MosTests/ScrollActionPortTests.swift
git commit -m "refactor(shortcut): ModifierFlagsProviding 端口切断 executor↔InputProcessor 残留边

ShortcutExecutor 合成事件改经 ModifierFlagsProviding 协议获取合并修饰键,
不再引用 InputProcessor 具体类型。配合 ScrollActionPort, executor 现仅依赖协议,
完全脱离 ScrollCore/InputProcessor 两单例 (STEP 03 三角断环的收尾)。

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task C: architecture.html SHEET 06 刷新

**Files:** Modify `docs/architecture.html`

- [ ] **Step 1: 更新 SHEET 06 问题卡片状态**

将以下卡片标注为"已修复"（在 card-t 后追加 `<span>` 标记或调 sev 文案，保持蓝图风格）：
- P1-2（三角循环）→ 已由 ScrollActionPort + ModifierFlagsProviding 解决，executor 完全无环
- P1-3（Options 写放大/无订阅/热路径直读）→ 已由 STEP 02 订阅+脏组写 与 STEP 03 配置快照解决
- P2-1（线程约定两极）→ 已由 assertMainThread 固化
- P2-3（死代码 + Charts）→ ButtonFilter 已删；Charts 已迁 DGCharts 5.1.0 移除两传递依赖（图表功能按用户要求保留）
- P3-1（权限轮询 Timer）→ 已收编

具体做法：每张已修复卡片的 `sev` 徽标改为带删除线或追加 `✓ FIXED <commit>` 小标；不删除卡片内容（保留问题描述供追溯）。

- [ ] **Step 2: 更新 ROADMAP 区**

STEP 01/02/03 标记完成日期与提交；剩余仅 STEP 04（LogiDeviceSession，需设备）与 STEP 05（UI 代码化，长期）。

- [ ] **Step 3: HTML 结构完整性校验**

Run: 用 python 的 HTMLParser 跑标签平衡检查（同初版校验脚本），Expected: `OK — well-formed`

- [ ] **Step 4: Commit**

```bash
git add docs/architecture.html
git commit -m "docs(architecture): SHEET 06 刷新, 标记 P1-2/P1-3/P2-1/P2-3/P3-1 已修复

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task D: 终验与推送

- [ ] **Step 1:** `xcodebuild -scheme Debug -destination 'platform=macOS' test` → `** TEST SUCCEEDED **`
- [ ] **Step 2:** `scripts/qa/lint-logi-boundary.sh` → `Lint passed`
- [ ] **Step 3:** `git push origin master`
- [ ] **Step 4:** 汇报：DGCharts 迁移结果（依赖图变化）、executor 完全无环、文档刷新；人工验证路径（Monitor 图表、侧键合成事件修饰键）。
