# Mos Mouse Scroll Action Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a reusable-tagged `[Mos] Mouse Scroll` action group to the Buttons preferences panel so multiple normal or Logi buttons can activate the same scroll role without migrating existing Scrolling preferences persistence.

**Architecture:** Keep the old `ScrollHotkey?` settings intact. Add Mos scroll role actions as stateful Button actions, route them through `InputProcessor` and `ShortcutExecutor`, and let ScrollCore track button-action activation counts per scroll role.

**Tech Stack:** Swift, AppKit `NSMenu`/`NSPopUpButton`, existing `SystemShortcut`, `BrandTag`, `InputProcessor`, `ShortcutExecutor`, `ScrollCore`, and `xcodebuild test`.

---

### Task 1: Add failing execution tests for Mos scroll actions

**Files:**
- Modify: `MosTests/InputProcessorTests.swift`

**Step 1: Write failing tests**

Add tests for:

- resolving `mosScrollDash` as a stateful scroll action
- down/up of a button binding toggling `ScrollCore.shared.dashScroll`
- two triggers bound to `mosScrollDash`, where releasing one trigger keeps dash active until both are up

**Step 2: Verify red**

Run:

```bash
xcodebuild test -project Mos.xcodeproj -scheme Debug -destination 'platform=macOS' -only-testing:MosTests/InputProcessorTests CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY=''
```

Expected: fail because Mos scroll actions do not exist yet.

### Task 2: Implement Mos scroll action execution

**Files:**
- Modify: `Mos/Shortcut/SystemShortcut.swift`
- Modify: `Mos/Shortcut/ShortcutExecutor.swift`
- Modify: `Mos/ScrollCore/ScrollCore.swift`
- Test: `MosTests/InputProcessorTests.swift`

**Step 1: Add action identifiers**

Add `mosScrollDash`, `mosScrollToggle`, and `mosScrollBlock` to `SystemShortcut`.

**Step 2: Add resolved action support**

Add `ResolvedAction.mosScroll(role: ScrollRole)` and map the three identifiers in `ShortcutExecutor.resolveAction(...)`.

**Step 3: Add ScrollCore activation API**

Add a method shaped like:

```swift
func handleMosScrollAction(role: ScrollRole, isDown: Bool)
```

It updates a per-role count and refreshes the final role state.

**Step 4: Verify green**

Run the focused InputProcessor tests again.

Expected: new Mos scroll action tests pass.

### Task 3: Add failing menu and tag tests

**Files:**
- Modify: `MosTests/ButtonBindingTests.swift`

**Step 1: Write failing tests**

Add tests for:

- `BrandTagConfig.mos` style values
- `ActionDisplayResolver` returning a Mos tag for Mos scroll actions
- `ShortcutManager.buildShortcutMenu(...)` placing Mos mouse scroll after mouse buttons and before Logi actions

**Step 2: Verify red**

Run:

```bash
xcodebuild test -project Mos.xcodeproj -scheme Debug -destination 'platform=macOS' -only-testing:MosTests/ButtonBindingTests CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY=''
```

Expected: fail because Mos tag and category are not present yet.

### Task 4: Implement reusable Mos tag and menu category

**Files:**
- Modify: `Mos/Components/BrandTag.swift`
- Modify: `Mos/Windows/PreferencesWindow/ButtonsView/ActionDisplayResolver.swift`
- Modify: `Mos/Windows/PreferencesWindow/ButtonsView/ActionDisplayRenderer.swift`
- Modify: `Mos/Shortcut/ShortcutManager.swift`
- Modify: `Mos/Shortcut/SystemShortcut.swift`
- Modify: `Mos/Localizable.xcstrings`
- Test: `MosTests/ButtonBindingTests.swift`

**Step 1: Generalize presentation naming**

Rename `ActionPresentation.brand` to `tag` if needed, and keep all existing Logi behavior on the same rendering path.

**Step 2: Add Mos tag configuration**

Add `BrandTagConfig.mos` with the Mos logo-inspired blue/purple gradient, near-white text, and a low-opacity inner highlight instead of a bright outer border.

**Step 3: Add menu category**

Insert the Mos mouse scroll category after mouse buttons and before Logi actions in `ShortcutManager.buildShortcutMenu(...)`.

**Step 4: Add localization keys**

Add keys for:

- `categoryMosMouseScroll`
- `mosScrollDash`
- `mosScrollToggle`
- `mosScrollBlock`

**Step 5: Verify green**

Run focused ButtonBinding tests again.

Expected: Mos tag and menu tests pass while existing Logi tests remain green.

### Task 5: Run integration verification

**Files:**
- Modify only if verification exposes issues.

**Step 1: Run focused tests**

Run:

```bash
xcodebuild test -project Mos.xcodeproj -scheme Debug -destination 'platform=macOS' -only-testing:MosTests/InputProcessorTests -only-testing:MosTests/ButtonBindingTests -only-testing:MosTests/ScrollCoreHotkeyTests CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY=''
```

**Step 2: Run full tests**

Run:

```bash
xcodebuild test -project Mos.xcodeproj -scheme Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY=''
```

**Step 3: Manual UI sanity check**

Open the Buttons preferences panel and confirm:

- `[Mos] Mouse Scroll` appears below Mouse Buttons.
- It exposes dash, toggle, and block actions.
- Selecting one renders with a Mos tag.
- Existing Logi tag rendering still looks unchanged.
