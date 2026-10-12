# 实验记录（在另一台设备上填写）

> 逐项记录 Phase 0 / Phase 1 的观测。命题编号见 `02-experiment-plan.md`。
> 环境: macOS 26.5.1 (25F80) + Xcode 26.0 (17A324) / iOS 26 / MacBook (Apple Silicon) / Logitech MX Master 3S (蓝牙直连, Logi Options+ 未运行) / 日期 2026-07-11

## Phase 0 — Karabiner 代理(2026-07-11 已完成)

**实际执行方式**(与原清单略有出入,记录以便复现):
- Karabiner-Elements 16.1.0(DriverKit VirtualHIDDevice 1.8.0),系统扩展 `activated enabled`,Core-Service 正常 grab 设备。
- 翻转不走 GUI,直接写 `~/.config/karabiner/karabiner.json` 设备级 `mouse_flip_vertical_wheel`(v16.1 源码确认的键名),核心服务热加载即时生效,便于 A/B 切换。
- **注意 GUI 会规范化重写 karabiner.json**(剔除等于默认值的键),做 A/B 时先退出设置窗口,并以 `core_service.log` 的 `Load ...karabiner.json` 行核对每轮生效时刻。
- 观测手段:肉眼 + **前后截图对比**(客观记录镜像内页面内容位置),测试期间退出 Mos/Mos Debug 与 Logi Options+,系统自然滚动全程保持 =1 未动。

| 观测 | 结果 | 备注 |
|---|---|---|
| Karabiner 安装并启用其虚拟 HID | ☑ 是 | `hidutil list` 可见 VirtualHIDPointing 1.8.0 (vendor 0x16c0 / product 0x27da);MX Master 3S 被 grab(seize) |
| 配置 vertical_wheel flip | ☑ 是 | 设备级 `mouse_flip_vertical_wheel`,热加载 |
| 镜像内能正常滚动 | ☑ 是 | 鼠标被 seize 后**唯一**输入通路是虚拟设备,镜像仍可正常滚动(截图佐证)→ 单此一条即证 C2 |
| 镜像内方向被 Karabiner 反转 (**C2+C3**) | ☑ 是 | A/B 对照:flip=off 时「滚轮朝自己」→ 视图向页顶;flip=on 同一手势 → 视图向页底(两轮均有截图)。期间系统自然滚动偏好未变,唯一变量是 flip 标志 |

**Phase 0 结论**: ☑ **go**(虚拟 HID 能到达镜像,方向可控;继续 Phase 1)
说明: 镜像内与普通 App 方向随 flip 同步变化(「内外一致」),符合层级模型——HID 层翻转发生在所有消费者的上游,镜像与普通 App 看到同一份已翻转数据。另:测试首轮曾被两个混淆变量干扰(Karabiner 设置 GUI 重写配置文件、Mos Debug 中途被拉起),复现时务必先清场。

## Phase 1 — CoreHID 原型 (MirroringHIDProbe)

| 命题 | 观测 | 结果 |
|---|---|---|
| 签名 | 带 com.apple.developer.hid.virtual.device 签名成功, init? 非 nil | 2026-07-11 否; 2026-09-30 是 (授权下发后, 见下方 Phase 1 复测) |
| C1 | hidutil list 见到 "Mos Mirroring HID Probe" | 是 (Transport Virtual, AppleUserHIDEventService / AppleUserHIDEventDriver) |
| C1 | 普通 App 能滚, 方向对 | 是 (kCGHIDEventTap 监听到滚轮事件, 已套用系统自然滚动与滚动加速) |
| C2 | iPhone 镜像内能滚动 | 是 |
| C3 | 镜像内方向可控 (--direction up / down 一致) | 是 (down, up, down 三轮截图对照, 方向随参数反转) |
| C4 | --mode smooth 镜像内平滑 (非跳格) | 未做逐帧测量。目标调整为触控板式输入 (连续平移加 iOS 原生惯性), 滚轮 notch / smooth 作为 Phase 3 的 W1 / W2 基线 |
| C5 | 物理鼠标是否也仍滚动镜像 (是否需 seize) | 未测 |

**签名卡点(2026-07-11 实测,证据链完整)**:
`com.apple.developer.hid.virtual.device` **在 development 阶段即被 Apple 门控,无法自助获取**。四条独立证据:
1. **AMFI 处决**:用 Apple Development 证书 + 该 entitlement 直接 codesign SwiftPM 裸二进制(README B 方案)→ 进程启动即 SIGKILL(exit 137)、零输出;同证书去掉 entitlement 重签 → 正常运行、`init?` 返回 nil 优雅降级。证明它是 AMFI 强管的受限 entitlement,必须有描述文件背书。
2. **门户拒发**:最小 Xcode App 工程(Automatic signing, Team N7Z52F27XK)+ `xcodebuild -allowProvisioningUpdates` → 确实连上门户并刷新了 Team Profile(新 profile 已下载),但报 `Provisioning profile "Mac Team Provisioning Profile: *" doesn't include the com.apple.developer.hid.virtual.device entitlement`,未能注册该能力。
3. **Xcode 无此能力映射**:Xcode 26.0 的门户能力缓存 `DVTPortal.framework/Resources/DVTPortalCachedPortalCapabilities.json`(102 项)**不含**任何对应 `hid.virtual.device` 的 capability——自动签名从机制上就不可能配出它。对照组:DriverKit HID 三项(`DRIVERKIT_FAMILY_HIDDEVICE_PUB` / `HIDEVENTSERVICE_PUB` / `TRANSPORT_HID_PUB`,均标注 "for development")在列表中存在。
4. **本机无背书**:本机全部描述文件均不含该 entitlement;Apple 官方文档(entitlement 页 + CoreHID "Creating virtual devices")也未公开任何申请渠道。

**推论**:Phase 1(CoreHID 原型实跑)硬阻塞于 Apple 授权,按 plan §决策门"以 Phase 0 结论推进"。**注意**:DriverKit HID 能力(Karabiner 架构)development 阶段反而是自助的(已在 App ID `com.caldis.Mos.driver` 启用,见 `04`)——若 Phase 0 = go 而 CoreHID 授权迟迟不下,可直接用 development 签名做 DriverKit dext 原型替代 Phase 1,不必等待。

### Phase 1 复测 (2026-09-30, HID Virtual Device 授权已下发)

环境: macOS 26 / Xcode 26.3 / iPhone 镜像连接中, 测试期间退出 Mos

签名链路:
- Apple 于 2026-09-15 为 Team N7Z52F27XK 下发 HID Virtual Device 能力, DriverKit 申请 (7CTL26535S) 同期被拒
- Xcode 26.3 的门户能力列表已包含 HID_VIRTUAL_DEVICE, 分发类型含 Development 与 Developer ID
- 在 Xcode 工程界面中打开或添加能力, 会在 App ID 上启用 HID Virtual Device 并生成描述文件; 仅用 xcodebuild -allowProvisioningUpdates 构建时, 报 "requires approval from Apple", 不会自动启用受管能力
- 原型改为 XcodeGen 生成的最小 .app (project.yml, App ID com.mos.vhidprobe), 内嵌描述文件后 HIDVirtualDevice(properties:) 返回非 nil, 进程退出后设备自动注销

观测:
- 首轮只用 CGWarpMouseCursorPosition 把光标移入镜像窗口, 虚拟滚轮无效; 先发送一次指针位移 (虚拟设备自身的 1px 往返位移, 或 kCGHIDEventTap 的 mouseMoved) 后生效。推断镜像需要指针进入事件, 仅观测到一次, 待复核
- 同一轮中 kCGHIDEventTap 投递的 CGEvent 行滚动也能滚动镜像, 与 Phase 2 一致
- 虚拟滚轮的 HID 方向与系统自然滚动叠加: 系统自然滚动开启时, wheel 正值产生 CGEvent deltaAxis1 负值
- CGEvent 字段 87 等于来源设备 IOHIDService 的 RegistryID: 物理罗技接收器为 0x10011F1CD, 虚拟设备为其 AppleUserHIDEventService 的 RegistryID, 每次创建设备都会变化。Mos 在 kCGHIDEventTap 可以据此区分物理滚动和自身虚拟设备发出的滚动
- 无 entitlement 的 IOHIDEventSystemClient 监听客户端 (类型 0/1/2/4, 队列与 RunLoop 两种调度) 在本机只收到 EventType NULL 事件, 收不到滚动事件, 与 07-11 另一台设备上 probeF2 的结果不同

虚拟触控板 (TouchpadProbe, Windows Precision Touchpad 形态的数字化仪描述符, usage 0x0D/0x05):
- 系统匹配 AppleUserHIDEventDriver, 双指滑动只产生 kCGEventGesture (type 29) 事件, 手势子类型字段 110 为 0, 没有滚动事件
- 结论: 系统没有把通用数字化仪触控板识别为触控板, 镜像侧响应待 Phase 3 验证

## Phase 3 — 触控板式输入 (待测)

目标: 让 iPhone 镜像收到触控板双指滑动的体验, 即连续平移加 iOS 原生惯性, 而非滚轮的分段滚动

依据 (社区实现):
- jfarcand/mirroir-mcp: kCGHIDEventTap 投递 IsContinuous=1 的滚动事件, scrollPhase 依次为 MayBegin(128, 零增量) / Began(1) / Changed(2) / Ended(4, 零增量), 快速滑动后追加 momentumPhase 1/2/3 的衰减尾巴 (每 16ms 乘 0.94)
- ShawnPana/phone-harness PR #52 (macOS 26.2): 镜像只接受带 phase 的连续滚动; 滚动距离与 Changed 事件个数成正比, 与单个事件的增量大小无关, 约 7pt/事件; 设置字段 137 / 45 / 101 / 87 会让事件被忽略

用例 (tools/mirror-session.sh, 每项录制镜像窗口 60fps 视频并逐帧计算内容位移):

| 用例 | 输入 | 验证点 |
|---|---|---|
| W1 / W2 | 虚拟鼠标滚轮 notch / smooth | 滚轮基线 |
| T1 | phased 连续滚动, 40 个 Changed, 16ms | 慢速拖动是否连续 |
| T2 | 12 个 Changed + 45 帧惯性尾巴 | 甩动后是否有 iOS 原生惯性 |
| T3 / T4 | 20 个 Changed, 增量 1 与 30 | 距离由事件个数还是增量决定 |
| T5 | 60 个 Changed, 8ms | 120Hz 投递是否更平滑 |
| V1 | 虚拟触控板双指滑动 | 镜像是否响应数字化仪手势事件 |

参考基线: tools/trackpad-ref.sh 录制真实触控板双指滑动的视频与 HID 层事件流, 用于对照逐帧位移曲线和事件字段

工具: tools/build.sh 构建 winctl / evspy 与原型 .app; mirror-session.sh 在镜像未连接时通过辅助功能树检测占位页并中止

## Phase 2 — cghidEventTap 注入(2026-07-11 新增,源自 cua.ai 文章方法论 + mirroir 项目)

**背景**:全网检索发现在售项目 `jfarcand/mirroir-mcp` 用 `CGEvent.post(tap: .cghidEventTap)` 驱动镜像 swipe,与"镜像够不到"的结论冲突,实测裁决。

| 观测 | 结果 | 备注 |
|---|---|---|
| 探针能滚普通 App(阳性对照) | ☑ 是 | 系统设置侧边栏从「辅助功能」滚回「陈标」,证明权限+机制有效 |
| **投递滚轮到 iPhone 镜像生效** | ☑ **是** | 微信公众号信息流下滚:顶部「保时捷」→「中海云颂玖章」 |
| **方向可控** | ☑ **是** | 反向上滚退回更早内容(「我给美团道的歉」「CLauto」栏头) |
| 可重复 | ☑ 是 | 下/上/再滚三轮均生效 |
| 权限成本 | 仅**辅助功能**;零 entitlement / 零虚拟设备 / 零 dext | 远轻于路线 B(dext) |

**Phase 2 结论**:`.cghidEventTap` **投递**的滚轮能到达镜像。**但仅解决"注入",未解决"翻转物理滚动"**。

**下一关键实验 → 已完成(2026-07-11),结论:能压制,#762 无需 dext 可修**

| 探针 | 做什么 | 结果 |
|---|---|---|
| probeD | `kCGHIDEventTap` 消费型 tap,吞掉所有物理滚轮(`return nil`) | 物理滚动镜像 **纹丝不动**(237 事件被吞,截图逐帧对齐)→ 底层消费**能压制**镜像那份副本 |
| probeE | `kCGHIDEventTap` 消费原始 + 取反 delta 从 `kCGHIDEventTap` 重投 | 物理滚动镜像时,镜像与普通 App **一致按翻转方向**移动(420+ 事件翻转)。probeE 全局翻转,若够不到镜像应"内外相反",实测一致 = 翻转到达镜像 |

**根因定位(Mos 代码)**:
- tap 挂 `.cgAnnotatedSessionEventTap`(`ScrollCore.swift:409`,session 最高层)→ 消费/改写在镜像底层读取点上游之后,镜像读走原始。
- 重投用 `event.postToPid()`(`ScrollDispatchContext.swift:131`)→ 到不了镜像(mirroir 项目已证)。

**→ 路线 C 成立**(见 `01-findings.md §4 路线 C`):镜像前台时下沉 `kCGHIDEventTap` 消费+翻转重投,仅需辅助功能,无 dext。

**仍待验证**:平滑(C4);与 session-tap 管线协同;动量/多显示器鲁棒性。**清洁 A/B**(probeE 开/关同手势看方向反转)因 iPhone 反复被使用断连未跑完,但 probeC+probeD 两个原子能力已分别铁证,组合逻辑上成立、probeE 已确认可组合不自锁。

## 总结论(2026-07-11)

☑ **路线 B 架构成立**:虚拟 HID 注入的滚轮可到达镜像(C2)且方向可控(C3)——由 Karabiner 代理实测证实。
☐ ~~路线 B 不可行~~(已排除)

尚未闭环的部分:
- **C4(平滑)**:Karabiner 的 flip 不改变事件频率/粒度,无法代测;需我们自己的注入器(CoreHID 或 dext)验证。
- **C5(是否必须 seize)**:Karabiner 场景下 seize 是既成事实(且证明 seize + 重发可行、无双份输入);「不 seize 直接注入会不会双份」仍未测,待 CoreHID 授权或 dext 原型。
- **Phase 1 路径选择**:CoreHID entitlement development 即门控(见上),两条路——① 向 Apple 争取 `hid.virtual.device`;② 直接做 DriverKit dext 原型(development 能力自助,App ID 已配好,架构同 Karabiner,Phase 0 已验证这条链路端到端可行)。

残留风险确认(见 plan §"全部通过是否足以支撑结论"):
- entitlement 分发授权: **CoreHID development 即门控(实测);DriverKit 分发申请 7CTL26535S 等回复**
- 多鼠标/热插拔/休眠: 未覆盖(原型阶段不测)
- CoreHID vs DriverKit: **天平已向 DriverKit 倾斜**——CoreHID 连开发验证都受阻,而 dext 链路被 Phase 0 端到端证实且 development 自助

## P0 — 字段记录器与离线核对 (2026-10-10, 工具实现与离线核对, 无设备实验)

环境: macOS 26.7.1 (25G241), SDK macosx27.0 (DTSDKBuild 26A425), 正式 Mos 4.3.0, 研究工作树 research/iphone-mirroring-scroll @ 752730c。本轮没有创建 tap, 没有投递事件, 没有真实设备实验, 没有 commit。

按 06 交接报告的 P0 实现工具, 目标是让后续轮次产出可对照的字段级记录。

| 位置 | 内容 |
|---|---|
| experiments/MirroringScrollLab/Sources/Recorder.swift | 每轮证据目录与 JSON 行记录。捕获事件在 tap 线程记录并带决定标记 (repost / pass_* / rewrite / own_observed), 输出事件在 CGOutput.post 记录 (kind 标明产生者, outcome 区分 posted 与 dropped_no_target), 引擎每帧另记一条 frame |
| experiments/MirroringScrollLab/Sources/ServiceMap.swift | HID 服务与属性快照。输入设备展开全部属性, 其余 IOHIDEventService 只留结构 |
| experiments/MirroringScrollLab/Sources/SelfTest.swift | 无权限离线自检, 核对字段读写语义、NSEvent 侧读数与记录链路 |
| experiments/MirroringScrollLab/tools/analyze-round.py | 离线汇总: 按 sender 的 raw/point 与 accel/point 中位及同号率、输出侧补齐率、帧节奏, 多轮时打印对照表 |
| experiments/MirroringScrollLab/README.md | 记录流程与字段对照 |

离线核对结果 (evidence/2026-10-10/field-selftest.txt, 全部通过):

| 核对项 | 结果 |
|---|---|
| 写入 96/97 不改变 175-178 | 确认。补齐 Raw 与 Accelerated 必须显式写入 |
| 写 123 覆盖 173 的整值 | 确认。每帧顺序为先写 123 再写 173, 否则丢掉惯性打断位 0x10 |
| 事件复制保留 87 与 175-178 | 确认 |
| CG 99 的 2/4/8 映射到 NSEvent.phase 的 4/8/16 | 确认 |
| CG 123 的 1/2/3 映射到 NSEvent.momentumPhase 的 1/4/8 | 确认 |
| 连续滚动的 NSEvent.scrollingDelta 取 Point 值 | 确认 (point_y 7 对应 scrollingDeltaY 7, point_x -8 对应 scrollingDeltaX -8) |
| 行滚动的 NSEvent.delta 与行位移一致 | 确认 (precise=false) |

设备属性对照 (evidence/2026-10-10/hid-services.json, 属性快照不构成因果关系):

| 设备 | HIDScrollResolution | HIDScrollAccelerationType | 其他 |
|---|---|---|---|
| 内置触控板 | 26214400 | HIDTrackpadScrollAcceleration | SupportsGestureScrolling, TrackpadMomentumScroll |
| 虚拟妙控板 (Magic Trackpad 2, Virtual) | 26214400 | HIDTrackpadScrollAcceleration | SupportsGestureScrolling, TrackpadMomentumScroll |
| MX Master 4 - BLE | 589824 | HIDMouseScrollAcceleration | ReportInterval 8000 |
| 虚拟鼠标 (Lab) | 589824 | HIDMouseScrollAcceleration | ReportInterval 8000 |

虚拟妙控板与内置触控板的滚动属性相同, 与鼠标类设备在 scrollResolution 与加速类型上不同。这给出 P1 中 V 组与 M1 组可直接对照的属性差异, 属性一致本身不能推出镜像平滑依赖设备属性。

待办:

- P1 的单变量 A/B 尚未运行, 需要用户确认后使用真实设备: M0 (当前 Point 策略) 与 M1 (按标定补齐 Raw/Accelerated), 同一有效鼠标 sender, 每组至少 5 次有效重复
- 触控板 service sender 作为设备属性对照; sender 无效或未证实事件到达的轮次记为无效实验
- 画面位移的像素测量仍缺工具, 属于 P2
- 记录开启时 tap 回调内的 NSEvent 构造与 JSON 编码开销未测量, 观察项见 Lab 的 CODE-GUIDE 3.2


### P0 接线修复 (2026-10-10, 接手后离线验证)

接手时 Recorder、ServiceMap、SelfTest 文件存在, 但 App 入口、配置、tap、输出和帧上下文接线缺失。旧的通过记录不能代表该时刻的源码状态。本轮补齐调用和记录界面, 保留原滚动算法与已有字段倍率设置。

独立目录 `DerivedDataVerification` 的签名 Debug build 通过。86 项离线自检通过, 包含并发记录、同名轮次隔离和停止后不追加。分析脚本读回通过。原 Lab PID 4981 未停止或替换, 未创建新的交互 tap, 未进行真实设备实验。Mos 生产代码未修改。

证据: `evidence/2026-10-10/lab-wiring-selftest.txt`, `lab-wiring-analysis.txt`, `lab-wiring-offline-round/`。构建仍有既有 CVDisplayLink 弃用提示。记录开销、界面操作和镜像效果需在下一轮实际使用中验证。


### 惯性衔接控件与接线恢复 (2026-10-10)

会话回退把 App、Config、ContentView、ScrollEngine、TapController 恢复到 10:16 的检查点, 字段记录接线随之丢失, Recorder 与 SelfTest 无法编译。本轮按 P0 接线修复的原始脚本重放接线, Debug build 通过, 离线自检全部通过。

界面新增的惯性相关控件:

| 控件 | 配置项 | 所在区 |
|---|---|---|
| 惯性交接阈值 | momentumHandoffPx | 触控板式 phased 参数, 合成惯性开启时显示 |
| 新手势前发送打断信号 (惯性结束 + 预备 + 取消) | resetBeforeGesture | phased 参数与虚拟妙控板参数, 两处共用 |
| 提前抬指阈值 | magicLiftPx | 虚拟妙控板参数 |

原 "先发 MayBegin (128)" 更名为 "手势开始前发送预备事件 (MayBegin, 128)", 只发预备事件; 打断信号是包含预备事件的三事件序列。手感与 iPhone 端惯性打断效果尚未实测


### 第 0 步实验: 惯性归属与 Sender 独立性 (2026-10-12, 待实测)

Lab 左栏新增 "实验" 区 (Sources/Experiments.swift)。每个变体以 2026-10-09 实测顺滑的 phased 配置为基线, 只改变一个变量; 套用变体时自动以变体编号开始记录轮次, 观察写入该轮次的 notes.txt。

| 实验 | 变体 | 变量 |
|---|---|---|
| E1 惯性归属 | E1-N / E1-S / E1-L | 不发惯性 / 合成惯性衰减 0.80 / 合成惯性衰减 0.99 |
| E2 Sender 独立性 | E2-V / E2-M1 / E2-M0 / E2-Z / E2-T | 虚拟妙控板 sender 加补齐 / 物理鼠标 sender 加补齐 / 物理鼠标 sender 不补齐 / sender 为 0 / 内置触控板 sender 加补齐 |

E2 中 sender 不指向虚拟妙控板的变体会销毁虚拟设备, 轮次目录的 services.json 在套用后 2 秒重拍, 用于确认设备已消失。E1-S 与 E1-L 启用惯性交接 (3 px), 插值末段被惯性替代, 因此 E1 的主要比较对象是 E1-S 与 E1-L, E1-N 作为 iOS 自身减速的参照


### 第 0 步实验结果 (2026-10-12)

用户实测评价 (原文见各轮次 notes.txt):

| 变体 | 评价 |
|---|---|
| E1-N / E1-S / E1-L | 三者滑行距离相近。E1-N 跟手, 惯性窗口内打断正常; E1-S 与 E1-L 首帧不跟手, 惯性窗口内再次滚动可能卡滞, 交接处卡顿, E1-L 更明显 |
| E2-V | 起步慢半拍, 往复滚动偶有跳变 |
| E2-M1 | 画面飞跃, 比 Mos 现状更严重 |
| E2-M0 | 完全无响应 |
| E2-Z | 画面跳跃, 与 Mos 现状类似 |
| E2-T | 与 E1-N 同样跟手, 往复滚动偶有轻微跳变 |

结论与限定:

- E1: 镜像的滑行距离不随 Mac 侧惯性衰减变化, 滑行由 iOS 按手势结束时的速度自行生成。Mac 侧合成惯性只带来首帧和交接处的卡顿, 镜像路径不发送惯性事件
- E2: 只有 sender 指向触控板类设备 (虚拟妙控板或内置触控板) 的变体可用。物理鼠标 sender 加补齐时, 镜像按鼠标设备属性解释 175-178, 位移被放大
- E1-N 与 E2-V 的配置完全相同 (config.json 一致, sender 同为 4295510148), 评价却不同。单次主观评价的偶然差异较大, V 与 T 的差异需要盲测 E3 复核
- E2-Z 与 E2-M0 的结果作废: Lab 的 phased 输出先写像素位移 96 再写行位移 11, 写行位移时 CGEvent 按 1 行 = 8 像素重算 93 与 96, 所有 phased 事件的公开位移都是 ±8 (frames.jsonl 中 point_y 恒为 ±8, 独立脚本复现)。sender 非零时镜像读取 175-178, 不受影响; sender 为 0 时镜像读取的正是被改写的公开位移。已修正写入顺序并加入自检, 两个变体需要重测
- 销毁虚拟设备有效: E2-M1 与 E2-T 轮次的 services.json 中没有虚拟妙控板, 重新创建后 sender 由 4295510001 变为 4295510148


### 重测与 E3 盲测结果 (2026-10-12)

| 变体 | 评价 | 记录数据 |
|---|---|---|
| E2-Z (修正后) | 卡顿, 不跟手, 整段位移在滚轮完全停止后才出现在镜像中 | 827 个 phased 事件全部 posted, sender 为 0 |
| E2-M0 (重测) | 毫无反应 | 1095 个事件全部 posted, sender 为物理鼠标 |
| E3-X = 虚拟妙控板 sender | 流畅, 有插值过度的拖滞感, 往复偶有跳变, 偶尔慢半拍 | |
| E3-Y = 内置触控板 sender | 首轮无反应, 之后各轮正常; 整体与 X 接近 | 首轮 (145602) 881 个事件全部 posted, sender 与后续正常轮次相同 |

结论与限定:

- 修正公开位移后 sender 为 0 仍不可用。镜像路径要求 sender 指向触控板类设备, 虚拟妙控板与内置触控板手感接近, 盲测中没有稳定差异
- E3-Y 首轮无反应时 Mac 侧输出与后续正常轮次一致, 原因在镜像或 iOS 一侧, 未定位。已知条件: 该轮紧接 sender 从虚拟妙控板切换到内置触控板之后。推断: 同一会话内切换 sender 可能让镜像暂时忽略新设备, 待验证
- 往复跳变: Mac 侧数据显示, 方向反转发生在同一个手势内部, 插值缓冲在反转时清零, 速度从 +7 直接跳到 -5, 快速拨动时单帧可达 -178。跳变与该速度突变的关系未验证
- 两个 sender 都有插值过度的反馈。iOS 会在手势结束后自行滑行, Mos 插值的拖尾与 iOS 滑行叠加, 镜像路径的插值时长需要单独调校


### 证据归档说明 (2026-10-12)

evidence/ 下体积较大的 frames.jsonl 与 services.json 以 gzip 压缩归档 (后缀 .gz), 使用前用 gunzip 解压; tools/analyze-round.py 读取解压后的 frames.jsonl
