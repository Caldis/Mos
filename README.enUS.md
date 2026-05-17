<p align="center">
  <a href="https://mos.caldis.me/">
    <img width="160" src="assets/readme/app-icon.png" alt="Mos app icon">
  </a>
</p>

<h1 align="center">Mos</h1>

<p align="center">
  Make mouse-wheel scrolling on macOS as smooth as a trackpad, while keeping the precision of a mouse.
</p>

<p align="center">
  <a href="https://github.com/Caldis/Mos/releases"><img alt="Latest release" src="https://img.shields.io/github/v/release/Caldis/Mos?style=flat-square"></a>
  <img alt="macOS 10.13+" src="https://img.shields.io/badge/macOS-10.13%2B-black?style=flat-square&logo=apple">
  <img alt="Swift 5" src="https://img.shields.io/badge/Swift-5.0-orange?style=flat-square&logo=swift">
  <a href="LICENSE"><img alt="License: CC BY-NC 4.0" src="https://img.shields.io/badge/license-CC%20BY--NC%204.0-lightgrey?style=flat-square"></a>
</p>

<p align="center">
  <a href="README.md">中文</a> ·
  <a href="README.enUS.md">English</a> ·
  <a href="README.de.md">Deutsch</a> ·
  <a href="README.ja.md">日本語</a> ·
  <a href="README.ko.md">한국어</a> ·
  <a href="README.ru.md">Русский</a> ·
  <a href="README.id.md">Bahasa Indonesia</a>
</p>

<p align="center">
  <a href="https://mos.caldis.me/">Homepage</a> ·
  <a href="https://github.com/Caldis/Mos/releases">Download</a> ·
  <a href="https://github.com/Caldis/Mos/wiki">Wiki</a> ·
  <a href="https://github.com/Caldis/Mos/discussions">Discussions</a>
</p>

<p align="center">
  <img src="assets/readme/en-us/application-settings.png" alt="Mos per-app scroll settings" width="920">
</p>

## Why Mos

Mouse-wheel scrolling can feel abrupt on macOS: it often lacks the continuous, predictable inertia of a trackpad. Mos intercepts mouse-wheel events and turns raw deltas into smoother scrolling while still letting you decide how each app, axis, and button should behave.

You can also use Mos to remap or rewrite any mouse button so it fits your workflow.

Mos is a free, open-source menu bar utility for macOS 10.13 and later.

## Highlights

- **Smooth scrolling**: tune step, gain, and duration, or enable the simulate-trackpad mode.
- **Independent axes**: configure smoothing and reverse direction separately for vertical and horizontal scrolling.
- **Scroll hotkeys**: bind custom keys for acceleration, axis conversion, and temporarily disabling smooth scrolling.
- **Per-app profiles**: let each app inherit global settings, or override scroll, shortcut, and button-binding behavior.
- **Button bindings**: record mouse, keyboard, or custom events, then bind them to system actions, shortcuts, apps, scripts, or files.
- **Action library**: built-in actions for Mission Control, Spaces, screenshots, Finder operations, document editing, mouse scrolling, and more.
- **Logi/HID++ support**: handle Logitech button events from Bolt, Unifying, and Bluetooth direct-connected devices, including Logi-specific actions.

## Screenshots

| Scroll tuning | Per-app profiles |
| --- | --- |
| <img src="assets/readme/en-us/scrolling.png" alt="Mos scroll settings" width="420"> | <img src="assets/readme/en-us/application-settings.png" alt="Mos per-app profile settings" width="420"> |

| Open apps, scripts, or files | Action library |
| --- | --- |
| <img src="assets/readme/en-us/buttons-open.png" alt="Mos open action" width="420"> | <img src="assets/readme/en-us/buttons-action.png" alt="Mos action library" width="420"> |

## Download & Install

### Manual Installation

Download the latest build from [GitHub Releases](https://github.com/Caldis/Mos/releases), unzip it, and move `Mos.app` into `/Applications`.

On first launch, macOS may ask you to grant Mos Accessibility permission. Mos needs this permission to read and rewrite scroll events. If the app still does not work after permission is granted, see the [permission troubleshooting guide](https://github.com/Caldis/Mos/wiki/If-the-App-not-work-properly).

### Homebrew

If you prefer managing apps with Homebrew:

```bash
brew install --cask mos
```

To update:

```bash
brew update
brew upgrade --cask mos
```

## Contributing

Mos is a small utility that handles system input, Accessibility permission, Logi/HID devices, and persisted user configuration. Maintenance cost and regression risk are real, so we strongly prefer small, focused changes.

Changes touching Logi/HID, Accessibility, signing, notarization, app updates, or real-device testing carry higher risk. Please explain the background in an issue or Discussion before opening a large PR in those areas.

Please explain the motivation, test coverage, and possible behavioral impact in the PR description.

> AI-written code has become mainstream, and we understand that many PRs are now generated with AI assistance, including our own work. But the submitter still needs to understand, curate, and verify what every line actually does, because every PR review has a cost.

### Very Welcome

- Small bug fixes with reproduction steps or validation notes.
- UI/UX refinements such as layout, copy, readability, and onboarding polish.
- Small security hardening, such as safer permission-state handling, input protection, and boundary checks.
- Localization, documentation, and test improvements.
- Single-topic PRs with limited line changes and a clear review surface.

### What We Will Not Merge For Now

- Large new features, modules, or architectural rewrites that have not been discussed first.
- Bulk AI-generated rewrites, formatting sweeps, migrations, or opportunistic cleanups.
- Behavior changes that affect input-event handling, permission prompts, app updates, legacy user data, or persisted configuration formats.
- Full machine-generated translation sets, especially when they cannot be reviewed by native speakers.

All forms of contribution are welcome. If you have suggestions or feedback, feel free to open an [issue](https://github.com/Caldis/Mos/issues).

If you are excited about a feature, please start with [Discussions](https://github.com/Caldis/Mos/discussions).

## Thanks

- [Charts](https://github.com/danielgindi/Charts)
- [LoginServiceKit](https://github.com/Clipy/LoginServiceKit)
- [Sparkle](https://github.com/sparkle-project/Sparkle)
- [Smoothscroll-for-websites](https://github.com/galambalazs/smoothscroll-for-websites)
- [Solaar](https://github.com/pwr-Solaar/Solaar)

## License

Copyright (c) 2017-2026 Caldis. All rights reserved.

Mos is licensed under [CC BY-NC 4.0](http://creativecommons.org/licenses/by-nc/4.0/). Do not upload Mos to the App Store.
