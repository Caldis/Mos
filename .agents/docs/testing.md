# Testing Matrix

本文件用于选择验证范围。不要用“看起来没问题”代替实际命令输出。

## 常规命令

```bash
xcodebuild -scheme Debug -configuration Debug -destination 'platform=macOS' build
xcodebuild -scheme Debug -destination 'platform=macOS' test
xcodebuild -scheme Debug -destination 'platform=macOS' test -only-testing:MosTests/<TestClassName>
xcodebuild -scheme Debug -destination 'platform=macOS' test -only-testing:MosTests/<TestClassName>/<testMethodName>
```

常规验证使用 `Debug` scheme。不要把历史 plans 里的 `-target Mos` 或旧 scheme 当作当前事实。

## 按改动选择验证

| 改动类型 | 最低验证 | 追加验证 |
|----------|----------|----------|
| 文档 / agent 配置 | `git diff --check`，检查相关链接和路径 | `rg` 查旧路径或旧入口 |
| Swift 纯逻辑 | 相关 `MosTests/<TestClassName>` | 全量 `xcodebuild ... test` |
| 新增 / 移动 Swift 文件 | Debug build | 相关测试类 |
| ScrollCore 热路径 | 相关 ScrollCore / Interpolator / ScrollFilter 测试 | 全量测试，必要时人工滚动验证 |
| ButtonCore / Shortcut / InputEvent | 相关 ButtonBinding / InputProcessor / ShortcutExecutor 测试 | 偏好设置按钮面板人工验证 |
| Logi / HID | 相关 `MosTests/Logi*` 测试，`scripts/qa/lint-logi-boundary.sh` | 真实设备测试 |
| 本地化 / UI 文案 | 检查 `LOCALIZATION.md`，确认 `.xcstrings` 同步 | 长文本、Dark Mode、macOS 10.13 fallback 人工验证 |
| 准备发布 / appcast 更新 | `release-preparation` skill 内的验证步骤 | GitHub draft 与 appcast URL 对齐 |

## 真实设备测试

真实 Logi 设备测试前必须先向用户确认设备已连接：

```bash
LOGI_REAL_DEVICE=1 xcodebuild -scheme Debug -testPlan DebugWithDevice -destination 'platform=macOS' test
```

不要把真实设备失败和普通单测失败混为一谈。先确认环境、设备连接、权限，再判断代码行为。

## 回归测试规则

bugfix 优先补回归测试。合适的测试应验证用户可见行为或稳定边界，而不是只锁住实现细节。

如果无法自动化测试，最终说明必须包含：

- 为什么不能自动化。
- 做过哪些手动或静态验证。
- 哪些风险仍需要用户确认。
