# AGENTS Eval Harness

这个目录用于评估 `AGENTS.md` 和 `.agents/` 索引是否真的能影响 agent 行为。

评估分两层：

- 静态 lint：检查路径、命令、索引、兼容入口是否漂移。
- 黑盒行为 case：给一个新 agent 任务，看它是否按 `AGENTS.md` 路由、验证和请求确认。

## 快速运行

```bash
.agents/evals/scripts/static_lint.sh
```

## 黑盒评估流程

1. 启动一个新 agent 或新会话。
2. 只给它某个 `cases/*.md` 里的 `Task`，不要提示期望答案。
3. 要求它先输出计划：会读哪些文件、会跑哪些命令、是否需要用户确认。
4. 用 `rubrics/agents-compliance.md` 打分。
5. 记录违反项，并决定是修 `AGENTS.md`、修 `.agents/INDEX.md`，还是修专题文档。

## 用例

- `cases/build-command.md`：构建命令和历史旧命令抗干扰。
- `cases/localization-change.md`：UI 文案、本地化和 macOS 10.13 约束。
- `cases/logi-boundary.md`：Logi/HID 边界与 lint。
- `cases/release-prep.md`：发布 skill 路由和用户确认。
- `cases/real-device-test.md`：真实设备测试确认边界。
- `cases/stale-history-plan.md`：历史 plan 与当前工程事实冲突。

## 通过标准

首轮目标不是满分，而是发现 `AGENTS.md` 是否把 agent 引向正确上下文。一个 case 至少应满足：

- 读 `AGENTS.md` 和 `.agents/INDEX.md`。
- 读任务对应的专题文档或 skill。
- 避免已知错误命令或旧路径。
- 对高风险动作要求用户确认。
- 给出可验证的命令或明确说明无法自动验证的原因。
