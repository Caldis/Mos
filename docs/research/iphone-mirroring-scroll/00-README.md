# iPhone 镜像滚动方向/平滑 — 研究与验证

issue [#762](https://github.com/Caldis/Mos/issues/762) 的完整研究、方案与验证工作区。用于跨设备继续。

## 文档
| 文件 | 内容 |
|---|---|
| [`01-findings.md`](01-findings.md) | 根因(二进制逆向证据)、层级模型、各家工具现状、方案排序、路线 A 实现状态 |
| [`02-experiment-plan.md`](02-experiment-plan.md) | 路线 B 验证方案:待验证命题、方式、"全绿是否足够"、残留风险、决策门 |
| [`03-experiment-log.md`](03-experiment-log.md) | 实验记录模板(在另一台设备上填) |
| [`04-entitlement-application.md`](04-entitlement-application.md) | DriverKit 申请记录(Request ID `7CTL26535S`)、跟进方式、entitlement 概念澄清 |

## 代码
| 位置 | 内容 |
|---|---|
| `Mos/ScrollCore/SwipeScrollDirection.swift` | 路线 A:系统自然滚动即时读写桥接 |
| `Mos/ScrollCore/MirroringScrollCoordinator.swift` | 路线 A:镜像前台聚焦时切换方向的协调器 |
| `Mos/AppDelegate.swift`(改) | 路线 A 生命周期接线 |
| `../../experiments/MirroringHIDProbe/` | 路线 B:CoreHID 虚拟 HID 验证原型(独立 SwiftPM,不入 Mos) |

## 结论速览
- **根因**:镜像在 IOHIDEventSystem 层(CGEvent 之下)读滚动,Mos 的 CGEventTap 够不到。
- **路线 A**(已实现,编译通过):系统级切自然滚动,零 entitlement,只修方向。
- **路线 B**(验证中):虚拟 HID 设备,能翻转+平滑,但"镜像认不认虚拟 HID"未实测——见 `02`。

## 从这里继续(在另一台设备上)
1. 读 `01` 与 `02`。
2. 做 `02` 的 **Phase 0(Karabiner 代理)** — 零签名,最快 go/no-go,结果记入 `03`。
3. go 则做 **Phase 1**:`experiments/MirroringHIDProbe/README.md` 编译、签名、运行、观测,结果记入 `03`。
4. 路线 A 的收尾:定 UX 开关形态(见 `01` §6 待办)、落地 UI 与正式 Options 字段。
5. 跟进 DriverKit 申请(`04`,Request ID `7CTL26535S`)。

## 分支
`research/iphone-mirroring-scroll`(off master)。路线 A 的 Mos 改动 + 本研究文档 + CoreHID 原型都在此分支。
