# Toast Default Wrap Width Sync Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a persisted global `defaultWrapWidth` setting, make `Toast.show(..., wrapWidth: nil)` fall back to it, and expose the same value in the Toast debug panel so UI and runtime behavior stay in sync.

**Architecture:** Store the default wrap width in `ToastStorage` as a sanitized numeric value where `0` means single-line mode. Route `wrapWidth: nil` through that stored default inside the toast presentation path, and add a debug-panel control that edits the same stored value and uses it for test toasts unless a call site explicitly overrides `wrapWidth`.

**Tech Stack:** Swift, AppKit, `UserDefaults`, existing toast regression harness in `tools/regression/toast-regression-tests.swift`

---

### Task 1: Write failing regression tests

**Files:**
- Modify: `tools/regression/toast-regression-tests.swift`

**Step 1: Write the failing test**

Add tests asserting:
- `ToastStorage.defaultWrapWidth` defaults to `0`
- stored negative values clamp back to `0`
- stored positive values round-trip
- positive wrap widths still produce wrapped multiline layout

**Step 2: Run test to verify it fails**

Run: `swiftc -module-cache-path /tmp/mos-toast-tests-cache -o /tmp/mos-toast-tests-bin tools/regression/toast-regression-tests.swift Mos/Components/Toast/ToastLayout.swift Mos/Components/Toast/ToastVisibilityRules.swift Mos/Components/Toast/ToastContentView.swift Mos/Components/Toast/ToastStorage.swift && /tmp/mos-toast-tests-bin`

Expected: FAIL because `ToastStorage` does not yet expose `defaultWrapWidth`.

### Task 2: Implement storage + runtime fallback

**Files:**
- Modify: `Mos/Components/Toast/ToastStorage.swift`
- Modify: `Mos/Components/Toast/ToastManager.swift`

**Step 1: Write minimal implementation**

Add `defaultWrapWidth` to `ToastStorage` with default `0` and sanitize negative values to `0`. When `ToastManager.present(..., wrapWidth: nil)` is called, resolve it to `ToastStorage.shared.defaultWrapWidth` before creating `ToastContentView`.

**Step 2: Run test to verify it passes**

Run the same regression command as Task 1.

Expected: PASS for the new storage behavior.

### Task 3: Add debug-panel sync control

**Files:**
- Modify: `Mos/Components/Toast/ToastPanel.swift`
- Modify: `Mos/Localizable.xcstrings`

**Step 1: Add a numeric control**

Add a `Wrap Width` configuration row to the debug panel. Bind it to `ToastStorage.shared.defaultWrapWidth`, display `0` as single-line mode, and refresh it when the panel opens.

**Step 2: Use the stored value when firing panel toasts**

Make debug-panel toasts pass `wrapWidth: ToastStorage.shared.defaultWrapWidth`.

**Step 3: Run verification**

Run:
- `swiftc -module-cache-path /tmp/mos-toast-tests-cache -o /tmp/mos-toast-tests-bin tools/regression/toast-regression-tests.swift Mos/Components/Toast/ToastLayout.swift Mos/Components/Toast/ToastVisibilityRules.swift Mos/Components/Toast/ToastContentView.swift Mos/Components/Toast/ToastStorage.swift && /tmp/mos-toast-tests-bin`
- `xcodebuild -project Mos.xcodeproj -scheme Debug -configuration Debug -sdk macosx build CODE_SIGNING_ALLOWED=NO`

Expected: regression tests pass and build succeeds.
