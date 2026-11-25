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

## 滚动管线基准

`scripts/qa/scroll-pipeline-benchmark.py` 在临时源码副本中构建 Mos. 探针使用实际帧时钟、ScrollPoster、CGEvent 字段编码和投递队列, 在系统投递之前记录出帧. 运行入口使用独立进程, 测量范围从 ScrollPoster 收到输入到投递队列出口. 需要 macOS、Xcode、Python 3 和已唤醒的显示器. `nsscreen` 需要 macOS 14 或更高版本

```bash
python3 scripts/qa/scroll-pipeline-benchmark.py cpu \
  --baseline a4c6794 --out /tmp/mos-scroll-cpu
python3 scripts/qa/scroll-pipeline-benchmark.py curves --out /tmp/mos-scroll-curves
python3 scripts/qa/scroll-pipeline-benchmark.py normalization --out /tmp/mos-scroll-normalization
python3 scripts/qa/scroll-pipeline-benchmark.py starts --out /tmp/mos-scroll-starts
python3 scripts/qa/scroll-pipeline-benchmark.py starts --display Type-c --alternate-display HX270S --out /tmp/mos-scroll-cross-screen
python3 scripts/qa/scroll-pipeline-benchmark.py report /tmp/mos-scroll-curves/trials.jsonl
```

- CPU 对照固定选用 CVDisplayLink 并关闭归一化, 在关闭覆盖率计数的优化构建中, 以 80 次每秒的输入预热 0.5 s, 测量 3 s. `--control` 可加入一个中间版本. `a4c6794` 使用内联 CVDisplayLink, 可作为抽取帧时钟前的基线
- `normalization` 在同一候选版本中配对测量开启和关闭, 分别比较自动选屏与固定同一物理时钟源. 选屏汇总记录首次会话和复用绑定时的查询、绑定耗时
- `starts` 记录冷启动会话、后续会话和模拟显示变更失效后的首个会话. `--alternate-display` 增加跨到另一屏和返回原屏的测量. `first-frame-summary.tsv` 汇总选屏、同步提交、首次插值回调以及首个非零位移事件的耗时
- 曲线默认在各屏幕上采集三种时钟和归一化开关的组合. `--display` 可指定屏幕名或 CGDisplay ID, `--rounds` 可设置重复次数. `--revision` 可选择已提交的候选版本, 省略时构建当前工作区. `--packages` 可复用 Xcode 的 SourcePackages 目录, 每次采集使用新输出目录
- 曲线的 `--targets` 用于测试采用共享发帧档位的历史版本. 按屏出帧的当前版本使用 `curves` 采集各物理屏幕的原生回调与位移
- `trials.jsonl` 保存原始记录和版本标识. CPU 输出 `cpu-runs.tsv` 和 `cpu-summary.tsv`, 包含单核 CPU、每次输出开销、实际输出频率和配对差值. 曲线输出 `curve-summary.tsv` 和 `curves.html`, 可以切换屏幕和归一化状态. 曲线汇总分别记录源时钟、目标帧率和进入位移计算的频率. T90 为累计输出到达该轮最终位移 90% 的时间
- 比较两个版本前核对实际时钟绑定、输出频率和累计位移. CPU 数字涵盖探针进程在测量窗口的工作, 曲线以系统投递前的事件为准. 用户在目标应用中实滚验证主观手感

## 输入事件端到端复验

`scripts/qa/mouse-input-qa.py` 用本机 Quartz 发送一对侧键按下和松开，在 Mos 的事件监听前后观察同一编号，再核对浏览器页面。远程桌面只需操作浏览器，侧键从 Mac 本机进入事件链。探针需要 macOS 10.15+、Xcode 命令行工具以及当前终端已有的辅助功能、输入监听和屏幕录制权限。浏览器使用前台窗口的标题确认测试目标。

准备修复前后的两份正常签名 Debug 构建，分别放在独立的 DerivedData 中。`app` 子命令接受已有辅助功能授权、支持 `--mos-check-input-permission` 的 `com.caldis.Mos.debug`。退出其他运行中的 Mos，再开始测试。工具先启动独立的本机 launchd 定时器，每轮只启动一份 Debug，绑定通过进程参数载入。到期时定时器会退出该会话的 Debug。

以下用 #1068 作例子。先运行 `start`，保存输出的 `session`，用 Chrome 访客窗口打开输出的 `url`，沿页内链接依次访问第 1、2、3 页。在最左边的 macOS 桌面运行测试，确保绑定的「向左移动空间」没有可切换的目标。每轮 `check` 都从第 3 页开始，退页后从浏览器前进回到第 3 页。

探针需要页面有可点击的露出区域。如果提示窗口被覆盖，可放大验收窗口后重试。

```bash
python3 scripts/qa/mouse-input-qa.py start

# 把 path 变量设为前一步输出的会话和实际的 Debug app 路径。
python3 scripts/qa/mouse-input-qa.py check "$qa_session" --expect both --page 2
python3 scripts/qa/mouse-input-qa.py app "$qa_session" "$qa_baseline_app" --bind 3=moveSpaceLeft
python3 scripts/qa/mouse-input-qa.py check "$qa_session" --expect up --page 2
python3 scripts/qa/mouse-input-qa.py app "$qa_session" "$qa_fixed_app" --bind 3=moveSpaceLeft
python3 scripts/qa/mouse-input-qa.py check "$qa_session" --expect none --page 3
python3 scripts/qa/mouse-input-qa.py check "$qa_session" --button 5 --expect both --page 3
python3 scripts/qa/mouse-input-qa.py stop "$qa_session"
```

`check` 返回非零表示输入链或页面与预期不符。保留会话内的 `results.jsonl` 作为对照证据。`stop` 清除该会话的 launchd 任务，并核对 Debug 持久设置和启动前一致。关闭为验收打开的浏览器窗口。

- **Quartz** 覆盖系统鼠标事件经过 Mos 到浏览器的路径，组合键的精确按下和松开语义另用 `InputProcessorTests` 验证。
- **虚拟 HID** 需要实际创建设备，并确认系统解析了它发出的 HID 报告。CoreHID 使用系统授权的 `com.apple.developer.hid.virtual.device`。此工具的记录标为 `quartz`，HID 设备枚举和报告链路需要单独证据。
- **实体设备** 覆盖 USB / 蓝牙和 Logitech HID++ 等硬件特有行为，按下面的设备测试流程验收。

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
