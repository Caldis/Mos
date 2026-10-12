// winctl list <所属 App 名称片段>  -> 打印匹配的屏幕窗口 ID 与位置尺寸
// winctl warp <x> <y>           -> 移动光标 (全局显示坐标, 左上角为原点)
// winctl where                  -> 打印当前光标位置
import Foundation
import CoreGraphics
import ApplicationServices
let a = CommandLine.arguments
switch a.count > 1 ? a[1] : "" {
case "list":
    let key = a.count > 2 ? a[2] : ""
    let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    for w in info {
        let owner = w[kCGWindowOwnerName as String] as? String ?? ""
        guard owner.localizedCaseInsensitiveContains(key) else { continue }
        let b = w[kCGWindowBounds as String] as? [String: Double] ?? [:]
        print("id=\(w[kCGWindowNumber as String] ?? 0) layer=\(w[kCGWindowLayer as String] ?? 0) owner=\(owner) name=\(w[kCGWindowName as String] ?? "") x=\(b["X"] ?? 0) y=\(b["Y"] ?? 0) w=\(b["Width"] ?? 0) h=\(b["Height"] ?? 0)")
    }
case "warp":
    CGWarpMouseCursorPosition(CGPoint(x: Double(a[2])!, y: Double(a[3])!))
    CGAssociateMouseAndMouseCursorPosition(1)
case "move":
    // 在 HID tap 投递真实的 mouseMoved, 让该点下方的窗口收到指针进入事件
    let pt = CGPoint(x: Double(a[2])!, y: Double(a[3])!)
    CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: pt, mouseButton: .left)!.post(tap: .cghidEventTap)
case "scroll":
    // winctl scroll <行数> <次数>: 在 HID tap 投递 CGEvent 行滚动 (路线 C 的阳性对照)
    let lines = Int32(a[2])!, n = Int(a[3])!
    for _ in 0..<n {
        CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: lines, wheel2: 0, wheel3: 0)!.post(tap: .cghidEventTap)
        usleep(15_000)
    }
case "key":
    // winctl key <键码> [cmd]: 在 HID tap 投递按键按下与抬起
    let code = CGKeyCode(a[2])!, cmd = a.count > 3 && a[3] == "cmd"
    let src = CGEventSource(stateID: .hidSystemState)
    func post(_ k: CGKeyCode, _ down: Bool, _ flags: CGEventFlags) {
        let e = CGEvent(keyboardEventSource: src, virtualKey: k, keyDown: down)!
        e.flags = flags
        e.post(tap: .cghidEventTap)
        usleep(40_000)
    }
    if cmd { post(55, true, .maskCommand) }
    post(code, true, cmd ? .maskCommand : [])
    post(code, false, cmd ? .maskCommand : [])
    if cmd { post(55, false, []) }
case "pxscroll":
    // winctl pxscroll <像素> <次数> <间隔毫秒>: 在 HID tap 投递连续 (类触控板) 像素滚动
    let px = Int32(a[2])!, n = Int(a[3])!, iv = UInt32(a[4])!
    for _ in 0..<n {
        let e = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: px, wheel2: 0, wheel3: 0)!
        e.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        e.post(tap: .cghidEventTap)
        usleep(iv * 1000)
    }
case "tpswipe":
    // winctl tpswipe <每帧像素> <Changed 个数> <间隔毫秒> <惯性帧数> [mayBegin 0|1]
    // 在 HID tap 投递类触控板的 phased 连续滚动:
    // [MayBegin(128) + 100ms] -> Began(1) -> Changed(2) x N -> Ended(4, 零位移) -> 惯性 1/2../3 (每帧衰减 0.94)
    let dy = Int32(a[2])!, n = Int(a[3])!, iv = UInt32(a[4])!, mom = Int(a[5])!
    let mayBegin = a.count > 6 ? a[6] == "1" : true
    func post(_ d: Int32, phase: Int64, momentum: Int64) {
        let e = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: d, wheel2: 0, wheel3: 0)!
        e.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        e.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
        e.setIntegerValueField(.scrollWheelEventMomentumPhase, value: momentum)
        e.post(tap: .cghidEventTap)
    }
    if mayBegin { post(0, phase: 128, momentum: 0); usleep(100_000) }
    post(dy, phase: 1, momentum: 0); usleep(iv * 1000)
    for _ in 0..<n { post(dy, phase: 2, momentum: 0); usleep(iv * 1000) }
    post(0, phase: 4, momentum: 0)
    if mom > 0 {
        var v = Double(dy)
        usleep(16_000)
        for f in 0..<mom {
            v *= 0.94
            let d = Int32(v.rounded()) == 0 ? (dy < 0 ? -1 : 1) : Int32(v.rounded())
            post(d, phase: 0, momentum: f == 0 ? 1 : 2)
            usleep(16_000)
        }
        post(0, phase: 0, momentum: 3)
    }
case "axdump":
    // winctl axdump <pid>: 打印该 App 辅助功能树中各元素的角色 / 标题 / 值 / 描述 (限制深度)
    let app = AXUIElementCreateApplication(pid_t(a[2])!)
    func attr(_ e: AXUIElement, _ k: String) -> String {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, k as CFString, &v) == .success, let v else { return "" }
        return (v as? String) ?? ""
    }
    func walk(_ e: AXUIElement, _ depth: Int) {
        guard depth < 12 else { return }
        let line = [attr(e, kAXRoleAttribute), attr(e, kAXTitleAttribute), attr(e, kAXValueAttribute), attr(e, kAXDescriptionAttribute)]
            .filter { !$0.isEmpty }.joined(separator: " | ")
        print(String(repeating: "  ", count: depth) + line)
        var kids: CFTypeRef?
        if AXUIElementCopyAttributeValue(e, kAXChildrenAttribute as CFString, &kids) == .success, let arr = kids as? [AXUIElement] {
            for k in arr { walk(k, depth + 1) }
        }
    }
    walk(app, 0)
case "phase":
    // winctl phase <像素> <Changed 个数> <间隔毫秒> <惯性帧数> [选项]
    // 选项 (逗号分隔): maybegin, wc2 (双轴事件, PointDeltaAxis2=-1), fixint (FixedPtDeltaAxis1 按整数 pt*65536/10 写入)
    let pt = Int64(a[2])!, n = Int(a[3])!, iv = UInt32(a[4])!, mom = Int(a[5])!
    let opts = Set((a.count > 6 ? a[6] : "").split(separator: ",").map(String.init))
    let loc = CGEvent(source: nil)!.location
    func post(_ p: Int64, phase: Int64, momentum: Int64) {
        let e = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: opts.contains("wc2") ? 2 : 1,
                        wheel1: 0, wheel2: 0, wheel3: 0)!
        e.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        e.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
        e.setIntegerValueField(.scrollWheelEventMomentumPhase, value: momentum)
        e.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: p)
        if opts.contains("fixint") {
            e.setIntegerValueField(.scrollWheelEventFixedPtDeltaAxis1, value: p * 65536 / 10)
        } else {
            e.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: Double(p) / 10)
        }
        e.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: p < 0 ? -1 : (p > 0 ? 1 : 0))
        if opts.contains("wc2") { e.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: p != 0 ? -1 : 0) }
        e.location = loc
        e.timestamp = CGEventTimestamp(mach_absolute_time())
        e.post(tap: .cghidEventTap)
    }
    if opts.contains("maybegin") { post(0, phase: 128, momentum: 0); usleep(100_000) }
    post(pt, phase: 1, momentum: 0); usleep(iv * 1000)
    for _ in 0..<n { post(pt, phase: 2, momentum: 0); usleep(iv * 1000) }
    post(0, phase: 4, momentum: 0)
    if mom > 0 {
        var v = Double(pt); usleep(16_000)
        for f in 0..<mom {
            v *= 0.94
            let d = Int64(v.rounded()) == 0 ? (pt < 0 ? -1 : 1) : Int64(v.rounded())
            post(d, phase: 0, momentum: f == 0 ? 1 : 2); usleep(16_000)
        }
        post(0, phase: 0, momentum: 3)
    }
case "rawphase":
    // winctl rawphase <阶段> <惯性> <像素>: 在 HID tap 投递单个连续滚动事件 (用于探测或复位状态)
    let e = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: 0, wheel2: 0, wheel3: 0)!
    e.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
    e.setIntegerValueField(.scrollWheelEventScrollPhase, value: Int64(a[2])!)
    e.setIntegerValueField(.scrollWheelEventMomentumPhase, value: Int64(a[3])!)
    e.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: Int64(a[4])!)
    e.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: Double(Int64(a[4])!) / 10)
    e.post(tap: .cghidEventTap)
case "click":
    // winctl click <x> <y>: 在 HID tap 投递一次左键单击
    let pt = CGPoint(x: Double(a[2])!, y: Double(a[3])!)
    for t in [CGEventType.mouseMoved, .leftMouseDown, .leftMouseUp] {
        CGEvent(mouseEventSource: nil, mouseType: t, mouseCursorPosition: pt, mouseButton: .left)!.post(tap: .cghidEventTap)
        usleep(t == .mouseMoved ? 100_000 : 60_000)
    }
case "menu":
    // winctl menu <pid> <标题>: 按下标题完全匹配的第一个菜单项
    let app = AXUIElementCreateApplication(pid_t(a[2])!)
    let want = a[3]
    func find(_ e: AXUIElement, _ depth: Int) -> AXUIElement? {
        guard depth < 8 else { return nil }
        var t: CFTypeRef?
        if AXUIElementCopyAttributeValue(e, kAXTitleAttribute as CFString, &t) == .success, (t as? String) == want { return e }
        var kids: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, kAXChildrenAttribute as CFString, &kids) == .success, let arr = kids as? [AXUIElement] else { return nil }
        for k in arr { if let f = find(k, depth + 1) { return f } }
        return nil
    }
    var bar: CFTypeRef?
    AXUIElementCopyAttributeValue(app, kAXMenuBarAttribute as CFString, &bar)
    if let bar, let item = find(bar as! AXUIElement, 0) { print("press:", AXUIElementPerformAction(item, kAXPressAction as CFString).rawValue) } else { print("not found") }
case "press":
    // winctl press <pid> <标题>: 按下标题或描述完全匹配的第一个窗口按钮
    let app = AXUIElementCreateApplication(pid_t(a[2])!)
    let want = a[3]
    func find(_ e: AXUIElement, _ depth: Int) -> AXUIElement? {
        guard depth < 20 else { return nil }
        var t: CFTypeRef?
        for key in [kAXTitleAttribute, kAXDescriptionAttribute] {
            if AXUIElementCopyAttributeValue(e, key as CFString, &t) == .success, (t as? String) == want { return e }
        }
        var kids: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, kAXChildrenAttribute as CFString, &kids) == .success, let arr = kids as? [AXUIElement] else { return nil }
        for k in arr { if let f = find(k, depth + 1) { return f } }
        return nil
    }
    var wins: CFTypeRef?
    AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &wins)
    let target = (wins as? [AXUIElement] ?? []).lazy.compactMap { find($0, 0) }.first
    if let target { print("press:", AXUIElementPerformAction(target, kAXPressAction as CFString).rawValue) } else { print("not found") }
case "where":
    print(CGEvent(source: nil)!.location)
default:
    print("usage: winctl list <owner> | warp x y | where")
}
