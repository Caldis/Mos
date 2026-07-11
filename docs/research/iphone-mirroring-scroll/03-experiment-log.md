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
| 签名 | 带 `com.apple.developer.hid.virtual.device` 签名成功、`init?` 非 nil | ☑ **否**(卡点见下,2026-07-11 实测) |
| C1 | `hidutil list` 见到 "Mos Mirroring HID Probe" | ☐ 是 ☐ 否 |
| C1 | 普通 App(TextEdit/Safari)能滚、方向对 | ☐ 是 ☐ 否 |
| **C2** | iPhone 镜像内能滚动 | ☐ 是 ☐ 否 |
| **C3** | 镜像内方向可控(`--direction up`/`down` 一致) | ☐ 是 ☐ 否 |
| C4 | `--mode smooth` 镜像内平滑(非跳格) | ☐ 是 ☐ 否 |
| C5 | 物理鼠标是否也仍滚动镜像(→ 是否需 seize) | ☐ 也滚(需 seize) ☐ 不滚 |

**签名卡点(2026-07-11 实测,证据链完整)**:
`com.apple.developer.hid.virtual.device` **在 development 阶段即被 Apple 门控,无法自助获取**。四条独立证据:
1. **AMFI 处决**:用 Apple Development 证书 + 该 entitlement 直接 codesign SwiftPM 裸二进制(README B 方案)→ 进程启动即 SIGKILL(exit 137)、零输出;同证书去掉 entitlement 重签 → 正常运行、`init?` 返回 nil 优雅降级。证明它是 AMFI 强管的受限 entitlement,必须有描述文件背书。
2. **门户拒发**:最小 Xcode App 工程(Automatic signing, Team N7Z52F27XK)+ `xcodebuild -allowProvisioningUpdates` → 确实连上门户并刷新了 Team Profile(新 profile 已下载),但报 `Provisioning profile "Mac Team Provisioning Profile: *" doesn't include the com.apple.developer.hid.virtual.device entitlement`,未能注册该能力。
3. **Xcode 无此能力映射**:Xcode 26.0 的门户能力缓存 `DVTPortal.framework/Resources/DVTPortalCachedPortalCapabilities.json`(102 项)**不含**任何对应 `hid.virtual.device` 的 capability——自动签名从机制上就不可能配出它。对照组:DriverKit HID 三项(`DRIVERKIT_FAMILY_HIDDEVICE_PUB` / `HIDEVENTSERVICE_PUB` / `TRANSPORT_HID_PUB`,均标注 "for development")在列表中存在。
4. **本机无背书**:本机全部描述文件均不含该 entitlement;Apple 官方文档(entitlement 页 + CoreHID "Creating virtual devices")也未公开任何申请渠道。

**推论**:Phase 1(CoreHID 原型实跑)硬阻塞于 Apple 授权,按 plan §决策门"以 Phase 0 结论推进"。**注意**:DriverKit HID 能力(Karabiner 架构)development 阶段反而是自助的(已在 App ID `com.caldis.Mos.driver` 启用,见 `04`)——若 Phase 0 = go 而 CoreHID 授权迟迟不下,可直接用 development 签名做 DriverKit dext 原型替代 Phase 1,不必等待。

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

**下一关键实验(未做)**:能否**压制原始物理滚动到达镜像的那份副本**?
- 若能(如 CGEventTap 消费 return nil 就足够,或需 seize 设备)→ #762 可用「消费原始 + 投递翻转」修复,**无需 dext**,只需辅助功能(+ 可能输入监控)。
- 若不能(镜像在 Mos 的 tap 上游读到原始)→ 注入翻转会与原始叠加成双份 → 仍需 seize(接近 Karabiner)。
- 测法:Mos 开翻转 + kCGHIDEventTap 消费型 tap,物理滚动镜像,看是否干净翻转 / 是否双份。需真人物理滚动。

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
