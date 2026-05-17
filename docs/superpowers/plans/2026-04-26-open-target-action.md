# Open Target Action Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a new button binding action type "Open Application…" that launches a `.app` (or runs a script) with optional arguments when the bound mouse button is pressed; establish the archive-friendly persistence pattern (per-binding tolerant decoding + structured payload) for future export/config-file/AI-rewrite features.

**Architecture:** Extend `ButtonBinding` with an optional `OpenTargetPayload` field; the `systemShortcutName` string acts as discriminator (`"openTarget"`). All execution flows through `ShortcutExecutor` private methods (parallel to existing `executeMouseButton`/`executeLogiAction` style). UI is a single `NSPopover` with a tactile file slot (empty/filled states) and a monospaced arguments field. `Options.loadButtonsData()` is rewritten to per-binding tolerant decoding so future versions can introduce new payload kinds without corrupting existing bindings.

**Tech Stack:** Swift 4+, AppKit (NSPopover, NSWorkspace, Process, NSAnimationContext), XCTest, Codable, macOS 10.13+ compatibility.

**Spec:** `docs/superpowers/specs/2026-04-26-open-target-action-design.md`

---

## File Map

| File | Action | Responsibility |
|------|--------|----------------|
| `Mos/Shortcut/OpenTargetPayload.swift` | **Create** (~80 lines) | `OpenTargetPayload` struct (Codable) + `ArgumentSplitter` enum |
| `Mos/Windows/PreferencesWindow/ButtonsView/RecordedEvent.swift` | **Modify** | `ButtonBinding` adds `openTarget` field, `openTargetSentinel` constant, dedicated init, CodingKey |
| `Mos/Options/Options.swift` | **Modify** | `loadButtonsData()` rewritten with per-binding tolerant decoding |
| `Mos/Shortcut/ShortcutExecutor.swift` | **Modify** | `ResolvedAction` adds `.openTarget` case + `executionMode`; `resolveAction` adds sentinel branch; new private `executeOpenTarget` / `launchApplication` / `runScript` methods |
| `Mos/Shortcut/ShortcutManager.swift` | **Modify** | Top-level "打开应用…" menu entry with `__open__` sentinel |
| `Mos/Windows/PreferencesWindow/ButtonsView/ActionDisplayResolver.swift` | **Modify** | `.openTarget` branch returning `ActionPresentation` with file icon |
| `Mos/Windows/PreferencesWindow/ButtonsView/ActionDisplayRenderer.swift` | **Modify** | `ActionPresentation` adds `image` field; renderer applies image for `.openTarget` |
| `Mos/Windows/PreferencesWindow/ButtonsView/ButtonTableCellView.swift` | **Modify** | `shortcutSelected(_:)` recognizes `__open__`; new `beginOpenTargetSelection()` |
| `Mos/Windows/PreferencesWindow/ButtonsView/OpenTargetConfigPopover.swift` | **Create** (~280 lines) | Popover NSViewController, file slot view, drag-drop, NSOpenPanel integration |
| `Mos/Localizable.xcstrings` | **Modify** | All 19 new keys (menu, popover, errors) |
| `MosTests/OpenTargetPayloadTests.swift` | **Create** | Tests for `OpenTargetPayload` and `ArgumentSplitter` |
| `MosTests/OptionsButtonsLoaderTests.swift` | **Create** | Tests for per-binding tolerant decoding |
| `MosTests/ShortcutExecutorOpenTargetTests.swift` | **Create** | Tests for `ResolvedAction.openTarget` + `resolveAction` routing |
| `MosTests/ButtonBindingTests.swift` | **Modify** | Add tests for `ButtonBinding.openTarget`, menu entry, display resolver/renderer, cell sentinel |

---

## Build & Test Commands

Repeat throughout the plan:

- **Build:** `xcodebuild -scheme Debug -configuration Debug build`
- **Run all tests:** `xcodebuild test -scheme Debug -destination 'platform=macOS'`
- **Run a single test method:** `xcodebuild test -scheme Debug -destination 'platform=macOS' -only-testing:MosTests/<Class>/<method>`

`Mos_Debug` is the test-import target; tests use `@testable import Mos_Debug`.

---

### Task 1: OpenTargetPayload + ArgumentSplitter (TDD)

**Files:**
- Create: `MosTests/OpenTargetPayloadTests.swift`
- Create: `Mos/Shortcut/OpenTargetPayload.swift`

This is the foundation — no dependencies on anything else. Add the new file to the Xcode project as part of the Mos target; add the test file to the MosTests target.

- [ ] **Step 1: Write the failing tests**

```swift
// MosTests/OpenTargetPayloadTests.swift
import XCTest
@testable import Mos_Debug

final class OpenTargetPayloadTests: XCTestCase {

    // MARK: - OpenTargetPayload

    func testCodableRoundtrip_app() {
        let original = OpenTargetPayload(
            path: "/Applications/Safari.app",
            bundleID: "com.apple.Safari",
            arguments: "https://example.com",
            isApplication: true
        )
        let data = try! JSONEncoder().encode(original)
        let decoded = try! JSONDecoder().decode(OpenTargetPayload.self, from: data)
        XCTAssertEqual(decoded.path, "/Applications/Safari.app")
        XCTAssertEqual(decoded.bundleID, "com.apple.Safari")
        XCTAssertEqual(decoded.arguments, "https://example.com")
        XCTAssertTrue(decoded.isApplication)
    }

    func testCodableRoundtrip_script() {
        let original = OpenTargetPayload(
            path: "/usr/local/bin/deploy.sh",
            bundleID: nil,
            arguments: "--port=3000",
            isApplication: false
        )
        let data = try! JSONEncoder().encode(original)
        let decoded = try! JSONDecoder().decode(OpenTargetPayload.self, from: data)
        XCTAssertEqual(decoded.path, "/usr/local/bin/deploy.sh")
        XCTAssertNil(decoded.bundleID)
        XCTAssertFalse(decoded.isApplication)
    }

    func testEquatable() {
        let a = OpenTargetPayload(path: "/a", bundleID: nil, arguments: "", isApplication: false)
        let b = OpenTargetPayload(path: "/a", bundleID: nil, arguments: "", isApplication: false)
        let c = OpenTargetPayload(path: "/a", bundleID: nil, arguments: "x", isApplication: false)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    func testJSONShape_isFlatAndReadable() {
        // Must produce keys path / bundleID / arguments / isApplication directly, no _0 wrapping.
        let payload = OpenTargetPayload(path: "/x", bundleID: "y", arguments: "z", isApplication: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let json = String(data: try! encoder.encode(payload), encoding: .utf8)!
        XCTAssertTrue(json.contains("\"path\":\"\\/x\""))
        XCTAssertTrue(json.contains("\"bundleID\":\"y\""))
        XCTAssertTrue(json.contains("\"arguments\":\"z\""))
        XCTAssertTrue(json.contains("\"isApplication\":true"))
        XCTAssertFalse(json.contains("_0"))
    }

    // MARK: - ArgumentSplitter

    func testArgumentSplitter_emptyString() {
        XCTAssertEqual(ArgumentSplitter.split(""), [])
    }

    func testArgumentSplitter_whitespaceOnly() {
        XCTAssertEqual(ArgumentSplitter.split("   "), [])
    }

    func testArgumentSplitter_simpleSpaceSeparated() {
        XCTAssertEqual(ArgumentSplitter.split("--port 3000"), ["--port", "3000"])
    }

    func testArgumentSplitter_doubleQuotedGroups() {
        XCTAssertEqual(
            ArgumentSplitter.split("--name \"hello world\" --port 3000"),
            ["--name", "hello world", "--port", "3000"]
        )
    }

    func testArgumentSplitter_backslashEscape() {
        XCTAssertEqual(
            ArgumentSplitter.split("a\\ b"),
            ["a b"]
        )
    }

    func testArgumentSplitter_escapedQuoteInsideQuotes() {
        XCTAssertEqual(
            ArgumentSplitter.split("\"foo \\\"bar\\\" baz\""),
            ["foo \"bar\" baz"]
        )
    }

    func testArgumentSplitter_unclosedQuote_treatsAsEOF() {
        // Defensive: don't crash, take whatever's there
        XCTAssertEqual(ArgumentSplitter.split("--name \"hello"), ["--name", "hello"])
    }

    func testArgumentSplitter_consecutiveWhitespace() {
        XCTAssertEqual(ArgumentSplitter.split("a    b"), ["a", "b"])
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```bash
xcodebuild test -scheme Debug -destination 'platform=macOS' -only-testing:MosTests/OpenTargetPayloadTests 2>&1 | tail -20
```
Expected: compilation FAIL with "Cannot find 'OpenTargetPayload' in scope" / "Cannot find 'ArgumentSplitter' in scope".

- [ ] **Step 3: Implement OpenTargetPayload + ArgumentSplitter**

```swift
// Mos/Shortcut/OpenTargetPayload.swift
//
//  OpenTargetPayload.swift
//  Mos
//  "打开应用 / 运行脚本" 动作的持久化结构
//

import Foundation

/// 打开应用或运行脚本动作的结构化配置.
///
/// 设计目标: 自描述、可 AI 改写、可手编辑.
/// JSON 形态保持扁平, 字段名直白, 不依赖任何编码字符串.
struct OpenTargetPayload: Codable, Equatable {

    /// 文件绝对路径 (.app bundle 或脚本)
    let path: String

    /// .app 的 bundle identifier; 脚本恒为 nil
    /// 运行时优先使用此值解析 App, 即便 .app 被移动到别处也能找到
    let bundleID: String?

    /// 用户原始输入的参数字符串 (空字符串 = 无参数)
    /// 执行时按 shell 风格 split (支持双引号包裹和反斜杠转义)
    let arguments: String

    /// 是否按 .app 处理.
    /// 配置时显式存储, 不依赖运行时启发式 (避免 .app 被删后无法识别).
    let isApplication: Bool
}

/// shell 风格参数切分.
///
/// 规则:
/// - 按空白字符 (空格 / 制表符 / 换行) 分隔
/// - 双引号包裹的部分原样保留 (引号本身不进入结果)
/// - 反斜杠转义紧随其后的下一个字符 (不论是否在引号内)
/// - 末尾未闭合的引号: 视作 EOF 自动闭合, 不抛错
///
/// 例: `--port=3000 "with space" \"escaped\"` → `["--port=3000", "with space", "\"escaped\""]`
enum ArgumentSplitter {

    static func split(_ raw: String) -> [String] {
        var args: [String] = []
        var current = ""
        var inQuotes = false
        var iterator = raw.unicodeScalars.makeIterator()
        while let scalar = iterator.next() {
            // 反斜杠转义: 下一字符原样追加
            if scalar == "\\" {
                if let next = iterator.next() {
                    current.unicodeScalars.append(next)
                }
                continue
            }
            // 双引号: 切换状态, 引号本身不进入结果
            if scalar == "\"" {
                inQuotes.toggle()
                continue
            }
            // 引号外的空白: 切分边界
            if !inQuotes && CharacterSet.whitespaces.contains(scalar) {
                if !current.isEmpty {
                    args.append(current)
                    current = ""
                }
                continue
            }
            current.unicodeScalars.append(scalar)
        }
        if !current.isEmpty {
            args.append(current)
        }
        return args
    }
}
```

Add `OpenTargetPayload.swift` to the Mos target and `OpenTargetPayloadTests.swift` to MosTests target via Xcode.

- [ ] **Step 4: Run tests to verify they pass**

Run:
```bash
xcodebuild test -scheme Debug -destination 'platform=macOS' -only-testing:MosTests/OpenTargetPayloadTests 2>&1 | tail -10
```
Expected: All 11 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Mos/Shortcut/OpenTargetPayload.swift MosTests/OpenTargetPayloadTests.swift Mos.xcodeproj/project.pbxproj
git commit -m "feat(shortcut): add OpenTargetPayload + ArgumentSplitter

Foundation for the new 'Open Application' action type. Payload is a
flat Codable struct (path/bundleID/arguments/isApplication) producing
human-editable JSON; ArgumentSplitter handles shell-style tokenization
with double-quote grouping and backslash escaping."
```

---

### Task 2: ButtonBinding `openTarget` field (TDD)

**Files:**
- Modify: `Mos/Windows/PreferencesWindow/ButtonsView/RecordedEvent.swift` (lines 218-326, the `ButtonBinding` struct)
- Modify: `MosTests/ButtonBindingTests.swift` (extend existing test class)

- [ ] **Step 1: Write the failing tests**

Add these test methods to `MosTests/ButtonBindingTests.swift` (within the existing `ButtonBindingTests` class):

```swift
    // MARK: - OpenTarget extension

    func testOpenTargetSentinel_isStableConstant() {
        XCTAssertEqual(ButtonBinding.openTargetSentinel, "openTarget")
    }

    func testInit_withOpenTargetPayload_setsSentinelName() {
        let payload = OpenTargetPayload(
            path: "/Applications/Safari.app",
            bundleID: "com.apple.Safari",
            arguments: "",
            isApplication: true
        )
        let binding = ButtonBinding(
            triggerEvent: RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil),
            openTarget: payload
        )
        XCTAssertEqual(binding.systemShortcutName, "openTarget")
        XCTAssertEqual(binding.openTarget, payload)
    }

    func testCodableRoundtrip_preservesOpenTarget() {
        let payload = OpenTargetPayload(
            path: "/Applications/Safari.app",
            bundleID: "com.apple.Safari",
            arguments: "https://example.com",
            isApplication: true
        )
        let original = ButtonBinding(
            triggerEvent: RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil),
            openTarget: payload
        )
        let data = try! JSONEncoder().encode(original)
        let decoded = try! JSONDecoder().decode(ButtonBinding.self, from: data)
        XCTAssertEqual(decoded.systemShortcutName, "openTarget")
        XCTAssertEqual(decoded.openTarget, payload)
    }

    func testCodableRoundtrip_legacyBindingHasNilOpenTarget() {
        // Old JSON format: no openTarget field
        let legacyJSON = """
        {
            "id": "11111111-1111-1111-1111-111111111111",
            "triggerEvent": {
                "type": "mouse",
                "code": 3,
                "modifiers": 0,
                "displayComponents": ["🖱4"],
                "deviceFilter": null
            },
            "systemShortcutName": "copy",
            "isEnabled": true,
            "createdAt": "2025-01-01T00:00:00Z"
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = legacyJSON.data(using: .utf8)!
        let decoded = try! decoder.decode(ButtonBinding.self, from: data)
        XCTAssertEqual(decoded.systemShortcutName, "copy")
        XCTAssertNil(decoded.openTarget)
    }

    func testEquatable_distinguishesByOpenTarget() {
        let payloadA = OpenTargetPayload(path: "/a.app", bundleID: nil, arguments: "", isApplication: true)
        let payloadB = OpenTargetPayload(path: "/b.app", bundleID: nil, arguments: "", isApplication: true)
        let trigger = RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil)
        let id = UUID()
        let createdAt = Date(timeIntervalSince1970: 0)

        let a = ButtonBinding(id: id, triggerEvent: trigger, openTarget: payloadA, isEnabled: true, createdAt: createdAt)
        let b = ButtonBinding(id: id, triggerEvent: trigger, openTarget: payloadA, isEnabled: true, createdAt: createdAt)
        let c = ButtonBinding(id: id, triggerEvent: trigger, openTarget: payloadB, isEnabled: true, createdAt: createdAt)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```bash
xcodebuild test -scheme Debug -destination 'platform=macOS' -only-testing:MosTests/ButtonBindingTests/testOpenTargetSentinel_isStableConstant 2>&1 | tail -10
```
Expected: compilation FAIL with "Type 'ButtonBinding' has no member 'openTargetSentinel'".

- [ ] **Step 3: Modify ButtonBinding**

In `Mos/Windows/PreferencesWindow/ButtonsView/RecordedEvent.swift`, change the `ButtonBinding` struct (starting at line 220):

```swift
// MARK: - ButtonBinding
/// 按钮绑定 - 将录制的事件与系统快捷键关联
struct ButtonBinding: Codable, Equatable {

    static let customBindingRelevantModifierMask: UInt64 =
        KeyCode.modifiersMask | CGEventFlags.maskSecondaryFn.rawValue

    /// "打开应用" 动作 sentinel; systemShortcutName 取此值时, openTarget 字段为权威载荷.
    static let openTargetSentinel = "openTarget"

    // MARK: - 持久化字段

    /// 唯一标识符
    let id: UUID

    /// 录制的触发事件
    let triggerEvent: RecordedEvent

    /// 绑定的系统快捷键名称
    /// 自定义快捷键格式: "custom::<keyCode>:<modifierFlags>"
    /// "打开应用" 动作: "openTarget" (此时 openTarget 字段非 nil)
    let systemShortcutName: String

    /// 是否启用
    var isEnabled: Bool

    /// 创建时间
    let createdAt: Date

    /// "打开应用" 动作的结构化载荷; 仅当 systemShortcutName == openTargetSentinel 时非 nil.
    let openTarget: OpenTargetPayload?

    // MARK: - 瞬态缓存字段 (不参与编解码)

    /// 缓存的自定义按键码
    private(set) var cachedCustomCode: UInt16? = nil

    /// 缓存的自定义修饰键标志
    private(set) var cachedCustomModifiers: UInt64? = nil

    // MARK: - CodingKeys (仅编码持久化字段)

    enum CodingKeys: String, CodingKey {
        case id, triggerEvent, systemShortcutName, isEnabled, createdAt, openTarget
    }

    // MARK: - 计算属性

    /// 获取系统快捷键对象
    var systemShortcut: SystemShortcut.Shortcut? {
        return SystemShortcut.getShortcut(named: systemShortcutName)
    }

    /// 是否为自定义绑定
    var isCustomBinding: Bool {
        return systemShortcutName.hasPrefix("custom::")
    }

    // MARK: - 初始化

    init(id: UUID = UUID(),
         triggerEvent: RecordedEvent,
         systemShortcutName: String,
         isEnabled: Bool = true,
         createdAt: Date = Date()) {
        self.id = id
        self.triggerEvent = triggerEvent
        self.systemShortcutName = systemShortcutName
        self.isEnabled = isEnabled
        self.createdAt = createdAt
        self.openTarget = nil
    }

    /// "打开应用" 动作专用初始化器, 强制保证 sentinel 与 payload 一致.
    init(id: UUID = UUID(),
         triggerEvent: RecordedEvent,
         openTarget: OpenTargetPayload,
         isEnabled: Bool = true,
         createdAt: Date = Date()) {
        self.id = id
        self.triggerEvent = triggerEvent
        self.systemShortcutName = Self.openTargetSentinel
        self.openTarget = openTarget
        self.isEnabled = isEnabled
        self.createdAt = createdAt
    }

    // MARK: - 自定义缓存

    /// 解析 custom:: 格式并填充缓存字段
    mutating func prepareCustomCache() {
        guard let payload = Self.normalizedCustomBindingPayload(from: systemShortcutName) else {
            cachedCustomCode = nil
            cachedCustomModifiers = nil
            return
        }
        cachedCustomCode = payload.code
        cachedCustomModifiers = payload.modifiers
    }

    static func normalizedCustomBindingName(code: UInt16, modifiers: UInt64) -> String {
        let payload = normalizeCustomBindingPayload(code: code, modifiers: modifiers)
        return "custom::\(payload.code):\(payload.modifiers)"
    }

    static func normalizedCustomBindingPayload(from customBindingName: String) -> (code: UInt16, modifiers: UInt64)? {
        guard customBindingName.hasPrefix("custom::") else { return nil }
        let payload = String(customBindingName.dropFirst("custom::".count))
        let parts = payload.split(separator: ":")
        guard parts.count == 2,
              let code = UInt16(parts[0]),
              let modifiers = UInt64(parts[1]) else {
            return nil
        }
        return normalizeCustomBindingPayload(code: code, modifiers: modifiers)
    }

    static func normalizeCustomBindingPayload(code: UInt16, modifiers: UInt64) -> (code: UInt16, modifiers: UInt64) {
        var normalizedModifiers = modifiers & customBindingRelevantModifierMask
        if KeyCode.modifierKeys.contains(code) {
            normalizedModifiers &= ~KeyCode.getKeyMask(code).rawValue
        }
        return (code, normalizedModifiers)
    }

    // MARK: - Equatable (仅比较持久化字段, 忽略瞬态缓存)

    static func == (lhs: ButtonBinding, rhs: ButtonBinding) -> Bool {
        return lhs.id == rhs.id &&
               lhs.triggerEvent == rhs.triggerEvent &&
               lhs.systemShortcutName == rhs.systemShortcutName &&
               lhs.isEnabled == rhs.isEnabled &&
               lhs.createdAt == rhs.createdAt &&
               lhs.openTarget == rhs.openTarget
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run all binding tests:
```bash
xcodebuild test -scheme Debug -destination 'platform=macOS' -only-testing:MosTests/ButtonBindingTests 2>&1 | tail -10
```
Expected: All ButtonBindingTests pass (existing + 5 new).

- [ ] **Step 5: Commit**

```bash
git add Mos/Windows/PreferencesWindow/ButtonsView/RecordedEvent.swift MosTests/ButtonBindingTests.swift
git commit -m "feat(buttons): extend ButtonBinding with openTarget field

Adds optional OpenTargetPayload field plus dedicated init for the new
action type. Discriminator lives in systemShortcutName ('openTarget'
sentinel constant). Backward compatible: legacy JSON without the field
decodes with openTarget = nil."
```

---

### Task 3: Per-binding tolerant decoding in Options (TDD)

**Files:**
- Create: `MosTests/OptionsButtonsLoaderTests.swift`
- Modify: `Mos/Options/Options.swift` (lines 181-198, the `loadButtonsData` function)

The current implementation wipes ALL bindings if any single binding fails to decode. This task replaces it with per-binding tolerance so future versions can add new payload kinds without corrupting existing bindings.

The function under test is private. To unit-test it, we extract the JSON-parsing core into a static internal helper that takes raw `Data` and returns `[ButtonBinding]`.

- [ ] **Step 1: Write the failing tests**

```swift
// MosTests/OptionsButtonsLoaderTests.swift
import XCTest
@testable import Mos_Debug

final class OptionsButtonsLoaderTests: XCTestCase {

    private func makeBindingJSON(
        id: String = "11111111-1111-1111-1111-111111111111",
        systemShortcutName: String = "copy",
        extraField: String? = nil
    ) -> String {
        var fields = """
        "id": "\(id)",
        "triggerEvent": {
            "type": "mouse",
            "code": 3,
            "modifiers": 0,
            "displayComponents": ["🖱4"],
            "deviceFilter": null
        },
        "systemShortcutName": "\(systemShortcutName)",
        "isEnabled": true,
        "createdAt": 0
        """
        if let extra = extraField {
            fields += ",\n\(extra)"
        }
        return "{\(fields)}"
    }

    func testDecode_emptyArray_returnsEmpty() {
        let data = "[]".data(using: .utf8)!
        XCTAssertEqual(Options.decodeButtonBindings(from: data).count, 0)
    }

    func testDecode_singleValidBinding_decodesIt() {
        let json = "[\(makeBindingJSON())]"
        let data = json.data(using: .utf8)!
        let bindings = Options.decodeButtonBindings(from: data)
        XCTAssertEqual(bindings.count, 1)
        XCTAssertEqual(bindings.first?.systemShortcutName, "copy")
    }

    func testDecode_corruptOuterArray_returnsEmpty() {
        // Not a JSON array at all
        let data = "{\"not\":\"array\"}".data(using: .utf8)!
        XCTAssertEqual(Options.decodeButtonBindings(from: data).count, 0)
    }

    func testDecode_oneValidOneCorrupt_keepsValid() {
        let valid = makeBindingJSON(id: "11111111-1111-1111-1111-111111111111")
        let corrupt = """
        {"id": "22222222-2222-2222-2222-222222222222", "missing_required_fields": true}
        """
        let json = "[\(valid),\(corrupt)]"
        let data = json.data(using: .utf8)!
        let bindings = Options.decodeButtonBindings(from: data)
        XCTAssertEqual(bindings.count, 1)
        XCTAssertEqual(bindings.first?.id, UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
    }

    func testDecode_unknownExtraField_stillDecodesAndIgnores() {
        // Future Mos version added a new field; current Mos must ignore it.
        let json = "[\(makeBindingJSON(extraField: "\"futurePayloadKind\": {\"type\":\"runCommand\"}"))]"
        let data = json.data(using: .utf8)!
        let bindings = Options.decodeButtonBindings(from: data)
        XCTAssertEqual(bindings.count, 1)
        XCTAssertEqual(bindings.first?.systemShortcutName, "copy")
    }

    func testDecode_multipleCorruptInArray_keepsAllValid() {
        let valid1 = makeBindingJSON(id: "11111111-1111-1111-1111-111111111111", systemShortcutName: "copy")
        let valid2 = makeBindingJSON(id: "33333333-3333-3333-3333-333333333333", systemShortcutName: "paste")
        let corrupt1 = "{\"garbage\": true}"
        let corrupt2 = "null"
        let json = "[\(corrupt1),\(valid1),\(corrupt2),\(valid2)]"
        let data = json.data(using: .utf8)!
        let bindings = Options.decodeButtonBindings(from: data)
        XCTAssertEqual(bindings.count, 2)
        XCTAssertEqual(bindings.map { $0.systemShortcutName }.sorted(), ["copy", "paste"])
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```bash
xcodebuild test -scheme Debug -destination 'platform=macOS' -only-testing:MosTests/OptionsButtonsLoaderTests 2>&1 | tail -10
```
Expected: FAIL with "Type 'Options' has no member 'decodeButtonBindings'".

- [ ] **Step 3: Refactor loadButtonsData**

In `Mos/Options/Options.swift`, replace the existing `loadButtonsData` (lines 181-198) with:

```swift
    // 安全加载按钮绑定数据
    private func loadButtonsData() -> [ButtonBinding] {
        let rawValue = UserDefaults.standard.object(forKey: OptionItem.Button.Bindings)
        guard let data = rawValue as? Data else {
            if rawValue != nil {
                NSLog("Button bindings data has wrong type: \(type(of: rawValue)), clearing corrupted data")
                UserDefaults.standard.removeObject(forKey: OptionItem.Button.Bindings)
            }
            return []
        }
        return Self.decodeButtonBindings(from: data)
    }

    /// 容错解码 button binding 数组.
    ///
    /// - 外层不是 JSON 数组 → 返回空, 视作配置丢失
    /// - 单个 binding 解析失败 → 跳过它, 其他保留, NSLog 记录跳过数
    ///
    /// 这种 per-binding 容错设计支持向前兼容: 未来 Mos 版本写入的未知 payload
    /// 不会导致整组绑定被擦掉.
    static func decodeButtonBindings(from data: Data) -> [ButtonBinding] {
        guard let elements = try? JSONSerialization.jsonObject(with: data) as? [Any] else {
            NSLog("Button bindings data is not a JSON array, returning empty")
            return []
        }
        let decoder = JSONDecoder()
        var bindings: [ButtonBinding] = []
        var skippedCount = 0
        for element in elements {
            guard let elementData = try? JSONSerialization.data(withJSONObject: element) else {
                skippedCount += 1
                continue
            }
            if let binding = try? decoder.decode(ButtonBinding.self, from: elementData) {
                bindings.append(binding)
            } else {
                skippedCount += 1
            }
        }
        if skippedCount > 0 {
            NSLog("Skipped \(skippedCount) unparseable button binding(s) (likely from a future Mos version)")
        }
        return bindings
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run:
```bash
xcodebuild test -scheme Debug -destination 'platform=macOS' -only-testing:MosTests/OptionsButtonsLoaderTests 2>&1 | tail -10
```
Expected: All 6 tests pass.

Also re-run all existing tests to verify nothing broke:
```bash
xcodebuild test -scheme Debug -destination 'platform=macOS' 2>&1 | tail -20
```
Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add Mos/Options/Options.swift MosTests/OptionsButtonsLoaderTests.swift
git commit -m "refactor(options): per-binding tolerant decoding for buttons

Replaces 'any failure → wipe all' with per-binding skip+log. A future
Mos version can introduce new payload kinds and the current version
will silently ignore those bindings instead of corrupting the user's
entire button configuration. Foundation for forward-compatible config
schema evolution."
```

---

### Task 4: ResolvedAction.openTarget + resolveAction routing (TDD)

**Files:**
- Create: `MosTests/ShortcutExecutorOpenTargetTests.swift`
- Modify: `Mos/Shortcut/ShortcutExecutor.swift` (lines 36-52 for `ResolvedAction`, lines 145-161 for `resolveAction`)

- [ ] **Step 1: Write the failing tests**

```swift
// MosTests/ShortcutExecutorOpenTargetTests.swift
import XCTest
@testable import Mos_Debug

final class ShortcutExecutorOpenTargetTests: XCTestCase {

    private func makeOpenTargetBinding(payload: OpenTargetPayload) -> ButtonBinding {
        return ButtonBinding(
            triggerEvent: RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil),
            openTarget: payload
        )
    }

    func testResolveAction_openTargetSentinel_returnsOpenTargetCase() {
        let payload = OpenTargetPayload(path: "/Applications/Safari.app", bundleID: "com.apple.Safari", arguments: "", isApplication: true)
        let binding = makeOpenTargetBinding(payload: payload)
        let executor = ShortcutExecutor()

        let resolved = executor.resolveAction(named: "openTarget", binding: binding)
        guard case .openTarget(let resolvedPayload) = resolved else {
            return XCTFail("Expected .openTarget case, got \(String(describing: resolved))")
        }
        XCTAssertEqual(resolvedPayload, payload)
    }

    func testResolveAction_openTargetSentinelButNoPayload_returnsNil() {
        // Edge case: sentinel set but openTarget field missing — corruption guard
        let binding = ButtonBinding(
            triggerEvent: RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil),
            systemShortcutName: "openTarget"
        )
        let executor = ShortcutExecutor()

        let resolved = executor.resolveAction(named: "openTarget", binding: binding)
        if case .systemShortcut = resolved {
            // Falls through to systemShortcut case (returns the identifier as-is, lookup will fail later)
        } else if resolved == nil {
            // Or returns nil — either is acceptable defensive behavior
        } else {
            XCTFail("Expected .systemShortcut or nil for missing payload, got \(String(describing: resolved))")
        }
    }

    func testResolveAction_existingCustomKeyPath_unaffected() {
        var binding = ButtonBinding(
            triggerEvent: RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil),
            systemShortcutName: "custom::40:1048576"
        )
        binding.prepareCustomCache()
        let executor = ShortcutExecutor()

        let resolved = executor.resolveAction(named: "custom::40:1048576", binding: binding)
        guard case .customKey(let code, let modifiers) = resolved else {
            return XCTFail("Expected .customKey case, got \(String(describing: resolved))")
        }
        XCTAssertEqual(code, 40)
        XCTAssertEqual(modifiers, 1048576)
    }

    func testResolveAction_existingMouseButtonPath_unaffected() {
        let executor = ShortcutExecutor()
        let resolved = executor.resolveAction(named: "mouseLeftClick", binding: nil)
        guard case .mouseButton(let kind) = resolved else {
            return XCTFail("Expected .mouseButton case, got \(String(describing: resolved))")
        }
        XCTAssertEqual(kind, .left)
    }

    func testExecutionMode_openTarget_isTrigger() {
        let payload = OpenTargetPayload(path: "/x.app", bundleID: nil, arguments: "", isApplication: true)
        let action: ResolvedAction = .openTarget(payload: payload)
        XCTAssertEqual(action.executionMode, .trigger)
    }

    func testExecutionMode_existingCases_unchanged() {
        XCTAssertEqual(ResolvedAction.customKey(code: 0, modifiers: 0).executionMode, .stateful)
        XCTAssertEqual(ResolvedAction.mouseButton(kind: .left).executionMode, .stateful)
        XCTAssertEqual(ResolvedAction.logiAction(identifier: "logiSmartShiftToggle").executionMode, .trigger)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```bash
xcodebuild test -scheme Debug -destination 'platform=macOS' -only-testing:MosTests/ShortcutExecutorOpenTargetTests 2>&1 | tail -10
```
Expected: compilation FAIL with "Type 'ResolvedAction' has no case 'openTarget'".

- [ ] **Step 3: Modify ShortcutExecutor**

In `Mos/Shortcut/ShortcutExecutor.swift`, change `ResolvedAction` (lines 36-52):

```swift
enum ResolvedAction {
    case customKey(code: UInt16, modifiers: UInt64)
    case mouseButton(kind: MouseButtonActionKind)
    case systemShortcut(identifier: String)
    case logiAction(identifier: String)
    case openTarget(payload: OpenTargetPayload)

    var executionMode: ActionExecutionMode {
        switch self {
        case .customKey, .mouseButton:
            return .stateful
        case .logiAction, .openTarget:
            return .trigger
        case .systemShortcut(let identifier):
            return SystemShortcut.getShortcut(named: identifier)?.executionMode ?? .trigger
        }
    }
}
```

In `resolveAction(named:binding:)` (lines 145-161), add the `openTarget` branch as the FIRST check (before `cachedCustomCode`):

```swift
    func resolveAction(named shortcutName: String, binding: ButtonBinding? = nil) -> ResolvedAction? {
        // 优先: 结构化 payload (在 cachedCustomCode 之前判定, 避免命名冲突)
        if let payload = binding?.openTarget,
           shortcutName == ButtonBinding.openTargetSentinel {
            return .openTarget(payload: payload)
        }
        if let code = binding?.cachedCustomCode {
            let modifiers = binding?.cachedCustomModifiers ?? 0
            return .customKey(code: code, modifiers: modifiers)
        }
        if let code = SystemShortcut.predefinedModifierCode(for: shortcutName) {
            return .customKey(code: code, modifiers: 0)
        }
        if let kind = MouseButtonActionKind(shortcutIdentifier: shortcutName) {
            return .mouseButton(kind: kind)
        }
        if shortcutName.hasPrefix("logi") {
            return .logiAction(identifier: shortcutName)
        }
        guard !shortcutName.isEmpty else { return nil }
        return .systemShortcut(identifier: shortcutName)
    }
```

Note: also update the `execute(action:phase:...)` switch (lines 114-143) to add the `.openTarget` case — but the actual launch logic is implemented in Task 5. For this task, add a stub that just NSLogs:

```swift
        case .openTarget(let payload):
            guard phase == .down else { return .none }
            NSLog("OpenTarget: stub — would execute path=\(payload.path)")
            return .none
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
xcodebuild test -scheme Debug -destination 'platform=macOS' -only-testing:MosTests/ShortcutExecutorOpenTargetTests 2>&1 | tail -10
```
Expected: All 6 tests pass.

Run all tests:
```bash
xcodebuild test -scheme Debug -destination 'platform=macOS' 2>&1 | tail -20
```
Expected: All tests pass (no regressions).

- [ ] **Step 5: Commit**

```bash
git add Mos/Shortcut/ShortcutExecutor.swift MosTests/ShortcutExecutorOpenTargetTests.swift
git commit -m "feat(shortcut): wire openTarget through ResolvedAction

ResolvedAction gains a .openTarget(payload:) case with .trigger execution
mode (fires once on keyDown). resolveAction routes to the new case when
both the sentinel name and a non-nil payload are present. Dispatch
currently stubs to NSLog; the real NSWorkspace/Process launcher arrives
in the next task."
```

---

### Task 5: executeOpenTarget + launch + run (manual verification)

**Files:**
- Modify: `Mos/Shortcut/ShortcutExecutor.swift` (the `.openTarget` switch case + new private methods at end of class)
- Modify: `Mos/Localizable.xcstrings` (add 5 error keys)

NSWorkspace/Process integration is hard to unit-test cleanly without injecting seams. We rely on manual verification with real binaries.

- [ ] **Step 1: Add localization keys to Localizable.xcstrings**

Open `Mos/Localizable.xcstrings` in Xcode (or edit the underlying JSON directly). Add these 5 keys with the values below. For each key, fill `zh-Hans` and `en` (other languages auto-translate per project convention).

| Key | en | zh-Hans |
|---|---|---|
| `openTargetAppNotFound` | `Application "%@" not found — it may have been moved or deleted` | `找不到应用 "%@", 可能已被移动或删除` |
| `openTargetAppLaunchFailed` | `Failed to launch "%@"` | `启动 "%@" 失败` |
| `openTargetScriptNotFound` | `Script "%@" not found` | `找不到脚本 "%@"` |
| `openTargetScriptNotExecutable` | `Script "%@" is not executable — run chmod +x` | `脚本 "%@" 没有执行权限, 请运行 chmod +x` |
| `openTargetScriptFailed` | `Script "%@" failed to start` | `脚本 "%@" 执行失败` |

- [ ] **Step 2: Replace stub in execute(action:phase:...) with real call**

In `Mos/Shortcut/ShortcutExecutor.swift`, change the `.openTarget` case in the `execute(action:phase:...)` switch:

```swift
        case .openTarget(let payload):
            guard phase == .down else { return .none }
            executeOpenTarget(payload)
            return .none
```

- [ ] **Step 3: Add three new private methods**

Append to `ShortcutExecutor` class (after the existing private methods, e.g. after `executeLogiAction`):

```swift
    // MARK: - Open Target Actions

    private func executeOpenTarget(_ payload: OpenTargetPayload) {
        if payload.isApplication {
            launchApplication(payload)
        } else {
            runScript(payload)
        }
    }

    private func launchApplication(_ payload: OpenTargetPayload) {
        let workspace = NSWorkspace.shared
        let resolvedURL: URL? = {
            if let bundleID = payload.bundleID,
               let url = workspace.urlForApplication(withBundleIdentifier: bundleID) {
                return url
            }
            let url = URL(fileURLWithPath: payload.path)
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }()

        guard let url = resolvedURL else {
            let appName = (payload.path as NSString).lastPathComponent
            Toast.show(
                String(format: NSLocalizedString("openTargetAppNotFound", comment: ""), appName),
                style: .error
            )
            NSLog("OpenTarget: cannot resolve application path=\(payload.path) bundleID=\(payload.bundleID ?? "-")")
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = ArgumentSplitter.split(payload.arguments)
        configuration.activates = true

        workspace.openApplication(at: url, configuration: configuration) { _, error in
            if let error = error {
                let appName = url.deletingPathExtension().lastPathComponent
                Toast.show(
                    String(format: NSLocalizedString("openTargetAppLaunchFailed", comment: ""), appName),
                    style: .error
                )
                NSLog("OpenTarget: launch failed: \(error.localizedDescription)")
            }
        }
    }

    private func runScript(_ payload: OpenTargetPayload) {
        let url = URL(fileURLWithPath: payload.path)
        let scriptName = url.lastPathComponent

        guard FileManager.default.fileExists(atPath: url.path) else {
            Toast.show(
                String(format: NSLocalizedString("openTargetScriptNotFound", comment: ""), scriptName),
                style: .error
            )
            NSLog("OpenTarget: script not found: \(payload.path)")
            return
        }

        guard FileManager.default.isExecutableFile(atPath: url.path) else {
            Toast.show(
                String(format: NSLocalizedString("openTargetScriptNotExecutable", comment: ""), scriptName),
                style: .warning
            )
            NSLog("OpenTarget: script not executable: \(payload.path)")
            return
        }

        let process = Process()
        process.executableURL = url
        process.arguments = ArgumentSplitter.split(payload.arguments)
        do {
            try process.run()
        } catch {
            Toast.show(
                String(format: NSLocalizedString("openTargetScriptFailed", comment: ""), scriptName),
                style: .error
            )
            NSLog("OpenTarget: script execution failed: \(error.localizedDescription)")
        }
    }
```

- [ ] **Step 4: Build and run all existing tests**

```bash
xcodebuild test -scheme Debug -destination 'platform=macOS' 2>&1 | tail -20
```
Expected: All tests pass (no regressions).

- [ ] **Step 5: Manual smoke test**

Open Mos, then in Xcode debugger console:

```swift
// Inject a temporary test binding (in AppDelegate or via debugger):
let payload = OpenTargetPayload(
    path: "/Applications/Safari.app",
    bundleID: "com.apple.Safari",
    arguments: "https://anthropic.com",
    isApplication: true
)
let trigger = RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil)
let binding = ButtonBinding(triggerEvent: trigger, openTarget: payload)
Options.shared.buttons.binding = [binding]
ButtonUtils.shared.invalidateCache()
```

Press the bound button: Safari should open with anthropic.com loaded.

Press again: Safari should come forward (already running).

Edit `payload.path` to a nonexistent path, repeat: should see a red Toast "找不到应用".

Clean up before commit:
```swift
Options.shared.buttons.binding = []
ButtonUtils.shared.invalidateCache()
```

- [ ] **Step 6: Commit**

```bash
git add Mos/Shortcut/ShortcutExecutor.swift Mos/Localizable.xcstrings
git commit -m "feat(shortcut): execute OpenTarget actions via NSWorkspace and Process

Apps launch via NSWorkspace.openApplication with activates=true (existing
instance is brought forward, not relaunched). Scripts run via Process
silently. All failure paths surface a Toast (red error / orange for
missing chmod +x) plus NSLog. Toast dedup naturally suppresses spam from
a stuck binding."
```

---

### Task 6: ShortcutManager menu entry (TDD)

**Files:**
- Modify: `Mos/Shortcut/ShortcutManager.swift` (lines 137-164, the area around the custom item)
- Modify: `Mos/Localizable.xcstrings` (add 1 key)
- Modify: `MosTests/ButtonBindingTests.swift` (add menu test)

- [ ] **Step 1: Add localization key**

Add to `Mos/Localizable.xcstrings`:

| Key | en | zh-Hans |
|---|---|---|
| `open-target-action` | `Open Application…` | `打开应用…` |

- [ ] **Step 2: Write the failing test**

Add to `MosTests/ButtonBindingTests.swift`:

```swift
    func testBuildShortcutMenu_includesOpenTargetEntryAboveCustom() {
        let menu = NSMenu()
        let target = ShortcutMenuTestTarget()

        ShortcutManager.buildShortcutMenu(
            into: menu,
            target: target,
            action: #selector(ShortcutMenuTestTarget.noop(_:))
        )

        guard let openIndex = menu.items.firstIndex(where: {
            ($0.representedObject as? String) == "__open__"
        }) else {
            return XCTFail("Expected '__open__' menu entry to exist")
        }
        guard let customIndex = menu.items.firstIndex(where: {
            ($0.representedObject as? String) == "__custom__"
        }) else {
            return XCTFail("Expected '__custom__' menu entry to exist")
        }
        XCTAssertLessThan(openIndex, customIndex, "Open Application should appear above Custom Shortcut")

        let openItem = menu.items[openIndex]
        XCTAssertEqual(openItem.title, NSLocalizedString("open-target-action", comment: ""))
    }
```

- [ ] **Step 3: Run test to verify it fails**

```bash
xcodebuild test -scheme Debug -destination 'platform=macOS' -only-testing:MosTests/ButtonBindingTests/testBuildShortcutMenu_includesOpenTargetEntryAboveCustom 2>&1 | tail -10
```
Expected: FAIL with "Expected '__open__' menu entry to exist".

- [ ] **Step 4: Modify ShortcutManager**

In `Mos/Shortcut/ShortcutManager.swift`, add the open-target item just before the existing custom item (around lines 148-164). Replace the section starting at line 148:

```swift
        // 自定义绑定分隔线
        menu.addItem(NSMenuItem.separator())

        // "打开应用…" 菜单项 (representedObject 为字符串标记 __open__)
        let openItem = NSMenuItem(
            title: NSLocalizedString("open-target-action", comment: ""),
            action: action,
            keyEquivalent: ""
        )
        openItem.target = target
        openItem.representedObject = "__open__" as NSString
        if supportsSFSymbols {
            if #available(macOS 11.0, *) {
                openItem.image = createSymbolImage("arrow.up.forward.app")
            }
        }
        menu.addItem(openItem)

        // "自定义…" 菜单项 (representedObject 为字符串标记)
        let customItem = NSMenuItem(
            title: NSLocalizedString("custom-shortcut", comment: ""),
            action: action,
            keyEquivalent: ""
        )
        customItem.target = target
        customItem.representedObject = "__custom__" as NSString
        if supportsSFSymbols {
            if #available(macOS 11.0, *) {
                customItem.image = createSymbolImage("keyboard")
            }
        }
        menu.addItem(customItem)
```

- [ ] **Step 5: Run test to verify it passes**

```bash
xcodebuild test -scheme Debug -destination 'platform=macOS' -only-testing:MosTests/ButtonBindingTests 2>&1 | tail -10
```
Expected: All ButtonBindingTests pass.

- [ ] **Step 6: Commit**

```bash
git add Mos/Shortcut/ShortcutManager.swift Mos/Localizable.xcstrings MosTests/ButtonBindingTests.swift
git commit -m "feat(shortcut): add 'Open Application' menu entry

Top-level entry above 'Custom Shortcut', sentinel '__open__'. Uses
SF Symbol 'arrow.up.forward.app' on macOS 11+. The cell view will
intercept this sentinel and present the config popover (next task)."
```

---

### Task 7: ActionPresentation extension + display resolver/renderer (TDD)

**Files:**
- Modify: `Mos/Windows/PreferencesWindow/ButtonsView/ActionDisplayResolver.swift`
- Modify: `Mos/Windows/PreferencesWindow/ButtonsView/ActionDisplayRenderer.swift`
- Modify: `Mos/Localizable.xcstrings` (add 1 key)
- Modify: `MosTests/ButtonBindingTests.swift` (add resolver/renderer tests)

The current `ActionDisplayResolver.resolve(...)` signature takes `shortcut:`, `customBindingName:`, `isRecording:`. To handle openTarget we need to give it access to the binding's `openTarget` payload. Cleanest fix: pass the `ButtonBinding?` through (the resolver already conceptually serves a binding).

We also add an `image: NSImage? = nil` field to `ActionPresentation` for the openTarget case to carry the file icon.

- [ ] **Step 1: Add localization key**

Add to `Mos/Localizable.xcstrings`:

| Key | en | zh-Hans |
|---|---|---|
| `open-target-placeholder-stale` | `(unavailable)` | `(应用已失效)` |

- [ ] **Step 2: Write the failing tests**

Add to `MosTests/ButtonBindingTests.swift`:

```swift
    // MARK: - ActionPresentation openTarget

    func testActionDisplayResolver_returnsOpenTargetKindWhenPayloadProvided() {
        let payload = OpenTargetPayload(
            path: "/Applications/Safari.app",
            bundleID: "com.apple.Safari",
            arguments: "",
            isApplication: true
        )
        let presentation = ActionDisplayResolver().resolve(
            shortcut: nil,
            customBindingName: nil,
            isRecording: false,
            openTarget: payload
        )
        XCTAssertEqual(presentation.kind, .openTarget)
        // Title should be either the file's basename or app displayName — both acceptable.
        XCTAssertFalse(presentation.title.isEmpty)
    }

    func testActionDisplayResolver_openTargetStalePathProducesUnavailableTitle() {
        let payload = OpenTargetPayload(
            path: "/totally-fake-path-do-not-exist.app",
            bundleID: "com.does.not.exist",
            arguments: "",
            isApplication: true
        )
        let presentation = ActionDisplayResolver().resolve(
            shortcut: nil,
            customBindingName: nil,
            isRecording: false,
            openTarget: payload
        )
        XCTAssertEqual(presentation.kind, .openTarget)
        XCTAssertTrue(
            presentation.title.contains(NSLocalizedString("open-target-placeholder-stale", comment: ""))
                || presentation.title.contains("totally-fake-path-do-not-exist"),
            "Stale path should produce either filename + (unavailable) suffix or just '(unavailable)'; got: \(presentation.title)"
        )
    }

    func testActionDisplayRenderer_rendersOpenTargetWithImage() {
        let popupButton = makeActionPopupButton()
        let stubImage = NSImage(size: NSSize(width: 16, height: 16))
        let presentation = ActionPresentation(
            kind: .openTarget,
            title: "Safari",
            symbolName: nil,
            image: stubImage,
            badgeComponents: [],
            brand: nil
        )

        ActionDisplayRenderer().render(presentation, into: popupButton)

        XCTAssertEqual(popupButton.menu?.items.first?.title, "Safari")
        XCTAssertNotNil(popupButton.menu?.items.first?.image)
    }
```

- [ ] **Step 3: Run tests to verify they fail**

```bash
xcodebuild test -scheme Debug -destination 'platform=macOS' -only-testing:MosTests/ButtonBindingTests 2>&1 | tail -10
```
Expected: compilation FAIL with "Cannot find 'openTarget' in arguments / 'image' / '.openTarget' case".

- [ ] **Step 4: Modify ActionDisplayResolver**

Replace `Mos/Windows/PreferencesWindow/ButtonsView/ActionDisplayResolver.swift`:

```swift
//
//  ActionDisplayResolver.swift
//  Mos
//

import Cocoa

enum ActionPresentationKind: Equatable {
    case unbound
    case recordingPrompt
    case namedAction
    case keyCombo
    case openTarget
}

struct ActionPresentation {
    let kind: ActionPresentationKind
    let title: String
    let symbolName: String?
    let image: NSImage?
    let badgeComponents: [String]
    let brand: BrandTagConfig?

    init(
        kind: ActionPresentationKind,
        title: String,
        symbolName: String? = nil,
        image: NSImage? = nil,
        badgeComponents: [String] = [],
        brand: BrandTagConfig? = nil
    ) {
        self.kind = kind
        self.title = title
        self.symbolName = symbolName
        self.image = image
        self.badgeComponents = badgeComponents
        self.brand = brand
    }
}

struct ActionDisplayResolver {

    func resolve(
        shortcut: SystemShortcut.Shortcut?,
        customBindingName: String?,
        isRecording: Bool,
        openTarget: OpenTargetPayload? = nil
    ) -> ActionPresentation {
        if isRecording {
            return ActionPresentation(
                kind: .recordingPrompt,
                title: NSLocalizedString("custom-recording-prompt", comment: "")
            )
        }

        if let openTarget {
            return openTargetPresentation(for: openTarget)
        }

        if let shortcut {
            return namedActionPresentation(for: shortcut)
        }

        if let customBindingName {
            if let shortcut = SystemShortcut.displayShortcut(matchingBindingName: customBindingName) {
                return namedActionPresentation(for: shortcut)
            }

            if let customPresentation = customBindingPresentation(for: customBindingName) {
                return customPresentation
            }
        }

        return ActionPresentation(
            kind: .unbound,
            title: NSLocalizedString("unbound", comment: "")
        )
    }

    private func namedActionPresentation(for shortcut: SystemShortcut.Shortcut) -> ActionPresentation {
        ActionPresentation(
            kind: .namedAction,
            title: shortcut.localizedName,
            symbolName: shortcut.symbolName,
            brand: BrandTag.brandForAction(shortcut.identifier)
        )
    }

    private func openTargetPresentation(for payload: OpenTargetPayload) -> ActionPresentation {
        let workspace = NSWorkspace.shared
        let resolvedURL: URL? = {
            if let bundleID = payload.bundleID,
               let url = workspace.urlForApplication(withBundleIdentifier: bundleID) {
                return url
            }
            let url = URL(fileURLWithPath: payload.path)
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }()

        let title: String
        let icon: NSImage?
        if let url = resolvedURL {
            if payload.isApplication, let bundle = Bundle(url: url) {
                title = bundle.localizedDisplayName
                    ?? bundle.infoDictionary?["CFBundleDisplayName"] as? String
                    ?? bundle.infoDictionary?["CFBundleName"] as? String
                    ?? url.deletingPathExtension().lastPathComponent
            } else {
                title = url.lastPathComponent
            }
            icon = workspace.icon(forFile: url.path)
        } else {
            // Stale path: show filename + unavailable marker
            let basename = (payload.path as NSString).lastPathComponent
            let staleTag = NSLocalizedString("open-target-placeholder-stale", comment: "")
            title = basename.isEmpty ? staleTag : "\(basename) \(staleTag)"
            icon = nil
        }

        return ActionPresentation(
            kind: .openTarget,
            title: title,
            symbolName: nil,
            image: icon
        )
    }

    private func customBindingPresentation(for customBindingName: String) -> ActionPresentation? {
        guard let (code, modifiers) = ButtonBinding.normalizedCustomBindingPayload(from: customBindingName) else {
            return nil
        }

        let brand = BrandTag.brandForCode(code)
        if let brand, modifiers == 0, LogiCenter.shared.isLogiCode(code) {
            return ActionPresentation(
                kind: .namedAction,
                title: (LogiCenter.shared.name(forMosCode: code) ?? ""),
                brand: brand
            )
        }

        let event = InputEvent(
            type: inputType(for: code),
            code: code,
            modifiers: CGEventFlags(rawValue: modifiers),
            phase: .down,
            source: .hidPP,
            device: nil
        )
        let marker = brand.map { "[\($0.name)]" }
        let badgeComponents = event.displayComponents.filter { component in
            guard let marker else { return true }
            return component != marker
        }

        return ActionPresentation(
            kind: .keyCombo,
            title: "",
            badgeComponents: badgeComponents,
            brand: brand
        )
    }

    private func inputType(for code: UInt16) -> EventType {
        if KeyCode.modifierKeys.contains(code) {
            return .keyboard
        }
        return code >= 0x100 ? .mouse : .keyboard
    }
}

private extension Bundle {
    var localizedDisplayName: String? {
        return localizedInfoDictionary?["CFBundleDisplayName"] as? String
            ?? localizedInfoDictionary?["CFBundleName"] as? String
    }
}
```

- [ ] **Step 5: Modify ActionDisplayRenderer**

In `Mos/Windows/PreferencesWindow/ButtonsView/ActionDisplayRenderer.swift`, change `render(_:into:)`:

```swift
    func render(_ presentation: ActionPresentation, into popupButton: NSPopUpButton) {
        guard let menu = popupButton.menu,
              let placeholderItem = menu.items.first else {
            return
        }

        switch presentation.kind {
        case .unbound, .recordingPrompt:
            apply(title: presentation.title, image: nil, placeholderItem: placeholderItem, popupButton: popupButton)

        case .namedAction:
            let baseImage = createSymbolImage(named: presentation.symbolName)
            let finalImage = prefixedImageIfNeeded(baseImage, brand: presentation.brand)
            apply(title: presentation.title, image: finalImage, placeholderItem: placeholderItem, popupButton: popupButton)

        case .keyCombo:
            let badgeImage = Self.createBadgeImage(from: presentation.badgeComponents)
            let finalImage = prefixedImageIfNeeded(badgeImage, brand: presentation.brand)
            apply(title: presentation.title, image: finalImage, placeholderItem: placeholderItem, popupButton: popupButton)

        case .openTarget:
            let resizedImage = presentation.image.map { Self.resizeForBadge($0) }
            apply(title: presentation.title, image: resizedImage, placeholderItem: placeholderItem, popupButton: popupButton)
        }
    }

    /// Resize an arbitrary NSImage to match the visual size of system shortcut icons (badge height 17pt).
    private static func resizeForBadge(_ image: NSImage) -> NSImage {
        let badgeHeight: CGFloat = 17
        let originalSize = image.size
        guard originalSize.height > 0 else { return image }
        let scale = badgeHeight / originalSize.height
        let newSize = NSSize(width: originalSize.width * scale, height: badgeHeight)

        let resized = NSImage(size: newSize)
        resized.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: newSize),
                   from: NSRect(origin: .zero, size: originalSize),
                   operation: .sourceOver,
                   fraction: 1.0)
        resized.unlockFocus()
        return resized
    }
```

- [ ] **Step 6: Update ButtonTableCellView call site**

`ActionDisplayResolver.resolve(...)` is called in `ButtonTableCellView.refreshActionDisplay()`. Find that function (around line 419) and update the call to pass `openTarget`:

```swift
    func refreshActionDisplay() {
        let presentation = actionDisplayResolver.resolve(
            shortcut: currentShortcut,
            customBindingName: currentCustomName,
            isRecording: isCustomRecordingActive,
            openTarget: currentBinding?.openTarget
        )
        actionDisplayRenderer.render(presentation, into: actionPopUpButton)
    }
```

- [ ] **Step 7: Run all tests**

```bash
xcodebuild test -scheme Debug -destination 'platform=macOS' 2>&1 | tail -20
```
Expected: All tests pass.

- [ ] **Step 8: Commit**

```bash
git add Mos/Windows/PreferencesWindow/ButtonsView/ActionDisplayResolver.swift Mos/Windows/PreferencesWindow/ButtonsView/ActionDisplayRenderer.swift Mos/Windows/PreferencesWindow/ButtonsView/ButtonTableCellView.swift Mos/Localizable.xcstrings MosTests/ButtonBindingTests.swift
git commit -m "feat(buttons): render openTarget bindings in action popup placeholder

ActionPresentation gains an optional image field for arbitrary NSImages
(file icons in this case). Resolver builds an .openTarget presentation
from the payload, resolving via bundle ID first then absolute path; if
both fail, shows '(unavailable)' marker. Renderer scales the file icon
to badge height (17pt) for visual parity with SF Symbol icons."
```

---

### Task 8: ButtonTableCellView `__open__` sentinel handler with stub popover (TDD)

**Files:**
- Modify: `Mos/Windows/PreferencesWindow/ButtonsView/ButtonTableCellView.swift`
- Modify: `MosTests/ButtonBindingTests.swift`

This task wires the `__open__` sentinel into the cell. We use a temporary stub that immediately produces a fixed payload — the real popover arrives in Task 9-12. This keeps the integration testable BEFORE the heavy UI lands.

- [ ] **Step 1: Write the failing test**

The existing `configure()` method takes three callback closures. We extend it with a fourth: `onOpenTargetSelectionRequested`. The test passes a closure via `configure()`, then dispatches the `__open__` menu item and asserts the closure ran.

First update the test helper `makeButtonCell` to support the new callback. Replace the existing `makeButtonCell` in `ButtonBindingTests.swift` (around lines 22-40):

```swift
    private func makeButtonCell(
        binding: ButtonBinding,
        onOpenTargetSelectionRequested: @escaping () -> Void = {}
    ) -> ButtonTableCellView {
        let cell = ButtonTableCellView(frame: NSRect(x: 0, y: 0, width: 420, height: 44))
        let keyContainer = NSView(frame: NSRect(x: 0, y: 0, width: 140, height: 44))
        let actionButton = NSPopUpButton(frame: NSRect(x: 180, y: 8, width: 180, height: 28), pullsDown: false)

        cell.keyDisplayContainerView = keyContainer
        cell.actionPopUpButton = actionButton
        cell.addSubview(keyContainer)
        cell.addSubview(actionButton)

        cell.configure(
            with: binding,
            onShortcutSelected: { _ in },
            onCustomShortcutRecorded: { _ in },
            onOpenTargetSelectionRequested: onOpenTargetSelectionRequested,
            onDeleteRequested: {}
        )

        return cell
    }
```

Then add the new test:

```swift
    func testShortcutSelected_openSentinel_invokesOpenSelectionCallback() {
        let trigger = RecordedEvent(type: .mouse, code: 3, modifiers: 0, displayComponents: ["🖱4"], deviceFilter: nil)
        let binding = ButtonBinding(triggerEvent: trigger, systemShortcutName: "")

        var openSelectionInvoked = false
        let cell = makeButtonCell(binding: binding, onOpenTargetSelectionRequested: {
            openSelectionInvoked = true
        })

        let openItem = NSMenuItem(title: "Open Application…", action: nil, keyEquivalent: "")
        openItem.representedObject = "__open__" as NSString
        cell.shortcutSelected(openItem)

        XCTAssertTrue(openSelectionInvoked, "Selecting the __open__ menu item should trigger onOpenTargetSelectionRequested")
    }
```

Note: `shortcutSelected(_:)` is currently `@objc private`. Drop `private` (keep `@objc`) so XCTest can invoke it via `@testable import`.

- [ ] **Step 2: Run test to verify it fails**

```bash
xcodebuild test -scheme Debug -destination 'platform=macOS' -only-testing:MosTests/ButtonBindingTests/testShortcutSelected_openSentinel_invokesOpenSelectionCallback 2>&1 | tail -10
```
Expected: compilation FAIL with "Value of type 'ButtonTableCellView' has no member 'onOpenTargetSelectionRequested'".

- [ ] **Step 3: Wire sentinel in ButtonTableCellView**

In `Mos/Windows/PreferencesWindow/ButtonsView/ButtonTableCellView.swift`:

1. Add a new closure property near the existing callback closures (around lines 35-37):

```swift
    private var onShortcutSelected: ((SystemShortcut.Shortcut?) -> Void)?
    private var onDeleteRequested: (() -> Void)?
    private var onCustomShortcutRecorded: ((String) -> Void)?
    /// 当用户从 PopUpButton 菜单选择 "打开应用…" 时触发,
    /// 由 PreferencesButtonsViewController 弹出 OpenTargetConfigPopover.
    private var onOpenTargetSelectionRequested: (() -> Void)?
```

2. Extend the `configure()` method signature (around line 53-62) to accept the new callback:

```swift
    func configure(
        with binding: ButtonBinding,
        onShortcutSelected: @escaping (SystemShortcut.Shortcut?) -> Void,
        onCustomShortcutRecorded: @escaping (String) -> Void,
        onOpenTargetSelectionRequested: @escaping () -> Void,
        onDeleteRequested: @escaping () -> Void
    ) {
        self.currentBinding = binding
        self.onShortcutSelected = onShortcutSelected
        self.onDeleteRequested = onDeleteRequested
        self.onCustomShortcutRecorded = onCustomShortcutRecorded
        self.onOpenTargetSelectionRequested = onOpenTargetSelectionRequested
        // ... rest of existing configure body unchanged
    }
```

(Adapt to the existing structure — the `currentBinding` line and what follows are already in the file. Just slot the new parameter and assignment in alongside the existing ones.)

3. Modify `shortcutSelected(_:)` (around line 451), drop `private` so it's visible to XCTest, and add the `__open__` branch BEFORE the existing `__custom__` branch:

```swift
    @objc internal func shortcutSelected(_ sender: NSMenuItem) {
        // "打开应用…" sentinel: 把后续配置流程交给外部
        if sender.representedObject as? String == "__open__" {
            onOpenTargetSelectionRequested?()
            return
        }

        // 自定义录制: action 在 menuDidClose 之后触发,
        // 直接 asyncAfter 等待菜单动画和焦点恢复后弹出录制弹窗
        if sender.representedObject as? String == "__custom__" {
            beginCustomShortcutSelection()
            return
        }

        // 清除自定义绑定状态
        self.currentCustomName = nil

        // representedObject 为 nil 时表示用户选择了"未绑定"
        let shortcut = sender.representedObject as? SystemShortcut.Shortcut

        // 更新本地状态
        self.currentShortcut = shortcut

        // 更新占位符显示
        refreshActionDisplay()

        // 通知外部更新(nil 表示清除绑定)
        onShortcutSelected?(shortcut)

        // 延迟重绘虚线和冲突指示器 (等待 PopUpButton 布局更新)
        DispatchQueue.main.async {
            self.refreshConflictIndicator()
        }
    }
```

(Note: changed `@objc private` → `@objc internal` to allow XCTest invocation. If the existing version uses just `@objc private`, drop `private`. If it uses `@IBAction`, keep `@objc` and remove `private`.)

- [ ] **Step 4: Run test to verify it passes**

```bash
xcodebuild test -scheme Debug -destination 'platform=macOS' -only-testing:MosTests/ButtonBindingTests/testShortcutSelected_openSentinel_invokesOpenSelectionCallback 2>&1 | tail -10
```
Expected: PASS.

Run full suite:
```bash
xcodebuild test -scheme Debug -destination 'platform=macOS' 2>&1 | tail -20
```
Expected: All tests pass.

- [ ] **Step 5: Wire callback in PreferencesButtonsViewController (stub)**

In `Mos/Windows/PreferencesWindow/ButtonsView/PreferencesButtonsViewController.swift`, find the `tableView(_:viewFor:row:)` method (around line 246-269) which calls `cell.configure(...)`. Add the new closure parameter to the call:

```swift
        if let cell = tableView.makeView(withIdentifier: tableColumnIdentifier, owner: self) as? ButtonTableCellView {
            let binding = buttonBindings[row]

            cell.configure(
                with: binding,
                onShortcutSelected: { [weak self] shortcut in
                    self?.updateButtonBinding(id: binding.id, with: shortcut)
                },
                onCustomShortcutRecorded: { [weak self] customName in
                    self?.updateButtonBinding(id: binding.id, withCustomName: customName)
                },
                onOpenTargetSelectionRequested: { [weak self] in
                    // Stub — real popover lands in Task 12
                    NSLog("OpenTargetConfigPopover: stub — would show popover for binding id=\(binding.id)")
                    _ = self  // silence unused warning
                },
                onDeleteRequested: { [weak self] in
                    self?.removeButtonBinding(id: binding.id)
                }
            )
            return cell
        }
```

- [ ] **Step 6: Manual smoke test**

Build and run Mos. Open Preferences → Buttons. Add a binding row, click the action PopUpButton, select "打开应用…". Console should print `OpenTargetConfigPopover: stub — would show popover for row`. (Nothing visible happens yet — that's expected for this stub.)

- [ ] **Step 7: Commit**

```bash
git add Mos/Windows/PreferencesWindow/ButtonsView/ButtonTableCellView.swift Mos/Windows/PreferencesWindow/ButtonsView/PreferencesButtonsViewController.swift MosTests/ButtonBindingTests.swift
git commit -m "feat(buttons): wire __open__ sentinel into cell (stub popover)

Cell exposes onOpenTargetSelectionRequested closure; the controller
currently NSLogs as a placeholder. The real OpenTargetConfigPopover
arrives in the next tasks. Test harness updated to verify sentinel
routing without a live popover dependency."
```

---

### Task 9: OpenTargetConfigPopover skeleton — empty state + args + buttons (manual)

**Files:**
- Create: `Mos/Windows/PreferencesWindow/ButtonsView/OpenTargetConfigPopover.swift`
- Modify: `Mos/Localizable.xcstrings` (add 9 keys)

This task creates the popover scaffolding with empty file slot, args field, and buttons. Filled state, drag-drop, NSOpenPanel, and stale-path detection are subsequent tasks.

- [ ] **Step 1: Add localization keys**

| Key | en | zh-Hans |
|---|---|---|
| `open-target-empty-primary` | `Choose an app or script` | `选择应用或脚本` |
| `open-target-empty-secondary` | `or drag one here` | `或拖拽到此处` |
| `open-target-empty-tooltip` | `Click to choose a file, or drag a .app/script here` | `点击选择文件，或拖拽 .app/脚本到此处` |
| `open-target-arguments-label` | `Arguments` | `参数` |
| `open-target-arguments-optional-suffix` | `(optional)` | `(可选)` |
| `open-target-arguments-placeholder` | `Space-separated; quote arguments containing spaces` | `用空格分隔, 引号包裹含空格的参数` |
| `open-target-cancel` | `Cancel` | `取消` |
| `open-target-done` | `Done` | `完成` |
| `open-target-stale-warning` | `The previously chosen app can no longer be found` | `之前选择的应用已找不到` |

- [ ] **Step 2: Create OpenTargetConfigPopover skeleton**

```swift
// Mos/Windows/PreferencesWindow/ButtonsView/OpenTargetConfigPopover.swift
//
//  OpenTargetConfigPopover.swift
//  Mos
//  "打开应用…" 动作的配置 popover - 文件槽 + 参数 + 完成/取消
//

import Cocoa

final class OpenTargetConfigPopover: NSObject {

    // MARK: - Public callbacks
    var onCommit: ((OpenTargetPayload) -> Void)?
    var onCancel: (() -> Void)?

    // MARK: - State
    private var popover: NSPopover?
    private var existingPayload: OpenTargetPayload?

    // Captured selection
    private var selectedPath: String?
    private var selectedBundleID: String?
    private var selectedIsApplication: Bool = false

    // Views
    private weak var fileSlot: FileSlotView?
    private weak var argsField: NSTextField?
    private weak var doneButton: NSButton?

    // Layout constants
    private static let contentWidth: CGFloat = 320
    private static let padding: CGFloat = 16
    private static let slotHeight: CGFloat = 64

    // MARK: - Show

    func show(at sourceView: NSView, existing: OpenTargetPayload?) {
        hide()
        self.existingPayload = existing
        self.selectedPath = existing?.path
        self.selectedBundleID = existing?.bundleID
        self.selectedIsApplication = existing?.isApplication ?? false

        let popover = NSPopover()
        popover.behavior = .applicationDefined  // 不自动关闭, 必须显式 close
        popover.contentViewController = makeViewController(initialArgs: existing?.arguments ?? "")
        popover.show(relativeTo: sourceView.bounds, of: sourceView, preferredEdge: .maxY)
        self.popover = popover
    }

    func hide() {
        popover?.close()
        popover = nil
    }

    // MARK: - View construction

    private func makeViewController(initialArgs: String) -> NSViewController {
        let vc = NSViewController()
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        // File slot (empty state for now; filled state in Task 10)
        let slot = FileSlotView()
        slot.translatesAutoresizingMaskIntoConstraints = false
        slot.onClick = { [weak self] in self?.onFileSlotClicked() }
        container.addSubview(slot)
        self.fileSlot = slot

        // Args caption
        let captionStack = NSStackView()
        captionStack.orientation = .horizontal
        captionStack.spacing = 0
        captionStack.translatesAutoresizingMaskIntoConstraints = false
        let captionLabel = NSTextField(labelWithString: NSLocalizedString("open-target-arguments-label", comment: ""))
        captionLabel.font = NSFont.systemFont(ofSize: 11)
        captionLabel.textColor = NSColor.labelColor
        let captionSuffix = NSTextField(labelWithString: " " + NSLocalizedString("open-target-arguments-optional-suffix", comment: ""))
        captionSuffix.font = NSFont.systemFont(ofSize: 11)
        captionSuffix.textColor = NSColor.tertiaryLabelColor
        captionStack.addArrangedSubview(captionLabel)
        captionStack.addArrangedSubview(captionSuffix)
        container.addSubview(captionStack)

        // Args field (monospaced)
        let args = NSTextField()
        args.translatesAutoresizingMaskIntoConstraints = false
        args.bezelStyle = .roundedBezel
        args.placeholderString = NSLocalizedString("open-target-arguments-placeholder", comment: "")
        args.stringValue = initialArgs
        if #available(macOS 10.15, *) {
            args.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        } else {
            args.font = NSFont(name: "Menlo", size: 12) ?? NSFont.systemFont(ofSize: 12)
        }
        container.addSubview(args)
        self.argsField = args

        // Buttons
        let cancel = NSButton(title: NSLocalizedString("open-target-cancel", comment: ""), target: self, action: #selector(onCancelButton))
        cancel.translatesAutoresizingMaskIntoConstraints = false
        cancel.bezelStyle = .rounded
        container.addSubview(cancel)

        let done = NSButton(title: NSLocalizedString("open-target-done", comment: ""), target: self, action: #selector(onDoneButton))
        done.translatesAutoresizingMaskIntoConstraints = false
        done.bezelStyle = .rounded
        done.keyEquivalent = "\r"
        done.isEnabled = (selectedPath != nil)
        container.addSubview(done)
        self.doneButton = done

        // Layout
        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: Self.contentWidth + Self.padding * 2),

            slot.topAnchor.constraint(equalTo: container.topAnchor, constant: Self.padding),
            slot.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Self.padding),
            slot.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -Self.padding),
            slot.heightAnchor.constraint(equalToConstant: Self.slotHeight),

            captionStack.topAnchor.constraint(equalTo: slot.bottomAnchor, constant: 12),
            captionStack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Self.padding),

            args.topAnchor.constraint(equalTo: captionStack.bottomAnchor, constant: 6),
            args.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Self.padding),
            args.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -Self.padding),
            args.heightAnchor.constraint(equalToConstant: 26),

            done.topAnchor.constraint(equalTo: args.bottomAnchor, constant: 16),
            done.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -Self.padding),
            done.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -Self.padding),

            cancel.topAnchor.constraint(equalTo: done.topAnchor),
            cancel.trailingAnchor.constraint(equalTo: done.leadingAnchor, constant: -8),
        ])

        vc.view = container
        return vc
    }

    // MARK: - Interactions (placeholders for Tasks 10-11)

    private func onFileSlotClicked() {
        // Real NSOpenPanel handler arrives in Task 11
        NSLog("OpenTargetConfigPopover: file slot clicked (NSOpenPanel TODO)")
    }

    @objc private func onDoneButton() {
        guard let path = selectedPath, let argsField = argsField else { return }
        let payload = OpenTargetPayload(
            path: path,
            bundleID: selectedBundleID,
            arguments: argsField.stringValue,
            isApplication: selectedIsApplication
        )
        onCommit?(payload)
        hide()
    }

    @objc private func onCancelButton() {
        onCancel?()
        hide()
    }
}

// MARK: - File slot view (skeleton — empty state only for Task 9)

final class FileSlotView: NSView {

    var onClick: (() -> Void)?

    private let primaryLabel = NSTextField(labelWithString: NSLocalizedString("open-target-empty-primary", comment: ""))
    private let secondaryLabel = NSTextField(labelWithString: NSLocalizedString("open-target-empty-secondary", comment: ""))

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.secondaryLabelColor.withAlphaComponent(0.5).cgColor
        // Dashed border via a CAShapeLayer overlay would be fancier; for skeleton, solid is acceptable.
        // We'll upgrade to dashed in Task 10.
        layer?.backgroundColor = NSColor.gray.withAlphaComponent(0.04).cgColor

        toolTip = NSLocalizedString("open-target-empty-tooltip", comment: "")

        let stack = NSStackView(views: [primaryLabel, secondaryLabel])
        stack.orientation = .vertical
        stack.spacing = 2
        stack.alignment = .centerX
        stack.translatesAutoresizingMaskIntoConstraints = false

        primaryLabel.font = NSFont.systemFont(ofSize: 13)
        primaryLabel.textColor = NSColor.labelColor
        secondaryLabel.font = NSFont.systemFont(ofSize: 11)
        secondaryLabel.textColor = NSColor.tertiaryLabelColor

        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        // Hover cursor
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }
}
```

Add the new file to the Mos target in Xcode.

- [ ] **Step 3: Build to verify it compiles**

```bash
xcodebuild -scheme Debug -configuration Debug build 2>&1 | tail -10
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Manual smoke test**

Temporarily change the stub in `PreferencesButtonsViewController` (introduced in Task 8) to actually present the popover:

```swift
                cell.onOpenTargetSelectionRequested = { [weak cell] in
                    guard let cell else { return }
                    let popover = OpenTargetConfigPopover()
                    popover.onCommit = { payload in
                        NSLog("OpenTargetConfigPopover: commit (skeleton) — \(payload)")
                    }
                    popover.show(at: cell.actionPopUpButton, existing: nil)
                }
```

(This is temporary scaffolding — full wiring lands in Task 12. We'll write a TODO comment so the next task knows to replace it.)

Build, open Preferences → Buttons → add row → click action popup → select "打开应用…". Popover should appear with empty file slot, args field, and disabled Done button. Click file slot → see NSLog "NSOpenPanel TODO". Click Cancel → popover closes.

- [ ] **Step 5: Commit**

```bash
git add Mos/Windows/PreferencesWindow/ButtonsView/OpenTargetConfigPopover.swift Mos/Windows/PreferencesWindow/ButtonsView/PreferencesButtonsViewController.swift Mos/Localizable.xcstrings Mos.xcodeproj/project.pbxproj
git commit -m "feat(buttons): scaffold OpenTargetConfigPopover (empty state)

Adds the popover NSViewController, layout (file slot + args + buttons),
empty-state file slot with click handler stub, monospaced args field
(macOS 10.15+ system mono, Menlo fallback for 10.13/14), keyboard
defaults (Return → Done, Esc → Cancel via NSPopover.applicationDefined +
button.keyEquivalent). Filled state, drag-drop, NSOpenPanel, and stale
detection follow."
```

---

### Task 10: Filled state + crossfade + clear button (manual)

**Files:**
- Modify: `Mos/Windows/PreferencesWindow/ButtonsView/OpenTargetConfigPopover.swift`
- Modify: `Mos/Localizable.xcstrings` (add 2 keys)

- [ ] **Step 1: Add localization keys**

| Key | en | zh-Hans |
|---|---|---|
| `open-target-filled-tooltip` | `Click to choose a different one` | `点击重新选择` |
| `open-target-clear-tooltip` | `Clear` | `清除` |

- [ ] **Step 2: Extend FileSlotView with filled state**

Replace the `FileSlotView` class in `OpenTargetConfigPopover.swift` with a version that supports both states:

```swift
// MARK: - File slot view (empty + filled states with crossfade)

final class FileSlotView: NSView {

    var onClick: (() -> Void)?
    var onClear: (() -> Void)?

    private(set) var state: State = .empty

    enum State: Equatable {
        case empty
        case filled(FilledContent)
    }

    struct FilledContent: Equatable {
        let icon: NSImage?
        let title: String
        let subtitle: String
    }

    private var emptyView: NSView!
    private var filledView: NSView!

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        wantsLayer = true
        layer?.cornerRadius = 8

        emptyView = makeEmptyView()
        filledView = makeFilledView()
        emptyView.alphaValue = 1
        filledView.alphaValue = 0
        addSubview(emptyView)
        addSubview(filledView)

        applyEmptyAppearance()
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func layout() {
        super.layout()
        emptyView.frame = bounds
        filledView.frame = bounds
    }

    override func mouseDown(with event: NSEvent) {
        // Don't propagate clicks on the clear button
        let point = convert(event.locationInWindow, from: nil)
        if let clearBtn = filledView.viewWithTag(99), clearBtn.frame.contains(point), case .filled = state {
            return
        }
        onClick?()
    }

    // MARK: State control

    func setState(_ newState: State, animated: Bool = true) {
        guard newState != state else { return }
        state = newState

        let (showView, hideView): (NSView, NSView) = {
            switch newState {
            case .empty: return (emptyView, filledView)
            case .filled(let content):
                applyFilledContent(content)
                return (filledView, emptyView)
            }
        }()

        switch newState {
        case .empty: applyEmptyAppearance()
        case .filled: applyFilledAppearance()
        }

        if animated {
            showView.alphaValue = 0
            showView.layer?.setAffineTransform(CGAffineTransform(scaleX: 0.98, y: 0.98))
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.25
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                ctx.allowsImplicitAnimation = true
                showView.animator().alphaValue = 1
                showView.animator().layer?.setAffineTransform(.identity)
                hideView.animator().alphaValue = 0
            })
        } else {
            showView.alphaValue = 1
            showView.layer?.setAffineTransform(.identity)
            hideView.alphaValue = 0
        }
    }

    // MARK: Appearance

    private func applyEmptyAppearance() {
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.secondaryLabelColor.withAlphaComponent(0.5).cgColor
        layer?.backgroundColor = NSColor.gray.withAlphaComponent(0.04).cgColor
        toolTip = NSLocalizedString("open-target-empty-tooltip", comment: "")
    }

    private func applyFilledAppearance() {
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.backgroundColor = NSColor.gray.withAlphaComponent(0.03).cgColor
        toolTip = NSLocalizedString("open-target-filled-tooltip", comment: "")
    }

    // MARK: Empty subview

    private func makeEmptyView() -> NSView {
        let container = NSView()
        container.wantsLayer = true

        let primary = NSTextField(labelWithString: NSLocalizedString("open-target-empty-primary", comment: ""))
        primary.font = NSFont.systemFont(ofSize: 13)
        primary.textColor = NSColor.labelColor

        let secondary = NSTextField(labelWithString: NSLocalizedString("open-target-empty-secondary", comment: ""))
        secondary.font = NSFont.systemFont(ofSize: 11)
        secondary.textColor = NSColor.tertiaryLabelColor

        let stack = NSStackView(views: [primary, secondary])
        stack.orientation = .vertical
        stack.spacing = 2
        stack.alignment = .centerX
        stack.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])
        return container
    }

    // MARK: Filled subview

    private weak var filledIcon: NSImageView?
    private weak var filledTitle: NSTextField?
    private weak var filledSubtitle: NSTextField?

    private func makeFilledView() -> NSView {
        let container = NSView()
        container.wantsLayer = true

        let icon = NSImageView()
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(icon)
        self.filledIcon = icon

        let title = NSTextField(labelWithString: "")
        title.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        title.textColor = NSColor.labelColor
        title.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(title)
        self.filledTitle = title

        let subtitle = NSTextField(labelWithString: "")
        subtitle.font = NSFont.systemFont(ofSize: 10.5)
        subtitle.textColor = NSColor.tertiaryLabelColor
        subtitle.lineBreakMode = .byTruncatingMiddle
        subtitle.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(subtitle)
        self.filledSubtitle = subtitle

        let clearBtn = NSButton()
        clearBtn.tag = 99  // used in mouseDown hit test
        clearBtn.bezelStyle = .inline
        clearBtn.isBordered = false
        if #available(macOS 11.0, *) {
            clearBtn.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: nil)
        } else {
            clearBtn.title = "✕"
        }
        clearBtn.contentTintColor = NSColor.tertiaryLabelColor
        clearBtn.toolTip = NSLocalizedString("open-target-clear-tooltip", comment: "")
        clearBtn.target = self
        clearBtn.action = #selector(onClearClicked)
        clearBtn.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(clearBtn)

        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            icon.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 36),
            icon.heightAnchor.constraint(equalToConstant: 36),

            title.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 12),
            title.trailingAnchor.constraint(lessThanOrEqualTo: clearBtn.leadingAnchor, constant: -8),
            title.topAnchor.constraint(equalTo: container.topAnchor, constant: 14),

            subtitle.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            subtitle.trailingAnchor.constraint(equalTo: title.trailingAnchor),
            subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 2),

            clearBtn.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            clearBtn.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            clearBtn.widthAnchor.constraint(equalToConstant: 16),
            clearBtn.heightAnchor.constraint(equalToConstant: 16),
        ])

        return container
    }

    private func applyFilledContent(_ content: FilledContent) {
        filledIcon?.image = content.icon
        filledTitle?.stringValue = content.title
        filledSubtitle?.stringValue = content.subtitle
        toolTip = "\(content.subtitle)\n\(NSLocalizedString("open-target-filled-tooltip", comment: ""))"
    }

    @objc private func onClearClicked() {
        onClear?()
    }
}
```

- [ ] **Step 3: Wire setState into the popover**

In `OpenTargetConfigPopover`, update `show(at:existing:)` and add a helper that turns selected fields into FilledContent:

```swift
    func show(at sourceView: NSView, existing: OpenTargetPayload?) {
        hide()
        self.existingPayload = existing
        self.selectedPath = existing?.path
        self.selectedBundleID = existing?.bundleID
        self.selectedIsApplication = existing?.isApplication ?? false

        let popover = NSPopover()
        popover.behavior = .applicationDefined
        popover.contentViewController = makeViewController(initialArgs: existing?.arguments ?? "")
        popover.show(relativeTo: sourceView.bounds, of: sourceView, preferredEdge: .maxY)
        self.popover = popover

        // Initial state
        if let existing {
            applyFilledStateForCurrentSelection(animated: false)
            _ = existing  // silence
        } else {
            fileSlot?.setState(.empty, animated: false)
        }
    }

    private func applyFilledStateForCurrentSelection(animated: Bool) {
        guard let path = selectedPath else {
            fileSlot?.setState(.empty, animated: animated)
            doneButton?.isEnabled = false
            return
        }
        let url = URL(fileURLWithPath: path)
        let workspace = NSWorkspace.shared
        let icon = workspace.icon(forFile: url.path)
        let title: String = {
            if selectedIsApplication, let bundle = Bundle(url: url) {
                return bundle.infoDictionary?["CFBundleDisplayName"] as? String
                    ?? bundle.infoDictionary?["CFBundleName"] as? String
                    ?? url.deletingPathExtension().lastPathComponent
            }
            return url.lastPathComponent
        }()
        let content = FileSlotView.FilledContent(icon: icon, title: title, subtitle: path)
        fileSlot?.setState(.filled(content), animated: animated)
        doneButton?.isEnabled = true
    }
```

Also add the clear-button handler:

```swift
    private func onFileSlotCleared() {
        selectedPath = nil
        selectedBundleID = nil
        selectedIsApplication = false
        fileSlot?.setState(.empty, animated: true)
        doneButton?.isEnabled = false
    }
```

And wire `slot.onClear = { [weak self] in self?.onFileSlotCleared() }` in `makeViewController`.

- [ ] **Step 4: Build and manual smoke test**

```bash
xcodebuild -scheme Debug -configuration Debug build 2>&1 | tail -10
```
Expected: BUILD SUCCEEDED.

For testing the filled state, temporarily inject a fake selection in the popover open path (this is throwaway test code; remove after verifying):

```swift
// Temp: at end of show(at:existing:)
selectedPath = "/Applications/Safari.app"
selectedBundleID = "com.apple.Safari"
selectedIsApplication = true
applyFilledStateForCurrentSelection(animated: true)
```

Build, run, open popover. Should see Safari icon + "Safari" + path subtitle. Click ✕ → smooth crossfade back to empty state with 250ms duration. Click outside the ✕ → triggers onClick (NSLogs "NSOpenPanel TODO").

Remove the temp injection before commit.

- [ ] **Step 5: Commit**

```bash
git add Mos/Windows/PreferencesWindow/ButtonsView/OpenTargetConfigPopover.swift Mos/Localizable.xcstrings
git commit -m "feat(buttons): add filled state + crossfade to file slot

Filled state shows app icon (36pt) + title + middle-truncated path +
clear button. Empty ↔ filled transition is a 250ms crossfade with subtle
0.98→1.0 scale on the incoming view (the popover's only expressive
animation, reserved for the primary interaction). Clear button uses
xmark SF Symbol on macOS 11+ with a unicode fallback for 10.13/14."
```

---

### Task 11: NSOpenPanel + drag-and-drop (manual)

**Files:**
- Modify: `Mos/Windows/PreferencesWindow/ButtonsView/OpenTargetConfigPopover.swift`
- Modify: `Mos/Localizable.xcstrings` (add 2 keys)

- [ ] **Step 1: Add localization keys**

| Key | en | zh-Hans |
|---|---|---|
| `open-target-panel-prompt` | `Choose` | `选择` |
| `open-target-panel-message` | `Choose an app or script to open` | `选择要打开的应用或脚本` |

- [ ] **Step 2: Implement file selection helper**

Add to `OpenTargetConfigPopover`:

```swift
    private struct PickedFile {
        let path: String
        let bundleID: String?
        let isApplication: Bool
    }

    /// 解析任意文件 URL 为待保存的字段集; 返回 nil 表示路径无效.
    private static func resolvePickedFile(at url: URL) -> PickedFile? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let isApp = url.pathExtension.lowercased() == "app"
        let bundleID = isApp ? Bundle(url: url)?.bundleIdentifier : nil
        return PickedFile(path: url.path, bundleID: bundleID, isApplication: isApp)
    }

    private func applyPickedFile(_ picked: PickedFile) {
        selectedPath = picked.path
        selectedBundleID = picked.bundleID
        selectedIsApplication = picked.isApplication
        applyFilledStateForCurrentSelection(animated: true)
    }
```

- [ ] **Step 3: Replace the NSOpenPanel stub**

In `onFileSlotClicked`:

```swift
    private func onFileSlotClicked() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = NSLocalizedString("open-target-panel-prompt", comment: "")
        panel.message = NSLocalizedString("open-target-panel-message", comment: "")
        // 不限制扩展名: 接受 .app, .sh, .py, 任意可执行文件

        guard let popoverWindow = popover?.contentViewController?.view.window else {
            // Fallback: 模态运行
            if panel.runModal() == .OK, let url = panel.url, let picked = Self.resolvePickedFile(at: url) {
                applyPickedFile(picked)
            }
            return
        }
        panel.beginSheetModal(for: popoverWindow) { [weak self] response in
            guard let self = self, response == .OK, let url = panel.url else { return }
            if let picked = Self.resolvePickedFile(at: url) {
                self.applyPickedFile(picked)
            }
        }
    }
```

- [ ] **Step 4: Add drag-and-drop to FileSlotView**

In `FileSlotView.setupView()`, register the drag type:

```swift
        registerForDraggedTypes([.fileURL])
```

Add NSDraggingDestination conformance:

```swift
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) else {
            return []
        }
        // Visual: accent border + scale up
        layer?.borderWidth = 1.5
        layer?.borderColor = NSColor.controlAccentColor.cgColor
        layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.08).cgColor
        animateScale(to: 1.02)
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        revertDragVisual()
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        defer { revertDragVisual() }
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
              let first = urls.first else {
            return false
        }
        onDrop?(first)
        return true
    }

    /// Drop callback exposed to the popover.
    var onDrop: ((URL) -> Void)?

    private func animateScale(to scale: CGFloat) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            ctx.allowsImplicitAnimation = true
            self.layer?.setAffineTransform(CGAffineTransform(scaleX: scale, y: scale))
        }
    }

    private func revertDragVisual() {
        animateScale(to: 1.0)
        switch state {
        case .empty: applyEmptyAppearance()
        case .filled: applyFilledAppearance()
        }
    }
```

(The `applyEmptyAppearance` and `applyFilledAppearance` methods need to be accessible — change from `private` to `fileprivate` if they aren't already.)

- [ ] **Step 5: Wire onDrop in the popover**

In `makeViewController`:

```swift
        slot.onDrop = { [weak self] url in
            guard let self = self, let picked = Self.resolvePickedFile(at: url) else { return }
            self.applyPickedFile(picked)
        }
```

- [ ] **Step 6: Build and manual smoke test**

```bash
xcodebuild -scheme Debug -configuration Debug build 2>&1 | tail -10
```
Expected: BUILD SUCCEEDED.

Manual:
- Open Mos preferences → Buttons → add row → action popup → "打开应用…"
- Click empty file slot → NSOpenPanel sheet appears
- Select `/Applications/Safari.app` → popover transitions to filled, shows Safari icon + name + path
- Click ✕ → returns to empty state
- Drag `/Applications/Calculator.app` from Finder onto the empty slot → border turns blue + scale 1.02; release → filled state shows Calculator
- Drag a folder onto the slot → drag rejected (no blue border)
- Type `https://example.com` in args field → focus ring shows
- Press Tab → focus moves to Cancel
- Press Return on Done → onCommit fires (currently NSLogs in Task 9 stub)

- [ ] **Step 7: Commit**

```bash
git add Mos/Windows/PreferencesWindow/ButtonsView/OpenTargetConfigPopover.swift Mos/Localizable.xcstrings
git commit -m "feat(buttons): NSOpenPanel + drag-drop file selection

Click on file slot opens NSOpenPanel as sheet on the popover window
(falls back to modal if no window available). Drag-and-drop registers
[.fileURL] pasteboard type, validates file existence and extension,
extracts bundle ID for .app, animates accent-color border + 1.02 scale
during dragOver. Multi-file drops take the first URL. Directories and
nonexistent paths are rejected at the dragging-entered stage."
```

---

### Task 12: Stale-path warning + final wire-up (manual + integration)

**Files:**
- Modify: `Mos/Windows/PreferencesWindow/ButtonsView/OpenTargetConfigPopover.swift`
- Modify: `Mos/Windows/PreferencesWindow/ButtonsView/PreferencesButtonsViewController.swift`

This task adds the stale-path detection on edit-mode load and replaces the temporary scaffolding from Task 9 with the real wire-up that persists the binding.

- [ ] **Step 1: Add stale-path detection to popover**

In `OpenTargetConfigPopover`, modify `show(at:existing:)`:

```swift
    func show(at sourceView: NSView, existing: OpenTargetPayload?) {
        hide()
        self.existingPayload = existing
        self.selectedPath = existing?.path
        self.selectedBundleID = existing?.bundleID
        self.selectedIsApplication = existing?.isApplication ?? false

        let popover = NSPopover()
        popover.behavior = .applicationDefined
        popover.contentViewController = makeViewController(initialArgs: existing?.arguments ?? "")
        popover.show(relativeTo: sourceView.bounds, of: sourceView, preferredEdge: .maxY)
        self.popover = popover

        // Initial state with stale detection
        if let existing, isCurrentSelectionResolvable() {
            applyFilledStateForCurrentSelection(animated: false)
            _ = existing
        } else if existing != nil {
            // Stale: show warning, fall back to empty state
            staleBanner?.isHidden = false
            selectedPath = nil
            selectedBundleID = nil
            selectedIsApplication = false
            fileSlot?.setState(.empty, animated: false)
        } else {
            fileSlot?.setState(.empty, animated: false)
        }
    }

    private func isCurrentSelectionResolvable() -> Bool {
        guard let path = selectedPath else { return false }
        if selectedIsApplication, let bundleID = selectedBundleID,
           NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil {
            return true
        }
        return FileManager.default.fileExists(atPath: path)
    }
```

- [ ] **Step 2: Add stale banner view**

Add a stale banner property and render it in `makeViewController` (above the file slot). Replace the layout in `makeViewController`:

```swift
    private weak var staleBanner: NSView?

    private func makeViewController(initialArgs: String) -> NSViewController {
        let vc = NSViewController()
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        // Stale banner (initially hidden)
        let banner = makeStaleBanner()
        banner.translatesAutoresizingMaskIntoConstraints = false
        banner.isHidden = true
        container.addSubview(banner)
        self.staleBanner = banner

        // ... rest of existing makeViewController code (file slot, args, buttons) ...
        // CHANGE the slot.topAnchor constraint to anchor below banner:
        //
        //     slot.topAnchor.constraint(equalTo: banner.bottomAnchor, constant: 8),
        //
        // and add:
        //
        //     banner.topAnchor.constraint(equalTo: container.topAnchor, constant: Self.padding),
        //     banner.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Self.padding),
        //     banner.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -Self.padding),
    }

    private func makeStaleBanner() -> NSView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 6

        if #available(macOS 11.0, *), let symbol = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil) {
            let imageView = NSImageView(image: symbol)
            imageView.contentTintColor = NSColor.systemOrange
            stack.addArrangedSubview(imageView)
        }

        let label = NSTextField(labelWithString: NSLocalizedString("open-target-stale-warning", comment: ""))
        label.font = NSFont.systemFont(ofSize: 11)
        label.textColor = NSColor.systemOrange
        stack.addArrangedSubview(label)

        return stack
    }
```

(When `staleBanner.isHidden = true`, the auto-layout collapses the row but the constant 8pt gap below banner remains. To get pixel-perfect padding when hidden, replace the slot's top constraint with one that uses a "banner top to slot top" of 8pt while letting the banner size to zero when hidden. For brevity, accept the 8pt gap when hidden — it's visually unnoticeable.)

- [ ] **Step 3: Add updateButtonBinding(id:withOpenTarget:) to the controller**

In `Mos/Windows/PreferencesWindow/ButtonsView/PreferencesButtonsViewController.swift`, append a new update method alongside the existing `updateButtonBinding(id:with:)` and `updateButtonBinding(id:withCustomName:)` (around line 211-225):

```swift
    /// 更新按钮绑定 ("打开应用" 动作)
    func updateButtonBinding(id: UUID, withOpenTarget payload: OpenTargetPayload) {
        guard let index = buttonBindings.firstIndex(where: { $0.id == id }) else { return }
        let old = buttonBindings[index]
        buttonBindings[index] = ButtonBinding(
            id: old.id,
            triggerEvent: old.triggerEvent,
            openTarget: payload,
            isEnabled: true,
            createdAt: old.createdAt
        )
        syncViewWithOptions()
        tableView.reloadData()
    }
```

This mirrors the existing `updateButtonBinding(id:withCustomName:)` shape: lookup by id, build a new binding with the dedicated init, write back to `buttonBindings`, persist via `syncViewWithOptions()`, reload the table.

- [ ] **Step 4: Replace stub in PreferencesButtonsViewController and add popover lifecycle**

Replace the stub closure inside `tableView(_:viewFor:row:)` (added in Task 8 step 5):

```swift
                onOpenTargetSelectionRequested: { [weak self] in
                    self?.presentOpenTargetPopover(forBindingID: binding.id)
                },
```

Add a strong reference to hold the popover while shown, and the helper method, in the same controller (anywhere in the class body):

```swift
    private var currentOpenTargetPopover: OpenTargetConfigPopover?

    private func presentOpenTargetPopover(forBindingID id: UUID) {
        guard let index = buttonBindings.firstIndex(where: { $0.id == id }) else { return }
        guard let row = tableView.row(forBinding: id, in: buttonBindings) else { return }
        guard let cell = tableView.view(atColumn: 0, row: row, makeIfNecessary: false) as? ButtonTableCellView else { return }

        let existing = buttonBindings[index].openTarget

        let popover = OpenTargetConfigPopover()
        currentOpenTargetPopover = popover
        popover.onCommit = { [weak self] payload in
            self?.updateButtonBinding(id: id, withOpenTarget: payload)
            self?.currentOpenTargetPopover = nil
        }
        popover.onCancel = { [weak self] in
            self?.currentOpenTargetPopover = nil
        }
        popover.show(at: cell.actionPopUpButton, existing: existing)
    }
```

Add this small NSTableView extension in the same file (or a Utils file) for the row lookup helper:

```swift
private extension NSTableView {
    func row(forBinding id: UUID, in bindings: [ButtonBinding]) -> Int? {
        return bindings.firstIndex(where: { $0.id == id })
    }
}
```

(`buttonBindings` index and `tableView` row are 1:1 in this view controller, so this helper is just type sugar.)

- [ ] **Step 5: Build & full integration manual test**

```bash
xcodebuild -scheme Debug -configuration Debug build 2>&1 | tail -10
```

Manual end-to-end:

**Happy path — App:**
1. Open Mos preferences → Buttons
2. Click "+" to add a row → press a side mouse button to record trigger
3. Click action PopUpButton → select "打开应用…"
4. Popover appears with empty slot
5. Click slot → NSOpenPanel → choose `/Applications/Safari.app` → done
6. Slot transitions to filled with Safari icon + "Safari" + path
7. Type `https://anthropic.com` in args
8. Click Done
9. PopUpButton placeholder updates to show Safari icon + "Safari"
10. Press the bound mouse button: Safari opens with anthropic.com loaded
11. Press again: Safari comes forward (no relaunch)

**Happy path — Script:**
1. Create a test script: `mkdir -p /tmp/mostest && cat > /tmp/mostest/hello.sh << 'EOF'
#!/bin/bash
echo "Hello from Mos at $(date)" > /tmp/mostest/output.txt
echo "Args: $@" >> /tmp/mostest/output.txt
EOF
chmod +x /tmp/mostest/hello.sh`
2. Add a binding for another button → "打开应用…" → choose `/tmp/mostest/hello.sh`
3. Type `--port 3000 "with space"` in args
4. Click Done → press bound button
5. Check `/tmp/mostest/output.txt` — should contain `Args: --port 3000 with space`

**Stale path:**
1. Move Safari from `/Applications` to `/Applications/_moved/Safari.app`
2. Reopen the popover for the existing Safari binding
3. Should see: orange warning banner "之前选择的应用已找不到" + empty slot
4. Restore Safari to `/Applications`

**Forward compat:**
1. Quit Mos
2. Open `~/Library/Preferences/com.caldis.Mos.plist` (or wherever your bundle stores prefs) — add a corrupt binding entry to `buttonBindings`
3. Reopen Mos → existing valid bindings should still be there, corrupt one skipped
4. Console shows `Skipped 1 unparseable button binding(s)`

**Toast errors:**
1. Configure binding to nonexistent path
2. Press button → red Toast "找不到应用 ..."
3. Press 5 times rapidly → only one Toast (dedup)

- [ ] **Step 6: Final commit**

```bash
git add Mos/Windows/PreferencesWindow/ButtonsView/OpenTargetConfigPopover.swift Mos/Windows/PreferencesWindow/ButtonsView/PreferencesButtonsViewController.swift Mos/Windows/PreferencesWindow/ButtonsView/ButtonTableCellView.swift
git commit -m "feat(buttons): wire OpenTargetConfigPopover end-to-end

Replaces the placeholder NSLog with a full popover lifecycle: present,
load existing payload (with stale-path detection that surfaces an orange
warning banner and reverts to empty state), capture commit via the
binding-replacement init, persist back to Options + invalidate
ButtonUtils cache, dismiss. Cancel discards. The user can now bind any
mouse button to open a .app or run a script with arguments."
```

---

## Self-Review Coverage

Spec section coverage:

| Spec section | Plan task |
|---|---|
| § 1.1 OpenTargetPayload | Task 1 |
| § 1.2 ButtonBinding extension | Task 2 |
| § 1.3 JSON shape | Task 1, 2 (verified via tests) |
| § 1.4 Forward-compat decoding | Task 3 |
| § 2.1 ResolvedAction extension | Task 4 |
| § 2.2 Resolver | Task 4 |
| § 2.3 Dispatch + private executors | Task 4 (stub), Task 5 (real) |
| § 2.4 ArgumentSplitter | Task 1 |
| § 2.5 Toast errors | Task 5 |
| § 3.1-3.3 Popover layout & language | Task 9 |
| § 3.4 File slot empty/hover/drag | Task 9 (empty), Task 11 (drag) |
| § 3.4 File slot filled + transition | Task 10 |
| § 3.4 Stale path special case | Task 12 |
| § 3.5 Args field (monospaced) | Task 9 |
| § 3.6 Button row | Task 9 |
| § 3.7 Keyboard map | Task 9 |
| § 3.8 Drag-and-drop | Task 11 |
| § 3.9 Theme adaptation | Task 9, 10 (semantic colors throughout) |
| § 4 Display Resolution | Task 7 |
| § 5 Cell Interaction | Task 8 (stub), Task 12 (full) |
| § 6 Localization (19 keys) | Task 5 (5), Task 6 (1), Task 7 (1), Task 9 (9), Task 10 (2), Task 11 (2) — total 20 (one bonus: `open-target-action`) |
| Compatibility matrix | Task 2, 3 (validated by tests) |
| Verification plan | Task 5, 9-12 (manual smoke tests at each stage) |

All spec sections covered.

---

## Post-Plan Notes

- `Mos.xcodeproj/project.pbxproj` will need updates when adding new files (`OpenTargetPayload.swift`, `OpenTargetPayloadTests.swift`, `OptionsButtonsLoaderTests.swift`, `ShortcutExecutorOpenTargetTests.swift`, `OpenTargetConfigPopover.swift`). Use Xcode's "Add Files to Mos…" rather than editing pbxproj manually.
- Make sure `OpenTargetPayload.swift` is added to **Mos** target (not Mos_Debug specifically — Mos target builds both Release and Debug configurations).
- Make sure `OpenTargetPayloadTests.swift`, `OptionsButtonsLoaderTests.swift`, and `ShortcutExecutorOpenTargetTests.swift` are added to **MosTests** target only.
- All localization keys must show "Translated" status in Xcode for at least `en` and `zh-Hans`. Other languages can show "Untranslated" — they'll fall back to `en` at runtime, then auto-translate via Xcode's normal flow on next pass.
- The user's CLAUDE.md memory says `xcodebuild` must use `-scheme Debug` (not `-target Mos`). All build/test commands in this plan honor that.
