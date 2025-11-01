# Localization Guide for Mos

This guide describes how Mos 4.0 handles localisation, how to extend it, and how to keep every language in sync with new features such as the Buttons panel and shortcut catalog.

---

## 1. String Catalog Layout

Mos ships Xcode’s string catalogs instead of legacy `.strings` files. There are **two catalogs** and they must remain separate:

| File | Scope | Notes |
|------|-------|-------|
| `Mos/Localizable.xcstrings` | Strings referenced from Swift (`NSLocalizedString`) | Keys are either human-readable phrases (`"Auth"`, `"Current Version"`) **or** camelCase identifiers that mirror code constants (e.g. `appExpose`, `categoryFunctionKeys`, shortcut identifiers in `SystemShortcut.Shortcut`). Do not rename identifiers—Swift enums and persistence depend on them. |
| `Mos/mul.lproj/Main.xcstrings` | Interface Builder (storyboards / XIBs) | Keys are Interface Builder Object IDs (`2AK-Pu-mot.title`). Xcode regenerates them on build. Never hand-edit Object IDs. |

`mul.lproj` is the canonical bundle for storyboard strings because we support many locales. Xcode fans out per-language nibs at build time, so do **not** split `Main.xcstrings` into multiple folders manually.

The project still targets macOS 10.13, so always use `NSLocalizedString(_:comment:)` in Swift rather than `String(localized:)`.

---

## 2. Current Language Coverage

Both catalogs expose the same set of locales (plus the English source column):

`de`, `el`, `ja`, `ko`, `ru`, `tr`, `uk`, `zh-Hans`, `zh-Hant`, `zh-Hant-HK`, `zh-Hant-TW`

To verify coverage and catch untranslated rows:

```bash
python3 - <<'PY'
import json, pathlib
catalog = json.loads(pathlib.Path("Mos/Localizable.xcstrings").read_text())
dupes = [(k, lang) for k, row in catalog["strings"].items()
         for lang, unit in row["localizations"].items()
         if lang != "en" and unit["stringUnit"]["value"] == row["localizations"]["en"]["stringUnit"]["value"]]
print(f"{len(dupes)} duplicate values (same as English). Sample:", dupes[:10])
PY
```

Run the same script against `Mos/mul.lproj/Main.xcstrings` if you suspect orphaned storyboard strings. A “duplicate” is acceptable when the official term matches English (e.g. “Launchpad”), but treat the report as a to-do list for translators.

The 4.0 release added ~40 strings across the Buttons panel, shortcut catalog, onboarding, and the refreshed Preferences UI. Make sure every locale is updated before tagging a new build.

---

## 3. Terminology Rules

### macOS Official Terms

Use the terminology Apple ships in System Preferences / System Settings. Never swap in colloquial variants.

| English | 简体中文 | 繁體中文 | 日本語 | Notes |
|---------|---------|---------|--------|-------|
| Preferences | 偏好设置 | 偏好設定 | 環境設定 | NOT “设置” or “Settings” |
| Accessibility | 辅助功能 | 輔助使用 | アクセシビリティ | System feature name |
| Mission Control | 任务控制 | Mission Control | ミッションコントロール | Use Apple’s official translation even if it matches English |
| Trackpad | 触控板 | 觸控式軌跡板 | トラックパッド | Hardware name |

### Modifier Keys

Keep modifier symbols intact and append translated names only if the locale expects it:

```
✓  "⌘ Command"  "⌥ Option"  "⌃ Control"  "⇧ Shift"
✗  "Command"    "Option键"   "Ctrl"
```

### Proper Nouns

- App name “Mos”, brand names (GitHub, macOS) and contributor credits remain unchanged.
- System features (Mission Control, Spotlight) use Apple’s official localisation.

### Numbers & Symbols

- Leave numbers, mathematical operators, and special characters untouched.
- Pay attention to locale-specific punctuation (e.g. Japanese full-width brackets) only when Apple’s UI uses them.

---

## 4. Adding Strings

### 4.1 Code (`Localizable.xcstrings`)

```swift
// Step 1 – Add the string in code
button.title = NSLocalizedString("Auth", comment: "Authorization button title")

// Step 2 – Build once (⌘B) so Xcode refreshes the catalog
// Step 3 – Open Localizable.xcstrings and fill every locale column
// Step 4 – Keep the key identical; do not rename identifiers already used in code
```

**Shortcut catalog:** When adding a new `SystemShortcut.Shortcut`, make sure its `identifier` property becomes a key in `Localizable.xcstrings`. The Buttons panel and popup menus rely on `NSLocalizedString(identifier, …)` to show the translated shortcut name.

### 4.2 Storyboards (`Main.xcstrings`)

1. Modify the base storyboard/XIB under `Base.lproj`.
2. Build (⌘B); Xcode extracts new Object IDs into `mul.lproj/Main.xcstrings`.
3. Translate the generated rows in Xcode’s catalog editor.
4. Do **not** change Object IDs. If you delete a UI element, search for its Object ID and remove the stale entry manually.

---

## 5. Maintenance Checklist

- [ ] macOS terms match Apple’s official localisation.
- [ ] Modifier symbols (⌘⌥⌃⇧) are preserved in every language.
- [ ] Keys in `Localizable.xcstrings` match the Swift constants (`SystemShortcut` identifiers, category names, etc.).
- [ ] No empty strings or placeholder text in any locale column.
- [ ] Duplicate values (translation == English) are intentional and documented with translators.
- [ ] Chinese variants respect locale: 简体 (`zh-Hans`), 台湾 (`zh-Hant-TW`), 香港 (`zh-Hant-HK`).
- [ ] Japanese strings use polite です／ます form unless Apple’s UI uses dictionary form.
- [ ] Buttons panel recorder, Application tab, Welcome flow, and Monitor window were sanity-checked in the new/edited locale.

---

## 6. Adding a New Language

1. In Xcode, Project ▸ Info ▸ Localizations → add the language.
2. Ensure Xcode offers to localise both catalogs; tick every checkbox.
3. Translate *all* keys in `Localizable.xcstrings` and `Main.xcstrings`.
4. Update external documentation (README variants, website) if the language is publicly visible.
5. Switch macOS to the new language (System Preferences ▸ Language & Region) and run through:
   - Welcome / Introduction windows
   - Preferences tabs (General, Scrolling, Application, Buttons, Updates, About)
   - Buttons recorder, shortcut pop-ups, simulated trackpad switches
6. Capture screenshots or notes for strings that require layout tweaks (long text, truncation).

---

## 7. Handy QA Commands

```bash
# Pretty-print a catalog for manual diffing
jq '.' Mos/Localizable.xcstrings | less

# List storyboard keys that no longer exist in Base.lproj
python3 Scripts/find_orphan_storyboard_keys.py  # create alongside other scripts if needed

# Export catalogs for external translators (creates XLIFF)
xcodebuild -exportLocalizations -project Mos.xcodeproj -localizationPath DerivedData/Localizations

# Reimport translated XLIFF back into the project
xcodebuild -importLocalizations -project Mos.xcodeproj -localizationPath DerivedData/Localizations
```

---

## 8. Module Reference

- **Shortcuts:** `Shortcut/SystemShortcut.swift` defines identifiers used in menus and the Buttons panel.
- **Buttons panel:** Strings originate from `Windows/PreferencesWindow/ButtonsView/`, especially `ButtonTableCellView.swift` and `PreferencesButtonsViewController.swift`.
- **Welcome & Introduction:** See `Windows/WelcomeWindow` and `Windows/IntroductionWindow` for onboarding copy.
- **Monitor window:** Mixing scroll/button logs relies on keys such as `buttonsLog`, `eventMonitor`, etc. in `Localizable.xcstrings`.

When new modules land (e.g. gesture editor, theme manager), append them here so translators know where to look.

---

Keeping localisation healthy is part of every feature cycle. Touch the catalog as soon as you add UI copy, run the duplicate check before merging, and leave notes for community translators whenever the wording carries product context. That habit keeps all 12 languages launch-ready the moment we ship a new build.
