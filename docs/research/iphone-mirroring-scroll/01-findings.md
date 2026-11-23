# iPhone Mirroring 滚动的早期机制判断与路线评估

> 2026-07 的研究记录. 方案状态见[研究索引](00-README.md). 2026-10-09 的机制还原取代独占 IOHID 路径的判断, 2026-10-12 的实机对照进一步验证了 sender 与惯性行为. [机制报告](06-2026-10-09-core-mechanism-and-experiment-handoff.md) · [实验记录](03-experiment-log.md)

关联 issue: [#762](https://github.com/Caldis/Mos/issues/762)
环境: macOS 26 (25A5316i) / iOS 26,复现于 Mos 3.5.0
调查方式: 系统二进制逆向（本机 dyld shared cache 提取 + 符号/字符串分析）+ 社区证据交叉验证

---

## 1. 原始问题

在系统开启「自然滚动」+ Mos 开启「翻转方向」时,几乎所有别处都表现为翻转后的方向,唯独 **iPhone 镜像内的滚轮方向不被翻转**;平滑滚动同样对镜像无效。Mos 的 per-app 例外规则也管不到它。

## 2. 早期二进制证据

### 2.1 输入实际由 WindowManager 承载,走 UniversalHID
- iPhone 镜像 App = `com.apple.ScreenContinuity`,但链接 `UniversalHID.framework` 的进程是 **`/System/Library/CoreServices/WindowManager.app`**。
- 早期检查在 ScreenContinuityUI 中找到用于设置拖拽坐标的 `CGEventSetIntegerValueField`. 10 月将分析扩展到相邻框架和事件转换器后, 确认了窗口内的滚动转换路径. [链路伪代码](06-scroll-pipeline.pseudo.swift)

### 2.2 UniversalHID 的 IOHIDEventSystem 路径

独占 IOHID 路径是早期假设. 10 月反汇编还原了镜像窗口的 `scrollWheel(with:)` 入口及后续事件转换, 见[机制报告](06-2026-10-09-core-mechanism-and-experiment-handoff.md)
`UniversalHID` 导入符号清一色 IOHIDEvent 系:
```
IOHIDEventSystemConnectionDispatchEvent      // 在 IOHIDEvent 层收发
IOHIDEventCreateScrollEvent / …DigitizerEvent / …FluidTouchGestureEvent
IOHIDEventGetScrollMomentum / SetPhase
```
类结构:`HIDEventSystemClient` / `HIDServiceClient`(订阅端)、`HIDVirtualService` / `HIDVirtualServicePool`(注入端)、以及 `ScrollFilter` / `PointerFilter` / `DigitizerFilter` / `FluidTouchGestureFilter`。它把鼠标滚轮的原始 HIDEvent 转成 iOS 的 **digitizer/触摸手势**再转发——这印证了 Scroll Reverser 作者的原话「iPhone 镜像吃 gestures,不吃 scroll signals」。

### 2.3 系统自然滚动在早期样本中的作用
- `UniversalHID.ScrollFilter` 内含字符串 **`ignoresNaturalScrollingPreference`** → 它**直接读系统偏好 `com.apple.swipescrolldirection`** 来决定方向。
- 自然滚动的翻转由 IOHIDFamily 的 `IOHIDPointerScrollFilter` 在 IOHIDEvent **分发之前**应用。
- 早期样本中, 系统设置可以改变镜像方向, 当时 Mos 的 Annotated Session 捕获和按进程投递路径无法控制镜像方向. HID 层的 CGEvent 投递随后在探针 C 中生效

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
   IOHIDEventSystem 事件分发          ← IOHID 订阅路径
        ▲   IOHIDPointerScrollFilter 在此应用自然滚动翻转 + 加速
   IOKit HID 驱动 (kext/dext)         ← 虚拟 HID 设备(路线 B)从这里进入,故镜像可见
        ▲
   物理鼠标
```
上图描述 IOHID 与 CGEvent 的层级, 原先从层级推导「CGEvent 无法影响镜像」的结论已撤回. 7 月的探针 C 和 D 分别验证 HID 层投递和消费可影响镜像. 11 月合入的适配器使用 Session 层捕获并从 HID 层投递. [方向实验](03-experiment-log.md) · [适配器方案](../../plans/2026-10-12-iphone-mirroring-scroll.md)

## 3. 2026-07 的社区方案快照

| 工具 | 结论 | 依据 |
|---|---|---|
| LinearMouse | can't fix | 维护者:镜像用更底层系统滚动事件,不经 LinearMouse |
| Scroll Reverser | can't fix | 作者:吃 gesture 不吃 scroll signal,取自更深事件流 |
| Mac Mouse Fix | 未修复 | 作者只承诺"别更糟",无时间表 |
| Logi Options+ | 能工作 | 走**自己的驱动**(即路线 B) |
| Flutter engine | 已修复(独立佐证) | PR #55285:「iOS 18 屏幕镜像只发 pan/scale 手势,不发 hover」 |

## 4. 方案评估

### 路线 A — 前台聚焦时切系统自然滚动 (已废弃)
- 机制:私有框架 `PreferencePanesSupport` 的 `setSwipeScrollDirection(bool)` / `swipeScrollDirection()`,即时生效、**无需注销**(`defaults write` 不即时生效);配合广播 `SwipeScrollDirectionDidChangeNotification`。
- 逻辑:聚焦镜像时把系统自然滚动设为"用户在别处的等效方向 = 系统自然 XOR Mos 垂直翻转",失焦恢复。**只在用户开了 Mos 翻转时动作**(正是本 bug 场景)。
- 原型只调整方向, 聚焦期间会改变全局「自然滚动」设置. 实验开关默认关闭
- 实现见 §6。

### 路线 B — 虚拟 HID 设备 (CoreHID 已采用, DriverKit 已搁置)
- 机制:seize 物理鼠标(可选)+ 用虚拟 HID 设备重发翻转/平滑后的滚轮,以**真 IOHIDEvent** 从 IOHIDFamily 进入 → 镜像可见(Logi Options+ 即此路)。
- 两种 API:
  - **CoreHID `HIDVirtualDevice`**(macOS 15+,公开框架,纯用户态,无需 dext)— 由 `com.apple.developer.hid.virtual.device` 门控. Apple 于 2026-09 授权, 原型复测确认虚拟滚轮能驱动镜像且方向可控
  - **DriverKit 虚拟 HID**(Karabiner 架构)— 需 dext + 系统扩展审批 + 重启,重一个数量级;需 `com.apple.developer.driverkit.*` + `family.hid.*`。
- 早期「只有虚拟 HID 能翻转并平滑」的判断已撤回. 2026-10 的 Lab 对照支持 CGEvent 平滑滚动, 条件包括有效的触控板类 sender 和适配字段. [实验记录](03-experiment-log.md)

### 2026-07 初期的投递与权限探针

- 早期对 `CGEventPost` 的整体排除已撤回. 探针 C 的 HID 层投递取得了阳性结果
- SkyLight 按 PID 定向投递是基于当时层级假设提出的比较项. 镜像窗口的 NSEvent 入口已在后续反汇编中确认, 按 PID 投递的适用性仍需按投递方式和事件形式分别判断
- **借用镜像自己的注入器 `UniversalHID.HIDVirtualService`**:逆向确认其注入侧(`HIDVirtualService`/`HIDConnection.dispatchEvent`/`sendReport(PointerReport)`)最终只汇聚到 IOKit 的 `IOHIDEventSystemConnectionDispatchEvent`,即需 `com.apple.private.hid.client.event-dispatch`(私有,Apple 专属);且三个相关二进制(UniversalHID/HID/ScreenSharingKit)**无任何 XPC/NSXPC 监听器**,注入器是进程内 Swift API,无对外 IPC 面可调。它只是 Apple 给私有注入原语套的封装,不是可借的侧门。
- **④ 层直接派发 `IOHIDEventSystemClientDispatchEvent`(无 entitlement)**:实测——client 建得成、dispatch 不报错,但拿系统设置长列表行为对照,**完全无滚动(静默 no-op)**,事件到不了任何消费者。
- **③ 层老 C API `IOHIDUserDeviceCreateWithProperties`(foohid 那代)**:实测——普通用户返回 NULL;**`sudo`(uid=0)仍返回 NULL**。`IOHIDServiceCheckEntitlements` 不看 uid,root 破不了。这正是 Karabiner 弃用 IOHIDUserDevice 转 DriverKit 的原因。
- **③ 层 CoreHID `HIDVirtualDevice`**:需 `com.apple.developer.hid.virtual.device`,development 阶段即门控(见 `03` Phase 1:AMFI SIGKILL + 门户拒发)。

> 探针源码留档:`experiments/` 外的一次性验证在 scratchpad(`probeA_userdevice.c` / `probeB_dispatch.c`),结论已录此处,可弃。
> 9 月的审批结果已取代 7 月的签名判断. CoreHID 可用, DriverKit 分发申请结案. [授权记录](04-entitlement-application.md)

### 路线 C — kCGHIDEventTap 消费与普通滚轮重投 (方向对照)
- **机制**:在 `kCGHIDEventTap`(CGEvent 管线最底层)挂一个消费型 tap:吞掉原始物理滚轮(`return nil`),用取反 delta 的新事件从 `CGEventPost(kCGHIDEventTap, …)` 重投。镜像既收不到原始、又收到翻转后的 → 干净翻转。
- **证据分级(诚实标注,勿再上调)**:
  - **probeD(硬证)**:在 `kCGHIDEventTap` **消费**物理滚动 → 镜像**收不到**(237 事件被吞,镜像纹丝不动,截图)。
  - **probeC(硬证)**:向 `kCGHIDEventTap` **投递**滚轮 → 镜像**滚动、方向可控**(上/下各测,3 轮截图)。
  - **probeE(支持性,非最强证明)**:二者合一(消费+翻转重投)→ 物理滚动镜像时观察到"内外一致"。按 case 分析,一致 ⇒ 镜像读取在本 tap 下游(= 翻转到达);但**最干净的 A/B(同手势、翻转开/关,看绝对方向是否反转)因 iPhone 反复被占用未跑完**。故:两个原子能力(投递到达 / 消费压制)是硬证,路线 C 由二者**逻辑推出**;"翻转把镜像方向真正掉过来"缺一个干净的当场演示,**待补**。
- **✅ 机制已查清(2026-07-11,probeF/probeF2 判别)**:结论是**假设①——镜像另有一条 CGEvent 滚动路径**。
  - probeF2(纯监听):物理滚动 → IOHIDEventSystem 监听**抓得到** scroll IOHIDEvent(10 个,无 entitlement 即可)。证明监听可用、物理滚动确是 IOHIDEvent。
  - probeF(监听 + 自投):`CGEventPost(kCGHIDEventTap)` 20 个 → 监听抓到 **0 个** scroll IOHIDEvent。→ **kCGHIDEventTap 投递的滚轮不是 IOHIDEvent**,却能滚镜像 ⇒ 镜像必有 CGEvent 路径。
  - 佐证:WindowManager 本体 import `CGEventGetIntegerValueField`/`GetDoubleValueField`(读 CGEvent 字段),且链接 AppKit + SkyLight。
- 这组探针支持 CGEvent 可驱动镜像. 探针未定位镜像读取点, 9 月在另一台机器上的 IOHID 监听也未复现相同结果. 10 月静态还原确认了窗口内的 NSEvent 转换路径. [实验记录](03-experiment-log.md) · [机制报告](06-2026-10-09-core-mechanism-and-experiment-handoff.md)
- 7 月的方向实验覆盖普通滚轮. 10 月对连续滚动的结果来自带阶段, 字段与 sender 对照的 Lab 实验. 产品采用 Session 层适配器, 早期「捕获也必须在 HID 层」的设计不再沿用
- **源码**:scratchpad `probeC_cghid.c`(投递)、`probeD_consume.c`(消费)、`probeE_flip.c`(消费+翻转端到端)。

## 5. 方案选择结果

PR #1045 采用窗口级捕获, phased CGEvent 和虚拟触控板身份. 全局自然滚动切换, DriverKit 分发和全局 HID 层消费原型均归档. [适配器方案](../../plans/2026-10-12-iphone-mirroring-scroll.md)

## 6. 路线 A 历史实现

源码与接线保存在[历史提交](https://github.com/Caldis/Mos/commit/b8130c023bb44254602a328aeb32abcec1c9c911)

- `Mos/ScrollCore/SwipeScrollDirection.swift` — dlsym 调 `PreferencePanesSupport` 的 `setSwipeScrollDirection`/`swipeScrollDirection`,符号缺失静默降级。
- `Mos/ScrollCore/MirroringScrollCoordinator.swift` — 监听 `com.apple.ScreenContinuity` 前台激活/失活,聚焦时改写方向、失焦/退出恢复;门控键 `overrideMirroringDirection`(默认关)。
- `Mos/AppDelegate.swift` — 在 ScrollCore 的 enable/disable/terminate 四处对称启停协调器。

## 7. 关键符号/路径速查
- iPhone 镜像 App: `/System/Applications/iPhone Mirroring.app`(`com.apple.ScreenContinuity`)
- 承载进程: `/System/Library/CoreServices/WindowManager.app`(链接 `UniversalHID`,持 `com.apple.private.hid.client.event-monitor`)
- 私有框架: `UniversalHID.framework`、`ScreenContinuityUI.framework`、`PreferencePanesSupport.framework`
- 公开框架: `CoreHID.framework`(`HIDVirtualDevice`,macOS 15+)
- 自然滚动偏好: `com.apple.swipescrolldirection`(NSGlobalDomain)
