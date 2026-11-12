# Contributing to Mos

Thanks for wanting to improve Mos. Bug fixes, UI/UX polish, security hardening, documentation, localization, and focused tests are all welcome.

Mos is a small macOS utility that touches system input, Accessibility permission, Logi/HID devices, and persisted user configuration. That makes maintenance cost and regression risk very real, so we strongly prefer small, focused contributions.

## What We Welcome

- Small bug fixes with clear reproduction steps or validation notes.
- UI/UX refinements such as layout, copy, readability, and onboarding polish.
- Small security hardening, such as safer permission-state handling, input protection, and boundary checks.
- Localization, documentation, and test improvements.
- Single-topic PRs with limited line changes and a clear review surface.

## What We Will Not Merge For Now

- Large new features, modules, or architectural rewrites that have not been discussed first.
- Bulk AI-generated rewrites, formatting sweeps, migrations, or opportunistic cleanups.
- Behavior changes that affect input-event handling, permission prompts, app updates, legacy user data, or persisted configuration formats without prior discussion.
- Full machine-generated translation sets, especially when they cannot be reviewed by native speakers.

If you are excited about a larger feature, please start with [Discussions](https://github.com/Caldis/Mos/discussions). Big ideas are welcome, but they need shared context around user value, maintenance cost, and safety boundaries before code review.

## AI-Assisted Contributions

AI-assisted coding is welcome, but the submitter is responsible for the final diff.

Before opening a PR, make sure you understand what every changed line does, remove generated noise, and verify the behavior yourself. Please do not submit AI output as-is.

## Reporting Bugs

Before opening a new issue, search existing [issues](https://github.com/Caldis/Mos/issues) and [Discussions](https://github.com/Caldis/Mos/discussions).

When reporting a bug, include:

- Mos version.
- macOS version.
- Mouse or trackpad model.
- Affected app, or whether it affects the whole system.
- Other mouse, keyboard, or window-management tools installed.
- Accessibility permission state for Mos.
- Reproduction steps and expected behavior.
- Screenshots, screen recordings, logs, or a sample app when they help explain the problem.

## Opening a Pull Request

Please keep PRs small and focused. A good PR usually does one thing, explains why it matters, and includes enough validation for reviewers to trust the change.

In the PR description, include:

- Motivation for the change.
- Summary of what changed.
- Test or validation steps.
- Possible behavior changes or compatibility risks.
- Related issue or discussion, if any.

Avoid unrelated formatting changes, broad refactors, and mixed-purpose commits.

## Higher-Risk Areas

Please discuss these areas before opening a large PR:

- Logi/HID and real-device behavior.
- Accessibility permission flow.
- Input-event interception, dispatching, and safety guards.
- Signing, notarization, Sparkle updates, and release packaging.
- Legacy user data, defaults, or persisted configuration formats.
- macOS-version compatibility and availability fallbacks.

## Local Changes and Verification

Mos is built with Swift 5, AppKit, Xcode, and Swift Package Manager. Match the style of the surrounding code, keep compatibility with macOS 10.13, and avoid new APIs without availability gates or fallbacks.

For code changes, run the relevant build or tests before opening a PR. For documentation-only changes, at least check links, image paths, and Markdown formatting.

## License

By contributing, you agree that your contribution will be licensed under Mos's project license.
