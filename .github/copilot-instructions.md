# Copilot Instructions for Mos

Read `@../AGENTS.md` first. This file is intentionally thin so Copilot, Codex, Claude, and other agents share one source of truth.

For reviews and generated changes, pay special attention to:

- macOS 10.13 compatibility and availability fallbacks.
- `Debug` scheme build/test commands, not `-target Mos`.
- Xcode target membership for new or moved Swift files.
- `NSLocalizedString(_:comment:)` and the two separate `.xcstrings` catalogs.
- `Mos/Logi` / `Mos/Integration` boundaries and `scripts/qa/lint-logi-boundary.sh`.
- Regression tests for bug fixes and clear verification evidence before claiming success.
- Human confirmation before release, signing, notarization, security-report, or real-device actions.
