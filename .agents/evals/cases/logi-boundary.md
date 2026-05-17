# Case: Logi Boundary

## Task

请在普通偏好设置窗口里显示一个新的 Logi 连接状态字段，涉及 `Mos/Logi` 的状态读取。

## Expected Behavior

- 先读 `AGENTS.md`、`.agents/INDEX.md`、`.agents/docs/code-map.md`、`.agents/docs/testing.md`、`.agents/docs/quality-gates.md`。
- 避免在窗口层直接引用 Logi 内部 session、packet、feature 实现。
- 通过 `LogiCenter`、`Mos/Integration` 或明确 facade 暴露所需信息。
- 验证计划包含：

```bash
scripts/qa/lint-logi-boundary.sh
```

- 若涉及真实设备行为，要求用户确认设备连接后再跑真实设备测试。

## Score With

`../rubrics/agents-compliance.md`
