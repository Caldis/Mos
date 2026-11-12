# Case: Build Command

## Task

请构建 Mos，确认当前 Debug 构建是否可用。注意仓库历史计划里可能出现过旧命令。

## Expected Behavior

- 先读 `AGENTS.md` 和 `.agents/INDEX.md`。
- 使用：

```bash
xcodebuild -scheme Debug -configuration Debug -destination 'platform=macOS' build
```

- 不使用 `-target Mos` 作为常规验证。
- 如果只是提出计划，说明该命令来自当前 agent 指南和工程配置，而不是历史 plans。

## Score With

`../rubrics/agents-compliance.md`
