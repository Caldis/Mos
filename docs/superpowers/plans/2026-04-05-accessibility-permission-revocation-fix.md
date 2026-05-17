# Accessibility Permission Revocation Fix - Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the critical bug where revoking accessibility permissions at runtime causes the entire system to lose keyboard and mouse click/scroll input.

**Architecture:** Add `AXIsProcessTrusted()` permission checks to `Interceptor.start()` (throw on failure) and `restart()` / keeper timer (stop + notify on failure). Decouple `ScrollPoster` from `Interceptor` via an optional `onRestart` closure. Add `tapDisabledByUserInput`/`tapDisabledByTimeout` handling to ButtonCore's callback. Add a permission-loss notification via `NotificationCenter` so the app reacts gracefully (disable cores, show Toast). Make `sessionDidActive` permission-aware.

**Tech Stack:** Swift, CGEventTap, macOS Accessibility API (`AXIsProcessTrusted`), NotificationCenter

---

## File Structure

| Action | File | Responsibility |
|--------|------|----------------|
| Modify | `Mos/Utils/Interceptor.swift` | Add permission check to `start()` (throw) and `restart()` / keeper (stop+notify), add `onRestart` closure |
| Modify | `Mos/ButtonCore/ButtonCore.swift` | Add `tapDisabledByUserInput`/`tapDisabledByTimeout` handling in callback |
| Modify | `Mos/ScrollCore/ScrollCore.swift` | Pass `onRestart` closure, nil out interceptors in `disable()` |
| Modify | `Mos/AppDelegate.swift` | Observe permission-loss notification, make `sessionDidActive` permission-aware |
| Modify | `Mos/Utils/Constants.swift` | Add notification name constant |

---

### Task 1: Add notification name constant

**Files:**
- Modify: `Mos/Utils/Constants.swift`

- [ ] **Step 1: Add the Notification.Name extension**

Find the end of `Mos/Utils/Constants.swift` and append:

```swift
// MARK: - Notification Names
extension Notification.Name {
    /// 辅助功能权限在运行时被撤销
    static let mosAccessibilityPermissionLost = Notification.Name("mosAccessibilityPermissionLost")
}
```

---

### Task 2: Decouple ScrollPoster from Interceptor and add permission checks

The core fix. Three protection layers:
- `start()`: throw when permissions missing (prevents zombie tap from init AND 0.5s restart)
- `restart()`: guard check before scheduling restart timer
- keeper timer: guard check before calling `restart()`

**Files:**
- Modify: `Mos/Utils/Interceptor.swift`

- [ ] **Step 1: Add `onRestart` closure property**

In `Mos/Utils/Interceptor.swift`, add the property after line 15 (`_runLoopSourceRef`):

```swift
/// 重启时的额外清理操作 (由调用方注入, 避免 Interceptor 耦合特定子系统)
var onRestart: (() -> Void)?
```

- [ ] **Step 2: Replace `start()` method (lines 60-77)**

`start()` now checks permissions before enabling the tap. When called from `init`, a throw makes init fail so the caller won't store a zombie interceptor. When called from the 0.5s restart timer via `#selector`, the throw is silently swallowed (safe — tap stays disabled). The notification is posted before throwing so AppDelegate can clean up regardless of caller context.

```swift
@objc public func start() throws {
    // 创建拦截层
    guard let tap = _eventTapRef, let source = _runLoopSourceRef else {
        throw InterceptorError.eventTapEnableFailed
    }
    // 权限已被撤销时, 不启用 tap, 避免僵尸 tap 吞没系统事件
    guard AXIsProcessTrusted() else {
        NotificationCenter.default.post(name: .mosAccessibilityPermissionLost, object: nil)
        throw InterceptorError.eventTapEnableFailed
    }
    // 确保 source 没有被重复添加
    if !CFRunLoopContainsSource(CFRunLoopGetCurrent(), source, .commonModes) {
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
    }
    // 启动拦截层
    CGEvent.tapEnable(tap: tap, enable: true)
    // 启动守护
    keeper = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
        guard let self = self else { return }
        // 权限被撤销时, 主动停止 tap 并通知, 不等 restart 判断
        guard AXIsProcessTrusted() else {
            self.stop()
            self.onRestart?()
            NotificationCenter.default.post(name: .mosAccessibilityPermissionLost, object: nil)
            return
        }
        if !self.isRunning() {
            self.restart()
        }
    }
}
```

- [ ] **Step 3: Replace `restart()` method (lines 103-114)**

```swift
public func restart() {
    // 权限已被撤销时, 不再尝试重新启用 tap
    guard AXIsProcessTrusted() else {
        stop()
        onRestart?()
        NotificationCenter.default.post(name: .mosAccessibilityPermissionLost, object: nil)
        return
    }
    stop()
    onRestart?()
    // 使用 closure timer 避免 @objc throws 方法作为 selector 的 ObjC bridge 问题
    keeper = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
        try? self?.start()
    }
}
```

- [ ] **Step 4: Build and verify**

Run: `xcodebuild -scheme Debug -configuration Debug build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

---

### Task 3: Add `tapDisabledByUserInput` handling in ButtonCore callback

ButtonCore's `.defaultTap` callback does not handle `tapDisabledByUserInput`/`tapDisabledByTimeout`, causing these special events to be misinterpreted as mouse button 0 events.

**Files:**
- Modify: `Mos/ButtonCore/ButtonCore.swift:36-57` (buttonEventCallBack)

- [ ] **Step 1: Add early return for tap-disabled events as the first check in callback**

In `Mos/ButtonCore/ButtonCore.swift`, the callback should become:

```swift
let buttonEventCallBack: CGEventTapCallBack = { (proxy, type, event, refcon) in
    // Tap 被系统禁用时, 清理活跃绑定状态并直接放行
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        MosInputProcessor.shared.clearActiveBindings()
        return Unmanaged.passUnretained(event)
    }
    // 跳过 Mos 合成事件, 避免 executeCustom 发出的事件被重复处理
    if event.getIntegerValueField(.eventSourceUserData) == MosEventMarker.syntheticCustom {
        return Unmanaged.passUnretained(event)
    }

    // 使用原始 flags 匹配绑定 (不注入虚拟修饰键, 保证匹配准确)
    let mosEvent = MosInputEvent(fromCGEvent: event)
    let result = MosInputProcessor.shared.process(mosEvent)
    switch result {
    case .consumed:
        return nil
    case .passthrough:
        // 注入虚拟修饰键 flags 到 passthrough 的键盘事件
        // 使长按鼠标侧键(绑定到修饰键) + 键盘按键 = 修饰键+按键
        let activeFlags = MosInputProcessor.shared.activeModifierFlags
        if activeFlags != 0 && (type == .keyDown || type == .keyUp) {
            event.flags = CGEventFlags(rawValue: event.flags.rawValue | activeFlags)
        }
        return Unmanaged.passUnretained(event)
    }
}
```

- [ ] **Step 2: Build and verify**

Run: `xcodebuild -scheme Debug -configuration Debug build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

---

### Task 4: Wire up `onRestart` in ScrollCore and nil out interceptors in `disable()`

**Files:**
- Modify: `Mos/ScrollCore/ScrollCore.swift`

- [ ] **Step 1: Set `onRestart` on scroll interceptor after creation**

In `enable()`, add the assignment right after `scrollEventInterceptor` is created (after line 342):

```swift
scrollEventInterceptor = try Interceptor(
    event: scrollEventMask,
    handleBy: scrollEventCallBack,
    listenOn: .cgAnnotatedSessionEventTap,
    placeAt: .tailAppendEventTap,
    for: .defaultTap
)
scrollEventInterceptor?.onRestart = {
    ScrollPoster.shared.stop(.TrackingEnd)
}
```

- [ ] **Step 2: Nil out interceptors in `disable()`**

Replace the `disable()` method (lines 365-376):

```swift
func disable() {
    // Guard
    if !isActive {return}
    isActive = false
    // 停止滚动事件发送器
    ScrollPoster.shared.stop()
    ScrollPoster.shared.stopKeeper()
    // 停止截取事件
    scrollEventInterceptor?.stop()
    hotkeyEventInterceptor?.stop()
    mouseEventInterceptor?.stop()
    // 显式释放, 避免旧 tap 残留在对象图中
    scrollEventInterceptor = nil
    hotkeyEventInterceptor = nil
    mouseEventInterceptor = nil
}
```

- [ ] **Step 3: Build and verify**

Run: `xcodebuild -scheme Debug -configuration Debug build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

---

### Task 5: Observe permission-loss notification in AppDelegate, make sessionDidActive permission-aware

**Files:**
- Modify: `Mos/AppDelegate.swift`

- [ ] **Step 1: Add observer in `applicationWillFinishLaunching`**

Add at the end of `applicationWillFinishLaunching` (after the screen change observer, around line 67):

```swift
// 监听辅助功能权限在运行时被撤销
NotificationCenter.default.addObserver(
    self,
    selector: #selector(handleAccessibilityPermissionLost),
    name: .mosAccessibilityPermissionLost,
    object: nil
)
```

- [ ] **Step 2: Add the permission-loss handler (after `sessionDidResign`, around line 136)**

This handler is designed to be idempotent — multiple Interceptors may post the notification simultaneously, and the `isActive` guard ensures only the first invocation runs the cleanup.

```swift
// 辅助功能权限在运行时被撤销 (可能由多个 Interceptor 同时触发, 此方法必须幂等)
@objc func handleAccessibilityPermissionLost() {
    // 避免多个 Interceptor 同时触发导致重复处理
    guard ScrollCore.shared.isActive || ButtonCore.shared.isActive else { return }
    NSLog("Accessibility permission lost at runtime, disabling cores")
    LogitechHIDManager.shared.stop()
    ScrollCore.shared.disable()
    ButtonCore.shared.disable()
    Toast.show(
        NSLocalizedString("Accessibility permission lost, Mos has been paused", comment: ""),
        style: .warning,
        duration: 5.0
    )
    // 启动定时器检测权限恢复
    Timer.scheduledTimer(
        timeInterval: 2.0,
        target: self,
        selector: #selector(startWithAccessibilityPermissionsChecker(_:)),
        userInfo: nil,
        repeats: true
    )
}
```

- [ ] **Step 3: Make `sessionDidActive` permission-aware**

Replace `sessionDidActive` (around line 127-131) to avoid the "enable → immediately discover no permission → disable" thrash:

```swift
@objc func sessionDidActive(notification: NSNotification){
    startWithAccessibilityPermissionsChecker(nil)
}
```

This reuses the existing permission-check-then-enable logic, which will poll if permissions are missing and enable when they become available.

- [ ] **Step 4: Build and verify**

Run: `xcodebuild -scheme Debug -configuration Debug build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit all changes**

```bash
git add Mos/Utils/Interceptor.swift Mos/Utils/Constants.swift Mos/ButtonCore/ButtonCore.swift Mos/ScrollCore/ScrollCore.swift Mos/AppDelegate.swift
git commit -m "fix: prevent system input block when accessibility permission revoked at runtime

Interceptor.start() now checks AXIsProcessTrusted() and throws if
permissions are missing, preventing zombie taps from being created.
The keeper timer and restart() also check permissions and post a
notification to gracefully disable all cores and inform the user.

Decouples ScrollPoster.stop() from Interceptor via onRestart closure.
Adds tapDisabledByUserInput handling to ButtonCore callback.
Makes sessionDidActive permission-aware to avoid enable/disable thrash."
```

---

## Verification Checklist

After implementation, manually test these scenarios:

1. **Normal operation**: Grant accessibility permissions → Mos works normally (smooth scroll, button bindings)
2. **Permission revocation**: While Mos is running, go to System Settings → Privacy & Security → Accessibility → toggle Mos OFF
   - Expected: System input remains fully functional (keyboard, mouse clicks, scroll all work)
   - Expected: Toast notification appears saying accessibility permission was lost
   - Expected: Console shows "Accessibility permission lost at runtime, disabling cores"
3. **Permission restoration**: Toggle Mos back ON in System Settings
   - Expected: Mos automatically resumes operation (smooth scroll returns)
4. **Session switch**: Switch users and back → Mos should re-enable normally (with permission check)
5. **Sleep/wake**: Sleep and wake → Mos should re-enable normally
6. **tapDisabledByTimeout recovery**: Normal timeout recovery should still work when permissions are present
7. **Localization**: Verify the toast string appears in Xcode's String Catalog after build (auto-extracted by Xcode from `NSLocalizedString`)

---

## Design Decisions

1. **Why `start()` throws instead of silently returning?** If `start()` just returned, `Interceptor.init` would appear to succeed even though the tap was never enabled. The caller would store a zombie interceptor. Throwing makes the init fail cleanly and prevents downstream initialization of resources like `ScrollPoster`. The notification is posted before throwing so AppDelegate can clean up regardless.

2. **Why three check locations (start, restart, keeper)?** Defense in depth closing all paths:
   - `start()` closes the 0.5s window between `restart()` scheduling and actual tap enable
   - `restart()` prevents scheduling the restart timer when permissions are clearly gone
   - keeper timer catches the 5-second periodic check before even calling `restart()`

3. **Why `onRestart` closure instead of hard-coded ScrollPoster?** `Interceptor` is a generic event tap wrapper used by both ScrollCore and ButtonCore. Hard-coding `ScrollPoster.shared.stop(.TrackingEnd)` means ButtonCore's tap restarts would needlessly stop smooth scrolling. The closure keeps Interceptor decoupled.

4. **Why post NotificationCenter instead of calling AppDelegate directly?** Decoupling — Interceptor doesn't need to know about AppDelegate or UI. Multiple Interceptors can independently detect the issue, and the handler deduplicates via `isActive` guard (guaranteed correct on main thread).

5. **Why reuse `startWithAccessibilityPermissionsChecker` for both recovery and `sessionDidActive`?** This method already handles the poll-then-enable pattern correctly. Using it for `sessionDidActive` eliminates the enable/disable thrash when waking without permissions.

6. **Why nil out interceptors in `ScrollCore.disable()`?** `ButtonCore.disable()` already does this. Making it consistent ensures old taps don't linger after permission loss + re-enable cycles.

7. **Localization**: Xcode's String Catalog system auto-discovers `NSLocalizedString` keys during build and adds them to `Localizable.xcstrings`. The new toast string will appear as "needs translation" in the catalog after the first build, to be translated by contributors.
