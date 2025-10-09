# Localization Guide for Mos

This document provides comprehensive guidelines for maintaining and adding translations to the Mos application.

## String Catalog (.xcstrings) Architecture

The project uses Xcode's modern String Catalog system with **two separate files**:

### 1. `Mos/Localizable.xcstrings` - Code-based localization
- For strings used in Swift code via `NSLocalizedString()`
- Keys are human-readable English strings (e.g., "Auth", "Preferences")
- Manually managed - you control all keys and values
- Use `NSLocalizedString()` (not `String(localized:)`) for macOS 10.13 compatibility

### 2. `Mos/mul.lproj/Main.xcstrings` - Storyboard localization
- Auto-generated from Storyboard UI elements during build
- Keys are ObjectID-based (e.g., "2AK-Pu-mot.title")
- Xcode automatically extracts/updates during compilation
- Never manually rename keys - Xcode uses ObjectIDs for mapping

**⚠️ DO NOT merge these files** - they serve different purposes and Xcode will break if combined.

## Supported Languages

The app supports 11 languages plus English:
- **de** (German), **el** (Greek), **ja** (Japanese), **ko** (Korean)
- **ru** (Russian), **tr** (Turkish), **uk** (Ukrainian)
- **zh-Hans** (Simplified Chinese), **zh-Hant** (Traditional Chinese)
- **zh-Hant-HK** (Hong Kong), **zh-Hant-TW** (Taiwan)

## Translation Guidelines

### 1. macOS System Terminology - MUST Follow Apple's Official Terms

Use correct macOS-specific terminology from System Preferences and HIG:

| English | 简体中文 | 繁體中文 | 日本語 | Notes |
|---------|---------|---------|--------|-------|
| Preferences | 偏好设置 | 偏好設定 | 環境設定 | NOT "设置" or "Settings" |
| Accessibility | 辅助功能 | 輔助使用 | アクセシビリティ | System feature name |
| Quit | 退出 | 結束 | 終了 | Menu item, NOT "关闭" |
| Application | 应用 | 應用程式 | アプリケーション | NOT "程序" |
| Trackpad | 触控板 | 觸控式軌跡板 | トラックパッド | Hardware name |

**Verify terminology in:** System Preferences (macOS 10.13+) or System Settings (macOS 13+)

### 2. Modifier Keys and Symbols - Keep Symbols Unchanged

Keyboard modifier keys must preserve Unicode symbols:

```
✓ Correct:  "⌘ Command", "⌥ Option", "⌃ Control", "⇧ Shift"
✗ Wrong:    "Command", "Option键", "Ctrl"
```

- **Symbols (⌘⌥⌃⇧) are universal** - never translate or remove
- **Key names** after symbols follow language conventions:
  - English/Most languages: Keep English name (e.g., "⌥ Option")
  - German: May translate (e.g., "⌘ Befehl" for Command)
  - CJK languages: Keep English for consistency (e.g., "⌘ Command")

### 3. Proper Names - Never Translate

- **App name**: "Mos" (always unchanged)
- **Person names**: "Andrew Mclaren(@mclvren)" (keep as-is)
- **Brand names**: "GitHub", "macOS" (never localize)
- **Technical terms**: "Mission Control", "Spotlight" (use official localized names)

### 4. Numbers and Symbols

- Keep numeric values unchanged: "1-10", "3.00", "35.00"
- Keep mathematical symbols: "*", "-", "+", "/"
- Keep punctuation in context of target language

## Adding New Localizable Strings

### For code-based strings in `Localizable.xcstrings`:

```swift
// 1. Add NSLocalizedString in code
button.title = NSLocalizedString("Auth", comment: "Authorization button")

// 2. Build project (⌘+B) - Xcode extracts the key
// 3. Open Localizable.xcstrings in Xcode
// 4. Add translations for all 11 languages
// 5. Verify key matches English value (keep them consistent)
```

### For Storyboard strings in `Main.xcstrings`:

```
1. Add UI element in Base.lproj/Main.storyboard
2. Build project (⌘+B) - Xcode auto-extracts to Main.xcstrings
3. Open Main.xcstrings and translate the auto-generated key
4. Never rename the ObjectID-based key
```

## Maintaining Translations

Regular cleanup tasks:

```bash
# Check for unused keys (orphaned after UI deletion)
# Manually: Search for ObjectID in Main.storyboard
# If not found → delete from Main.xcstrings

# Check for duplicate English values (fake 100% translation)
# Remove translations where value === English source

# Check for empty string values
# Usually placeholder text, safe to delete
```

## Common Localization Patterns

### Menu Items
```swift
// Menu bar items often have leading space for icon alignment
NSLocalizedString(" Preferences", comment: "")  // Note the space
NSLocalizedString(" Event Monitor", comment: "")
```

### Version Display
```swift
let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")!
versionLabel.stringValue = "\(NSLocalizedString("Current Version", comment: "")) : \(version as! String)"
```

### Accessibility Permissions
```swift
// Use macOS official terminology for system features
allowToAccessButton.title = NSLocalizedString("Auth", comment: "")
statusMessage = NSLocalizedString("Needs access to Accessibility controls", comment: "")
```

## Translation Quality Checklist

Before committing translations:

- [ ] All macOS system terms match official localization (check System Preferences)
- [ ] Modifier key symbols (⌘⌥⌃⇧) are preserved in all languages
- [ ] App name "Mos" is unchanged everywhere
- [ ] Person names and GitHub handles are untranslated
- [ ] Numbers and technical values are unchanged
- [ ] No duplicate translations (translated value ≠ English value)
- [ ] No empty or placeholder-only strings
- [ ] Keys in Localizable.xcstrings match their English values
- [ ] Chinese uses correct variant (简体 vs 繁體 vs 港台)
- [ ] Japanese uses appropriate formality level (です/ます form for UI)

## Workflow for Adding New Languages

1. Add language in Xcode: Project Settings → Info → Localizations
2. Check both .xcstrings files for new language columns
3. Translate all existing keys using this guide's terminology rules
4. Test the app in new language (System Preferences → Language & Region)
5. Verify all UI elements display correctly (no truncation, proper spacing)
