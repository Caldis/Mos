# Toast Expand Message Default Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a persisted `Show Full Text` toast preference, expose it in the Toast debug panel, and make the default behavior show full toast text instead of truncating to two lines.

**Architecture:** Persist the preference in `ToastStorage`, thread that value through `ToastManager` into `ToastContentView`, and keep the debug panel checkbox in sync with storage. Cover the new default and view configuration with focused toast regression tests before implementation.

**Tech Stack:** Swift, AppKit, `UserDefaults`, existing toast regression test harness in `tools/regression/toast-regression-tests.swift`

---

### Task 1: Add the failing regression tests

**Files:**
- Modify: `tools/regression/toast-regression-tests.swift`

**Step 1: Write the failing test**

Add tests that assert:
- `ToastStorage.shared.showsFullText` defaults to `true`
- `ToastContentView` created with `expandMessage: true` uses unlimited lines and word wrapping
- `ToastContentView` created with `expandMessage: false` still keeps the truncated two-line behavior

**Step 2: Run test to verify it fails**

Run: `swiftc -module-cache-path /tmp/mos-toast-tests -o /tmp/mos-toast-tests tools/regression/toast-regression-tests.swift Mos/Components/Toast/ToastLayout.swift Mos/Components/Toast/ToastVisibilityRules.swift Mos/Components/Toast/ToastContentView.swift Mos/Components/Toast/ToastStorage.swift && /tmp/mos-toast-tests`

Expected: FAIL because `ToastStorage` does not yet expose the new preference

### Task 2: Persist the preference and make it the default

**Files:**
- Modify: `Mos/Components/Toast/ToastStorage.swift`
- Modify: `Mos/Components/Toast/Toast.swift`
- Modify: `Mos/Components/Toast/ToastManager.swift`

**Step 1: Write minimal implementation**

Add a `showsFullText` boolean to `ToastStorage` with default `true`. Use it as the default `expandMessage` value in `Toast.show(...)`, and make `ToastManager.present(...)` respect that default when callers do not override it.

**Step 2: Run test to verify it passes**

Run the same regression command as Task 1.

Expected: PASS for the new default/presentation behavior checks

### Task 3: Expose the setting in the debug panel

**Files:**
- Modify: `Mos/Components/Toast/ToastPanel.swift`
- Modify: `Mos/Localizable.xcstrings`

**Step 1: Add UI and persistence hook**

Add a `Show Full Text` checkbox in the Toast debug panel configuration area. Bind it to `ToastStorage.shared.showsFullText`, default on, and refresh it when the panel opens.

**Step 2: Add localization entry**

Add the localized string key used by the new checkbox.

**Step 3: Run regression/build verification**

Run the toast regression command again, then run a focused build command for the app target if available.

### Task 4: Final verification

**Files:**
- Review only

**Step 1: Run verification**

Run:
- `swiftc -module-cache-path /tmp/mos-toast-tests -o /tmp/mos-toast-tests tools/regression/toast-regression-tests.swift Mos/Components/Toast/ToastLayout.swift Mos/Components/Toast/ToastVisibilityRules.swift Mos/Components/Toast/ToastContentView.swift Mos/Components/Toast/ToastStorage.swift && /tmp/mos-toast-tests`

**Step 2: Inspect diff**

Run: `git diff -- Mos/Components/Toast/ToastStorage.swift Mos/Components/Toast/Toast.swift Mos/Components/Toast/ToastManager.swift Mos/Components/Toast/ToastPanel.swift Mos/Localizable.xcstrings tools/regression/toast-regression-tests.swift docs/plans/2026-04-11-toast-expand-message-default.md`
