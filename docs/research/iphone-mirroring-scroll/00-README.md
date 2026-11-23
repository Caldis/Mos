# iPhone Mirroring 滚动研究

PR #1045 已在 `master` 接入 iPhone Mirroring 滚动适配器. 适配器在 Session 层按目标窗口捕获滚轮, 输出带虚拟 Magic Trackpad 2 sender 的 phased CGEvent, iPhone 负责手势结束后的滑行. [Issue #762](https://github.com/Caldis/Mos/issues/762) · [PR #1045](https://github.com/Caldis/Mos/pull/1045) · [实现与实机复验记录](../../plans/2026-10-12-iphone-mirroring-scroll.md)

## 方案状态

| 方案 | 状态 |
|---|---|
| 路线 A, 镜像聚焦时切换全局「自然滚动」 | 已废弃并移出 Mos 主程序. 原型支持方向切换, 源码可在[历史提交](https://github.com/Caldis/Mos/commit/b8130c023bb44254602a328aeb32abcec1c9c911)查阅 |
| 路线 B, DriverKit 虚拟 HID | 已搁置. Karabiner-Elements 实验证实虚拟滚轮可以驱动镜像且方向可控. Mos 的 DriverKit 分发申请被拒. [授权记录](04-entitlement-application.md) |
| 路线 B, CoreHID 虚拟设备 | Apple 已授予 HID Virtual Device 能力. Mos 使用虚拟设备提供 sender 身份, 通过 CGEvent 投递滚动. 直接发送触点报文的完整虚拟触控板仍是 Lab 原型 |
| 路线 C, 在 HID 层消费并重投普通滚轮 | 归档为方向实验. 探针分别证实 HID 层投递与消费可影响镜像. 消费后翻转重投有支持性观察, 同手势开关对照未完成 |

## 实验证据

- 2026-07-11 的滚轮注入实验和 2026-10-09 的 Mac 端反汇编均支持镜像存在 CGEvent 滚动路径, 早期 IOHID-only 判断已撤回. [方向实验](03-experiment-log.md#phase-2--cgevent-投递与消费) · [机制报告](06-2026-10-09-core-mechanism-and-experiment-handoff.md) · [链路伪代码](06-scroll-pipeline.pseudo.swift)
- 2026-10-12 的 E1 中, 更改 Mac 侧合成惯性衰减后, 镜像滑行距离相近. E2 和 E3 中, 虚拟和内置触控板 sender 均获得连续滚动. 鼠标 sender 或零 sender 未达到相同效果. 这些结果限于当时的设备, 字段与投递配置. [实验记录](03-experiment-log.md) · [原始轮次](evidence/2026-10-12/lab/)
- 2026-11-23 复验记录了两项接受的限制. 平滑尾段移出再移回窗口可能继续滚动. 关闭「流畅滚动」期间在镜像内滚动后, 镜像输入可能卡住并需要重连. 第二项的内部触发条件待确认. [实机复验记录](../../plans/2026-10-12-iphone-mirroring-scroll.md#2026-11-23-实机复验)

## 实验工具与后续分支

- [MirroringScrollLab](../../../experiments/MirroringScrollLab/) 记录原始输入, 引擎帧, 投递事件和设备服务属性, 支持帧时钟, 字段和 sender 的对照实验. [代码指南](../../../experiments/MirroringScrollLab/CODE-GUIDE.md) · [离线分析脚本](../../../experiments/MirroringScrollLab/tools/analyze-round.py)
- [MirroringHIDProbe](../../../experiments/MirroringHIDProbe/) 保存独立的虚拟鼠标与触控板探针, 事件监听和画面位移分析工具

| 分支 | 开发范围与参考实现 |
|---|---|
| `feat/monitor` | Mos Event Monitor. 参考 Lab 的[图表](../../../experiments/MirroringScrollLab/Sources/TraceViews.swift), [事件记录器](../../../experiments/MirroringScrollLab/Sources/Recorder.swift)与[服务映射](../../../experiments/MirroringScrollLab/Sources/ServiceMap.swift) |
| `feat/frame-clock` | 滚动帧时钟与时间归一化. 参考 Lab 的[时钟实现](../../../experiments/MirroringScrollLab/Sources/FrameClock.swift)与[插值换算](../../../experiments/MirroringScrollLab/Sources/ScrollEngine.swift) |
| `feat/virtual-trackpad` | 虚拟触控板接触, 移动与抬指报文. 参考 Lab 的[虚拟设备原型](../../../experiments/MirroringScrollLab/Sources/VirtualDevices.swift)和 Mos 的[设备身份组件](../../../Mos/ScrollCore/Adapters/Shared/VirtualTrackpadIdentity.swift) |

## 历史资料

- [早期机制判断与路线评估](01-findings.md) · [虚拟 HID 验证计划](02-experiment-plan.md) · [已废弃的 issue 回复草稿](05-issue-comment-draft.md)
- [2026-10-09 反汇编与离线字段证据](evidence/2026-10-09/) · [2026-10-12 Lab 证据](evidence/2026-10-12/)
