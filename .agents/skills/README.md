# Agent Skills

本目录存放仓库内可复用的 agent skill。新增、移动或删除 skill 后，要同步更新本文件和 `.agents/INDEX.md`。

## release-preparation

路径：`.agents/skills/release-preparation/SKILL.md`

触发场景：

同时满足两个条件时触发：

- 用户有明确的 Mos release 意图。
- 任务需要至少一个 release 动作：bump version / build number、创建 release archive、签名、notarization、zip、生成 changelog、签名或更新 Sparkle appcast、创建 GitHub release draft。

约束：

- 不要跳过 skill 自带验证步骤。
- 不要在用户确认前发布 GitHub release。
- 不要在用户确认前推送发布分支。

## community-pr-loop

路径：`.agents/skills/community-pr-loop/SKILL.md`

触发场景：

- 处理外部贡献者的 PR：评估价值、审查、合并、关闭、批量扫描 open PR。
- 发版后回访相关 issue 与贡献者（通知验证、shipped 告知）。

约束：

- 决策优先级固定为 稳定性 > 兼容性 > 性能 > 可维护性。
- 触碰 event tap 位置/模式/掩码的 PR 必须逐项出具专项清单评估。
- 每个合并/关闭的 PR 都必须留具体的致谢评论。
