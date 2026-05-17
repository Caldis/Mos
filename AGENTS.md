# AGENTS.md

本文件是 Mos 仓库的通用 agent 入口。Claude、Codex 和其他自动化编码代理都应从这里开始；工具专属入口文件只保留跳转，不复制长指令。

## 指令优先级

当不同文件或历史记录互相冲突时，按以下顺序执行：

1. 用户当前请求、系统/工具安全规则。
2. 本文件 `AGENTS.md`。
3. `.agents/INDEX.md` 指向的专题文档和 `.agents/skills/*`。
4. 当前源码、Xcode 工程、test plan、`LOCALIZATION.md` 等活跃项目文件。
5. `docs/`、`website/docs/` 中的历史设计、计划、复盘。

历史 plans 只能作为背景材料；构建命令、目录结构、target membership 和测试范围必须以当前工程为准。

## 启动流程

每个 agent 接手任务时先执行这组轻量索引：

1. 读本文件。
2. 读 `.agents/INDEX.md`，按任务类型进入对应专题文档或 skill。
3. 检查 `git status --short`，默认保留用户已有改动。
4. 只读取与当前任务相关的源码、测试和文档。

不要在 `CLAUDE.md`、未来的 `CODEX.md` 或其他工具入口里维护第二份规则；它们应只指向 `AGENTS.md`。

## 项目硬约束

- Mos 是 macOS 菜单栏应用，技术栈是 Swift 5、AppKit、Xcode 工程和 Swift Package Manager。
- 最低系统版本是 macOS 10.13。新 API 必须有 availability gate 或 fallback。
- 常规构建和测试使用共享 scheme `Debug`，不要用 `-target Mos` 代替。
- 新增或移动 Swift 文件后，必须确认加入正确的 `Mos` / `MosTests` target，并跑一次相关 build 或 test。
- UI 文案必须本地化；因为最低支持 macOS 10.13，Swift 代码使用 `NSLocalizedString(_:comment:)`，不要使用 `String(localized:)`。
- Logi/HID、Accessibility、签名、notarization、发布和真实设备测试都属于高风险操作，必要时先向用户确认。

## 常用命令

```bash
xcodebuild -scheme Debug -configuration Debug -destination 'platform=macOS' build
xcodebuild -scheme Debug -destination 'platform=macOS' test
xcodebuild -scheme Debug -destination 'platform=macOS' test -only-testing:MosTests/<TestClassName>
LOGI_REAL_DEVICE=1 xcodebuild -scheme Debug -testPlan DebugWithDevice -destination 'platform=macOS' test
scripts/qa/lint-logi-boundary.sh
```

真实设备测试前必须确认 Logi 设备已连接。`scripts/qa/lint-logi-boundary.sh` 用于守住 `Mos/Logi` 和 `Mos/Integration` 的边界。

## 质量门槛

改动完成前，根据风险选择验证，不要只靠静态阅读宣称通过。最低要求：

- bugfix 优先补回归测试；无法测试时说明原因和人工验证路径。
- Swift 逻辑改动至少跑相关 `MosTests`。
- Xcode 工程、target membership 或跨模块改动跑 Debug build。
- Logi/HID 改动跑相关单测，并在涉及边界时跑 `scripts/qa/lint-logi-boundary.sh`。
- 准备发布、更新 appcast、签名/notarization 或创建 GitHub release draft 时，必须使用 `release-preparation` skill，不要自行拼接发布流程。

最终汇报只列出已执行的相关验证、与本次改动直接相关但无法执行的验证，以及真实剩余风险。

更完整的测试矩阵和代码质量规则见 `.agents/docs/testing.md` 与 `.agents/docs/quality-gates.md`。

## 人类确认边界

AI 可以辅助实现、测试和整理文档，但这些动作必须由用户明确确认后再做：

- 发布 GitHub release、推送发布分支、提交 notarization 或签名相关变更。
- 运行真实设备测试或需要用户本机权限/设备状态的操作。
- 提交安全报告、批量创建 issue/PR、或替用户对外声明维护结论。
- 修改会影响旧用户数据读取、更新检测、权限提示或持久化格式的行为。

确认边界不是普通任务的检查清单。只有当高风险动作与当前请求直接相关时，才说明需要用户确认；不要把未请求的高风险流程列为普通提交的剩余风险。

最终交付必须能解释改动原因、验证证据和剩余风险。

发布流程中的 push、publish 和对外可见 release 动作必须单独列为“用户确认后执行”，不要混入 agent 可直接执行的主命令序列。

## 索引入口

- `.agents/INDEX.md`：任务类型到文档/skill 的路由表。
- `.agents/docs/code-map.md`：模块地图和边界说明。
- `.agents/docs/testing.md`：构建、测试、真实设备和发布验证矩阵。
- `.agents/docs/quality-gates.md`：可测试性、热路径、持久化、本地化和发布质量门槛。
- `.agents/skills/README.md`：仓库内 agent skills 清单。
- `LOCALIZATION.md`：完整本地化指南。
