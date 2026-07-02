# 实验记录（在另一台设备上填写）

> 逐项记录 Phase 0 / Phase 1 的观测。命题编号见 `02-experiment-plan.md`。
> 环境: macOS ___ / iOS ___ / 设备 ___ / 鼠标 ___ / 日期 ___

## Phase 0 — Karabiner 代理

| 观测 | 结果 | 备注 |
|---|---|---|
| Karabiner 安装并启用其虚拟 HID | ☐ 是 ☐ 否 | |
| 配置 vertical_wheel flip | ☐ 是 ☐ 否 | |
| 镜像内能正常滚动 | ☐ 是 ☐ 否 | |
| 镜像内方向被 Karabiner 反转 (**C2+C3**) | ☐ 是 ☐ 否 | |

**Phase 0 结论**: ☐ go(虚拟 HID 能到达镜像,继续 Phase 1) ☐ no-go(停止路线 B) ☐ 未定
说明: ______________________________________________

## Phase 1 — CoreHID 原型 (MirroringHIDProbe)

| 命题 | 观测 | 结果 |
|---|---|---|
| 签名 | 带 `com.apple.developer.hid.virtual.device` 签名成功、`init?` 非 nil | ☐ 是 ☐ 否(卡点见下) |
| C1 | `hidutil list` 见到 "Mos Mirroring HID Probe" | ☐ 是 ☐ 否 |
| C1 | 普通 App(TextEdit/Safari)能滚、方向对 | ☐ 是 ☐ 否 |
| **C2** | iPhone 镜像内能滚动 | ☐ 是 ☐ 否 |
| **C3** | 镜像内方向可控(`--direction up`/`down` 一致) | ☐ 是 ☐ 否 |
| C4 | `--mode smooth` 镜像内平滑(非跳格) | ☐ 是 ☐ 否 |
| C5 | 物理鼠标是否也仍滚动镜像(→ 是否需 seize) | ☐ 也滚(需 seize) ☐ 不滚 |

**签名卡点(若有)**: ______________________________________________
(例:能力勾不了 / 描述文件不含该 entitlement / init 一直 nil。若卡住,以 Phase 0 结论推进,待 entitlement 到手补做。)

## 总结论

☐ 路线 B 可行(API 能实现方向+平滑) —— 下一步: ______________________
☐ 路线 B 需 seize 物理设备(接近 Karabiner 复杂度) —— 评估: ____________
☐ 路线 B 不可行 —— 长期仅保留路线 A + 等 Apple 开放

残留风险确认(见 plan §"全部通过是否足以支撑结论"):
- entitlement 分发授权: ______  多鼠标/热插拔/休眠: ______  CoreHID vs DriverKit: ______
