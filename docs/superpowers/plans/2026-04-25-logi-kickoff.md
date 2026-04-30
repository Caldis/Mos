# Logi Module Consolidation — Implementation Kickoff

> Read this file from a fresh Claude Code session to take over implementation. Everything you need is below or referenced by absolute path. Do not read the prior conversation — it is not needed.

## Where things stand

- **Branch:** `refactor/logi-consolidation` (already created, head = `0bca526` "docs(plan): logi module consolidation 6-step implementation plan").
- **Master:** clean of in-flight refactor work; brainstorm/spec/plan commits already on master through `0bca526`. Only an unrelated `.gitignore` line is stashed (`stash@{0}: On master: unrelated gitignore: scheduled_tasks.lock`) — leave it stashed for now.
- **Spec (final, v4 + Round 4 fixes):** `docs/superpowers/specs/2026-04-25-logi-module-consolidation-design.md` (commit `79f7090`).
- **Plan (6-step):** `docs/superpowers/plans/2026-04-25-logi-module-consolidation.md` (commit `0bca526`). 30+ tasks, each with 4–7 atomic steps including write-test, run-fail, implement, run-pass, commit.

## Workflow contract

Use the `superpowers:subagent-driven-development` skill. The user has explicitly chosen this option and confirmed:

- **Implementer:** `Agent` tool with `subagent_type: "general-purpose"`. The implementer reads/writes/edits files, runs `xcodebuild`, runs tests, makes commits.
- **Review:** Two stages per task, both via `codex` CLI (NOT Claude subagents). The user's `~/.codex/config.toml` defaults to `model = "gpt-5.5"` + `model_reasoning_effort = "xhigh"` — these are honored automatically when you invoke `codex exec` with no `-m` flag. Use `--dangerously-bypass-approvals-and-sandbox --skip-git-repo-check` to skip prompts. The user's max plan has effectively unlimited tokens — do not optimize for token consumption.
  - **Stage 1 (spec compliance):** verify implementer built what plan & spec required, no more no less.
  - **Stage 2 (code quality):** verify clean code, tests, file boundaries.
  - If either review finds issues, dispatch the implementer subagent again to fix; re-run that review; do not proceed to next stage / next task until both stages return ✅.
- **No new push to master.** Each task's commits land on `refactor/logi-consolidation`. After Step 5 lands and final review passes, ask the user whether to merge or open a PR.
- **Real device testing:** the user's machine has a Logi device permanently attached. Step 3 and Step 4 contain Tier 3a tests gated by `LOGI_REAL_DEVICE=1`. When you reach those, ask the user to confirm the device is connected, then run `LOGI_REAL_DEVICE=1 xcodebuild ... -testPlan DebugWithDevice ...`.

## Hard constraints (from spec §2 / §11)

- `UserDefaults["logitechFeatureCache"]` literal MUST NOT change across rename.
- `"HIDDebug.FeaturesControls.v3"` autosaveName MUST NOT change.
- Hot-path `NotificationCenter.post` calls capped at exactly two: `rawButtonEvent` (always) + `buttonEventRelay` (recording or unconsumed).
- `LogiCenter.externalBridge` is strong, non-optional, never `weak`.
- `LogiDeviceSession.handleInputReport` accepts `UnsafeBufferPointer<UInt8>`, not `[UInt8]` (Step 0).
- Logi work is main-thread-only (DEBUG `precondition(Thread.isMainThread)`).
- All Logi-internal symbols stay `internal`. Only the small public surface escapes (see acceptance §11).

## Build & test commands

- Build (Debug): `xcodebuild -scheme Debug -configuration Debug -destination 'platform=macOS' build` — note that the user's project uses **scheme `Debug`** (NOT `-target Mos`; that fails). This is documented in their memory.
- Run all tests: `xcodebuild -scheme Debug -destination 'platform=macOS' test`
- Run a single test class: `xcodebuild -scheme Debug -destination 'platform=macOS' test -only-testing:MosTests/<ClassName>`
- Real-device tests: `LOGI_REAL_DEVICE=1 xcodebuild -scheme Debug -testPlan DebugWithDevice -destination 'platform=macOS' test` (the `DebugWithDevice` xctestplan is created in Step 3 Task 3.14).

## How each task should run

For each task in the plan (in order, Step 0 → Step 5):

1. **Extract the full task text** from `docs/superpowers/plans/2026-04-25-logi-module-consolidation.md`. Identify which spec sections (`§N.M`) it references; copy those sections in too.
2. **Dispatch implementer** via `Agent` tool (`subagent_type: "general-purpose"`):
   - Prompt template: `~/.claude/plugins/cache/claude-plugins-official/superpowers/5.0.7/skills/subagent-driven-development/implementer-prompt.md`.
   - Pass full task text + spec excerpts + the constraints above. Do NOT instruct the implementer to read the plan or spec files; provide the text inline.
   - Working dir: `/Users/caldis/Code/Mos`.
   - Tell the implementer it MUST commit on `refactor/logi-consolidation`. Verify after dispatch by `git log --oneline -3` on that branch.
3. **Stage 1: spec compliance review** via codex:
   ```bash
   codex exec --dangerously-bypass-approvals-and-sandbox --skip-git-repo-check "$(cat <<'PROMPT'
   Review commit <SHA> against Task <N> of docs/superpowers/plans/2026-04-25-logi-module-consolidation.md and the relevant spec sections in docs/superpowers/specs/2026-04-25-logi-module-consolidation-design.md.
   Focus exclusively on: did the implementer build exactly what plan + spec require? Missing requirements? Extra/unrequested work? Misinterpretations?
   Output format:
   ✅ Spec compliant — proceed to code quality review.
   OR
   ❌ Issues found:
     - severity: file:line — concrete description
   Be terse. Do not propose alternatives.
   PROMPT
   )" 2>&1 | tee /tmp/codex_task<N>_spec.txt
   ```
   If ❌, dispatch implementer to fix the listed issues, then re-run this stage.
4. **Stage 2: code quality review** via codex:
   ```bash
   codex exec --dangerously-bypass-approvals-and-sandbox --skip-git-repo-check "$(cat <<'PROMPT'
   Code quality review on commit <SHA> for Task <N>.
   Check: each file has one clear responsibility; well-defined interfaces; tests verify behavior not mocks; no overbuilt features; existing patterns followed; no needless abstraction; no broken main-thread invariants; matches file structure declared in the plan.
   Output:
   Strengths: <bullets>
   Issues:
     Critical: <bullets or "none">
     Important: <bullets or "none">
     Minor: <bullets or "none">
   Assessment: <Approved | Needs fixes>
   Be terse.
   PROMPT
   )" 2>&1 | tee /tmp/codex_task<N>_quality.txt
   ```
   Critical / Important issues → re-dispatch implementer to fix → re-review. Minor issues → note but proceed.
5. **Mark task complete** in your TaskCreate/TaskUpdate list, then continue to the next task.

## Step-by-step task list

Read these from the plan; do NOT re-derive. Total ~30 tasks:

- **Step 0** (2 tasks): pre-refactor cleanup — HID alloc, reportingDidComplete fix.
- **Step 1** (6 tasks): rename `Logitech*` → `Logi*` and ScrollCore method rename + canary tests + CID directory tests.
- **Step 2** (9 tasks): `LogiCenter` facade + `LogiNoOpBridge` + facade migration of all external call sites.
- **Step 3** (15 tasks): `UsageRegistry` + `LogiUsageBootstrap` + 5 panel migrations + delete `syncDivertWithBindings` + KeyRecorder migration + Tier 3a baseline test.
- **Step 4** (5 tasks): `LogiExternalBridge` + `LogiIntegrationBridge` + `dispatchButtonEvent` rewrite + Toast bridge + Tier 2/3 tests.
- **Step 5** (5 tasks): subdir reorg + `ConflictDetector` 5-state + Self-Test Wizard + CI lint + boundary enforcement test.

End-of-Step Codex review (× 2 rounds at the step boundary, in addition to per-task) is recommended for Steps 3 and 4 because they have the largest semantic surface. The plan already includes "Step N Codex review × 2" as the final task within each step.

## Final acceptance (after all 6 steps land)

The plan's "Final acceptance check" section enumerates:
- `./scripts/lint-logi-boundary.sh` passes.
- `Debug.xctestplan` all green.
- `DebugWithDevice.xctestplan` all green with device.
- Self-Test Wizard: Bolt suite 14/14 + BLE suite all pass.
- `UserDefaults["logitechFeatureCache"]` still loads.
- AppDelegate launch order verified.
- Zero `Logitech*` references outside `Mos/Logi/` and `Mos/Integration/`.

After acceptance, hand back to the user for merge / PR decision.

## Things to NOT do

- Do not push to `origin/master`.
- Do not push to `origin/refactor/logi-consolidation` without asking.
- Do not amend or rebase commits already on the branch unless the user explicitly asks.
- Do not bypass Codex review on the grounds of "task is small" — every task on this branch goes through both review stages.
- Do not modify the spec or plan files unless a Codex review explicitly identifies a spec/plan defect; in that case, ask the user before editing.

## When in doubt

Ask the user. Spec/plan are detailed — most ambiguity is resolvable by re-reading the relevant section. If a section seems contradictory, surface it before implementing.
