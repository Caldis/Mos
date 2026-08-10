# Open Target Action Design

## Overview

Add a new button binding action type **"Open…"** that launches a `.app` bundle, runs an executable script, or opens any other file with its default app, when the bound mouse button is pressed. Apps and scripts accept user-supplied arguments; default-app file open does not. The new action is the first entry in Mos's button system that carries structured per-binding configuration data (path + bundleID + arguments + kind) rather than a simple string identifier.

This work also establishes the **archive-friendly persistence pattern** for future related features: data export, config-file ingestion, and AI-assisted rewriting of bindings.

## Evolution Since Initial Design

This spec was originally written for a **two-state action** (apps vs. scripts via `isApplication: Bool`). Implementation revealed that allowing the user to drag any file (e.g. a PNG) was a natural extension; the design has since evolved to a **three-state `kind: OpenTargetKind`** (`.application` / `.script` / `.file`), with backward-compatible Codable migration from the old `isApplication` shape. Other notable post-implementation changes captured in this spec:

- **Menu entry renamed**: `"Open Application…"` → `"Open…"` (more inclusive of the three kinds)
- **CellActionState consolidation**: the cell view's per-action-type fields (`currentShortcut` / `currentCustomName` / `currentOpenTarget` / `isCustomRecordingActive`) were collapsed into a single `CellActionState` enum so the compiler enforces switch-coverage when new action types are added (see § 4)
- **Subprocess env hardening**: when launching `.application` via XPC/`NSWorkspace.openApplication` or `.script` via `Process()`, Xcode-injected env vars (`DYLD_INSERT_LIBRARIES`, `__XPC_DYLD_*`, etc.) propagate into the child and crash sealed-system apps that don't satisfy `libViewDebuggerSupport.dylib`'s symbol expectations. Mitigated by `unsetenv`-ing those keys at app startup (see § 7)
- **NSWorkspace as canonical app launcher**: the original spec proposed `NSWorkspace.openApplication`, switched briefly to `Process(/usr/bin/open)` for cold-start reliability, then back to `NSWorkspace.openApplication` (with macOS 10.13/14 fallback to legacy `launchApplication`) once the env source-clearing fix landed

## Requirements

- New action type accessible from the action picker in `ButtonsView`
- Single unified action handles `.app` / executable scripts / arbitrary files; runtime branches by a 3-state `kind: OpenTargetKind` enum captured at config time
- Per-binding configuration: file path, bundle ID (apps only), arguments string, kind enum
- Smart relaunch semantics: `NSWorkspace.OpenConfiguration.activates = true` for apps (existing instance brought forward); scripts run silently in the background each press; files open with their system-default app
- Arguments parsed shell-style (whitespace separation, double-quote groups, backslash escape); only meaningful for `.application` and `.script` kinds (`.file` ignores arguments because `NSWorkspace.open(_:)` doesn't accept argv)
- Path robustness: `.app` resolved by bundle ID first, falls back to absolute path; scripts/files use absolute path only
- User-visible failure feedback via Toast (no NSLog-only failures)
- Persistence schema must be: self-describing JSON, plain-text values, AI-rewritable, forward-compatible (and backward-compatible: a binding written under the old two-state schema must still decode)
- Forward compatibility: reading binding data written by a future Mos version must not corrupt existing bindings
- Subprocess env isolation: child apps/scripts must not inherit Xcode-injected `DYLD_INSERT_LIBRARIES` etc. from Mos's debug-launched env (would otherwise crash sealed system apps using AVKit)
- macOS 10.13+ compatibility
- All UI strings localizable

## Non-goals

- Migration of existing `custom::<code>:<modifiers>` encoding into the new structured form
- Configuration export/import UI
- Reading bindings from `~/.mos/config.json`
- Visible-Terminal mode for script output (users can wrap with `open -a Terminal …` manually)
- Multi-instance launch / toggle-launch / quit-app modes
- URL opening as a separate action type
- Multi-file batch binding via drag

## Design

### 1. Persistence Layer

#### 1.1 `OpenTargetPayload`

New file `Mos/Shortcut/OpenTargetPayload.swift`:

```swift
import Foundation

/// 三态枚举: 配置时确定, 持久化保存, 运行时直接派发, 不依赖文件系统启发式.
enum OpenTargetKind: String, Codable {
    case application   // .app bundle, 通过 NSWorkspace.openApplication 启动 (支持 launch arguments)
    case script        // 可执行脚本或二进制, 通过 Process 运行 (支持 argv)
    case file          // 普通文件 (PDF / 图片 / 视频 / 文本 / etc.), 通过 NSWorkspace.open 用系统默认 app 打开
}

/// "打开" 动作的持久化结构.
/// 设计目标: 自描述、可 AI 改写、可手编辑.
struct OpenTargetPayload: Equatable {

    /// 文件绝对路径 (.app / 脚本 / 任意文件)
    let path: String

    /// .app 的 bundle identifier; 仅 kind=.application 时非 nil.
    /// 运行时优先使用此值解析 App, 即便 .app 被移动到别处也能找到
    let bundleID: String?

    /// 用户原始输入的参数字符串 (空字符串 = 无参数).
    /// 执行时按 shell 风格 split. 仅 .application / .script 使用; .file 忽略
    /// (NSWorkspace.open 不支持参数).
    let arguments: String

    /// 配置时确定的目标类型. 决定运行时执行路径.
    let kind: OpenTargetKind
}

// 自定义 Codable 兼容老数据 (原本只有 isApplication: Bool):
//  - 解码: 优先读 kind, 缺失则 fallback 读 isApplication (true → .application, false → .script)
//  - 编码: 只写 kind, 不再保留 isApplication, 避免双源
extension OpenTargetPayload: Codable { /* ... */ }
```

Field design rationale:

- **Plain-text values, no base64/hex** — supports archival, manual editing, AI rewrite without schema docs
- **`bundleID` stored separately** rather than re-extracted from `path` at runtime — decouples persistence from filesystem state, allows AI to edit `path` and `bundleID` together coherently
- **`arguments` stored as raw string** rather than `[String]` — matches user input mental model, defers tokenization to a single shared splitter
- **`kind` as 3-state enum** instead of multiple boolean flags — type-safe; switch over the enum at runtime gets compile-time exhaustiveness checking; adding a new kind (e.g. `.openURL`) is one new enum case + one new switch arm
- **Backward-compat Codable**: legacy data with `isApplication: Bool` (no `kind` field) still decodes via custom `init(from:)` that reads either field

#### 1.2 `ButtonBinding` Extension

Modify `Mos/Windows/PreferencesWindow/ButtonsView/RecordedEvent.swift`:

```swift
struct ButtonBinding: Codable, Equatable {
    static let openTargetSentinel = "openTarget"

    let id: UUID
    let triggerEvent: RecordedEvent
    let systemShortcutName: String      // discriminator
    var isEnabled: Bool
    let createdAt: Date
    let openTarget: OpenTargetPayload?  // NEW

    // Existing transient cache fields unchanged
    private(set) var cachedCustomCode: UInt16? = nil
    private(set) var cachedCustomModifiers: UInt64? = nil

    enum CodingKeys: String, CodingKey {
        case id, triggerEvent, systemShortcutName, isEnabled, createdAt, openTarget
    }

    /// New dedicated init for OpenTarget bindings
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
}
```

Schema design rationale:

- **Optional field** — old JSON without `openTarget` deserializes to `nil`; no migration needed
- **`systemShortcutName` as discriminator** — value `"openTarget"` indicates `openTarget` field is authoritative; reuses existing dispatcher field, avoids parallel "kind" field
- **Static sentinel constant** — single source of truth, prevents string drift across `ShortcutManager`, `ShortcutExecutor`, `ActionDisplayResolver`

#### 1.3 Serialized JSON Shape

OpenTarget binding:

```json
{
  "id": "9F4A2D3E-...",
  "triggerEvent": {
    "type": "mouse",
    "code": 4,
    "modifiers": 0,
    "displayComponents": ["M5"],
    "deviceFilter": null
  },
  "systemShortcutName": "openTarget",
  "isEnabled": true,
  "createdAt": "2026-04-26T10:30:00Z",
  "openTarget": {
    "path": "/Applications/Safari.app",
    "bundleID": "com.apple.Safari",
    "arguments": "https://example.com",
    "kind": "application"
  }
}
```

Existing binding (unchanged shape, `openTarget: null` appended):

```json
{
  "id": "...",
  "triggerEvent": { ... },
  "systemShortcutName": "copy",
  "isEnabled": true,
  "createdAt": "...",
  "openTarget": null
}
```

#### 1.4 Forward-Compatible Per-Binding Decoding

Modify `Mos/Options/Options.swift` `loadButtonsData()`:

```swift
private func loadButtonsData() -> [ButtonBinding] {
    let rawValue = UserDefaults.standard.object(forKey: OptionItem.Button.Bindings)
    guard let data = rawValue as? Data else {
        if rawValue != nil {
            NSLog("Button bindings data has wrong type: \(type(of: rawValue)), clearing corrupted data")
            UserDefaults.standard.removeObject(forKey: OptionItem.Button.Bindings)
        }
        return []
    }

    // Step 1: Parse the outer JSON array without decoding individual elements
    guard let elements = try? JSONSerialization.jsonObject(with: data) as? [Any] else {
        NSLog("Button bindings data is not a JSON array, resetting to defaults")
        UserDefaults.standard.removeObject(forKey: OptionItem.Button.Bindings)
        return []
    }

    // Step 2: Try-decode each binding individually; skip & log failures
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

This replaces the existing "any decode failure → wipe everything" behavior. With per-binding tolerance, a future Mos version that introduces a new payload kind can be opened by the current Mos without corrupting the user's other bindings.

### 2. Execution Layer

#### 2.1 `ResolvedAction` Extension

Modify `Mos/Shortcut/ShortcutExecutor.swift`:

```swift
enum ResolvedAction {
    case customKey(code: UInt16, modifiers: UInt64)
    case mouseButton(kind: MouseButtonActionKind)
    case systemShortcut(identifier: String)
    case logiAction(identifier: String)
    case openTarget(payload: OpenTargetPayload)    // NEW

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

`OpenTarget` is `.trigger` mode — fires once on keyDown only.

#### 2.2 Resolver

Add the new branch ahead of `cachedCustomCode` to avoid mis-matching:

```swift
func resolveAction(named shortcutName: String, binding: ButtonBinding? = nil) -> ResolvedAction? {
    if let payload = binding?.openTarget,
       shortcutName == ButtonBinding.openTargetSentinel {
        return .openTarget(payload: payload)
    }
    if let code = binding?.cachedCustomCode { ... }
    // existing branches unchanged
}
```

#### 2.3 Dispatch and Private Executors

Add a switch case in `execute(action:phase:...)`:

```swift
case .openTarget(let payload):
    guard phase == .down else { return .none }
    executeOpenTarget(payload)
    return .none
```

Add three new private methods, parallel in style to `executeMouseButton` / `executeLogiAction`. Note that the actual open work runs on a dedicated `userInitiated` background queue — the dispatch chain that arrives here originates from a CGEvent tap callback, which has a strict latency budget (default ~1 s); any synchronous `NSWorkspace.openApplication` / `Process.run()` / `FileManager` call risks getting the tap auto-disabled by the system.

```swift
// Serial userInitiated queue; calls below all hop here before doing real work.
private static let openTargetQueue = DispatchQueue(label: "com.caldis.Mos.openTarget", qos: .userInitiated)

private func executeOpenTarget(_ payload: OpenTargetPayload) {
    Self.openTargetQueue.async { [payload] in
        switch payload.kind {
        case .application: self.launchApplication(payload)
        case .script:      self.runScript(payload)
        case .file:        self.openFile(payload)
        }
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

    guard let resolvedURL else { /* Toast: app not found */ return }

    let appArguments = ArgumentSplitter.split(payload.arguments)
    let appName = resolvedURL.deletingPathExtension().lastPathComponent

    if #available(macOS 10.15, *) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true   // 已运行则置前 (不重启)
        configuration.arguments = appArguments
        workspace.openApplication(at: resolvedURL, configuration: configuration) { _, error in
            if error != nil { /* Toast: app launch failed */ }
        }
    } else {
        // macOS 10.13/10.14 fallback: legacy launchApplication. 同样走 LaunchServices.
        var configuration: [NSWorkspace.LaunchConfigurationKey: Any] = [:]
        if !appArguments.isEmpty { configuration[.arguments] = appArguments }
        do {
            _ = try workspace.launchApplication(at: resolvedURL, options: [.default], configuration: configuration)
        } catch {
            // Toast: app launch failed
        }
    }
}

private func openFile(_ payload: OpenTargetPayload) {
    // 用系统默认 app 打开任意文件 (PNG / PDF / 文本 / etc.).
    // NSWorkspace.open(_:) 不支持参数, payload.arguments 在此忽略.
    let url = URL(fileURLWithPath: payload.path)
    guard FileManager.default.fileExists(atPath: url.path) else { /* Toast: file not found */ return }
    if !NSWorkspace.shared.open(url) { /* Toast: open failed */ }
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

#### 2.4 `ArgumentSplitter`

Co-located in `OpenTargetPayload.swift` (small enough to share file):

```swift
/// shell 风格参数切分: 按空白分隔, 支持双引号包裹空白, 反斜杠转义下一字符
/// 例: `--port=3000 "with space" \"escaped\"` → ["--port=3000", "with space", "\"escaped\""]
enum ArgumentSplitter {
    static func split(_ raw: String) -> [String] {
        var args: [String] = []
        var current = ""
        var inQuotes = false
        var iterator = raw.unicodeScalars.makeIterator()
        while let c = iterator.next() {
            if c == "\\" {
                if let next = iterator.next() {
                    current.unicodeScalars.append(next)
                }
                continue
            }
            if c == "\"" {
                inQuotes.toggle()
                continue
            }
            if !inQuotes && CharacterSet.whitespaces.contains(c) {
                if !current.isEmpty {
                    args.append(current)
                    current = ""
                }
                continue
            }
            current.unicodeScalars.append(c)
        }
        if !current.isEmpty {
            args.append(current)
        }
        return args
    }
}
```

#### 2.5 Failure Toast Catalog

| Scenario | Localization key | Style | Rationale |
|---|---|---|---|
| App path & bundleID both unresolvable | `openTargetAppNotFound` | `.error` | Hard failure, user must reconfigure |
| App launch returned error | `openTargetAppLaunchFailed` | `.error` | System-level failure (sandbox, quarantine, corrupted) |
| Script file does not exist | `openTargetScriptNotFound` | `.error` | Hard failure, user must reconfigure |
| Script lacks execute permission | `openTargetScriptNotExecutable` | `.warning` | User can self-resolve via `chmod +x` — orange tone encourages action |
| Script `Process.run()` throws | `openTargetScriptFailed` | `.error` | Likely shebang or interpreter issue |

Toast's default `allowDuplicateVisibleMessage: false` provides automatic spam suppression when a stuck binding is repeatedly triggered.

### 3. UI Layer

#### 3.1 Aesthetic Direction

The popover follows Mos's existing "restrained native + micro-expression" language. All differentiation lives in two intentional micro-decisions:

1. **The file slot is the primary tactile object** — not a button + label combo, but a single click-and-drop card with distinct empty/filled visual languages
2. **Arguments use a monospaced font** (`SF Mono`) — visually signals "this is CLI semantics" and distinguishes the field from any system NSTextField

Everything else stays native: system bezel buttons, system focus ring, semantic colors via NSColor tokens, automatic light/dark adaptation.

#### 3.2 Menu Entry

In `ShortcutManager.buildShortcutMenu`, add a top-level entry above the existing "自定义快捷键…":

```
─── (separator) ───
↗  打开应用…              ← NEW
⌨  自定义快捷键…
```

- Sentinel: `__open__`
- SF Symbol: `arrow.up.forward.app`
- Localization key: `open-target-action`

#### 3.3 Overall Layout

```
┌─────────────────────────────────────────┐  popover (320pt content / 16pt padding)
│                                         │
│  ┌ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ┐   │
│                                         │
│        选择应用或脚本                   │  ← File slot (320 × 64pt)
│        或拖拽到此处                     │
│                                         │
│  └ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ┘   │
│                                         │
│  参数 (可选)                            │  ← 11pt caption
│  ┌─────────────────────────────────┐    │
│  │ 用空格分隔, 引号包裹含空格的参数 │    │  ← SF Mono 12pt
│  └─────────────────────────────────┘    │
│                                         │
│                       [取消] [完成]     │  ← Standard 28pt buttons
│                                         │
└─────────────────────────────────────────┘
                                            Final size: 352 × 198pt
```

Vertical rhythm (4pt grid):
- 16 padding + 64 file slot + 12 + (14 caption + 6 + 26 input) + 16 + 28 buttons + 16 padding = 198pt

#### 3.4 File Slot

##### Empty state

| Property | Value |
|---|---|
| Size | 320 × 64pt |
| Corner radius | 8pt |
| Border | 1pt dashed, `secondaryLabelColor.withAlphaComponent(0.5)` |
| Background | `getMainLightBlack(for:)` × 4% alpha |
| Content | Centered vertical stack: 13pt regular labelColor primary, 11pt regular tertiaryLabelColor secondary, 2pt gap |
| Primary text | `选择应用或脚本` |
| Secondary text | `或拖拽到此处` |
| Cursor | Pointing hand |

##### Empty hover

- Border alpha 0.5 → 0.8 (150ms ease-out)
- Background 4% → 7% alpha
- No scale, no elevation

##### Drag-over

- Border 1.5pt solid `controlAccentColor`
- Background `controlAccentColor` × 8% alpha
- Scale 1.0 → 1.02 (200ms ease-out)

##### Filled state

```
┌─────────────────────────────────────┐
│  [icon]  Safari                  ⊗  │   ← 36pt app icon via NSWorkspace
│          /Applications/Safari.app    │   ← middle-truncated path
└─────────────────────────────────────┘
```

| Property | Value |
|---|---|
| Size | 320 × 64pt (matches empty for layout stability) |
| Border | 1pt solid, `separatorColor` |
| Background | `getMainLightBlack` × 3% alpha |
| Inner padding | 12pt horizontal, 14pt vertical |
| App icon | 36 × 36pt, `NSWorkspace.shared.icon(forFile:)` |
| Primary text | App `displayName` or script filename, 13pt medium labelColor |
| Subtitle | Full path, 10.5pt regular tertiaryLabelColor, `lineBreakMode = .byTruncatingMiddle` |
| Clear button | 16 × 16pt, "xmark" SF Symbol; default tertiaryLabelColor; hover systemRed |
| Body cursor | Pointing hand (clear button = arrow) |
| Body click | Re-opens NSOpenPanel |
| Tooltip | Full path + `点击重新选择` |

##### Empty ↔ Filled transition

`NSAnimationContext` 250ms `easeInOut`. Incoming view fades from alpha 0 + scale 0.98 to alpha 1.0 + scale 1.0; outgoing view fades opposite. This is the popover's sole "expressive" animation, reserved for the primary interaction.

##### Stale path special case

When opening the popover to edit an existing binding whose path no longer resolves (and bundle ID also fails to resolve for `.app`):

- File slot falls back to empty state visually
- A 14pt warning banner appears above the slot:
  ```
  ⚠  之前选择的应用已找不到
  ```
- Banner: 11pt, `systemOrange`, leading SF Symbol `exclamationmark.triangle.fill`
- Forces user to re-pick before binding can be saved

#### 3.5 Arguments Field

| Property | Value |
|---|---|
| Caption font | 11pt regular |
| Caption color | `labelColor`, `(可选)` suffix `tertiaryLabelColor` |
| Caption gap | 6pt below caption |
| Field size | 320 × 26pt |
| Field bezel | `.roundedBezel` |
| Field font | `NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)` |
| Field color | `controlTextColor` (default) |
| Placeholder | `用空格分隔, 引号包裹含空格的参数` |
| Focus | System default focus ring |

`monospacedSystemFont` exists since macOS 10.15. For 10.13/10.14, fall back to `NSFont(name: "Menlo", size: 12)` — `Menlo` ships with all macOS versions.

#### 3.6 Button Row

- Right-aligned to right inner padding
- 8pt gap between buttons
- **Cancel**: `NSButton(bezelStyle: .rounded)`, no keyEquivalent, action → `dismiss`
- **Done**: `NSButton(bezelStyle: .rounded)`, `keyEquivalent = "\r"` (system applies blue accent), `isEnabled = (validFilledState)`

`PrimaryButton` is intentionally not used here — that component is for window-level CTAs (Introduction/Welcome). Standard NSButton is correct for popover form actions.

#### 3.7 Keyboard Map

| Key | Action |
|---|---|
| Esc | Cancel (close, no save) |
| Return | Done (if button enabled) |
| Tab | File slot → Args field → Cancel → Done |
| ⌘W | Cancel |

#### 3.8 Drag-and-drop

- File slot registers `[.fileURL]` pasteboard type
- `prepareForDragOperation` validates: must be file URL, file must exist
- Multiple files: take first, ignore rest
- `.app` extension → `kind = .application`, extract bundle ID via `Bundle(url:)?.bundleIdentifier`
- Executable bit set on non-`.app` → `kind = .script`, `bundleID = nil`
- Anything else (regular file: PNG, PDF, text, etc.) → `kind = .file`, `bundleID = nil`
- The same validation function is shared with the NSOpenPanel completion handler (DRY)
- When `kind = .file` is selected, the Args section is hidden in the popover (NSWorkspace.open doesn't accept argv, showing the field would mislead users)

#### 3.9 Theme Adaptation

All colors use NSColor semantic tokens:

| Role | Token |
|---|---|
| Body text | `labelColor` / `secondaryLabelColor` / `tertiaryLabelColor` |
| Border (filled) | `separatorColor` |
| Border (empty dashed) | `secondaryLabelColor.withAlphaComponent(0.5)` |
| Accent (drag) | `controlAccentColor` |
| Warning | `systemOrange` |
| Destructive (clear hover) | `systemRed` |
| Card tint | `NSColor.getMainLightBlack(for:)` × variable alpha |

Light/dark switching is automatic.

### 4. Display Resolution

Modify `Mos/Windows/PreferencesWindow/ButtonsView/ActionDisplayResolver.swift`:

Add `.openTarget` as the first branch in `resolve(...)`, ahead of `customBindingName`:

```swift
if shortcut == nil, let payload = currentBinding?.openTarget {
    return openTargetPresentation(for: payload)
}
```

`openTargetPresentation` returns:
- `kind: .openTarget` (new `ActionPresentationKind` case)
- `title`: app `displayName` or script filename; if path resolves to nothing, `(应用已失效)` localized text
- App icon via `NSWorkspace.shared.icon(forFile:)` resized to 17pt (badge height)
- `brand: nil`

Modify `ActionDisplayRenderer.swift` to handle `.openTarget`:
- Use the resolved file icon (not SF Symbol)
- Append same trailing-space treatment as SF Symbol path (consistency)

Note: `ActionPresentation` already supports passing arbitrary `NSImage`; this requires generalizing slightly — replace `symbolName: String?` with `image: NSImage?` resolved upstream, OR add a parallel `image` field. Choose the latter (additive) to minimize churn:

```swift
struct ActionPresentation {
    let kind: ActionPresentationKind
    let title: String
    let symbolName: String?       // existing, used for SF Symbol path
    let image: NSImage?           // NEW, used for OpenTarget app icon
    let badgeComponents: [String]
    let brand: BrandTagConfig?
}
```

### 5. Cell Interaction

Modify `Mos/Windows/PreferencesWindow/ButtonsView/ButtonTableCellView.swift`:

In `shortcutSelected(_:)`, before the `__custom__` branch:

```swift
if sender.representedObject as? String == "__open__" {
    beginOpenTargetSelection()
    return
}
```

`beginOpenTargetSelection()` instantiates `OpenTargetConfigPopover` (loaded with current binding's `openTarget` if any), shows it relative to `actionPopUpButton`, and on `done` callback:

```swift
guard let existing = currentBinding else { return }   // popover 只从已有 trigger 的行触发
let payload = popover.completedPayload
let newBinding = ButtonBinding(
    id: existing.id,
    triggerEvent: existing.triggerEvent,
    openTarget: payload,
    isEnabled: true
)
onBindingReplaced?(newBinding)
refreshActionDisplay()
```

Invariant: the popover is only ever shown from a table row whose `currentBinding` is already populated (the row exists because the user already recorded a trigger event). The popover lifecycle is owned by the cell view; on `cancel`, no state change.

### 6. Cell State Consolidation (`CellActionState`)

> Added post-implementation. Original spec tracked the cell's "currently displayed action" across four parallel fields: `currentShortcut` / `currentCustomName` / `currentOpenTarget` / `isCustomRecordingActive`. Adding `.openTarget` to the mix exposed how brittle that pattern is — the menu's `adjustMenuStructure.hasBoundAction` check forgot to include `currentOpenTarget`, silently rendering OpenTarget bindings as "未绑定" in the menu top item. Refactored to:

```swift
enum CellActionState: Equatable {
    case unbound
    case recordingPrompt
    case namedShortcut(SystemShortcut.Shortcut)
    case customBinding(name: String)
    case openTarget(OpenTargetPayload)

    var hasBoundAction: Bool { /* exhaustive switch */ }

    init(binding: ButtonBinding) {
        // Priority: openTarget > systemShortcut > customBinding > unbound
    }
}
```

Cell now stores `currentBinding: ButtonBinding?` (the persisted state) + `isCustomRecordingActive: Bool` (the transient overlay). All display logic derives from a computed `actionState: CellActionState`. Adding a new action type = one new enum case; the compiler enforces every switch site (resolver, hasBoundAction, etc.) handles it. No more silent-omission bugs.

`ActionDisplayResolver` gains `resolve(state:)` as the canonical entry point; the legacy `resolve(shortcut:customBindingName:isRecording:openTarget:)` is kept as a thin wrapper for existing tests.

### 7. Subprocess Environment Hardening

> Added post-implementation. When Mos Debug is launched from Xcode, Xcode injects `DYLD_INSERT_LIBRARIES=...libViewDebuggerSupport.dylib` and `__XPC_DYLD_*` env vars onto Mos's process. These propagate via libxpc across the XPC boundary into `launchservicesd`, then into any app Mos asks LaunchServices to launch. Sealed system apps (FindMy, Maps, Podcasts) that depend on AVKit can't satisfy `libViewDebuggerSupport`'s symbol expectations on macOS 26, so they `dyld halt → SIGABRT` immediately on launch.

This is **not** a bug in Mos's launch logic; it's the OS faithfully forwarding what Xcode set. The fix is to clear those env vars from Mos's own environment as early as possible, *before* any subprocess launch:

```swift
// AppDelegate.applicationWillFinishLaunching
ShortcutExecutor.sanitizeOwnLaunchEnvironment()

// In ShortcutExecutor:
static func sanitizeOwnLaunchEnvironment() {
    for key in ProcessInfo.processInfo.environment.keys where shouldStripEnvKey(key) {
        unsetenv(key)
    }
}

private static func shouldStripEnvKey(_ key: String) -> Bool {
    if key.hasPrefix("DYLD_")           { return true }
    if key.hasPrefix("__XPC_DYLD_")     { return true }   // crosses XPC boundary
    if key.hasPrefix("__XPC_LLVM_")     { return true }
    if key == "SWIFTUI_VIEW_DEBUG"      { return true }
    if key.hasPrefix("OS_ACTIVITY_DT_") { return true }
    if key.hasPrefix("MallocStack")     { return true }
    if key == "NSZombieEnabled"         { return true }
    if key == "NSDeallocateZombies"     { return true }
    if key.hasPrefix("LSAN_") || key.hasPrefix("ASAN_")
       || key.hasPrefix("TSAN_") || key.hasPrefix("UBSAN_") { return true }
    return false
}
```

dyld already loaded Mos's own dylibs (including Xcode's view debugger) at process start by reading these env vars; `unsetenv` after launch doesn't unload them, so Xcode's view debugger keeps working in Mos itself. The clearing only affects what subsequent `Process()` / XPC / `NSWorkspace.openApplication` calls hand to children.

**Process.environment override is kept as belt-and-suspenders** for `runScript`, in case future code changes call `Process()` before `applicationWillFinishLaunching` runs.

**Release impact: zero.** These env vars are never set on a normally-launched Release Mos; `unsetenv` is a no-op.

### 8. Localization

All new strings added to `Mos/Localizable.xcstrings`. Chinese and English filled manually; other 10 languages auto-translate via Xcode's normal flow (per `LOCALIZATION.md`).

#### Menu

| Key | 中文 | English |
|---|---|---|
| `open-target-action` | `打开…` | `Open…` |

#### Popover

| Key | 中文 | English |
|---|---|---|
| `open-target-empty-primary` | `选择应用或脚本` | `Choose an app or script` |
| `open-target-empty-secondary` | `或拖拽到此处` | `or drag one here` |
| `open-target-empty-tooltip` | `点击选择文件，或拖拽 .app/脚本到此处` | `Click to choose a file, or drag a .app/script here` |
| `open-target-filled-tooltip` | `点击重新选择` | `Click to choose a different one` |
| `open-target-clear-tooltip` | `清除` | `Clear` |
| `open-target-arguments-label` | `参数` | `Arguments` |
| `open-target-arguments-optional-suffix` | `(可选)` | `(optional)` |
| `open-target-arguments-placeholder` | `用空格分隔, 引号包裹含空格的参数` | `Space-separated; quote arguments containing spaces` |
| `open-target-cancel` | `取消` | `Cancel` |
| `open-target-done` | `完成` | `Done` |
| `open-target-stale-warning` | `之前选择的应用已找不到` | `The previously chosen app can no longer be found` |
| `open-target-panel-prompt` | `选择` | `Choose` |
| `open-target-panel-message` | `选择要打开的应用或脚本` | `Choose an app or script to open` |
| `open-target-placeholder-stale` | `(应用已失效)` | `(unavailable)` |

#### Runtime errors

| Key | 中文 | English |
|---|---|---|
| `openTargetAppNotFound` | `找不到应用 "%@", 可能已被移动或删除` | `Application "%@" not found — it may have been moved or deleted` |
| `openTargetAppLaunchFailed` | `启动 "%@" 失败` | `Failed to launch "%@"` |
| `openTargetScriptNotFound` | `找不到脚本 "%@"` | `Script "%@" not found` |
| `openTargetScriptNotExecutable` | `脚本 "%@" 没有执行权限, 请运行 chmod +x` | `Script "%@" is not executable — run chmod +x` |
| `openTargetScriptFailed` | `脚本 "%@" 执行失败` | `Script "%@" failed to start` |
| `openTargetFileNotFound` | `找不到文件 "%@"` | `File "%@" not found` |
| `openTargetFileFailed` | `无法打开 "%@"` | `Failed to open "%@"` |

Translation conventions (per `LOCALIZATION.md`):
- "打开" → "Open" (Finder/Spotlight terminology, not "Launch")
- "应用" → "Application" (System Preferences terminology, not "App")
- File names, paths, and bundle IDs are never translated

## File-level Change Summary

### New files (2)

| Path | Content | Estimated lines |
|---|---|---|
| `Mos/Shortcut/OpenTargetPayload.swift` | `OpenTargetPayload` struct + `ArgumentSplitter` enum | ~80 |
| `Mos/Windows/PreferencesWindow/ButtonsView/OpenTargetConfigPopover.swift` | Popover NSViewController + file slot NSView + drag support | ~280 |

### Modified files (8)

| Path | Change |
|---|---|
| `Mos/Windows/PreferencesWindow/ButtonsView/RecordedEvent.swift` | `ButtonBinding` adds `openTarget` field, `openTargetSentinel` constant, dedicated init, CodingKey |
| `Mos/Shortcut/ShortcutExecutor.swift` | `ResolvedAction` adds `.openTarget` case + `executionMode`; `resolveAction` adds sentinel branch; new `executeOpenTarget` / `launchApplication` / `runScript` private methods |
| `Mos/Shortcut/ShortcutManager.swift` | Menu builder adds top-level "打开…" entry |
| `Mos/Windows/PreferencesWindow/ButtonsView/ButtonTableCellView.swift` | `shortcutSelected(_:)` recognizes `__open__` sentinel; new `beginOpenTargetSelection()` |
| `Mos/Windows/PreferencesWindow/ButtonsView/ActionDisplayResolver.swift` | New `.openTarget` branch with app icon presentation |
| `Mos/Windows/PreferencesWindow/ButtonsView/ActionDisplayRenderer.swift` | `.openTarget` rendering case; add `image` field to `ActionPresentation` |
| `Mos/Options/Options.swift` | `loadButtonsData` rewritten with per-binding tolerant decoding |
| `Mos/Localizable.xcstrings` | All keys from § 6 |

Total: ~30 lines of external touch + ~360 lines of new feature code. All changes scoped to `Shortcut/`, `ButtonsView/`, and `Options/` directories — the existing homes of the button/action subsystem.

## Compatibility Matrix

| Scenario | Behavior | Mechanism |
|---|---|---|
| New Mos reads old binding (no `openTarget` field) | Old `systemShortcutName` path unchanged | Optional Codable field |
| Old Mos reads new binding (has `openTarget`) | Unknown sentinel → `resolveAction` returns nil → silent no-op; binding preserved | `getShortcut(named:)` returns nil for unknown ID |
| Current Mos reads future binding (unknown payload) | The binding's raw JSON is preserved in `Options.preservedUnknownBindings`; on next save it's merged back into the array, so a downgrade-then-upgrade cycle doesn't lose data | Per-binding tolerant decode + unknown round-trip |
| Future ButtonBinding adds new payload type | Add new payload file in `Shortcut/`, add `ResolvedAction` case, add executor method, add UI dispatch | Same extension shape as existing 4 action types |

## Verification Plan

### Build / Static
- `xcodebuild -scheme Debug -configuration Debug build` succeeds
- No new SwiftLint warnings introduced
- All new keys in `Localizable.xcstrings` show "Translated" status in Xcode

### Persistence
- Create OpenTarget binding, restart app, binding persists intact
- **Forward compat probe**: hand-craft a binding with unknown sentinel into UserDefaults JSON, restart app
  - Recognized bindings preserved
  - Unknown binding skipped with NSLog warning
  - App does not crash, UI normal
- **AI rewrite probe**: copy `buttonBindings` JSON from UserDefaults, ask AI to change `path`, paste back, restart, configuration applied

### Execution (with Monitor window)
- `.app` binding (Safari): press → Safari launches; press again → Safari brought forward
- `.app` + arguments: press → Safari receives arguments (e.g., URL auto-opens)
- Script with shebang + `chmod +x`: press → background execution
- Script + quoted arguments: write `echo` script that captures `argv`, verify split correctness
- Binding to nonexistent path: red error Toast
- Script without execute permission: orange warning Toast
- 5 rapid presses on broken binding → only 1 Toast visible (dedup)
- App moved to a different folder: bundle ID still resolves → normal launch
- App fully uninstalled: both fail → Toast

### UI
- Open popover: empty state shows "选择应用或脚本"
- Click empty: NSOpenPanel appears
- Pick `.app`: transitions to filled with app icon + name + path (middle truncated)
- Pick script: filled state with generic script icon + filename
- Drag `.app` to empty: border accent + scale 1.02, drop completes
- Drag multiple files: only first accepted
- Drag directory or nonexistent file URL: drag rejected
- Filled state click ✕: returns to empty with smooth transition
- Filled state click body: re-opens NSOpenPanel
- Done button disabled (alpha 0.5) in empty state
- Tab through fields in correct order
- Esc cancels (no save)
- Return submits (when valid)
- **Stale-path edit**: open existing binding whose target no longer exists → orange banner + empty slot
- Light/Dark switch: all colors invert correctly
- macOS 10.13 fallback: `Menlo` instead of `monospacedSystemFont`, no crash

## Future Hooks

This feature establishes patterns for related future work, none of which are in this spec's scope:

- **Bindings export/import UI**: a "Settings → Export Bindings…" menu, dumping `Options.shared.buttons.binding` to JSON. The data is already archive-ready due to this design.
- **Config file ingestion**: read `~/.config/mos/buttons.json` on startup, merge with UserDefaults. Zero schema changes needed.
- **AI-assisted binding suggestions**: Mos sends current binding JSON + user intent prompt to a local-first AI, parses returned JSON, validates, applies. Field names are stable and self-documenting.
- **Additional action types**: e.g., `RunCommand` (shell command without script file), `OpenURL` (web URL with default browser). Each adds a new optional field on `ButtonBinding` (or, when there are 3+, refactors into a sum type), a `ResolvedAction` case, and an executor method — same shape as this design.
