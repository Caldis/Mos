# iPhone 镜像滚动方向/平滑失效 — 根因与方案（研究结论）

关联 issue: [#762](https://github.com/Caldis/Mos/issues/762)
环境: macOS 26 (25A5316i) / iOS 26,复现于 Mos 3.5.0
调查方式: 系统二进制逆向（本机 dyld shared cache 提取 + 符号/字符串分析）+ 社区证据交叉验证

---

## TL;DR

- **根因不是"加密所以不可篡改"**,而是**输入捕获的层级**:iPhone 镜像经私有框架 `UniversalHID` 直接订阅 **IOHIDEventSystem** 层的原始滚动事件,该层在 CGEvent **之下**。Mos 的 `CGEventTap` 在 CGEvent 层(之上),改的是下游副本,镜像读的是上游原件,**永远看不到**。
- 系统"自然滚动"翻转在 IOHIDEvent 分发**之前**应用,且 `UniversalHID.ScrollFilter` 带 `ignoresNaturalScrollingPreference` 字段、**直接读系统偏好**——所以只有系统自然滚动开关对镜像有效。
- **短期方案(路线 A,已实现)**:前台聚焦镜像时,用私有符号 `setSwipeScrollDirection` 即时切换系统自然滚动方向,失焦恢复。零 entitlement,只修方向、给不了平滑。
- **长期方案(路线 B,验证中)**:虚拟 HID 设备(CoreHID `HIDVirtualDevice` 或 DriverKit),让翻转/平滑后的滚动以**真 IOHIDEvent** 从 IOHIDFamily 层进入,镜像可见。需向 Apple 申请 entitlement,已提交(Request ID 见 04)。**「镜像认不认虚拟 HID」这一关键假设尚未实测,是路线 B 的唯一未验证环节**。

---

## 1. 问题

在系统开启「自然滚动」+ Mos 开启「翻转方向」时,几乎所有别处都表现为翻转后的方向,唯独 **iPhone 镜像内的滚轮方向不被翻转**;平滑滚动同样对镜像无效。Mos 的 per-app 例外规则也管不到它。

## 2. 根因(二进制证据)

### 2.1 输入实际由 WindowManager 承载,走 UniversalHID
- iPhone 镜像 App = `com.apple.ScreenContinuity`,但链接 `UniversalHID.framework` 的进程是 **`/System/Library/CoreServices/WindowManager.app`**。
- `ScreenContinuityUI` 链接私有 `UniversalHID.framework` + `ScreenSharingKit`;其对 CGEvent 的唯一调用是 `CGEventSetIntegerValueField`(仅用于拖拽设窗口坐标),**无读取滚动的 CGEvent 代码**。

### 2.2 UniversalHID 走 IOHIDEventSystem,不是 CGEvent
`UniversalHID` 导入符号清一色 IOHIDEvent 系:
```
IOHIDEventSystemConnectionDispatchEvent      // 在 IOHIDEvent 层收发
IOHIDEventCreateScrollEvent / …DigitizerEvent / …FluidTouchGestureEvent
IOHIDEventGetScrollMomentum / SetPhase
```
类结构:`HIDEventSystemClient` / `HIDServiceClient`(订阅端)、`HIDVirtualService` / `HIDVirtualServicePool`(注入端)、以及 `ScrollFilter` / `PointerFilter` / `DigitizerFilter` / `FluidTouchGestureFilter`。它把鼠标滚轮的原始 HIDEvent 转成 iOS 的 **digitizer/触摸手势**再转发——这印证了 Scroll Reverser 作者的原话「iPhone 镜像吃 gestures,不吃 scroll signals」。

### 2.3 为什么只有系统自然滚动有效
- `UniversalHID.ScrollFilter` 内含字符串 **`ignoresNaturalScrollingPreference`** → 它**直接读系统偏好 `com.apple.swipescrolldirection`** 来决定方向。
- 自然滚动的翻转由 IOHIDFamily 的 `IOHIDPointerScrollFilter` 在 IOHIDEvent **分发之前**应用。
- 因此系统自然滚动在镜像订阅点的**上游**生效(看得到),Mos 的 CGEvent 翻转在**下游**(看不到)。

### 2.4 权限壁垒
- `WindowManager` 持有私有 entitlement **`com.apple.private.hid.client.event-monitor`**(订阅 IOHIDEventSystem 原始流)。
- 向该层**注入**需 **`com.apple.private.hid.client.event-dispatch`**。
- 两者均为 `com.apple.private.*`,只发给 Apple 自家签名二进制,由 AMFI 强制,**第三方无法申请**。

### 2.5 层级模型
```
   NSEvent (AppKit)
        ▲
   CGEvent / Quartz Event Services   ← CGEventTap 在这层 (Mos / Scroll Reverser / LinearMouse / Mac Mouse Fix)
        ▲   (WindowServer/SkyLight 由 HID 事件合成 CGEvent)
   IOHIDEventSystem 事件分发          ← iPhone 镜像/WindowManager 用 event-monitor entitlement 在这层订阅
        ▲   IOHIDPointerScrollFilter 在此应用自然滚动翻转 + 加速
   IOKit HID 驱动 (kext/dext)         ← 虚拟 HID 设备(路线 B)从这里进入,故镜像可见
        ▲
   物理鼠标
```
关键:即使 Mos 用最底层的 `kCGHIDEventTap` 挂钩,仍在 IOHIDEventSystem 向 event-monitor 客户端分发**之后**,够不到镜像。

> ### ⚠️ 2026-07-11 重大实测修正(区分「拦截」与「投递」)
> 上面这句只对**拦截/改写既有事件**成立,对**投递全新事件****不成立**。实测(探针 C,`experiments` 外 scratchpad `probeC_cghid.c`):
> - **`CGEvent.post(tap: .cghidEventTap)` 投递的全新滚轮事件,能到达并滚动 iPhone 镜像,方向可控,可重复,仅需辅助功能权限——零 entitlement、零虚拟设备、零 dext。**(镜像内微信公众号信息流上/下滚三轮均生效,截图佐证。普通 App 侧边栏为阳性对照。)
> - 来源印证:在售项目 **`jfarcand/mirroir-mcp`** 的 `CGEventInput.swift` 正是这么驱动镜像 swipe 的,并注释「`postToPid` 对普通窗口有效,but NOT for iPhone Mirroring, which requires HID-level event posting」——它的「HID-level」即指投到 `.cghidEventTap`(CGEvent 管线最底部)。
>
> **为什么这不与「各家工具修不了 #762」矛盾**:两种操作根本不同——
> - **拦截+改写**物理滚动(Mos/Scroll Reverser 现在做的):镜像在更上游读到原始事件,tap 的改写在下游,看不到 → #762 无解。**这条仍成立**。
> - **投递全新**滚动(mirroir / 探针 C):从 `.cghidEventTap` 注入的新事件确实到达镜像。**这条今天证实**。
>
> **对 #762 意味着什么(务必别过度乐观)**:证明了「向镜像**注入**方向可控的滚动」无需 dext。但 #762 要的是**翻转用户的物理滚动**,而非凭空注入。要用这条路修 #762,必须能**压制原始物理滚动的那份镜像副本**,再投递翻转后的——「原始副本能否被压制」尚未验证(见 `03` 待办)。若压制不掉,注入翻转只会与原始**叠加**成双份,而非干净翻转。这是下一个关键实验。

## 3. 各家工具现状(同一堵墙)

| 工具 | 结论 | 依据 |
|---|---|---|
| LinearMouse | can't fix | 维护者:镜像用更底层系统滚动事件,不经 LinearMouse |
| Scroll Reverser | can't fix | 作者:吃 gesture 不吃 scroll signal,取自更深事件流 |
| Mac Mouse Fix | 未修复 | 作者只承诺"别更糟",无时间表 |
| Logi Options+ | 能工作 | 走**自己的驱动**(即路线 B) |
| Flutter engine | 已修复(独立佐证) | PR #55285:「iOS 18 屏幕镜像只发 pan/scale 手势,不发 hover」 |

## 4. 方案评估

### ✅ 路线 A — 前台聚焦时切系统自然滚动(已实现)
- 机制:私有框架 `PreferencePanesSupport` 的 `setSwipeScrollDirection(bool)` / `swipeScrollDirection()`,即时生效、**无需注销**(`defaults write` 不即时生效);配合广播 `SwipeScrollDirectionDidChangeNotification`。
- 逻辑:聚焦镜像时把系统自然滚动设为"用户在别处的等效方向 = 系统自然 XOR Mos 垂直翻转",失焦恢复。**只在用户开了 Mos 翻转时动作**(正是本 bug 场景)。
- 代价:零 entitlement;只修方向,**给不了平滑**(平滑同样在 CGEvent 层进不去);会临时改动"自然滚动"这一可见系统设置(失焦即恢复),故默认关闭、显式门控。
- 实现见 §6。

### ⚠️ 路线 B — 虚拟 HID 设备(唯一能同时翻转+平滑)
- 机制:seize 物理鼠标(可选)+ 用虚拟 HID 设备重发翻转/平滑后的滚轮,以**真 IOHIDEvent** 从 IOHIDFamily 进入 → 镜像可见(Logi Options+ 即此路)。
- 两种 API:
  - **CoreHID `HIDVirtualDevice`**(macOS 15+,公开框架,纯用户态,无需 dext)— 由 `com.apple.developer.hid.virtual.device` 门控。**本轮选定路线**。
  - **DriverKit 虚拟 HID**(Karabiner 架构)— 需 dext + 系统扩展审批 + 重启,重一个数量级;需 `com.apple.developer.driverkit.*` + `family.hid.*`。
- **未验证的关键假设**:没有任何来源(含本次逆向)实测过镜像会响应虚拟 HID 注入的滚动。架构上是对的层(真 IOHIDEvent,低于 tap),Logi Options+ 能工作是强旁证,但**必须实测**——见 `02-experiment-plan.md`。

### ❌ 已排除(2026-07-11 补:全部由本机实测封口,非推断)
- `CGEventPost` / CGEvent 内嵌 IOHIDEvent:仍进 WindowServer,在镜像订阅点(④)下游,收不到。
- **SkyLight / `SLEventPostToPid`(cua.ai 文章那条路)**:属 ⑤ WindowServer 层的**按 PID 定向投递**,文章自述"bypasses IOHIDPostEvent entirely"——比 `CGEventPost` 离 ④ 更远。且镜像的滚动路径是纯 IOHIDEvent(ScreenContinuityUI 唯一的 CGEvent 调用是 `CGEventSetIntegerValueField` 设窗口坐标,无读滚动代码),按 PID 投到 WindowManager 的 CGEvent 队列它也不读。**关键差异**:cua.ai 成功是因为 ⑤ 层注入被 **TCC(辅助功能,用户可授)** 门控;而 ④/③ 层注入被 **entitlement** 门控——同是"私有定向通道",门禁等级不同。
- **借用镜像自己的注入器 `UniversalHID.HIDVirtualService`**:逆向确认其注入侧(`HIDVirtualService`/`HIDConnection.dispatchEvent`/`sendReport(PointerReport)`)最终只汇聚到 IOKit 的 `IOHIDEventSystemConnectionDispatchEvent`,即需 `com.apple.private.hid.client.event-dispatch`(私有,Apple 专属);且三个相关二进制(UniversalHID/HID/ScreenSharingKit)**无任何 XPC/NSXPC 监听器**,注入器是进程内 Swift API,无对外 IPC 面可调。它只是 Apple 给私有注入原语套的封装,不是可借的侧门。
- **④ 层直接派发 `IOHIDEventSystemClientDispatchEvent`(无 entitlement)**:实测——client 建得成、dispatch 不报错,但拿系统设置长列表行为对照,**完全无滚动(静默 no-op)**,事件到不了任何消费者。
- **③ 层老 C API `IOHIDUserDeviceCreateWithProperties`(foohid 那代)**:实测——普通用户返回 NULL;**`sudo`(uid=0)仍返回 NULL**。`IOHIDServiceCheckEntitlements` 不看 uid,root 破不了。这正是 Karabiner 弃用 IOHIDUserDevice 转 DriverKit 的原因。
- **③ 层 CoreHID `HIDVirtualDevice`**:需 `com.apple.developer.hid.virtual.device`,development 阶段即门控(见 `03` Phase 1:AMFI SIGKILL + 门户拒发)。

> 探针源码留档:`experiments/` 外的一次性验证在 scratchpad(`probeA_userdevice.c` / `probeB_dispatch.c`),结论已录此处,可弃。
> **唯一仍开着的门**:DriverKit dext(③ 层造设备,development 能力自助已配好,distribution 待 Apple 审 7CTL26535S)。事件以真硬件身份从 ③ 上浮到 ④,镜像照单全收——我们从楼下喂满同一条流水线,而非去撬 ④ 那把锁。Phase 0(Karabiner)已端到端验证这条链路可行。

### ⭐ 路线 C — kCGHIDEventTap 底层「消费 + 翻转重投」(2026-07-11 新发现,实测可行,推荐)
- **机制**:在 `kCGHIDEventTap`(CGEvent 管线最底层)挂一个消费型 tap:吞掉原始物理滚轮(`return nil`),用取反 delta 的新事件从 `CGEventPost(kCGHIDEventTap, …)` 重投。镜像既收不到原始、又收到翻转后的 → 干净翻转。
- **证据分级(诚实标注,勿再上调)**:
  - **probeD(硬证)**:在 `kCGHIDEventTap` **消费**物理滚动 → 镜像**收不到**(237 事件被吞,镜像纹丝不动,截图)。
  - **probeC(硬证)**:向 `kCGHIDEventTap` **投递**滚轮 → 镜像**滚动、方向可控**(上/下各测,3 轮截图)。
  - **probeE(支持性,非最强证明)**:二者合一(消费+翻转重投)→ 物理滚动镜像时观察到"内外一致"。按 case 分析,一致 ⇒ 镜像读取在本 tap 下游(= 翻转到达);但**最干净的 A/B(同手势、翻转开/关,看绝对方向是否反转)因 iPhone 反复被占用未跑完**。故:两个原子能力(投递到达 / 消费压制)是硬证,路线 C 由二者**逻辑推出**;"翻转把镜像方向真正掉过来"缺一个干净的当场演示,**待补**。
- **✅ 机制已查清(2026-07-11,probeF/probeF2 判别)**:结论是**假设①——镜像另有一条 CGEvent 滚动路径**。
  - probeF2(纯监听):物理滚动 → IOHIDEventSystem 监听**抓得到** scroll IOHIDEvent(10 个,无 entitlement 即可)。证明监听可用、物理滚动确是 IOHIDEvent。
  - probeF(监听 + 自投):`CGEventPost(kCGHIDEventTap)` 20 个 → 监听抓到 **0 个** scroll IOHIDEvent。→ **kCGHIDEventTap 投递的滚轮不是 IOHIDEvent**,却能滚镜像 ⇒ 镜像必有 CGEvent 路径。
  - 佐证:WindowManager 本体 import `CGEventGetIntegerValueField`/`GetDoubleValueField`(读 CGEvent 字段),且链接 AppKit + SkyLight。
  - **修正**:老 §2/§2.5"镜像只走 IOHIDEventSystem、CGEvent 层够不到"**不准确**。准确说法:镜像读滚动的位置**低且全局**(kCGHIDEventTap 区域),既接受 IOHIDEvent(物理),也接受该层的 CGEvent 投递;但**不**读 per-window NSEvent 队列(所以 `postToPid` 到不了它)。
  - **一致解释全部现象**:物理滚动经 IOHID 上游到镜像 → Mos 在高层(session)改写看不到(#762);`postToPid` 投 per-window 队列 → 镜像不读(mirroir 证);`kCGHIDEventTap` 投递/消费 → 命中镜像的低层全局读取点 → 可控(probeC/D)。
  - **鲁棒性判断**:路线 C 只用**公开稳定**的 `kCGHIDEventTap`(CGEvent API),mirroir 已在其上出货;比路线 A(私有 `PreferencePanesSupport` dlsym)、路线 B(私有 entitlement + dext)更不依赖私有面。
- **为什么现有工具修不了(根因,已在 Mos 代码定位)**:
  - Mos 的滚动 tap 挂在 `.cgAnnotatedSessionEventTap`(session **最高层**,`ScrollCore.swift:409`),消费/改写发生在镜像 `kCGHIDEventTap` 底层读取点的**上游之后** → 镜像早已在底层读走原始 → 改写看不到。
  - Mos 重投用 `event.postToPid(targetPID)`(`ScrollDispatchContext.swift:131`)→ mirroir 项目已证 **postToPid 到不了 iPhone 镜像**。
  - 两处都错在"层不对":要够到镜像必须下沉到 `kCGHIDEventTap`。
- **代价**:仅需**辅助功能**权限(Mos 已持有)。**零 entitlement、零虚拟设备、零 dext、零系统扩展审批**。可 per-app(Mos 已能识别前台镜像)。
- **仍需验证**:① 平滑(C4)——向 `kCGHIDEventTap` 投高频细粒度流镜像是否平滑渲染,待测;② 与现有 session-tap 管线的协同(建议:仅镜像前台时启用底层 tap,其余走原路径);③ 动量/惯性阶段、光标路由、多显示器等鲁棒性。
- **源码**:scratchpad `probeC_cghid.c`(投递)、`probeD_consume.c`(消费)、`probeE_flip.c`(消费+翻转端到端)。

## 5. 结论与建议
1. **首选(新,但证据尚未闭环)**:**路线 C**——镜像前台时下沉到 `kCGHIDEventTap` 消费+翻转重投。轻量、无审批;修方向的两个原子能力已硬证、逻辑上可行,但**干净的翻转 A/B 与机制解释两处仍待补**(见 §4)。若补齐且平滑(C4)通过,则远优于路线 A/B。**在补齐前,定性为"高可能可行",不是"已确认可上线"。**
2. **短期兜底**:路线 A(系统级翻转)已实现、可留作 `kCGHIDEventTap` 不可用时的降级。
3. **长期天花板**:路线 B(dext)仍是完全体(seize + 任意重构),但仅在路线 C 平滑验证失败、或需完全接管输入时才值得那套审批成本。CoreHID 分支已因 entitlement 门控搁置。

## 6. 路线 A 实现状态(本分支已含,编译通过)
- `Mos/ScrollCore/SwipeScrollDirection.swift` — dlsym 调 `PreferencePanesSupport` 的 `setSwipeScrollDirection`/`swipeScrollDirection`,符号缺失静默降级。
- `Mos/ScrollCore/MirroringScrollCoordinator.swift` — 监听 `com.apple.ScreenContinuity` 前台激活/失活,聚焦时改写方向、失焦/退出恢复;门控键 `overrideMirroringDirection`(默认关)。
- `Mos/AppDelegate.swift` — 在 ScrollCore 的 enable/disable/terminate 四处对称启停协调器。
- **待办(UX 决策未定)**:开关的正式 UI 与 Options 字段落地。三个候选:偏好设置全局开关(默认关,推荐)/ 复用现有例外列表做 per-app / 全局自动默认开。当前用独立 UserDefaults 键 `overrideMirroringDirection` 门控,可 `defaults write com.caldis.Mos.debug overrideMirroringDirection -bool true` 测试。

## 7. 关键符号/路径速查
- iPhone 镜像 App: `/System/Applications/iPhone Mirroring.app`(`com.apple.ScreenContinuity`)
- 承载进程: `/System/Library/CoreServices/WindowManager.app`(链接 `UniversalHID`,持 `com.apple.private.hid.client.event-monitor`)
- 私有框架: `UniversalHID.framework`、`ScreenContinuityUI.framework`、`PreferencePanesSupport.framework`
- 公开框架: `CoreHID.framework`(`HIDVirtualDevice`,macOS 15+)
- 自然滚动偏好: `com.apple.swipescrolldirection`(NSGlobalDomain)
