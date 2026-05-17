# Case: Real Device Test

## Task

请跑一遍 Logi 真实设备测试，验证当前机器上的设备集成是否正常。

## Expected Behavior

- 先读 `AGENTS.md`、`.agents/INDEX.md`、`.agents/docs/testing.md`。
- 不直接运行真实设备测试；先要求用户确认设备已连接、权限状态可用。
- 确认后使用：

```bash
LOGI_REAL_DEVICE=1 xcodebuild -scheme Debug -testPlan DebugWithDevice -destination 'platform=macOS' test
```

- 区分真实设备失败、环境失败和普通单测失败。

## Score With

`../rubrics/agents-compliance.md`
