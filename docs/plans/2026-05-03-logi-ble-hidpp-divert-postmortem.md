# Logi BLE HID++ 按键接管调试回溯

> 时间: 2026-05-01 ~ 2026-05-03
> 结论状态: 已收敛为产品策略;提交前已移除默认高频饱和日志,保留 DEBUG 自动日志框架与可选 verbose trace
> 相关代码: `Mos/Logi/*`, `Mos/ButtonCore/*`, `Mos/Windows/PreferencesWindow/ButtonsView/*`

---

## 1. 背景

Mos 的 [按键] 模块通过 Logitech HID++ `REPROG_CONTROLS_V4` 接管部分 Logi 设备按键。用户报告:

- 同一设备通过 Bolt/Unifying 接收器连接时,HID++ 按键识别稳定。
- 同一设备通过 BLE 直连时,HID++ 按键只在 discover / re-discover / 录制后的数秒内生效,随后失效。
- 失效后点击 HID++ 面板的 re-discover,或在 [按键] 面板点击 [+] 进入录制,能短暂恢复。
- 退出或卸载 Logi Options+ 后,BLE 通道恢复稳定。

最终确认: 主要问题不是 Mos 的普通事件分发,而是 BLE 直连下 Logi Options+ 会持续抢占或清除 HID++ 按键通知/接管状态。Bolt/Unifying 路径没有表现出同样的不稳定,因为 Mos 与设备的 HID++ 通信和按键通知经由接收器路径,不容易被 Logi Options+ 以同样方式清掉。

---

## 2. 现象与实验记录

### 2.1 初始现象

测试流程:

1. 打开 Mos。
2. 在 [按键] 面板录入 BLE 设备的 Back Button / Forward Button / DPI Switch。
3. 绑定动作为调度中心等可观察动作。
4. 持续按键。

观察:

- 录入后约 3~5 秒内有效。
- 之后 HID++ 按键事件不再进入 Mos。
- 切回 Mos 设置窗口后又短暂恢复,之后再次失效。
- 点击 HID++ 面板 re-discover 会短暂恢复。
- 点击 [按键] 面板 [+] 进入录制也会短暂恢复。

### 2.2 标准侧键实验

曾经在引入 HID++ 前,Back / Forward 会被录为系统鼠标键 `3/4`,触发稳定。

实验:

- 临时关闭 HID++ 层后,重新录入 Back / Forward。
- 录入结果变为系统鼠标按键 `3/4`。
- 长时间持续按压,触发稳定,不再出现 3~5 秒后失效。

结论:

- BLE Back / Forward 这类标准侧键不需要走 HID++。
- 将它们强行 divert 到 HID++ 反而把稳定的 macOS CGEvent 路径换成了会被 Logi Options+ 抢占的路径。

### 2.3 DPI Switch 实验

DPI Switch 没有标准 macOS 鼠标键回退,只能通过 HID++ 通知识别。

实验:

- BLE 下录入 DPI Switch。
- 录入后短时间有效,随后失效。
- 之前尝试过 keepalive / pulse / 定时 GetControlReporting。

观察:

- 某些 keepalive / GetControlReporting 可短暂唤醒通知流。
- 但无法形成稳定修复。
- 用户观察到: BLE 下按 3/4 后,短时间内再按 DPI Switch 更容易触发,久了又不行。

结论:

- BLE HID++-only 按键可被短暂唤醒,但这不是可靠的产品策略。
- Mos 不应通过周期性 keepalive/pulse 与 Logi Options+ 争抢设备状态。
- 对这类按键应明确提示 BLE HID++ 通知可能被 Logi Options+ 抢占或中断,建议 Bolt/Unifying。

### 2.4 Logi Options+ 验证

用户尝试卸载 Logi Options+:

- 卸载后 BLE 通道明显稳定。
- BLE HID++-only 按键也不再表现出原来的快速失效。

结论:

- "BLE 通道不稳定由 Logi Options+ 抢占引发"不是纯推测,有本地实验证据。
- UI 文案可以明确提及 Logi Options+。

---

## 3. 为什么 Bolt 无问题, BLE 有问题

### 3.1 Bolt / Unifying

Bolt/Unifying 通过 Logitech 接收器呈现设备和 HID++ 通道。Mos 接管按键时,主要面向接收器下的目标设备。

实测表现:

- HID++ 按键通知稳定。
- GetControlReporting / SetControlReporting 与按键事件流基本一致。
- 切换 BLE -> Bolt 的恢复路径稳定。

### 3.2 BLE 直连

BLE 直连时,设备同时暴露:

- 标准 HID / CGEvent 层: Back / Forward 可作为系统鼠标键 `3/4` 到达。
- Logitech HID++ 通知层: DPI Switch / SmartShift 等 HID++-only 控件需要 divert 后通过 HID++ 通知到达。

Logi Options+ 也会打开并操作同一 BLE HID++ 通道。当它清除或重写 control reporting 后:

- Mos 认为自己已经 set 过 divert,但设备真实状态已变化。
- HID++ 按键通知停止到达。
- re-discover / 录制会重新 set 或 query,所以短暂恢复。

---

## 4. 调试中走过但放弃的方案

### 4.1 runtime fallback / shadow binding

尝试:

- 当 Logi Back / Forward 失效时,运行时把 HID++ MosCode `1006/1007` fallback 到系统鼠标键 `3/4`。
- InputProcessor 同时兼容 Logi binding 与 native mouse event。

问题:

- 真正失效时,HID++ 事件根本没有进入 Mos,运行时翻译无从发生。
- 如果原始绑定仍是 Logi MosCode,标准 `3/4` CGEvent 不一定能匹配。
- 容易出现重复触发和状态释放复杂度。

处理:

- 已移除 runtime shadow fallback。
- 新策略改为录入/迁移阶段就把标准侧键转换为系统鼠标键。

### 4.2 keepalive / pulse 修复 BLE HID++ 通知

尝试:

- 使用 IRoot.Ping / GetControlReporting / SetControlReporting pulse 维持 BLE 通知流。
- 对 DPI Switch 等 HID++-only 控件做多轮探针。

问题:

- 可短暂唤醒,但不能稳定维持。
- 与 Logi Options+ 同时存在时,本质是两个应用抢同一个 HID++ ownership。
- 可能增加设备负担和状态振荡。

处理:

- 已移除 HID++ notification watchdog / pulse / protocol probe matrix。
- 不再把 keepalive 作为产品修复策略。

### 4.3 对所有 BLE 按键都强制 HID++

问题:

- Back / Forward 原本标准 CGEvent 稳定。
- `temporarilyDivertAll()` 在录制时把标准侧键也拉进 HID++,导致用户无法录到 `3/4`。

处理:

- BLE 标准侧键在 normal 和 recording 阶段都走 native-first。
- 录制 Back / Forward 会得到系统鼠标键 `3/4`,而不是 Logi MosCode。

---

## 5. 最终策略

### 5.1 三类按键分层

| 类型 | 示例 | BLE 策略 | Bolt/Unifying 策略 | UI |
|---|---|---|---|---|
| 标准鼠标键 | Middle / Back / Forward | 使用系统鼠标键 `2/3/4`,不争 HID++ | 保持 HID++ 可用 | 蓝色 branch 仅用于历史 Logi 绑定迁移 |
| HID++-only 按键 | DPI Switch / SmartShift 等 | 允许绑定,但提示 BLE HID++ 可能不稳定 | 保持 HID++ | 琥珀色无线/警告图标 |
| 真实接管冲突 | 外部应用清除 Mos divert | 不自动硬抢;按类型提示 | 提示冲突 | 黄色 branch |

### 5.2 蓝色 branch / 黄色 branch / 琥珀无线图标分工

#### 蓝色 branch: 可改用系统鼠标键

含义:

- 当前绑定是历史 Logi Back/Forward/Middle 绑定。
- 当前 BLE 策略认为该按键可以用稳定的 macOS 鼠标键替代。
- 用户点击后,绑定 trigger 从 Logi MosCode 改为 `2/3/4`。
- 替换时会去除已有重复 `2/3/4` 绑定,避免列表重复。

对应模块:

- `LogiStandardMouseButtonAlias`
- `ButtonBindingReplacement`
- `ButtonCapturePresentationStatus.standardMouseAliasAvailable`

#### 黄色 branch: HID++ 接管冲突

含义:

- Mos 需要 HID++ 通知才能识别该控件。
- 检测到外部应用清除或竞争 HID++ divert。
- 对 BLE 场景,文案明确指出通常由 Logi Options+ 抢占引发。

对应模块:

- `ConflictStatus`
- `LogiButtonDeliveryMode.contended`
- `ButtonCapturePresentationStatus.contended`

#### 琥珀无线/警告图标: BLE HID++ 通知可能不稳定

含义:

- 该控件没有标准 macOS 鼠标键回退。
- 当前连接是 BLE。
- Mos 只能通过 HID++ 通知识别,但 BLE 下该通知流可能被 Logi Options+ 抢占或中断。

对应模块:

- `LogiButtonCaptureDiagnosis.isBLEHIDPPOnlyControl`
- `ButtonCapturePresentationStatus.bleHIDPPUnstable`
- `logi_ble_hidpp_unstable_toast`

---

## 6. 关键代码改动

### 6.1 传输与投递策略

文件:

- `Mos/Logi/Divert/LogiButtonDeliveryPolicy.swift`
- `Mos/Logi/Divert/LogiButtonDeliveryMode.swift`
- `Mos/Logi/Core/LogiDeviceSession.swift`
- `Mos/Logi/Core/LogiSessionManager.swift`

核心概念:

- `LogiTransportIdentity`: `.bleDirect`, `.receiver`, `.unsupported`
- `LogiButtonDeliveryPolicy`: 决定某 CID 在某 transport/phase 下是否走 HID++。
- `LogiButtonDeliveryMode`: 当前接管模式,目前保留 `.hidpp` 与 `.contended`。
- `LogiButtonCaptureDiagnosis`: UI 读取的统一诊断对象,包含 ownership / delivery / transport / native alias 等。

当前默认:

- BLE + standard mouse aliases -> native event。
- Receiver + standard mouse aliases -> HID++。
- BLE + HID++-only -> HID++ best-effort + UI 风险提示。

### 6.2 标准鼠标键映射

文件:

- `Mos/Logi/Core/LogiCIDDirectory.swift`
- `Mos/ButtonCore/LogiStandardMouseButtonAlias.swift`
- `Mos/Windows/PreferencesWindow/ButtonsView/RecordedEvent.swift`

映射:

| HID++ CID | Logi MosCode | macOS 鼠标键 |
|---|---:|---:|
| `0x0052` Middle Button | `1005` | `2` |
| `0x0053` Back Button | `1006` | `3` |
| `0x0056` Forward Button | `1007` | `4` |

原则:

- 只在录入/迁移边界做转换。
- `InputProcessor` 不再做 Logi MosCode -> native mouse runtime 翻译。
- 已转换为 `3/4` 的绑定就是普通鼠标绑定,不再依赖 HID++。

### 6.3 BLE standard-button undivert guard

文件:

- `Mos/Logi/Core/LogiDeviceSession.swift`
- `Mos/Logi/Divert/LogiButtonDeliveryMode.swift`

目的:

- 对 BLE 标准侧键,确保设备不被 Mos 留在 diverted 状态。
- 仅对 native-first CIDs 做轻量 GetControlReporting query;如果发现仍处于 divert,发 SetControlReporting OFF。

注意:

- 这不是 HID++-only keepalive。
- 它只用于让标准侧键回到系统鼠标键路径,避免 Mos 自己残留接管。

### 6.4 UI 状态与交互

文件:

- `Mos/Windows/PreferencesWindow/ButtonsView/ButtonCapturePresentationStatus.swift`
- `Mos/Windows/PreferencesWindow/ButtonsView/ButtonTableCellView.swift`
- `Mos/Windows/PreferencesWindow/ButtonsView/PreferencesButtonsViewController.swift`
- `Mos/Localizable.xcstrings`

改动:

- popup 中删除"恢复 HID++ 接管"按钮,避免给用户一个意义不清且不稳定的选择。
- 蓝色 branch popup 只提供"改用系统鼠标按键"。
- BLE HID++-only 录入后同步 toast 提醒。
- popup 文案增加 Bolt/Unifying 推荐。
- 冲突文案明确提及 Logi Options+。

### 6.5 DEBUG 自动日志

文件:

- `Mos/Logi/Debug/LogiDebugPanel.swift`
- `Mos/Logi/LogiCenter.swift`
- `MosTests/LogiPersistenceCanaryTests.swift`

行为:

- DEBUG 构建自动写入 `~/Library/Logs/Mos/hidpp-debug-latest.log`。
- 每次会话同时生成时间戳文件 `hidpp-debug-YYYY-MM-DD-HHMMSS.log`。
- 写入逻辑位于 `#if DEBUG` 下,不会进入线上构建。
- 本轮用于定位的 ButtonCore / InputProcessor 每按键日志已删除。
- `LogiTrace` 仍保留为 DEBUG 可选诊断通道,默认关闭;需要临时打开时设置 UserDefaults `LogiVerboseTraceEnabled=true`。

用途:

- 后续用户测试无需手动复制控制台日志。
- 后续如需再次排查 HID++ 状态流,可以临时打开 verbose trace;常规 DEBUG 运行不会持续写入高频 trace。

---

## 7. 术语表

| 中文概念 | 代码命名 | 含义 |
|---|---|---|
| BLE 直连 | `LogiTransportIdentity.bleDirect` | 不经 Bolt/Unifying 接收器的蓝牙连接 |
| 接收器连接 | `LogiTransportIdentity.receiver` | Bolt/Unifying/Lightspeed 等 receiver 路径 |
| HID++ 投递策略 | `LogiButtonDeliveryPolicy` | 决定某按键走 HID++ 还是 native CGEvent |
| 投递模式 | `LogiButtonDeliveryMode` | 当前 ownership 是否仍走 HID++ 或进入 contended |
| 接管诊断 | `LogiButtonCaptureDiagnosis` | UI 的统一状态输入 |
| 标准鼠标键别名 | `LogiStandardMouseButtonAlias` | Logi Back/Forward/Middle 到 `3/4/2` 的映射 |
| BLE 标准键 undivert guard | `LogiBLEStandardButtonUndivertPlanner` / StandardButtonGuard log tag | 防止 BLE 标准侧键残留 HID++ divert |
| 可改用系统鼠标键 | `ButtonCapturePresentationStatus.standardMouseAliasAvailable` | 蓝色 branch |
| 接管冲突 | `ButtonCapturePresentationStatus.contended` / `ConflictStatus` | 黄色 branch |
| BLE HID++ 不稳定 | `ButtonCapturePresentationStatus.bleHIDPPUnstable` | 琥珀无线/警告图标 |

---

## 8. 外部参考与社区案例

### 8.1 Linux 6.1: 蓝牙 HID++ catch-all 合入后回退

Linux 内核社区曾尝试对所有 Logitech Bluetooth 设备默认启用 HID++:

- Patch 说明中提到: Logitech 没有完整列表标识哪些 Bluetooth 设备支持 HID++,因此尝试对每个 Logitech Bluetooth 设备 probe HID++ 支持;不支持时应 fallback 到普通 HID。参考: [Linux Input 邮件列表](https://www.spinics.net/lists/linux-input/msg80310.html)。
- 该策略进入 Linux 6.1 过程后被回退。回退说明指出 `hid-logitech-hidpp` 会绑定所有 Bluetooth mice,但某些 corner case 下驱动会放弃设备,最终用户得到 dead mouse。参考: [kernel revert commit](https://git.zx2c4.com/linux-rng/commit/arch/x86/kernel/cpu/scattered.c?h=jd%2Fvdso-test-harness&id=a9d9e46c755a189ccb44d91b8cf737742a975de8) 与 [Phoronix 归纳](https://www.phoronix.com/news/Linux-6.1-Demotes-Logitech-HID)。
- 另一个相关 revert 提到 catch-all Bluetooth HID++ 可能让驱动绑定到支持不足的设备,probe 返回 `-ENODEV`,导致鼠标不可用。参考: [Software Heritage mirror](https://archive.softwareheritage.org/browse/revision/40f2432b53a01b6d5e3a9057f1d5c406930e1360/?path=Kconfig)。

对 Mos 的启发:

- BLE HID++ 不能简单等同于 receiver HID++。
- 对 BLE 设备做 blanket HID++ 接管风险较高。
- 产品策略应保守:标准 HID 能稳定表达的按键优先走系统事件;HID++-only 控件只做 best-effort 并明确提示。

### 8.2 Solaar: HID++ diversion 是显式 opt-in,依赖通知

Solaar 文档说明:

- Solaar 规则处理基于 HID++ notifications。
- 对那些本来产生普通 HID 输出的动作,必须先设置为 diverted,才会生成 HID++ notification。
- 未 diverted 时,规则不会因该动作触发。参考: [Solaar rules: HID++ notifications and diversion](https://pwr-solaar.github.io/Solaar/rules/)。
- Solaar 支持部分通过 USB 或 Bluetooth 直连的 Logitech 设备,但不是所有直连设备都支持,需要逐设备信息。参考: [Solaar capabilities](https://pwr-solaar.github.io/Solaar/capabilities/)。

对 Mos 的启发:

- HID++-only 按键天然依赖 notification stream。
- 如果 notification stream 被另一个应用抢占或中断,应用层无法从 CGEvent 重新构造这些按键。
- 标准 Back/Forward 可通过普通鼠标键表达,不应为了统一模型而强制走 diversion。

### 8.3 HID++ REPROG_CONTROLS_V4 协议说明

社区整理的 `0x1B04 Special Keys and Mouse Buttons` 文档说明:

- divert 的含义是抑制设备原生动作,改为通过 HID++ `divertedButtonsEvent` 报告给软件。
- `getCidReporting` 返回当前 divert / persist / rawXY / remap 状态。
- `setCidReporting` 的 `divert` + `dvalid` 控制临时 divert。
- `remap=0` 表示保持之前 remap 设置不变,不是清 remap;清 remap 应 remap 到自身 CID。
- 如果 control 同时 temporarily diverted 和 remapped,diversion 使用原始 control ID,remap 对 temporary divert 无效。
- 配置改变不会影响当前正在按下的按钮,新状态要到下一次物理按下才生效。参考: [x1b04 special keys and mouse buttons](https://lekensteyn.nl/files/logitech/x1b04_specialkeysmsebuttons.html)。

对 Mos 的启发:

- Mos 不应随意修改 remap target。
- `SetControlReporting` 保持 `remap=0` 是保守选择。
- 对用户正在按住按键时切换 divert 状态,不能指望立即改变本次按压的事件流。

### 8.4 Solaar 源码侧的 setCidReporting

Solaar 当前实现中,setCidReporting 将 `(cid, flags, remap)` 打包为 `struct.pack("!HBH", ...)`,其中 `remap=0` 的语义是保留当前 mapping。参考: [Solaar hidpp20.py](https://github.com/pwr-Solaar/Solaar/blob/master/lib/logitech_receiver/hidpp20.py)。

对 Mos 的启发:

- 不需要为了 BLE 直连特殊改成 self-target remap。
- 本轮 Mos 最终没有采用 "BLE self targetCID" 方案。

---

## 9. 后续维护建议

### 9.1 保留的可调开关

当前策略保留 UserDefaults 级开关,便于灰度或回退:

- `LogiBLEStandardButtonsNativeFirst`
- `LogiBLEStandardUndivertGuardEnabled`
- `LogiBLEStandardUndivertGuardInterval`

建议:

- 线上默认保持 native-first enabled。
- 如果未来发现某设备 Back/Forward 不发 CGEvent,可以针对设备或用户开关回退 HID++。

### 9.2 后续可删的内容

提交前已经清理:

- `InputProcessor` / `ButtonCore` 中仅用于本轮定位的按键级 verbose 日志。
- `LogiTrace` 默认关闭,避免常规 DEBUG 运行持续写入高频 trace。

不建议删除:

- DEBUG 自动本地日志框架。
- `LogiStandardMouseButtonAlias`。
- `ButtonCapturePresentationStatus` 状态聚合。
- delivery policy / mode 纯函数测试。

### 9.3 回归测试重点

每次改 Logi 按键前应至少验证:

1. BLE Back / Forward 新录入直接成为 `3/4`,长按/连按稳定。
2. 历史 Logi Back / Forward 绑定在 BLE 下显示蓝色 branch,点击后转成 `3/4` 且不重复。
3. BLE DPI Switch 可录入,但显示 BLE HID++ 不稳定提示。
4. Bolt/Unifying 下 Logi HID++ 按键仍正常接管。
5. Bolt <-> BLE 快速切换后,UI 状态刷新,`3/4` 绑定不失效。
6. Logi Options+ 存在时,DPI Switch 类 HID++-only 按键可以提示冲突/不稳定;卸载或退出后 BLE 稳定性恢复。

---

## 10. 当前验证结果

本轮收尾前已执行:

```bash
xcodebuild test -scheme Debug -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO
```

结果:

- 423 tests
- 3 skipped
- 0 failures

同时执行:

```bash
scripts/qa/lint-logi-boundary.sh
jq empty Mos/Localizable.xcstrings
git diff --check
```

结果均通过。

---

## 11. 最终结论

BLE 问题的根因不是单一 "Mos 没有定时 keepalive",而是:

1. BLE 直连下 Logi Options+ 会与 Mos 竞争 HID++ control reporting / notification stream。
2. Back / Forward 这类标准侧键本来有稳定的系统鼠标事件路径,不应被拉进 HID++。
3. DPI Switch 这类 HID++-only 控件没有系统事件替代,只能 best-effort 并向用户透明呈现风险。

因此最终产品策略是:

- **能用系统鼠标键表达的 BLE 按键,就不走 HID++。**
- **必须 HID++ 的 BLE 按键,允许绑定但明确提示不稳定和 Logi Options+ 抢占风险。**
- **Bolt/Unifying 路径继续作为稳定 HID++ 接管推荐路径。**
