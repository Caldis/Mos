# 验证方案 — 虚拟 HID 能否驱动 iPhone 镜像滚动

> 2026-07 的路线 B 验证计划. Karabiner 与 CoreHID 的执行结果见[实验记录](03-experiment-log.md), 当前方案见[研究索引](00-README.md)

关联路线 B 的[早期评估](01-findings.md)与 [MirroringHIDProbe](../../../experiments/MirroringHIDProbe/)

## 验证范围与结果

| 编号 | 命题 | 状态 |
|---|---|---|
| C0 | 镜像只在 CGEvent tap 之下读取滚动 | 原假设已撤回. 10 月确认了窗口内的 NSEvent 转换路径 |
| C1 | 虚拟 HID 定位设备的滚轮能被系统识别 | 2026-09-30 的 CoreHID 原型复测通过 |
| C2 | iPhone Mirroring 响应虚拟 HID 滚轮 | Karabiner 与 CoreHID 均取得阳性结果 |
| C3 | 虚拟 HID 滚轮能控制镜像内的滚动方向 | Karabiner 与 CoreHID 均取得阳性结果 |
| C4 | 高频细粒度虚拟鼠标滚轮可获得连续滚动 | 原型未取得逐帧测量结果. 后续实验改为对照触控板式 phased 输入 |
| C5 | 物理滚轮与虚拟滚轮的输入叠加 | Karabiner 在独占设备条件下验证. CoreHID 原型未覆盖这一项 |

## 验证方式(分层,先便宜后昂贵)

### Phase 0 — Karabiner 代理 (已完成)
Karabiner-Elements 是已获授权的成熟 DriverKit 虚拟 HID 实现,它 seize 物理设备并经虚拟设备重发一切输入。启用 vertical_wheel flip 后在镜像里测:
- **反向滚动在镜像里生效** → C2+C3 成立(且 C5 已被 Karabiner 的 seize 处理)→ 架构 go。
- **不生效** → 虚拟 HID 路可能走不通 → no-go,回退重估。
> 这是最便宜、最决定性的一步,给出 go/no-go,无需任何签名。

### Phase 1 — CoreHID 原型 (已复测)
用 CoreHID `HIDVirtualDevice` 创建虚拟鼠标并 `dispatchInputReport` 发滚轮:
1. `hidutil list` 确认设备注册 → C1 前置。
2. 普通 App(TextEdit/Safari)验证能滚、方向对 → C1。
3. iPhone 镜像前台,重复观察能滚/方向/平滑 → **C2、C3**;`--mode smooth` 测 **C4**。
4. 观察物理鼠标是否也仍滚动镜像 → **C5**。
> `com.apple.developer.hid.virtual.device` 的审批和 9 月复测环境见[授权记录](04-entitlement-application.md)

## 观测手段
- **行为观测**(主):肉眼看镜像内长列表的滚动/方向/平滑度。
- **设备注册**:`hidutil list | grep -i 'Mos Mirroring'`。
- **旁路对照**:先在普通 App 确认虚拟滚轮有效,排除"设备没发滚轮"的混淆。
- 无法直接探针镜像进程内部(需 event-monitor 私有 entitlement),故以行为观测为准。

## 后续方案

2026-09 的审批结果结束了原先的签名阻塞. 虚拟鼠标原型验证了设备注册, 滚轮到达与方向控制. 多鼠标, 热插拔, 休眠唤醒与物理输入叠加超出原型覆盖范围. 合入 Mos 的方案使用虚拟设备提供身份, 以 phased CGEvent 投递滑动. [适配器方案](../../plans/2026-10-12-iphone-mirroring-scroll.md)
