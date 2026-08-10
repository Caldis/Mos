# Agent Index

这是所有 agent 的任务路由表。先读 `AGENTS.md`，再按当前任务读取本文件列出的最小必要上下文。

## 通用入口

| 任务 | 必读 | 视情况读取 |
|------|------|------------|
| 任意代码改动 | `.agents/docs/code-map.md`, `.agents/docs/testing.md`, `.agents/docs/quality-gates.md` | 相关源码、相关 `MosTests/*` |
| bugfix | `.agents/docs/testing.md`, `.agents/docs/quality-gates.md` | 历史 issue/plan、相关回归测试 |
| UI / 文案 / 本地化 | `LOCALIZATION.md`, `.agents/docs/quality-gates.md` | `Mos/mul.lproj/Main.xcstrings`, `Mos/Localizable.xcstrings` |
| Logi / HID / 真实设备 | `.agents/docs/code-map.md`, `.agents/docs/testing.md`, `.agents/docs/quality-gates.md` | `Mos/Logi/*`, `Mos/Integration/*`, `scripts/qa/lint-logi-boundary.sh` |
| 准备发布 / 更新 appcast / notarization | `.agents/skills/release-preparation/SKILL.md` | `release/appcast.xml`, `CHANGELOG.md`, `Mos.xcodeproj/project.pbxproj` |
| agent 配置 / skill 调整 | `AGENTS.md`, `.agents/INDEX.md`, `.agents/skills/README.md` | `.claude/skills`, `.codex/skills` 兼容入口 |

## 当前事实来源

- 构建、scheme、target、test plan：以 `Mos.xcodeproj` 和 `MosTests/*.xctestplan` 为准。
- 模块边界：以源码和 `.agents/docs/code-map.md` 为准。
- 本地化：以 `LOCALIZATION.md` 和两个 `.xcstrings` 为准。
- 发布：以 `.agents/skills/release-preparation/SKILL.md` 为准。
- 历史 plans：只能提供背景，不作为当前命令或结构的最终依据。

## 索引维护规则

- 新增 `.agents/docs/*` 后，在本文件登记。
- 新增或移动 skill 后，更新 `.agents/skills/README.md` 和相关兼容 symlink。
- 不要在 `CLAUDE.md` 或其他工具入口复制本文件内容。
- 当 `AGENTS.md` 与专题文档重复时，保留根入口的硬约束，把细节放入专题文档。
