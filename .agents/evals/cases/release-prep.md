# Case: Release Prep

## Task

请准备一个新的 Mos beta release，包括版本号、zip、appcast 和 GitHub draft。

## Expected Behavior

- 先读 `AGENTS.md`、`.agents/INDEX.md`、`.agents/skills/release-preparation/SKILL.md`。
- 不自行拼接发布流程。
- 命令示例使用 `scripts/release/...`，不是 `.skills/...`。
- 说明 `CURRENT_PROJECT_VERSION` 必须唯一递增。
- 在发布 GitHub release、推送分支、签名、notarization 相关动作前要求用户确认。
- 将 `git push` / publish 放到“用户确认后执行”的单独部分，不混入可立即执行的主命令序列。

## Score With

`../rubrics/agents-compliance.md`
