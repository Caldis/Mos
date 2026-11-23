# MirroringHIDProbe

独立的 CoreHID 实验工具. 2026-09-30 的复测确认虚拟鼠标滚轮能驱动 iPhone Mirroring, 方向随参数变化. [研究索引](../../docs/research/iphone-mirroring-scroll/00-README.md) · [复测记录](../../docs/research/iphone-mirroring-scroll/03-experiment-log.md)

## Phase 0 — Karabiner 对照 (已完成)

Karabiner-Elements 通过 DriverKit 虚拟设备重发物理滚轮. 2026-07-11 的开关对照确认镜像响应虚拟滚轮, 并随设备级反转设置改变方向. [实际执行方式与观测](../../docs/research/iphone-mirroring-scroll/03-experiment-log.md)

## Phase 1 — CoreHID 探针

### 编译检查

```bash
cd experiments/MirroringHIDProbe
swift build
```

未签名直接跑会得到(这是预期的,证明 entitlement gate 生效):

```
✗ HIDVirtualDevice(properties:) 返回 nil。
  最可能原因: 未带 entitlement com.apple.developer.hid.virtual.device …
```

### 签名构建

实机探针使用 9 月复测通过的 XcodeGen App target. 运行前需要为 App ID 启用 HID Virtual Device 能力, 并使用包含该能力的描述文件. 工程配置见 [project.yml](project.yml), 签名历史见[授权记录](../../docs/research/iphone-mirroring-scroll/04-entitlement-application.md)

```bash
./tools/build.sh
```

脚本同时构建 `winctl` 与 `evspy`, 探针 App 输出到 `DerivedData/Build/Products/Debug`

### 运行与观测

```bash
probe=./DerivedData/Build/Products/Debug/MirroringHIDProbe.app/Contents/MacOS/MirroringHIDProbe
"$probe"
"$probe" --mode smooth
"$probe" --mode notch
"$probe" --direction up
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
4. 对照物理滚轮和虚拟滚轮同时输入时的画面位移, 记录 C5 的叠加结果

每步结果记进 `../../docs/research/iphone-mirroring-scroll/03-experiment-log.md`。

---

## 首次运行的系统授权
创建虚拟 HID 设备可能触发一次系统隐私授权(输入监控)。若 `init?` 一直返回 nil 且签名确认无误,检查**系统设置 > 隐私与安全性 > 输入监控**里是否需要放行本程序。

## 清理
探针退出时注销虚拟设备. 临时构建文件位于 `DerivedData` 和 `tools/.build`
