---
name: community-pr-loop
description: Mos 仓库社区 PR 的完整处理回路：扫描受理 → 交叉分析 → 深度审查 → 合并致谢或 request-changes → 发版纳入 → issue 通知验证。凡是涉及处理外部贡献者的 PR（评估、review、合并、关闭、批量扫描 open PR）、发版后回访相关 issue、或用户说"看看有哪些 MR/PR 要处理"时，必须使用本 skill，即使用户只要求其中一个环节。
---

# Community PR Loop

社区 PR 从受理到用户验证的完整回路。Mos 拦截并修改操作系统底层的用户输入——**每个 event tap 的位置、模式、掩码变化都是关键且珍贵的决策，性能敏感且对下游影响重大**。本回路的存在就是保证每个外部改动都经受与此相称的审查，同时让贡献者获得与其付出相称的尊重。

## 触发规则

以下任一场景触发：

- 用户要求评估/审查/合并/关闭某个 PR，或批量扫描 open PR。
- 发版完成后需要通知 issue 报告者验证。
- 用户询问"某个 PR 是否有价值 / 是否该合"。

## 决策优先级（用户既定）

**稳定性 > 兼容性 > 性能 > 可维护性**。所有取舍按此排序。

## 阶段 1：受理与交叉分析

1. `gh pr list` 获取全量 open PR，按性质分层：bug 修复（小、可验证）/ 功能（需产品决策）/ 依赖机器人。功能类 PR 不做代码审查结论，标注"需产品决策"交给用户。
2. 对每个候选 PR 做**分支交叉分析**：bug 在 master 与活跃重构分支（如有）上分别是否存在。
   - 两分支都有 → 真实修复，走审查。
   - 重构分支已修、master 未修 → 仍合入 master（用户既定策略），同步 master 进重构分支时按重构侧形态解冲突。
   - 交叉分析常发现外部贡献与内部质量批独立修了同一 bug——这是审查覆盖面的免费盲测，值得在感谢评论里提及。
3. 同作者的递进式 PR（后者完全包含前者）：合并后者，关闭前者并在关闭评论中致谢说明。

## 阶段 2：深度审查

通用清单：完整 diff 逐字读、pbxproj 测试注册四处齐全、测试是否真实红转绿、验证声明的浸泡等级（**开发者本机浸泡 ≠ 用户群浸泡**——未发版的 master 变更首次随版本曝露时，只能算零用户浸泡，须绑定 beta 通道过渡）。

### Event tap / 事件流专项清单（触碰 `CGEventTapLocation`、`CGEventTapOptions`、事件掩码、tap 生命周期的 PR 必须逐项出具评估）

1. **层级语义**：annotation（`eventTargetUnixProcessID` 等）只在 annotated 层可靠——per-app 功能依赖它；session 层在系统符号快捷键（Mission Control 等）消费点之前。迁层前 grep 整条消费链确认是否读注释字段。
2. **事件流生态**：与 BetterTouchTool/Karabiner/远程桌面等工具的仲裁顺序变化、消费独占性变化。这类风险单测测不出，只能靠 beta 用户群暴露——审查结论要写明。
3. **合成事件回环**：Mos post 到 `cghidEventTap` 的事件对所有下游 tap 可见，核对 `syntheticCustom` marker 防护。
4. **secure input 与 tap 禁用/重启边界**行为。
5. **default tap 是同步阻塞的**——回调耗时直接加进全系统输入延迟。
6. **删除与移动的不对称**：删除 listenOnly 无行为观察者的失效面是空集（可逻辑证明，可快合）；移动主动消费点的风险只能实测覆盖（必须绑 beta + 预置单行回退路径）。

### 性能红线（Logi/HID 类 PR）

任何"随时间反复发 HID++ 请求"的实现直接 request-changes——引用 `docs/plans/2026-05-03-logi-ble-hidpp-divert-postmortem.md` §4.2（keepalive 被移除的教训：抢 ownership、状态振荡、设备负担）。离散事件驱动 + one-shot + "已完成"守卫才可接受。修复类改动优先建议 **probe-then-repair**（先读回确认状态确实丢失，再一次性修复），而非无条件重发。

## 阶段 3：结论三态

- **合并**：squash merge。**每个合并的 PR 必须发感谢评论**——具体到该 PR 的亮点（诊断方法、验证质量、范围自律），不用模板套话。连环 pbxproj 冲突：`gh pr checkout` → rebase → union 解冲突 → force push 回 fork（maintainer edits 权限通常开启）。
- **request-changes**：给可执行的修改方向而非仅指出问题；引用仓库历史教训（postmortem、红线、既有测试）作论据——这会把贡献者拉进仓库的证据纪律。同根因的多个 PR 建议作者统一机制。
- **关闭**：被取代/不采纳的 PR 也要在关闭评论中致谢并说明理由。

## 阶段 4：发版纳入

- Release notes 面向普罗大众：**大白话，不写技术术语**（"调整了按键监听的层级"而非 tap location 迁移；debug 面板类改动一条都不写）。
- 贡献者 **inline 致谢**（`感谢 @login`），不设单独致谢区；GitHub login 用 `gh api repos/.../commits/<sha> --jq '.author.login'` 核实，不要用 git 显示名猜测。
- 行为变更类修复：顶部 `⚠️ 行为变更` 置顶说明（老配置用户视角描述"从 A 变为 B"）。
- 生态风险类改动（如 tap 迁层）：修复区末尾加 `注:` 写明原因与反馈渠道，语气克制不说教。

## 阶段 5：发版后 issue 通知

发布（publish 后）逐个回访本次修复对应的 issue：

1. 从 PR body 的 `Fixes #N` / `closes #N` 收集 issue 清单；PR 未链接的用关键字搜索补全。
2. **覆盖范围是整个发版区间，不只是最近一批**：`git log <last_tag>..HEAD` 里所有外部作者的 PR 都要回访——早先合并时的技术讨论不等于"已发布"告知，贡献者应得知自己的工作到达了用户。给每个外部 PR 补一条 shipped 评论（含 release 链接 + inline 致谢）。
3. **同症状 issue 搜索**：一个修复往往对应多个措辞不同的 issue（例如同一卡顿 bug 的中英文两个报告）。按症状关键词搜 open + closed issue，逐个通知。
4. 每条评论包含：`@报告者` + 一句修复了什么 + inline 致谢修复贡献者 `@login` + release 链接 + 请验证的邀请。
5. **语言匹配对方**：中文 issue 用中文回复；本地化贡献者可用其语言致意。
6. 已关闭的 issue 同样回访（报告者仍会收到通知）。

## 绝对约束

- 违反性能红线的实现不合入，无论问题多真实。
- 行为变更未写入 release notes 前不发版。
- 大规模重构分支不搭当期发版的车：真机回归 + 浸泡是它单独的晋级门槛。
- 合并、评论、关闭都是以用户 GitHub 身份进行的外部动作——批量操作前确认用户已授权该范围。
