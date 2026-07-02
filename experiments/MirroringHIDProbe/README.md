# MirroringHIDProbe

一次性验证工具:回答**「用 CoreHID 虚拟 HID 设备注入滚轮,iPhone 镜像认不认、方向可不可控、能不能平滑」**这个决定 Mos 长期方案（路线 B）的核心问题。

> 这不是 Mos 的一部分,是独立的 SwiftPM 可执行文件。验证完即可丢弃。
> 背景与结论见 `../../docs/research/iphone-mirroring-scroll/`。

---

## 先做 Phase 0(零代码、零 entitlement,最先做这个)

在写/签任何代码之前,用 **Karabiner-Elements**(已获 Apple 授权、成熟的 DriverKit 虚拟 HID 实现)做一次代理验证——它能几分钟内给出架构层面的 go/no-go:

1. 安装 [Karabiner-Elements](https://karabiner-elements.pqrs.org/)(会装它的 DriverKit 虚拟 HID 驱动)。启用后,它把物理设备 seize 掉、所有输入经**虚拟 HID 设备**重发。
2. 加一条 Complex Modification 或用 `mouse_basic` 把 **vertical_wheel 反向**(flip)。
3. 打开 iPhone 镜像,让其窗口在前台,用鼠标滚轮滚动。
4. 观察:
   - **镜像里能正常滚动 + 方向被 Karabiner 反转了** → 虚拟 HID 的滚轮**确实**能到达 iPhone 镜像。**架构假设成立,路线 B 可行**,继续 Phase 1 验证我们自己的 CoreHID 实现。
   - **镜像里滚不动 / 方向没被反转** → 虚拟 HID 这条路**可能走不通**。先别在 CoreHID/DriverKit 上继续投入,回到文档重新评估。

Phase 0 的结论请记到 `../../docs/research/iphone-mirroring-scroll/03-experiment-log.md`。

---

## Phase 1:我们自己的 CoreHID 原型

### 1) 编译

```bash
cd experiments/MirroringHIDProbe
swift build
```

未签名直接跑会得到(这是预期的,证明 entitlement gate 生效):

```
✗ HIDVirtualDevice(properties:) 返回 nil。
  最可能原因: 未带 entitlement com.apple.developer.hid.virtual.device …
```

### 2) 签名(主要摩擦点)

`com.apple.developer.hid.virtual.device` 是**受门控**的 entitlement——必须用一个「App ID 上启用了该能力 + 描述文件包含它」的签名,`init?` 才会成功。两条路,推荐 A:

**A. 丢进一个极小的 Xcode App target(最省心)**
把 `Sources/MirroringHIDProbe/MirroringHIDProbe.swift` 拷进一个新的 macOS App(或 Command Line Tool)工程 →
- Signing & Capabilities 里 Team 选你的、开 **Automatic signing**;
- 加 Capability(或直接把本目录的 `MirroringHIDProbe.entitlements` 设为工程 entitlements)包含 `com.apple.developer.hid.virtual.device`;
- 若该能力在 App ID 列表里可自助勾选,Xcode 会自动生成带它的描述文件;若勾不了,说明它可能和 DriverKit 一样需要 Apple 审批(见下方「若签不下来」)。
- Run。

**B. SwiftPM 产物手动签名(bare CLI 较繁,仅在你已有含该能力的描述文件时用)**

```bash
BIN="$(swift build --show-bin-path)/MirroringHIDProbe"
codesign --force --options runtime \
  --sign "Apple Development: <你的证书名>" \
  --entitlements MirroringHIDProbe.entitlements \
  "$BIN"
# 受限 entitlement 通常还需描述文件背书; bare Mach-O 无处内嵌 embedded.provisionprofile,
# 因此 A 方案(.app 能内嵌描述文件)通常更顺。
```

**若签不下来(能力勾不了/描述文件不含它):**
说明 `com.apple.developer.hid.virtual.device` 对分发也需 Apple 单独授权。这不影响结论采集——**Phase 0(Karabiner)已能回答架构层面的 go/no-go**;CoreHID 具体实现的验证可等该 entitlement 到手后补。把这个卡点记进 log。

### 3) 运行与观测

```bash
# 默认: 每 ~1.5s 交替上下滚一阵, 便于判断方向
mirroring-hid-probe

# 平滑测试: 高频小步长
mirroring-hid-probe --mode smooth

# 传统"格"滚动: 低频大步长
mirroring-hid-probe --mode notch

# 固定方向, 便于对照
mirroring-hid-probe --direction up
```

签名成功后应看到:

```
✓ 虚拟 HID 鼠标已创建并激活: …
  确认设备已注册:  hidutil list | grep -i 'Mos Mirroring'
```

**观测步骤**:
1. 另开终端 `hidutil list | grep -i 'Mos Mirroring'` → 确认虚拟设备已注册(C2 前置)。
2. **先在普通 App 验证**(TextEdit/Safari 长页面):虚拟滚轮能不能滚、方向对不对 → 排除"设备本身没在发滚轮"的可能。
3. 打开 **iPhone 镜像**,让其窗口在前台,重复观察:能否滚动 / 方向 / 平滑度。
4. 观察**物理鼠标是否也仍能滚动镜像**——若是,说明不 seize 物理设备会"双份输入",这决定最终方案是否必须走 Karabiner 式 seize(见 log 里 C5)。

每步结果记进 `../../docs/research/iphone-mirroring-scroll/03-experiment-log.md`。

---

## 首次运行的系统授权
创建虚拟 HID 设备可能触发一次系统隐私授权(输入监控)。若 `init?` 一直返回 nil 且签名确认无误,检查**系统设置 > 隐私与安全性 > 输入监控**里是否需要放行本程序。

## 清理
删除本目录即可。系统里不残留任何东西(进程退出时虚拟设备自动注销)。若装了 Karabiner 且不再需要,按其官方说明卸载。
