# 验证方案 — 虚拟 HID 能否驱动 iPhone 镜像滚动

关联: `01-findings.md` 路线 B。工具: `../../experiments/MirroringHIDProbe/`。

## 要回答的唯一问题
**用虚拟 HID 设备注入滚轮,iPhone 镜像是否响应、方向是否可控、能否平滑?** —— 即路线 B 在架构上是否成立、能否满足 Mos 需求。

## 待验证的可证伪子命题

| 编号 | 命题 | 状态 |
|---|---|---|
| C0 | 镜像在 CGEvent tap 之下读取滚动 | ✅ 已由二进制逆向证实(`01-findings.md` §2) |
| C1 | 虚拟 HID 定位设备的滚轮能被系统识别(普通 App 可滚) | 待测(Phase 1 步骤 2) |
| C2 | 该滚轮能被 **iPhone 镜像**响应(不止普通 App) | 待测(核心) |
| C3 | 能控制方向(发"反向"滚轮,镜像内即反向) | 待测(核心 — 对应本 bug) |
| C4 | 能发高频细粒度流,镜像平滑渲染(非跳格) | 待测(加分项) |
| C5 | 不 seize 物理设备时,物理滚轮是否也到达镜像(会否"双份") | 待测(决定最终架构复杂度) |

## 验证方式(分层,先便宜后昂贵)

### Phase 0 — Karabiner 代理(零代码/零 entitlement,最先做)
Karabiner-Elements 是已获授权的成熟 DriverKit 虚拟 HID 实现,它 seize 物理设备并经虚拟设备重发一切输入。启用 vertical_wheel flip 后在镜像里测:
- **反向滚动在镜像里生效** → C2+C3 成立(且 C5 已被 Karabiner 的 seize 处理)→ 架构 go。
- **不生效** → 虚拟 HID 路可能走不通 → no-go,回退重估。
> 这是最便宜、最决定性的一步,给出 go/no-go,无需任何签名。

### Phase 1 — 我们的 CoreHID 原型(`MirroringHIDProbe`)
用 CoreHID `HIDVirtualDevice` 创建虚拟鼠标并 `dispatchInputReport` 发滚轮:
1. `hidutil list` 确认设备注册 → C1 前置。
2. 普通 App(TextEdit/Safari)验证能滚、方向对 → C1。
3. iPhone 镜像前台,重复观察能滚/方向/平滑 → **C2、C3**;`--mode smooth` 测 **C4**。
4. 观察物理鼠标是否也仍滚动镜像 → **C5**。
> 需带 `com.apple.developer.hid.virtual.device` 签名(见工具 README「签名」)。若该 entitlement 也需 Apple 审批而暂不可用,Phase 0 已足以回答架构 go/no-go,C1–C5 的 CoreHID 具体验证可待授权到手补做。

## 观测手段
- **行为观测**(主):肉眼看镜像内长列表的滚动/方向/平滑度。
- **设备注册**:`hidutil list | grep -i 'Mos Mirroring'`。
- **旁路对照**:先在普通 App 确认虚拟滚轮有效,排除"设备没发滚轮"的混淆。
- 无法直接探针镜像进程内部(需 event-monitor 私有 entitlement),故以行为观测为准。

## 全部通过是否足以支撑结论?

**能支撑「CoreHID 虚拟 HID 在技术上可实现该功能」这一结论**(C1–C4 通过即证明方向+平滑可达且可控;C5 给出是否必须 seize)。

但即使全绿,以下**残留风险**不在原型覆盖范围,需在正式方案中单独处理——所以结论应表述为"**API 能做到**",而非"**可以直接上线**":
1. **分发 entitlement**:`com.apple.developer.hid.virtual.device` 的分发授权仍在申请中(Request ID 见 `04-entitlement-application.md`)。
2. **是否必须 seize 物理设备**(C5 结果):若必须,则要 seize + 重发,复杂度接近 Karabiner,并牵出系统扩展审批 + 用户批准 + 重启的 UX。
3. **鲁棒性**:多鼠标、热插拔、休眠/唤醒、与 Mos 现有 CGEvent 管线的协同——原型不覆盖。
4. **CoreHID vs DriverKit 取舍**:若 CoreHID 分发授权拿不到,可能仍需回落 DriverKit(Karabiner 架构)。

## 决策门
- Phase 0 = no-go → 停止路线 B,长期只保留路线 A + 等 Apple 官方开放。
- Phase 0 = go,Phase 1 C2/C3 通过 → 路线 B 立项,按 C5 结果决定 seize 与否。
- Phase 1 因签名受阻 → 记录卡点,以 Phase 0 结论推进,待 entitlement 到手补 Phase 1。
