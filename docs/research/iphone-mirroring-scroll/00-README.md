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
- **2026-07-11 ①**:CoreHID entitlement 经实测 **development 阶段即门控、无法自助获取**(AMFI SIGKILL + 门户拒发 + Xcode 无能力映射,证据链见 `03`)→ CoreHID 版 Phase 1 硬阻塞于 Apple 授权。
- **2026-07-11 ② Phase 0 完成,结论 GO**:Karabiner 代理实测,**虚拟 HID 滚轮可到达 iPhone 镜像(C2)且方向可控(C3)**——A/B 截图对照、系统自然滚动全程未动,见 `03`。路线 B 架构成立;因 CoreHID 受阻而 dext 链路已被端到端验证。
- **2026-07-11 ③ ⭐ 重大突破 — 路线 C(推荐,轻量)**:受 cua.ai 文章 + 在售项目 `mirroir-mcp` 启发,实测发现 **`CGEventPost(kCGHIDEventTap)` 投递的滚轮能到达镜像(probeC),而 `kCGHIDEventTap` 消费型 tap 能压制物理滚动到镜像的副本(probeD)**。二者合一 = **在底层「消费原始 + 翻转重投」即可干净翻转镜像方向,仅需辅助功能权限,无 dext / 无 entitlement**(probeE 端到端确认)。根因也定位:Mos 现在 tap 挂 session 最高层 + 用 postToPid 重投,两处都够不到镜像。**这是目前最优解**,详见 `01-findings.md §4 路线 C`、`03` Phase 2。

## 从这里继续(在另一台设备上)
1. 读 `01` 与 `02`;实验结果读 `03`(Phase 0 已 GO,勿重测)。
2. **Phase 1 改道**:CoreHID 无法签名(见 `03`)→ 做 **DriverKit dext 原型**(development 能力自助、App ID `com.caldis.Mos.driver` 已配好,架构对齐 Karabiner),验证 C4(平滑)与注入细节;或等 Apple 授权后回补 CoreHID。
3. 路线 A 的收尾:定 UX 开关形态(见 `01` §6 待办)、落地 UI 与正式 Options 字段。
4. 跟进 DriverKit 申请(`04`,Request ID `7CTL26535S`),并借跟进渠道询问 CoreHID `hid.virtual.device` 的申请途径。
5. 向 issue #762 同步进展(`05` 草稿待更新:补 Phase 0 GO 结论)。

## 分支
`research/iphone-mirroring-scroll`(off master)。路线 A 的 Mos 改动 + 本研究文档 + CoreHID 原型都在此分支。
