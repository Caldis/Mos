## 深入定位:根因已在系统二进制层面确认

对 macOS 26 上的 iPhone 镜像做了一轮逆向,之前"底层 CGEvent + Secure Enclave 加密所以不可篡改"的猜测方向对了(不走 CGEvent),但**归因归错了层**——加密只发生在**发往 iPhone 的网络传输**那一段,和本地滚动方向失效无关。

真正原因是**输入捕获的层级**:

- iPhone 镜像(`com.apple.ScreenContinuity`,输入实际由 **`WindowManager`** 进程承载)经私有框架 **`UniversalHID.framework`** 直接以 `HIDEventSystemClient` 订阅 **IOHIDEventSystem** 层的原始滚动事件;
- 该层位于 CGEvent **之下**。Mos 的 `CGEventTap` 工作在 CGEvent 层(之上),**改的是下游副本,镜像读的是上游原件**,所以永远看不到。
- 而系统"自然滚动"由 IOHIDFamily 的 `IOHIDPointerScrollFilter` 在 IOHIDEvent **分发之前**就应用了,且 `UniversalHID` 的 `ScrollFilter` 里带有 `ignoresNaturalScrollingPreference` 字段——它**直接读系统偏好** `com.apple.swipescrolldirection` 决定方向。这就是"只有系统自然滚动开关有效"的原因。

**关键权限壁垒**:`WindowManager` 持有私有 entitlement `com.apple.private.hid.client.event-monitor`(订阅 IOHIDEventSystem 原始流);向该层注入需要 `com.apple.private.hid.client.event-dispatch`。这两个都是 `com.apple.private.*`,只发给 Apple 自家签名的二进制,**第三方无法申请**。

独立佐证:Flutter engine 也踩到同一问题并已修复,其结论一致——"iOS 18 屏幕镜像只发送 pan/scale 手势,不发 hover"(engine PR #55285)。Scroll Reverser 作者、LinearMouse 维护者也都确认是同一堵墙(gesture 而非 scroll event)。

---

## 解决方向

### ✅ 短期(已在开发):前台聚焦时自动切换系统自然滚动
把社区那套"手动去系统设置切自然滚动"的 workaround,升级成**自动、即时生效、无需注销**:
监听 iPhone 镜像成为前台 → 临时把系统自然滚动方向改写为"你在其它应用中的等效方向"(= 系统自然 XOR Mos 翻转)→ 失焦即恢复。
经私有框架 `PreferencePanesSupport` 的 `setSwipeScrollDirection()` 即时生效(不是 `defaults write`,那个需要注销)。**零 entitlement 门槛**,只能修方向、给不了平滑。下个版本会带上。

### ⚠️ 长期(唯一能同时拿到翻转+平滑):虚拟 HID 设备
用 **CoreHID `HIDVirtualDevice`(macOS 15+,公开框架)** 或 DriverKit 虚拟 HID(Karabiner 架构:seize 物理鼠标 + 虚拟设备重发),让翻转/平滑后的滚动以**真 IOHIDEvent** 从 IOHIDFamily 层进入,镜像即可见(Logi Options+ 正是走驱动路线才能工作)。分发需向 Apple 申请虚拟 HID entitlement,是架构级改动,作为长期方向评估中。

### ❌ 已排除
`CGEventPost` / CGEvent 内嵌 IOHIDEvent(仍在下游,收不到)、直接向 IOHIDEventSystem 注入(需私有 entitlement,拿不到)。

在兼容前,建议继续把 iPhone 镜像留在平滑滚动默认禁用列表中。

---

## Root cause confirmed at the system-binary level

I reverse-engineered iPhone Mirroring on macOS 26. The earlier "low-level CGEvent + Secure Enclave encryption, so it can't be tampered with" guess was right that it bypasses CGEvent, but **attributed it to the wrong layer** — the encryption only applies to the **network transport to the iPhone**, and is unrelated to why local scroll direction fails.

The real cause is the **input-capture layer**:

- iPhone Mirroring (`com.apple.ScreenContinuity`, whose input is actually handled by the **`WindowManager`** process) uses the private **`UniversalHID.framework`** to subscribe, via `HIDEventSystemClient`, to the raw scroll events on the **IOHIDEventSystem** layer.
- That layer sits **below** CGEvent. Mos's `CGEventTap` runs on the CGEvent layer (above it), so **it modifies a downstream copy while Mirroring reads the upstream original** — it can never see Mos's changes.
- The system "natural scrolling" flip is applied by IOHIDFamily's `IOHIDPointerScrollFilter` **before** IOHIDEvent fan-out, and `UniversalHID`'s `ScrollFilter` carries an `ignoresNaturalScrollingPreference` field — it **reads the `com.apple.swipescrolldirection` preference directly**. That's why only the system natural-scrolling toggle has any effect.

**The entitlement wall**: `WindowManager` holds the private entitlement `com.apple.private.hid.client.event-monitor` (to subscribe to the raw IOHIDEventSystem stream); injecting into that layer needs `com.apple.private.hid.client.event-dispatch`. Both are `com.apple.private.*`, granted only to Apple-signed binaries — **third parties cannot apply for them**.

Independent corroboration: the Flutter engine hit and fixed the same issue, reaching the same conclusion — "the iOS 18 screen mirroring feature sends only pan/scale gestures, but doesn't hover" (engine PR #55285). The Scroll Reverser author and the LinearMouse maintainer confirm the same wall (gestures, not scroll events).

---

## Direction

**Short term (in development):** auto-toggle the system natural-scrolling direction when iPhone Mirroring becomes frontmost, restoring it on blur — an automatic, instant, no-logout version of the community workaround, via `PreferencePanesSupport`'s `setSwipeScrollDirection()`. Zero entitlement needed; fixes direction only, not smoothness. Shipping next release.

**Long term (only path to both flip + smooth):** a virtual HID device — CoreHID `HIDVirtualDevice` (macOS 15+, public) or DriverKit virtual HID (the Karabiner architecture: seize the physical mouse + re-emit from a virtual device) — so the reversed/smoothed scroll enters as a **real IOHIDEvent** from the IOHIDFamily layer, which Mirroring can see (this is how Logi Options+ works). Distribution requires applying to Apple for a virtual-HID entitlement; it's an architectural change, under evaluation.

**Ruled out:** `CGEventPost` / embedding IOHIDEvent in CGEvent (still downstream), and injecting directly into IOHIDEventSystem (needs a private entitlement that's unobtainable).

Until compatible, keeping iPhone Mirroring in the default smooth-scrolling exclusion list is recommended.
