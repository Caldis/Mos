# Quality Gates

本文件定义 agent 改代码前后要守住的质量门槛。

## 可测试性

- 新行为优先落到可测试的纯逻辑、planner、packet builder、formatter 或 bridge 层。
- bugfix 优先补回归测试；测试应覆盖旧失败路径。
- 不为了测试暴露宽泛 API。优先使用小型 internal helper、protocol、test double 或现有 seam。
- 新增测试文件必须确认加入 `MosTests` target。

## 热路径

`Mos/ScrollCore/`、输入事件处理和 HID 回调路径要避免：

- 不必要的对象分配或数组复制。
- 同步 I/O、重日志、频繁 NotificationCenter 广播。
- 把 UI、持久化或外部服务调用塞进事件热路径。
- 没有必要的跨模块依赖。

## 持久化兼容

改动 `UserDefaults` key、shortcut identifier、Logi cache key、CID/feature 常量或 Sparkle `CURRENT_PROJECT_VERSION` / appcast build number 时，必须考虑旧用户数据能否继续读取、更新检测是否仍正常。

需要兼容时，补 canary 或迁移测试；不能兼容时，必须在说明中明确风险和用户影响。

## Logi / HID

- HID++ packet 构造和 divert/reconcile 决策应保持可单测。
- 普通应用层不要直接引用 Logi 内部 session、packet、feature 实现。
- 涉及 `Mos/Logi/` 或 `Mos/Integration/` 边界时运行 `scripts/qa/lint-logi-boundary.sh`。
- 真实设备逻辑必须由 `LOGI_REAL_DEVICE=1` gate 隔离。

## UI 与本地化

- Swift 文案使用 `NSLocalizedString(_:comment:)`；因为 Mos 最低支持 macOS 10.13，不要使用 `String(localized:)`。
- `Mos/Localizable.xcstrings` 和 `Mos/mul.lproj/Main.xcstrings` 保持分离。
- 不重命名已被代码、持久化或 Interface Builder 使用的 key。
- UI 改动检查长文本、Light/Dark Mode、Auto Layout 和 macOS 10.13 fallback。

## 发布

准备发布、更新 appcast、生成或签名 release artifact、notarization 和 GitHub release draft 必须使用 `.agents/skills/release-preparation/SKILL.md`。每次 release 都必须让 `CURRENT_PROJECT_VERSION` 唯一递增。不要在没有用户确认的情况下发布 release 或推送发布分支；在计划或命令列表中也要把 push/publish 与可自动执行步骤分开。
