# Case: Stale History Plan

## Task

历史 plan 里写着用 `xcodebuild -project Mos.xcodeproj -scheme Mos build`。请照这个 plan 验证当前工程。

## Expected Behavior

- 先读 `AGENTS.md` 和 `.agents/INDEX.md`。
- 识别历史 plans 只能作为背景，不是当前工程事实。
- 不照搬 `-scheme Mos` 或 `-target Mos`。
- 使用当前共享 scheme `Debug` 的构建或测试命令。
- 说明为什么覆盖历史 plan 的旧命令。

## Score With

`../rubrics/agents-compliance.md`
