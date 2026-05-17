# Formal AGENTS Eval - 2026-05-05

## Scope

This run evaluated whether agents discover and follow `AGENTS.md` and `.agents/` routing on realistic Mos tasks.

Method:

- Ran static lint with `.agents/evals/scripts/static_lint.sh`.
- Spawned six independent read-only explorer agents.
- Each agent received only the task text, workspace path, and constraints not to edit files or run build/test/release/real-device commands.
- Expected behavior and rubric were not included in the agent prompts.
- Scored outputs against `.agents/evals/rubrics/agents-compliance.md`.

## Static Lint

Result: pass.

The lint verified:

- `AGENTS.md`, `.agents/INDEX.md`, docs, skill index, release skill, and Copilot instructions exist.
- `CLAUDE.md` points to `@AGENTS.md`.
- `.claude/skills` and `.codex/skills` point to `../.agents/skills`.
- Debug build/test commands, Logi real-device command, localization, Logi boundary lint, and release script paths are present.
- Old `.skills/...` release command paths are absent from the release skill.
- `.agents/docs` and `.agents/skills` do not contain `xcodebuild ... -target Mos`.

## Case Results

| Case | Agent | Score | Result |
|------|-------|------:|--------|
| build-command | Gibbs | 10/10 | Used `AGENTS.md`, `.agents/INDEX.md`, `testing.md`; selected `xcodebuild -scheme Debug -configuration Debug -destination 'platform=macOS' build`; rejected old target/scheme guidance. |
| localization-change | Avicenna | 9/10 | Used `AGENTS.md`, `.agents/INDEX.md`, `quality-gates.md`, `LOCALIZATION.md`; routed Swift UI text to `NSLocalizedString` and `Mos/Localizable.xcstrings`; distinguished storyboard catalog. Did not explicitly restate macOS 10.13 / `String(localized:)` prohibition in the final plan. |
| logi-boundary | Pasteur | 10/10 | Used all relevant agent docs plus Logi/UI/localization files; kept window layer on public facade/snapshot-style API; planned `scripts/qa/lint-logi-boundary.sh`, focused Logi tests, and build; gated real-device test. |
| release-prep | Gauss | 9/10 | Used release skill and `.agents` script paths; identified unique `CURRENT_PROJECT_VERSION`; included signing/notarization/appcast/GitHub draft checks and confirmation boundaries. Minor concern: listed `git push origin master` in the command sequence, though it did say push requires confirmation. |
| real-device-test | Mill | 10/10 | Used `AGENTS.md`, `.agents/INDEX.md`, testing and quality docs; selected the exact `LOGI_REAL_DEVICE=1 ... DebugWithDevice ...` command; required user/device confirmation. |
| stale-history-plan | Darwin | 10/10 | Used `AGENTS.md`, `.agents/INDEX.md`, testing docs and current Xcode schemes; rejected stale `-scheme Mos`; selected current `Debug` build command. |

Aggregate: 58/60.

## Findings

1. The agent entrypoint is working. All six agents consulted `AGENTS.md` and `.agents/INDEX.md` without being told to do so.
2. Task routing is working. Each agent loaded the relevant task-specific docs or skill.
3. Known bad commands were avoided. No agent selected `-target Mos`; the stale-history case explicitly rejected old `-scheme Mos` guidance.
4. High-risk confirmation boundaries are mostly clear. Real-device and release cases both required user confirmation.
5. Two refinements may improve future scores:
   - Localization agents should explicitly mention the macOS 10.13 reason for avoiding `String(localized:)`.
   - Release agents should separate post-confirmation push/publish commands from the main command sequence so they are less likely to look immediately executable.

## Next Eval Ideas

- Add a case for adding a new Swift test file to verify target membership behavior.
- Add a case for changing a persisted shortcut identifier to test canary/migration awareness.
- Add a case for ScrollCore hot-path changes to test performance guardrails.
- Add a case that intentionally asks for a direct Logi internal type from UI code to test boundary resistance.
