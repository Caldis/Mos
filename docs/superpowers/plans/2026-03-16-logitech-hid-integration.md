# Logitech HID++ 2.0 Hardware Button Integration Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Logitech HID++ 2.0 hardware button identification to Mos, allowing users to bind Logitech-specific buttons (gesture, DPI, etc.) to system shortcuts.

**Architecture:** Introduce MosInputEvent abstraction layer (Mode C) that unifies CGEventTap and HID++ event sources. Both sources feed into MosInputProcessor independently. LogitechHIDManager communicates with Logitech devices via IOKit HIDManager and HID++ 2.0 protocol.

**Tech Stack:** Swift, IOKit (IOHIDManager), HID++ 2.0 protocol, existing Mos Interceptor/ButtonCore/KeyRecorder infrastructure.

**Spec:** `docs/superpowers/specs/2026-03-16-logitech-hid-integration-design.md`

**Important:** This is a macOS Xcode project (Mos.xcodeproj). New .swift files must be added to the Xcode project's target. After creating each new file, run `open Mos.xcodeproj` and add it via File > Add Files, or use the `ruby` script in the verification step. macOS Deployment Target is 10.13+.

---

## File Structure

### New Files

| File | Directory | Responsibility |
|------|-----------|----------------|
| `MosInputEvent.swift` | `Mos/InputEvent/` | MosInputEvent struct, MosInputPhase, MosInputSource, MosInputDevice, DeviceFilter, LogitechCIDMap |
| `MosInputProcessor.swift` | `Mos/InputEvent/` | MosInputProcessor singleton, MosInputResult enum |
| `LogitechHIDManager.swift` | `Mos/LogitechHID/` | IOKit HIDManager wrapper, device enumeration, lifecycle, notification constants |
| `LogitechDeviceSession.swift` | `Mos/LogitechHID/` | HID++ 2.0 protocol: feature discovery, button divert, report parsing, event dispatch |

### Modified Files

| File | Key Changes |
|------|-------------|
| `Mos/Windows/PreferencesWindow/ButtonsView/RecordedEvent.swift` | Add `deviceFilter` to RecordedEvent, add `matchesMosInput()`, add `init(from: MosInputEvent)`, add `ScrollHotkey.init(from: MosInputEvent)` |
| `Mos/Keys/KeyCode.swift` | Add Logitech button code display mappings (1000+ range) |
| `Mos/ButtonCore/ButtonCore.swift` | Refactor callback to use MosInputProcessor |
| `Mos/Keys/KeyRecorder.swift` | Change delegate protocol from @objc to Swift protocol, add HID++ event listening during recording, update handleRecordedEvent for dual-source |
| `Mos/Windows/PreferencesWindow/ButtonsView/PreferencesButtonsViewController.swift` | Update delegate method signatures from CGEvent to MosInputEvent |
| `Mos/Windows/PreferencesWindow/ScrollingView/PreferencesScrollingViewController.swift` | Update delegate method signatures from CGEvent to MosInputEvent |
| `Mos/AppDelegate.swift` | Add LogitechHIDManager start/stop lifecycle calls |

---

## Chunk 1: Data Model Layer

### Task 1: Create MosInputEvent

**Files:**
- Create: `Mos/InputEvent/MosInputEvent.swift`

- [ ] **Step 1: Create directory and file**

```bash
mkdir -p /Users/caldis/Desktop/Code/Mos/Mos/InputEvent
```

Write `Mos/InputEvent/MosInputEvent.swift`:

```swift
//
//  MosInputEvent.swift
//  Mos
//  统一输入事件 - 抽象 CGEventTap 和 HID++ 两种事件源
//  Created by Mos on 2026/3/16.
//  Copyright © 2026 Caldis. All rights reserved.
//

import Cocoa

// MARK: - MosInputPhase
/// 事件阶段
enum MosInputPhase {
    case down
    case up
}

// MARK: - MosInputSource
/// 事件来源 - 携带源头特有的数据
/// 注意: 因为 cgEvent 关联值包含 CGEvent (非 Codable), MosInputEvent 整体不可序列化
/// 只有从中提取的 RecordedEvent 走持久化路径
enum MosInputSource {
    /// 来自 CGEventTap, 携带原始 CGEvent 用于 pass-through/consume
    case cgEvent(CGEvent)
    /// 来自 Logitech HID++ 协议
    case hidPlusPlus
}

// MARK: - MosInputDevice
/// 设备信息 (可序列化, 用于 DeviceFilter 匹配和 UI 展示)
struct MosInputDevice: Codable, Equatable {
    let vendorId: UInt16      // USB Vendor ID (Logitech = 0x046D)
    let productId: UInt16     // USB Product ID
    let name: String          // 人类可读名称 (如 "MX Master 3S")
}

// MARK: - DeviceFilter
/// 设备过滤器 - 用于 ButtonBinding 中限制触发设备
struct DeviceFilter: Codable, Equatable {
    let vendorId: UInt16?     // nil = 不限厂商
    let productId: UInt16?    // nil = 不限型号

    func matches(_ device: MosInputDevice?) -> Bool {
        guard let device = device else { return false }
        if let vid = vendorId, vid != device.vendorId { return false }
        if let pid = productId, pid != device.productId { return false }
        return true
    }
}

// MARK: - LogitechCIDMap
/// Logitech CID -> Mos 按钮码映射
/// 标准 CGEvent 鼠标按钮: 0~31, Logitech HID++ 专有: 1000+
struct LogitechCIDMap {
    private static let cidToCode: [UInt16: UInt16] = [
        0x00C3: 1000,  // Gesture Button
        0x00C4: 1001,  // SmartShift
        0x00D7: 1002,  // DPI Change Button
    ]

    static func toMosCode(_ cid: UInt16) -> UInt16 {
        if let known = cidToCode[cid] { return known }
        let mapped = UInt32(2000) + UInt32(cid)
        return mapped <= UInt32(UInt16.max) ? UInt16(mapped) : UInt16(cid & 0x0FFF) + 2000
    }

    static func displayName(forCode code: UInt16) -> String {
        switch code {
        case 1000: return "Gesture"
        case 1001: return "SmartShift"
        case 1002: return "DPI"
        default:   return "Logi(\(code))"
        }
    }

    /// 判断按钮码是否属于 Logitech HID++ 专有范围
    static func isLogitechCode(_ code: UInt16) -> Bool {
        return code >= 1000
    }
}

// MARK: - MosInputEvent
/// 统一输入事件 (运行时对象, 不可序列化)
struct MosInputEvent {
    let type: EventType           // .keyboard 或 .mouse (复用现有枚举)
    let code: UInt16              // 按键码 / 按钮码
    let modifiers: CGEventFlags   // 修饰键状态
    let phase: MosInputPhase      // 按下 / 抬起
    let source: MosInputSource    // 事件来源
    let device: MosInputDevice?   // 设备信息 (CGEventTap 来源为 nil)

    /// 从 CGEvent 构造
    /// 注意: .flagsChanged 事件也属于键盘域 (修饰键按下/抬起), 必须和 keyDown/keyUp 同类处理
    /// 这与 ScrollHotkey.init(from: CGEvent) 和 RecordedEvent.init(from: CGEvent) 中的判断一致
    init(fromCGEvent event: CGEvent) {
        if event.isKeyboardEvent || event.type == .flagsChanged {
            self.type = .keyboard
            self.code = event.keyCode
        } else {
            self.type = .mouse
            self.code = event.mouseCode
        }
        self.modifiers = event.flags
        self.phase = event.isKeyDown ? .down : .up
        self.source = .cgEvent(event)
        self.device = nil
    }

    /// 从 HID++ 数据构造
    init(type: EventType, code: UInt16, modifiers: CGEventFlags,
         phase: MosInputPhase, source: MosInputSource, device: MosInputDevice?) {
        self.type = type
        self.code = code
        self.modifiers = modifiers
        self.phase = phase
        self.source = source
        self.device = device
    }

    // MARK: - Display

    /// 构造展示用名称组件
    var displayComponents: [String] {
        var components: [String] = []
        // 修饰键
        if modifiers.rawValue & CGEventFlags.maskShift.rawValue != 0 { components.append("⇧") }
        if modifiers.rawValue & CGEventFlags.maskControl.rawValue != 0 { components.append("⌃") }
        if modifiers.rawValue & CGEventFlags.maskAlternate.rawValue != 0 { components.append("⌥") }
        if modifiers.rawValue & CGEventFlags.maskCommand.rawValue != 0 { components.append("⌘") }
        // 按键名称
        switch type {
        case .keyboard:
            components.append(KeyCode.keyMap[code] ?? "Key(\(code))")
        case .mouse:
            if LogitechCIDMap.isLogitechCode(code) {
                components.append(LogitechCIDMap.displayName(forCode: code))
            } else {
                components.append(KeyCode.mouseMap[code] ?? "Mouse(\(code))")
            }
        }
        return components
    }

    /// 是否为键盘事件
    var isKeyboardEvent: Bool { type == .keyboard }

    /// 是否为鼠标事件
    var isMouseEvent: Bool { type == .mouse }

    /// 是否有修饰键
    var hasModifiers: Bool {
        return modifiers.rawValue & KeyCode.modifiersMask != 0
    }

    /// 事件是否可录制 (combination 模式)
    var isRecordable: Bool {
        switch type {
        case .keyboard:
            if KeyCode.functionKeys.contains(code) { return true }
            if !hasModifiers { return false }
            return true
        case .mouse:
            if LogitechCIDMap.isLogitechCode(code) { return true }
            if KeyCode.mouseMainKeys.contains(code) { return hasModifiers }
            return true
        }
    }

    /// 事件是否可录制 (singleKey 模式)
    /// 注意: 修饰键 (.flagsChanged) 只在 key-down 时录制, key-up 忽略
    /// 这与原 KeyRecorder.isRecordableAsSingleKey 中 event.isKeyDown && event.isModifiers 逻辑一致
    var isRecordableAsSingleKey: Bool {
        switch type {
        case .keyboard:
            if KeyCode.modifierKeys.contains(code) {
                return phase == .down
            }
            return true
        case .mouse:
            if KeyCode.mouseMainKeys.contains(code) { return false }
            return true
        }
    }
}
```

- [ ] **Step 2: Verify file compiles**

```bash
cd /Users/caldis/Desktop/Code/Mos && xcodebuild -project Mos.xcodeproj -scheme Mos -configuration Debug build 2>&1 | tail -5
```

Note: The file must first be added to Xcode project. If building from CLI fails because the file isn't in the project, add it manually or verify syntax by checking for obvious errors.

- [ ] **Step 3: Commit**

```bash
git add Mos/InputEvent/MosInputEvent.swift
git commit -m "feat: add MosInputEvent unified input event abstraction"
```

---

### Task 2: Create MosInputProcessor

**Files:**
- Create: `Mos/InputEvent/MosInputProcessor.swift`

- [ ] **Step 1: Write MosInputProcessor**

```swift
//
//  MosInputProcessor.swift
//  Mos
//  统一事件处理器 - 接收 MosInputEvent, 匹配 ButtonBinding, 执行动作
//  Created by Mos on 2026/3/16.
//  Copyright © 2026 Caldis. All rights reserved.
//

import Cocoa

// MARK: - MosInputResult
/// 事件处理结果
enum MosInputResult {
    case consumed     // 事件已处理,不再传递
    case passthrough  // 事件未匹配,继续传递
}

// MARK: - MosInputProcessor
/// 统一事件处理器 (无状态单例)
/// 从 ButtonUtils 获取绑定配置, 匹配 MosInputEvent, 执行 ShortcutExecutor
class MosInputProcessor {
    static let shared = MosInputProcessor()
    init() { NSLog("Module initialized: MosInputProcessor") }

    /// 处理输入事件
    /// - Parameter event: 统一输入事件
    /// - Returns: .consumed 表示事件已处理, .passthrough 表示未匹配
    func process(_ event: MosInputEvent) -> MosInputResult {
        // 只处理按下事件 (避免 down+up 触发两次)
        guard event.phase == .down else { return .passthrough }

        let bindings = ButtonUtils.shared.getButtonBindings()
        guard let binding = bindings.first(where: {
            $0.triggerEvent.matchesMosInput(event) && $0.isEnabled
        }) else {
            return .passthrough
        }

        ShortcutExecutor.shared.execute(named: binding.systemShortcutName)
        return .consumed
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add Mos/InputEvent/MosInputProcessor.swift
git commit -m "feat: add MosInputProcessor unified event processor"
```

---

### Task 3: Extend RecordedEvent with MosInputEvent support

**Files:**
- Modify: `Mos/Windows/PreferencesWindow/ButtonsView/RecordedEvent.swift`

- [ ] **Step 1: Add `deviceFilter` field to RecordedEvent**

In `RecordedEvent.swift`, after line 99 (`let displayComponents: [String]`), add:

```swift
    // 设备过滤器 (optional, 向后兼容: 旧数据解码为 nil, 匹配所有设备)
    let deviceFilter: DeviceFilter?
```

- [ ] **Step 2: Add `matchesMosInput` method**

In `RecordedEvent.swift`, after the existing `matches(_ event: CGEvent)` method (line 147), add:

```swift
    /// 匹配 MosInputEvent (供 MosInputProcessor 使用)
    func matchesMosInput(_ event: MosInputEvent) -> Bool {
        // 1. 修饰键匹配
        guard UInt(event.modifiers.rawValue) == modifiers else { return false }
        // 2. 类型匹配
        guard event.type == type else { return false }
        // 3. 按键码匹配
        switch type {
        case .keyboard:
            guard event.phase == .down else { return false }
            guard code == event.code else { return false }
        case .mouse:
            guard code == event.code else { return false }
        }
        // 4. 设备过滤 (可选)
        if let filter = deviceFilter {
            guard filter.matches(event.device) else { return false }
        }
        return true
    }
```

- [ ] **Step 3: Add `init(from: MosInputEvent)` constructor**

After the existing `init(from event: CGEvent)` (line 127), add:

```swift
    /// 从 MosInputEvent 构造
    init(from event: MosInputEvent, deviceFilter: DeviceFilter? = nil) {
        self.type = event.type
        self.code = event.code
        self.modifiers = UInt(event.modifiers.rawValue)
        self.deviceFilter = deviceFilter
        self.displayComponents = event.displayComponents
    }
```

- [ ] **Step 4: Update existing `init(from event: CGEvent)` to include deviceFilter**

Change the existing CGEvent init to also set `deviceFilter = nil`:

```swift
    init(from event: CGEvent) {
        self.modifiers = UInt(event.flags.rawValue)
        if event.isKeyboardEvent {
            self.type = .keyboard
            self.code = event.keyCode
        } else {
            self.type = .mouse
            self.code = event.mouseCode
        }
        self.displayComponents = event.displayComponents
        self.deviceFilter = nil
    }
```

- [ ] **Step 5: Add `ScrollHotkey.init(from: MosInputEvent)` extension**

At the bottom of the file, add:

```swift
// MARK: - ScrollHotkey + MosInputEvent
extension ScrollHotkey {
    /// 从 MosInputEvent 构造
    init(from event: MosInputEvent) {
        self.type = event.type
        self.code = event.code
    }
}
```

- [ ] **Step 6: Commit**

```bash
git add Mos/Windows/PreferencesWindow/ButtonsView/RecordedEvent.swift
git commit -m "feat: extend RecordedEvent with MosInputEvent support and DeviceFilter"
```

---

### Task 4: Extend KeyCode with Logitech button names

**Files:**
- Modify: `Mos/Keys/KeyCode.swift:157-167`

- [ ] **Step 1: Add Logitech mouse map entries**

In `KeyCode.swift`, extend the `mouseMap` dictionary (line 157) to include Logitech codes. Add after the existing entries (before the closing `]` on line 165):

```swift
        // Logitech HID++ 专有按键
        1000: "Gesture", 1001: "SmartShift", 1002: "DPI",
```

- [ ] **Step 2: Commit**

```bash
git add Mos/Keys/KeyCode.swift
git commit -m "feat: add Logitech HID++ button names to KeyCode map"
```

---

### Task 5: Refactor ButtonCore to use MosInputProcessor

**Files:**
- Modify: `Mos/ButtonCore/ButtonCore.swift:34-50`

- [ ] **Step 1: Replace buttonEventCallBack implementation**

Replace the entire `buttonEventCallBack` closure (lines 34-50) with:

```swift
    let buttonEventCallBack: CGEventTapCallBack = { (proxy, type, event, refcon) in
        let mosEvent = MosInputEvent(fromCGEvent: event)
        let result = MosInputProcessor.shared.process(mosEvent)
        switch result {
        case .consumed:
            return nil
        case .passthrough:
            return Unmanaged.passUnretained(event)
        }
    }
```

- [ ] **Step 2: Verify existing button bindings still work**

Build and run. Test that existing button bindings (e.g., mouse button 3 -> Mission Control) still trigger correctly. The behavior should be identical to before.

- [ ] **Step 3: Commit**

```bash
git add Mos/ButtonCore/ButtonCore.swift
git commit -m "refactor: ButtonCore callback uses MosInputProcessor"
```

---

### Task 6: Refactor KeyRecorder delegate and recording

**Files:**
- Modify: `Mos/Keys/KeyRecorder.swift`

This is the most complex modification. Three changes:
1. Delegate protocol: `@objc protocol` -> Swift protocol + extension default
2. `handleRecordedEvent`: support both CGEvent and MosInputEvent from notification
3. Add HID++ event observer during recording

- [ ] **Step 1: Change delegate protocol (lines 21-32)**

Replace:

```swift
@objc protocol KeyRecorderDelegate: AnyObject {
    /// 录制完成回调
    func onEventRecorded(_ recorder: KeyRecorder, didRecordEvent event: CGEvent, isDuplicate: Bool)

    @objc optional func validateRecordedEvent(_ recorder: KeyRecorder, event: CGEvent) -> Bool
}
```

With:

```swift
protocol KeyRecorderDelegate: AnyObject {
    /// 录制完成回调
    func onEventRecorded(_ recorder: KeyRecorder, didRecordEvent event: MosInputEvent, isDuplicate: Bool)

    /// 验证录制的事件是否为重复
    func validateRecordedEvent(_ recorder: KeyRecorder, event: MosInputEvent) -> Bool
}

/// 默认实现 (替代 @objc optional 语义)
extension KeyRecorderDelegate {
    func validateRecordedEvent(_ recorder: KeyRecorder, event: MosInputEvent) -> Bool {
        return true
    }
}
```

- [ ] **Step 2: Add HID++ event observer property (after line 48)**

Add to the private properties section:

```swift
    private var hidEventObserver: NSObjectProtocol?  // HID++ 事件监听 (录制期间)
```

- [ ] **Step 3: Update `startRecording` to add HID++ listener**

At the end of the `do` block in `startRecording` (after the interceptor creation, before `keyPopover = KeyPopover()`), add:

```swift
            // 监听 HID++ 事件 (如果 LogitechHIDManager 已启动)
            hidEventObserver = NotificationCenter.default.addObserver(
                forName: LogitechHIDManager.buttonEventNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let self = self, self.isRecording, !self.isRecorded else { return }
                guard let mosEvent = notification.userInfo?["event"] as? MosInputEvent else { return }
                guard mosEvent.phase == .down else { return }
                NotificationCenter.default.post(
                    name: KeyRecorder.FINISH_NOTI_NAME,
                    object: mosEvent
                )
            }
```

- [ ] **Step 4: Update `stopRecording` to remove HID++ listener**

In `stopRecording()`, after the line removing `CANCEL_NOTI_NAME` observer (line 287), add:

```swift
        if let observer = hidEventObserver {
            NotificationCenter.default.removeObserver(observer)
            hidEventObserver = nil
        }
```

- [ ] **Step 5: Rewrite `handleRecordedEvent` to support dual-source (lines 204-240)**

Replace the entire method:

```swift
    @objc private func handleRecordedEvent(_ notification: NSNotification) {
        guard isRecording else { return }

        // 统一转换为 MosInputEvent
        let mosEvent: MosInputEvent
        if let cgEvent = notification.object as? CGEvent {
            mosEvent = MosInputEvent(fromCGEvent: cgEvent)
        } else if let hidEvent = notification.object as? MosInputEvent {
            mosEvent = hidEvent
        } else {
            NSLog("[EventRecorder] Unknown event type in notification")
            return
        }

        // 检查事件有效性 (根据录制模式)
        let isValid = recordingMode == .singleKey
            ? mosEvent.isRecordableAsSingleKey
            : mosEvent.isRecordable
        guard isValid else {
            NSLog("[EventRecorder] Invalid event ignored")
            keyPopover?.keyPreview.shakeWarning()
            invalidKeyPressCount += 1
            if invalidKeyPressCount >= invalidKeyThreshold {
                keyPopover?.showEscHint()
            }
            return
        }

        guard !isRecorded else { return }
        isRecorded = true

        let isNew = self.delegate?.validateRecordedEvent(self, event: mosEvent) ?? true
        let isDuplicate = !isNew
        let status: KeyPreview.Status = isNew ? .recorded : .duplicate

        keyPopover?.keyPreview
            .update(from: mosEvent.displayComponents, status: status)
        self.delegate?.onEventRecorded(self, didRecordEvent: mosEvent, isDuplicate: isDuplicate)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
            self?.stopRecording()
        }
    }
```

- [ ] **Step 6: Update `handleModifierFlagsChanged` to use MosInputEvent for singleKey recording**

In `handleModifierFlagsChanged` (line 172), the method posts to `FINISH_NOTI_NAME` with a CGEvent. This is fine -- `handleRecordedEvent` now handles both types. No change needed here since it posts a CGEvent that gets converted.

- [ ] **Step 7: Remove the private `isRecordableAsSingleKey` method (lines 249-270)**

This logic is now in `MosInputEvent.isRecordableAsSingleKey`. Delete the method:

```swift
    // DELETE: private func isRecordableAsSingleKey(_ event: CGEvent) -> Bool { ... }
```

- [ ] **Step 8: Commit**

```bash
git add Mos/Keys/KeyRecorder.swift
git commit -m "refactor: KeyRecorder supports MosInputEvent dual-source recording"
```

---

### Task 7: Update PreferencesButtonsViewController delegate

**Files:**
- Modify: `Mos/Windows/PreferencesWindow/ButtonsView/PreferencesButtonsViewController.swift:228-243`

- [ ] **Step 1: Update delegate methods**

Replace the `KeyRecorderDelegate` extension (lines 228-243):

```swift
// MARK: - EventRecorderDelegate
extension PreferencesButtonsViewController: KeyRecorderDelegate {
    func validateRecordedEvent(_ recorder: KeyRecorder, event: MosInputEvent) -> Bool {
        let recordedEvent = RecordedEvent(from: event)
        return !buttonBindings.contains(where: { $0.triggerEvent == recordedEvent })
    }

    func onEventRecorded(_ recorder: KeyRecorder, didRecordEvent event: MosInputEvent, isDuplicate: Bool) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.66) { [weak self] in
            self?.addRecordedEvent(event, isDuplicate: isDuplicate)
        }
    }
}
```

- [ ] **Step 2: Update `addRecordedEvent` method signature (line 92)**

Change from `private func addRecordedEvent(_ event: CGEvent, isDuplicate: Bool)` to:

```swift
    private func addRecordedEvent(_ event: MosInputEvent, isDuplicate: Bool) {
        let recordedEvent = RecordedEvent(from: event)

        if isDuplicate {
            if let existing = buttonBindings.first(where: { $0.triggerEvent == recordedEvent }) {
                highlightExistingRow(with: existing.id)
            }
            return
        }

        let binding = ButtonBinding(triggerEvent: recordedEvent, systemShortcutName: "", isEnabled: false)
        buttonBindings.append(binding)
        tableView.reloadData()
        toggleNoDataHint()
        syncViewWithOptions()
    }
```

- [ ] **Step 3: Commit**

```bash
git add Mos/Windows/PreferencesWindow/ButtonsView/PreferencesButtonsViewController.swift
git commit -m "refactor: PreferencesButtonsViewController uses MosInputEvent"
```

---

### Task 8: Update PreferencesScrollingViewController delegate

**Files:**
- Modify: `Mos/Windows/PreferencesWindow/ScrollingView/PreferencesScrollingViewController.swift:328-347`

- [ ] **Step 1: Update delegate method**

Replace the `KeyRecorderDelegate` extension (lines 328-347):

```swift
// MARK: - KeyRecorderDelegate
extension PreferencesScrollingViewController: KeyRecorderDelegate {
    func onEventRecorded(_ recorder: KeyRecorder, didRecordEvent event: MosInputEvent, isDuplicate: Bool) {
        guard let popup = currentRecordingPopup else { return }

        let hotkey = ScrollHotkey(from: event)

        if popup === dashKeyBindButton {
            getTargetApplicationScrollOptions().dash = hotkey
        } else if popup === toggleKeyBindButton {
            getTargetApplicationScrollOptions().toggle = hotkey
        } else if popup === disableKeyBindButton {
            getTargetApplicationScrollOptions().block = hotkey
        }

        currentRecordingPopup = nil
        syncViewWithOptions()
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add Mos/Windows/PreferencesWindow/ScrollingView/PreferencesScrollingViewController.swift
git commit -m "refactor: PreferencesScrollingViewController uses MosInputEvent"
```

---

### Task 9: Verify all existing functionality

- [ ] **Step 1: Build project**

```bash
cd /Users/caldis/Desktop/Code/Mos && xcodebuild -project Mos.xcodeproj -scheme Mos -configuration Debug build 2>&1 | tail -20
```

Fix any compilation errors.

- [ ] **Step 2: Manual testing checklist**

Run the app and verify:
- Scroll smoothing works as before
- Existing button bindings trigger correctly
- Recording new button bindings works (both combination and singleKey mode)
- Scroll hotkey recording works (dash/toggle/block)
- Per-app scroll settings work
- ESC cancels recording
- Duplicate detection works (blue highlight for repeat bindings)

- [ ] **Step 3: Commit if any fixes were needed**

```bash
git add -A && git commit -m "fix: resolve compilation issues from MosInputEvent migration"
```

---

## Chunk 2: Logitech HID Module

### Task 10: Create LogitechHIDManager

**Files:**
- Create: `Mos/LogitechHID/LogitechHIDManager.swift`

- [ ] **Step 1: Create directory**

```bash
mkdir -p /Users/caldis/Desktop/Code/Mos/Mos/LogitechHID
```

- [ ] **Step 2: Write LogitechHIDManager**

```swift
//
//  LogitechHIDManager.swift
//  Mos
//  Logitech HID 设备管理器 - 通过 IOKit 枚举和监控 Logitech 设备
//  Created by Mos on 2026/3/16.
//  Copyright © 2026 Caldis. All rights reserved.
//

import Foundation
import IOKit
import IOKit.hid

class LogitechHIDManager {
    static let shared = LogitechHIDManager()
    init() { NSLog("Module initialized: LogitechHIDManager") }

    // MARK: - Constants
    static let logitechVendorId: Int = 0x046D
    static let buttonEventNotification = NSNotification.Name("LogitechHIDButtonEvent")

    // MARK: - State
    private var hidManager: IOHIDManager?
    private var sessions: [IOHIDDevice: LogitechDeviceSession] = [:]
    private(set) var isActive = false

    // MARK: - Lifecycle

    func start() {
        guard !isActive else { return }
        NSLog("[LogitechHID] Starting")

        hidManager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        guard let manager = hidManager else {
            NSLog("[LogitechHID] Failed to create IOHIDManager")
            return
        }

        // 只匹配 Logitech 设备
        let matchDict: [String: Any] = [
            kIOHIDVendorIDKey as String: LogitechHIDManager.logitechVendorId
        ]
        IOHIDManagerSetDeviceMatching(manager, matchDict as CFDictionary)

        // 注册回调 (使用 C 函数指针 + context)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, Self.deviceMatchedCallback, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, Self.deviceRemovedCallback, context)

        // Schedule 到 main RunLoop (HID++ 事件低频, 避免线程同步)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)

        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        if result != kIOReturnSuccess {
            NSLog("[LogitechHID] Failed to open IOHIDManager: 0x%08x", result)
            return
        }

        isActive = true
        NSLog("[LogitechHID] Started")
    }

    func stop() {
        guard isActive else { return }
        NSLog("[LogitechHID] Stopping")

        // 清理所有设备会话
        for (_, session) in sessions {
            session.teardown()
        }
        sessions.removeAll()

        if let manager = hidManager {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        }
        hidManager = nil
        isActive = false
        NSLog("[LogitechHID] Stopped")
    }

    // MARK: - Device Callbacks (C function pointers)

    private static let deviceMatchedCallback: IOHIDDeviceCallback = { context, result, sender, device in
        guard let context = context else { return }
        let manager = Unmanaged<LogitechHIDManager>.fromOpaque(context).takeUnretainedValue()
        manager.deviceConnected(device)
    }

    private static let deviceRemovedCallback: IOHIDDeviceCallback = { context, result, sender, device in
        guard let context = context else { return }
        let manager = Unmanaged<LogitechHIDManager>.fromOpaque(context).takeUnretainedValue()
        manager.deviceDisconnected(device)
    }

    // MARK: - Device Management

    private func deviceConnected(_ device: IOHIDDevice) {
        // 读取设备信息
        let vendorId = IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? Int ?? 0
        let productId = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int ?? 0
        let productName = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "Unknown"

        NSLog("[LogitechHID] Device connected: %@ (VID: 0x%04X, PID: 0x%04X)", productName, vendorId, productId)

        // 避免重复会话
        guard sessions[device] == nil else { return }

        // 创建会话
        let session = LogitechDeviceSession(hidDevice: device)
        sessions[device] = session
        session.setup()
    }

    private func deviceDisconnected(_ device: IOHIDDevice) {
        guard let session = sessions.removeValue(forKey: device) else { return }
        NSLog("[LogitechHID] Device disconnected: %@", session.deviceInfo.name)
        session.teardown()
    }

    // MARK: - Query

    /// 获取当前已连接的 Logitech 设备列表
    var connectedDevices: [MosInputDevice] {
        return sessions.values.map { $0.deviceInfo }
    }
}
```

- [ ] **Step 3: Commit**

```bash
git add Mos/LogitechHID/LogitechHIDManager.swift
git commit -m "feat: add LogitechHIDManager for IOKit device enumeration"
```

---

### Task 11: Create LogitechDeviceSession

**Files:**
- Create: `Mos/LogitechHID/LogitechDeviceSession.swift`

- [ ] **Step 1: Write LogitechDeviceSession**

```swift
//
//  LogitechDeviceSession.swift
//  Mos
//  单个 Logitech 设备的 HID++ 2.0 通信会话
//  实现 Feature Discovery, Button Divert, 事件解析
//  Created by Mos on 2026/3/16.
//  Copyright © 2026 Caldis. All rights reserved.
//

import Foundation
import IOKit
import IOKit.hid

class LogitechDeviceSession {

    // MARK: - Public
    let hidDevice: IOHIDDevice
    let deviceInfo: MosInputDevice

    // MARK: - HID++ State
    private var featureIndex: [UInt16: UInt8] = [:]
    private var divertedCIDs: Set<UInt16> = []
    private var lastActiveCIDs: Set<UInt16> = []
    private var deviceIndex: UInt8 = 0x01

    // MARK: - Report Buffer
    // 必须用堆指针, Swift Array 是 value type, copy-on-write 时地址会变
    private var reportBufferPtr: UnsafeMutablePointer<UInt8>?
    private static let reportBufferSize = 64

    // MARK: - Async Discovery
    private var pendingDiscovery: [UInt16: (UInt8?) -> Void] = [:]
    private var discoveryTimer: Timer?
    private static let discoveryTimeout: TimeInterval = 5.0

    // MARK: - HID++ Constants
    private static let featureIRoot: UInt16 = 0x0000
    private static let featureReprogV4: UInt16 = 0x1B04
    private static let hidppShortReportId: UInt8 = 0x10
    private static let hidppLongReportId: UInt8 = 0x11
    private static let hidppErrorFeatureIdx: UInt8 = 0xFF

    // MARK: - Init

    init(hidDevice: IOHIDDevice) {
        self.hidDevice = hidDevice
        self.deviceInfo = MosInputDevice(
            vendorId: UInt16(IOHIDDeviceGetProperty(hidDevice, kIOHIDVendorIDKey as CFString) as? Int ?? 0),
            productId: UInt16(IOHIDDeviceGetProperty(hidDevice, kIOHIDProductIDKey as CFString) as? Int ?? 0),
            name: IOHIDDeviceGetProperty(hidDevice, kIOHIDProductKey as CFString) as? String ?? "Unknown"
        )
    }

    deinit {
        reportBufferPtr?.deallocate()
    }

    // MARK: - Setup / Teardown

    func setup() {
        NSLog("[LogitechHID:%@] Setting up session", deviceInfo.name)

        // 分配稳定的 report buffer
        reportBufferPtr = .allocate(capacity: Self.reportBufferSize)
        reportBufferPtr!.initialize(repeating: 0, count: Self.reportBufferSize)

        // 注册 Input Report 回调
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(
            hidDevice,
            reportBufferPtr!,
            Self.reportBufferSize,
            Self.inputReportCallback,
            context
        )

        // Feature Discovery: 查找 REPROG_CONTROLS_V4
        discoverFeature(featureId: Self.featureReprogV4) { [weak self] index in
            guard let self = self, let index = index else {
                NSLog("[LogitechHID] Device does not support REPROG_CONTROLS_V4, skipping button divert")
                return
            }
            self.featureIndex[Self.featureReprogV4] = index
            NSLog("[LogitechHID:%@] REPROG_CONTROLS_V4 at index 0x%02X", self.deviceInfo.name, index)
            self.queryAndDivertButtons(featureIndex: index)
        }
    }

    func teardown() {
        NSLog("[LogitechHID:%@] Tearing down session", deviceInfo.name)
        discoveryTimer?.invalidate()
        discoveryTimer = nil
        pendingDiscovery.removeAll()

        // 取消 divert (恢复按键的默认行为)
        if let reprogIdx = featureIndex[Self.featureReprogV4] {
            for cid in divertedCIDs {
                setControlReporting(featureIndex: reprogIdx, cid: cid, divert: false)
            }
        }
        divertedCIDs.removeAll()
        lastActiveCIDs.removeAll()
    }

    // MARK: - Input Report Callback (C function pointer)

    static let inputReportCallback: IOHIDReportCallback = { context, result, sender, type, reportID, report, reportLength in
        guard let context = context else { return }
        let session = Unmanaged<LogitechDeviceSession>.fromOpaque(context).takeUnretainedValue()
        let data = Array(UnsafeBufferPointer(start: report, count: reportLength))
        session.handleInputReport(data)
    }

    // MARK: - HID++ Send

    private func sendShortRequest(featureIndex: UInt8, functionId: UInt8, params: [UInt8] = []) {
        var report = [UInt8](repeating: 0, count: 7)
        report[0] = Self.hidppShortReportId
        report[1] = deviceIndex
        report[2] = featureIndex
        report[3] = (functionId << 4) | 0x01  // FuncID | SwID
        for (i, p) in params.prefix(3).enumerated() {
            report[4 + i] = p
        }
        let result = IOHIDDeviceSetReport(
            hidDevice,
            IOHIDReportType(kIOHIDReportTypeOutput),
            CFIndex(report[0]),
            report,
            report.count
        )
        if result != kIOReturnSuccess {
            NSLog("[LogitechHID:%@] SetReport failed: 0x%08x", deviceInfo.name, result)
        }
    }

    // MARK: - Feature Discovery

    private func discoverFeature(featureId: UInt16, completion: @escaping (UInt8?) -> Void) {
        let params: [UInt8] = [UInt8(featureId >> 8), UInt8(featureId & 0xFF)]
        sendShortRequest(featureIndex: 0x00, functionId: 0, params: params)
        pendingDiscovery[featureId] = completion

        discoveryTimer?.invalidate()
        discoveryTimer = Timer.scheduledTimer(withTimeInterval: Self.discoveryTimeout, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            if let pending = self.pendingDiscovery.removeValue(forKey: featureId) {
                NSLog("[LogitechHID:%@] Feature discovery timed out for 0x%04X", self.deviceInfo.name, featureId)
                pending(nil)
            }
        }
    }

    // MARK: - Button Divert

    private func queryAndDivertButtons(featureIndex: UInt8) {
        // GetControlCount: function 0
        sendShortRequest(featureIndex: featureIndex, functionId: 0)
        // 响应在 handleInputReport 中处理 (会触发后续的 GetControlInfo + SetControlReporting)
    }

    private func setControlReporting(featureIndex: UInt8, cid: UInt16, divert: Bool) {
        // SetControlReporting: function 3
        // Params: CID_MSB, CID_LSB, flags (bit 0 = divert)
        let flags: UInt8 = divert ? 0x01 : 0x00
        let params: [UInt8] = [UInt8(cid >> 8), UInt8(cid & 0xFF), flags]
        sendShortRequest(featureIndex: featureIndex, functionId: 3, params: params)
        if divert {
            divertedCIDs.insert(cid)
        } else {
            divertedCIDs.remove(cid)
        }
        NSLog("[LogitechHID:%@] CID 0x%04X divert=%@", deviceInfo.name, cid, divert ? "ON" : "OFF")
    }

    // MARK: - Report Parsing

    func handleInputReport(_ report: [UInt8]) {
        guard report.count >= 7 else { return }
        guard report[0] == Self.hidppShortReportId || report[0] == Self.hidppLongReportId else { return }

        let featureIdx = report[2]

        // Error report
        if featureIdx == Self.hidppErrorFeatureIdx {
            let errorCode = report.count > 6 ? report[6] : 0
            NSLog("[LogitechHID:%@] Error report: featureIdx=0x%02X errorCode=0x%02X",
                  deviceInfo.name, report[3], errorCode)
            // 清理对应的 pending discovery
            for (featureId, callback) in pendingDiscovery {
                callback(nil)
                pendingDiscovery.removeValue(forKey: featureId)
            }
            return
        }

        // IRoot response (feature discovery)
        if featureIdx == 0x00 {
            handleDiscoveryResponse(report)
            return
        }

        // REPROG_CONTROLS_V4 events
        if let reprogIdx = featureIndex[Self.featureReprogV4], featureIdx == reprogIdx {
            handleReprogEvent(report)
            return
        }
    }

    private func handleDiscoveryResponse(_ report: [UInt8]) {
        // IRoot.GetFeature response: params[0] = featureIndex, params[1] = featureType
        let discoveredIndex = report[4]

        // 尝试匹配 pending discovery
        // 由于我们发送了 feature ID 作为参数, 这里简化处理: 取第一个 pending
        if let (featureId, callback) = pendingDiscovery.first {
            discoveryTimer?.invalidate()
            pendingDiscovery.removeValue(forKey: featureId)
            if discoveredIndex == 0 {
                // Index 0 = not found
                callback(nil)
            } else {
                callback(discoveredIndex)
            }
        }
    }

    private func handleReprogEvent(_ report: [UInt8]) {
        let functionId = report[3] >> 4

        // divertedButtonsEvent notification (function varies by firmware, typically event index 0)
        // Parse CID pairs from params
        var activeCIDs: Set<UInt16> = []
        var offset = 4
        while offset + 1 < report.count {
            let cid = (UInt16(report[offset]) << 8) | UInt16(report[offset + 1])
            if cid == 0 { break }
            activeCIDs.insert(cid)
            offset += 2
        }

        // 差分检测
        let newlyPressed = activeCIDs.subtracting(lastActiveCIDs)
        let newlyReleased = lastActiveCIDs.subtracting(activeCIDs)
        lastActiveCIDs = activeCIDs

        for cid in newlyPressed {
            dispatchButtonEvent(cid: cid, isDown: true)
        }
        for cid in newlyReleased {
            dispatchButtonEvent(cid: cid, isDown: false)
        }
    }

    // MARK: - Event Dispatch

    private func dispatchButtonEvent(cid: UInt16, isDown: Bool) {
        let currentFlags = CGEventSource.flagsState(.combinedSessionState)

        let mosEvent = MosInputEvent(
            type: .mouse,
            code: LogitechCIDMap.toMosCode(cid),
            modifiers: currentFlags,
            phase: isDown ? .down : .up,
            source: .hidPlusPlus,
            device: deviceInfo
        )

        // 处理事件
        let _ = MosInputProcessor.shared.process(mosEvent)

        // 发送通知 (供 KeyRecorder 录制监听)
        NotificationCenter.default.post(
            name: LogitechHIDManager.buttonEventNotification,
            object: nil,
            userInfo: ["event": mosEvent]
        )
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add Mos/LogitechHID/LogitechDeviceSession.swift
git commit -m "feat: add LogitechDeviceSession for HID++ 2.0 protocol communication"
```

---

### Task 12: Integrate LogitechHIDManager into AppDelegate

**Files:**
- Modify: `Mos/AppDelegate.swift`

- [ ] **Step 1: Add LogitechHIDManager.start() after ButtonCore.enable()**

In `startWithAccessibilityPermissionsChecker` (lines 69-96), add `LogitechHIDManager.shared.start()` after every `ButtonCore.shared.enable()` call.

Line 76 (after first `ButtonCore.shared.enable()`):
```swift
                LogitechHIDManager.shared.start()
```

Line 82 (after second `ButtonCore.shared.enable()`):
```swift
                LogitechHIDManager.shared.start()
```

- [ ] **Step 2: Add LogitechHIDManager.stop() in applicationWillTerminate**

In `applicationWillTerminate` (line 62), add before `ScrollCore.shared.disable()`:
```swift
        LogitechHIDManager.shared.stop()
```

- [ ] **Step 3: Add LogitechHIDManager lifecycle in session callbacks**

In `sessionDidActive` (line 99), add after `ButtonCore.shared.enable()`:
```swift
        LogitechHIDManager.shared.start()
```

In `sessionDidResign` (line 103), add before `ScrollCore.shared.disable()`:
```swift
        LogitechHIDManager.shared.stop()
```

- [ ] **Step 4: Commit**

```bash
git add Mos/AppDelegate.swift
git commit -m "feat: integrate LogitechHIDManager lifecycle into AppDelegate"
```

---

### Task 13: Final build and integration test

- [ ] **Step 1: Ensure all new files are in Xcode project**

New files that must be added to the Mos target in Xcode:
- `Mos/InputEvent/MosInputEvent.swift`
- `Mos/InputEvent/MosInputProcessor.swift`
- `Mos/LogitechHID/LogitechHIDManager.swift`
- `Mos/LogitechHID/LogitechDeviceSession.swift`

- [ ] **Step 2: Full build**

```bash
cd /Users/caldis/Desktop/Code/Mos && xcodebuild -project Mos.xcodeproj -scheme Mos -configuration Debug build 2>&1 | tail -20
```

- [ ] **Step 3: Manual testing - existing features**

- Scroll smoothing: mouse wheel in any app
- Scroll reverse: toggle in preferences
- Button binding: record mouse button 3, bind to Mission Control, verify trigger
- Scroll hotkey: set dash key, verify amplification works
- Per-app settings: add exception for an app, verify independent scroll config
- ESC cancels recording
- Monitor window: verify scroll event visualization

- [ ] **Step 4: Manual testing - Logitech HID (requires Logitech mouse)**

- Check Console.app logs for `[LogitechHID] Device connected: ...`
- If Logitech Options+ is running, quit it first
- Verify gesture button press appears in logs as `[LogitechHID] CID 0x00C3 divert=ON`
- Open Preferences > Buttons, click Add, press gesture button -> should appear as "Gesture"
- Bind gesture button to a system shortcut, verify it triggers

- [ ] **Step 5: Final commit**

```bash
git add -A && git commit -m "feat: complete Logitech HID++ 2.0 hardware button integration"
```
