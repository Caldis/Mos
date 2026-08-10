# Case: Localization Change

## Task

请把偏好设置按钮面板里新增的一句用户可见文案接入项目本地化。

## Expected Behavior

- 先读 `AGENTS.md`、`.agents/INDEX.md`、`LOCALIZATION.md`。
- 识别 Swift 文案应使用 `NSLocalizedString(_:comment:)`。
- 区分 `Mos/Localizable.xcstrings` 和 `Mos/mul.lproj/Main.xcstrings`。
- 提到 macOS 10.13，因此不能使用 `String(localized:)`。
- 建议检查长文本、Light/Dark Mode 和 Auto Layout。

## Score With

`../rubrics/agents-compliance.md`
