# Mos research follow-up questions - 2026-05-10

This note extends `docs/research/mos-online-discussions-2026-05-09.md` and the visual dashboard.

Subagent archives:

- Logitech buttons: `.codex-archives/logitech-buttons-2026-05-10/research.md`
- Source expansion to 100: `.codex-archives/source-expansion-100-2026-05-10/research.md`
- AI-friendly direction: `.codex-archives/ai-friendly-2026-05-10/research.md`

## 1. Should the research expand from 50 to 100 sources?

Recommendation: **not as a broad sweep**.

The first 50 effective websites already show strong theme saturation:

- third-party mouse scrolling feels broken on macOS
- users want separate mouse and trackpad scroll direction
- Logitech / MX Master / Logi Options+ conflict guidance is high value
- per-app exceptions are essential for design, PDF, browser, DAW, CAD, and game workflows
- trust, Accessibility permission, Gatekeeper, and notarization are adoption blockers
- advanced settings need presets and clearer language

The expansion agent found 24 new distinct website/domain candidates and 13 same-domain supplemental URLs. It estimated:

- 70-80% duplicate rate among distinct website candidates
- 80-90% duplicate rate if same-domain supplemental threads are counted
- only about 8-12 candidates likely worth deeper validation
- only about 5-7 candidates likely to carry meaningfully new or semi-new themes

Better use of time: add a small **10-15 source appendix** rather than forcing the main report to 100. The highest-yield appendix would cover:

- Homebrew install/adoption signals
- Mos 4.0/4.2 release distribution and download mirrors
- MX Master 4 / newer Logitech hardware
- BetterTouchTool "one app for all mouse needs" consolidation demand
- Portuguese, Vietnamese, Traditional Chinese, and Japanese long-tail discovery paths
- competitor comparison snippets around BetterMouse, Mac Mouse Fix, SmoothScroll, Smooze, SteerMouse, LinearMouse

## 2. Are there discussions about the recent Logitech button adaptation?

Direct project-external discussion found: **0**.

The Logitech buttons subagent did not find public user discussions directly about Mos 4.2.0 / native Logi HID++ / Logitech button independent adaptation outside `github.com/caldis/Mos`.

What exists:

- Release/update synchronization:
  - `newreleases.io` mirrors the 4.2.0 release note and mentions native Logi/HID++ support.
  - MacUpdate shows Mos 4.2.0, but without visible Logitech button comments.
- Strong adjacent demand:
  - Reddit and V2EX users discuss Logitech side buttons, Back/Forward, gesture/thumb buttons, horizontal wheel, Options+ permissions, Options+ conflicts, and replacement stacks.
  - MacRumors and HN discussions show that Logitech thumb/gesture buttons often depend on vendor software rather than native macOS buttons.
  - BetterTouchTool / SteerMouse / Mac Mouse Fix / Mouser / LinearMouse appear as adjacent or competing tools for button remapping.

Interpretation:

Mos has a feature-market fit opportunity, but the market has not yet learned that Mos can cover this use case. The product work should be paired with outward-facing docs:

- Which Logitech buttons can Mos record and bind?
- What works over Bolt, Unifying, and Bluetooth?
- When should Logi Options+ stay installed?
- Which features should be handled by Mos vs Options+?
- How do Back/Forward, gesture/thumb button, mode shift, horizontal wheel, games, VMs, and remote desktops differ?

## 3. What changed in the visualization?

The dashboard at `docs/research/mos-online-discussions-visual-summary-2026-05-09.html` now includes:

- Base UI-inspired styling without importing Base UI or any framework
- semantic native controls
- visible focus rings
- low-radius neutral surfaces
- source index table with all 50 effective websites
- sort by rank, website, confidence, source type, and region
- search across website, region, type, and theme text
- confidence filters for High / Medium / Low
- no external CDN or runtime dependency, so it opens directly via `file://`

Base UI reference points used for the redesign:

- Base UI describes itself as an unstyled, accessible, composable React component library.
- Its styling handbook emphasizes plain CSS control, data attributes, CSS variables, and clear state hooks.
- This dashboard borrows those interaction and accessibility principles while remaining plain HTML/CSS/JS.

Sources:

- https://base-ui.com/react/overview/about
- https://base-ui.com/react/handbook/styling
- https://base-ui.com/llms.txt

## 4. What can Mos do for AI friendliness?

Mos should not add an in-app chatbot. AI friendliness should mean:

1. Easy for AI to understand what Mos is.
2. Easy for users to export a safe diagnostic bundle.
3. Easy for AI to explain or draft configuration changes.
4. Safe for local automation to inspect status and open relevant UI.

Recommended roadmap:

### P0: AI-readable docs map

Mos already has useful foundations in the website:

- `website/public/llms.txt`
- `website/public/llms-full.txt`
- `website/public/.well-known/agent-card.json`
- `website/public/.well-known/agent-instructions.md`
- `website/public/.well-known/api-catalog.json`
- public `AGENTS.md`

Next improvement: keep these synchronized with release notes, troubleshooting pages, Logi/HID docs, button-binding docs, and known limitation pages. `llms.txt` should be a compact stable entry point; `llms-full.txt` should be the full context bundle.

### P0: Diagnostics Export / Issue Bundle

Highest practical payoff. Add a one-click export that produces:

- `summary.md`
- `diagnostics.json`
- `button-events.log`
- `logi-debug.log`
- `redaction.md`

Suggested fields:

- schema version
- Mos version/build/channel
- macOS version/build
- Mac model/chip
- Accessibility and Input Monitoring status
- active scroll settings summary
- per-app rules count and affected bundle IDs
- button bindings summary with sensitive paths redacted by default
- connected pointing devices, vendor/product IDs, connection type when known
- Logi/HID session summary
- recent Monitor and Logi debug excerpts

This gives users something they can paste into GitHub or ask an AI assistant to interpret.

### P1: Config schema and import/export

Define a `mos-config.schema.json` covering:

- global scroll settings
- per-app profiles
- axis settings
- scroll hotkeys
- button bindings
- open target actions
- Logi/HID button identifiers

Import must be preview-first and safe:

- validate before apply
- show diff
- support partial import
- require explicit confirmation for script/file/open-target actions
- preserve compatibility with old configs

### P1: Structured changelog

Keep `CHANGELOG.md`, but add JSON/YAML sidecar data with:

- version/date/channel
- category: added / changed / fixed / security / known_issue
- affected area: scroll / buttons / logi / accessibility / update / localization / docs
- issue/PR links
- user impact
- compatibility notes
- validation summary

This improves release notes, appcast, website docs, and AI answers.

### P2: CLI / URL scheme / AppleScript

Start with read-only or explicit UI-opening actions:

- `mosctl status --json`
- `mosctl diagnostics export`
- `mosctl config export`
- `mosctl config validate <file>`
- `mos://preferences?tab=buttons`
- `mos://diagnostics/export`

Write operations should be dry-run or app-confirmed.

### P3: Shortcuts / App Intents

Useful on newer macOS versions, but Mos supports macOS 10.13, so this should be an availability-gated enhancement. Good actions:

- Open Mos Preferences
- Export Mos Diagnostics
- Export Mos Settings
- Validate Mos Settings File
- Toggle Smooth Scrolling only when the user explicitly creates the Shortcut

### P4: MCP

Only after docs, diagnostics, and schemas are stable. Keep it local, optional, and read-only first:

- `get_mos_status`
- `export_diagnostics_bundle`
- `read_config_schema`
- `validate_config`
- `explain_issue_bundle`
- `open_preferences`

Avoid early MCP write operations because Mos controls input behavior and script/file actions.

## 5. Base UI-style dashboard redesign

The HTML report has been rewritten with a Base UI-inspired style:

- no imported framework
- no external script or stylesheet
- semantic buttons, search input, table, and navigation
- `data-active` and `data-level` attributes for state styling
- visible keyboard focus
- clean neutral color system with restrained accent colors
- stable table layout for scanning and sorting

The file remains directly openable:

- `docs/research/mos-online-discussions-visual-summary-2026-05-09.html`

## Final recommendation

Do not expand the main research corpus to 100 broad sources right now. Put that effort into:

1. Logitech button capability docs and outreach.
2. A 10-15 source appendix for fresh hardware / locale / adoption signals.
3. A first-class Diagnostics Export / Issue Bundle.
4. Configuration schema and structured changelog.
5. A Pro/support path around presets, diagnostics, automation, and team configuration support.

