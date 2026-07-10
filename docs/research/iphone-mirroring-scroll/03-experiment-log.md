# 实验记录（在另一台设备上填写）

> 逐项记录 Phase 0 / Phase 1 的观测。命题编号见 `02-experiment-plan.md`。
> 环境: macOS 26.5.1 (25F80) + Xcode 26.0 (17A324) / iOS ___ / 设备 ___ / 鼠标 ___ / 日期 2026-07-11（Phase 1 签名部分）

## Phase 0 — Karabiner 代理

**操作清单(2026-07-11 备好,本机 Karabiner 尚未安装)**:
1. `brew install --cask karabiner-elements`(要管理员密码);首启按引导批准:系统设置 → 隐私与安全性 → 允许其**驱动扩展**,并授予**输入监控**。
2. **退出 Mos**(排除 CGEvent 层翻转的混淆变量),记下系统「自然滚动」当前值,测试中不改动。
3. 基线:打开 iPhone 镜像(连 iPhone),前台用物理滚轮滚一个长列表,记住方向。
4. Karabiner-Elements → **Devices** → 找到鼠标并启用 Modify events → **Open mouse settings** → 勾选 **Flip mouse vertical wheel**。
5. 先在普通 App(如 TextEdit 长文档)确认方向已被翻转(证明输入确实走了 Karabiner 虚拟设备)。
6. 回到镜像窗口滚动,对比第 3 步:方向变了 → **C2+C3 成立,go**;没变/滚不动 → no-go。
7. 填下表,测完可 `brew uninstall --cask karabiner-elements` 清理。

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

## 总结论

☐ 路线 B 可行(API 能实现方向+平滑) —— 下一步: ______________________
☐ 路线 B 需 seize 物理设备(接近 Karabiner 复杂度) —— 评估: ____________
☐ 路线 B 不可行 —— 长期仅保留路线 A + 等 Apple 开放

残留风险确认(见 plan §"全部通过是否足以支撑结论"):
- entitlement 分发授权: ______  多鼠标/热插拔/休眠: ______  CoreHID vs DriverKit: ______
