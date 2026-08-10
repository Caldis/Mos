# Tooling and Packaging Layout Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Organize packaging assets, automation scripts, and developer tools into explicit directories with all live path references updated.

**Architecture:** `packaging/` owns app distribution packaging assets, `scripts/` owns repeatable project automation, and `tools/` owns manually run developer diagnostics/regression harnesses. Release automation scripts move from the agent skill bundle into `scripts/release/`, while the release skill keeps the process documentation and points to those repo-owned scripts.

**Tech Stack:** Bash, Swift script harnesses, Xcode test invocation, create-dmg, Sparkle appcast tooling.

---

### Task 1: Inspect Current Files

**Files:**
- Read: `dmg/README.md`
- Read: `dmg/create-dmg.command`
- Read: `scripts/lint-logi-boundary.sh`
- Read: `tools/*.swift`
- Read: `.agents/skills/release-preparation/scripts/*.sh`

**Steps:**
- Identify embedded relative paths before moving files.
- Identify repo references with `rg`.

### Task 2: Move Packaging Assets

**Files:**
- Move: `dmg/README.md` to `packaging/dmg/README.md`
- Move: `dmg/create-dmg.command` to `packaging/dmg/create-dmg.command`
- Move: `dmg/dmg-bg.png` to `packaging/dmg/assets/dmg-bg.png`
- Move: `dmg/dmg-icon.png` to `packaging/dmg/assets/dmg-icon.png`
- Move: `dmg/archive/` to `packaging/dmg/archive/`

**Steps:**
- Update `create-dmg.command` so paths are resolved from its own directory.
- Update packaging docs with the new layout.

### Task 3: Move Automation Scripts

**Files:**
- Move: `scripts/lint-logi-boundary.sh` to `scripts/qa/lint-logi-boundary.sh`
- Move: `.agents/skills/release-preparation/scripts/*.sh` to `scripts/release/`

**Steps:**
- Update script root discovery if directory depth changes.
- Update release skill instructions and agent docs.
- Update tests that execute the QA script.

### Task 4: Move Developer Tools

**Files:**
- Move: `tools/hidpp-*.swift` to `tools/hidpp/`
- Move: `tools/toast_regression_tests.swift` to `tools/regression/toast-regression-tests.swift`

**Steps:**
- Update usage comments inside scripts.
- Update active documentation references.

### Task 5: Verify

**Commands:**
- `rg -n "dmg/|tools/hidpp-|tools/toast_regression_tests|scripts/lint-logi-boundary|\\.agents/skills/release-preparation/scripts" ...`
- `bash -n scripts/qa/lint-logi-boundary.sh scripts/release/*.sh packaging/dmg/create-dmg.command`
- `scripts/qa/lint-logi-boundary.sh`
- `xcodebuild -scheme Debug -destination 'platform=macOS' test -only-testing:MosTests/LogiBoundaryEnforcementTests`

**Expected:** Live references point to the new paths, shell scripts parse, Logi boundary lint passes, and the Xcode test that shells out to the lint script passes.
