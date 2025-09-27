//
//  HotkeyListener.swift
//  Mos
//  全局热键监听器 - 监听用户设置的热键并触发对应系统快捷键
//  Created by Claude on 2025/9/27.
//  Copyright © 2025年 Caldis. All rights reserved.
//

import Cocoa

/// 全局热键监听器
class HotkeyListener {

    // MARK: - 单例
    static let shared = HotkeyListener()
    private init() {}

    // MARK: - 私有属性
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var buttonBindings: [ButtonBinding] = []
    private var isListening = false

    // MARK: - 事件掩码
    private let eventMask: CGEventMask =
        (1 << CGEventType.keyDown.rawValue) |
        (1 << CGEventType.leftMouseDown.rawValue) |
        (1 << CGEventType.rightMouseDown.rawValue) |
        (1 << CGEventType.otherMouseDown.rawValue)

    // MARK: - 公共方法

    /// 开始监听热键
    func startListening() {
        guard !isListening else {
            NSLog("[HotkeyListener] 已在监听状态")
            return
        }

        do {
            try createEventTap()
            isListening = true
            NSLog("[HotkeyListener] 开始监听全局热键")
        } catch {
            NSLog("[HotkeyListener] 启动监听失败: \(error)")
        }
    }

    /// 停止监听热键
    func stopListening() {
        guard isListening else {
            NSLog("[HotkeyListener] 未在监听状态")
            return
        }

        destroyEventTap()
        isListening = false
        NSLog("[HotkeyListener] 停止监听全局热键")
    }

    /// 更新按钮绑定列表
    func updateBindings(_ bindings: [ButtonBinding]) {
        self.buttonBindings = bindings.filter { $0.isEnabled }
        NSLog("[HotkeyListener] 更新按钮绑定: \(self.buttonBindings.count) 个")
    }

    /// 添加单个按钮绑定
    func addBinding(_ binding: ButtonBinding) {
        if !buttonBindings.contains(binding) {
            buttonBindings.append(binding)
        }
    }

    /// 移除单个按钮绑定
    func removeBinding(_ binding: ButtonBinding) {
        buttonBindings.removeAll { $0 == binding }
    }

    /// 获取当前监听状态
    var listening: Bool {
        return isListening
    }

    // MARK: - 私有方法

    /// 创建事件拦截器
    private func createEventTap() throws {
        let eventTapCallback: CGEventTapCallBack = { (proxy, type, event, refcon) in
            let listener = Unmanaged<HotkeyListener>.fromOpaque(refcon!).takeUnretainedValue()
            return listener.handleEvent(proxy: proxy, type: type, event: event)
        }

        let selfPtr = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: eventTapCallback,
            userInfo: selfPtr
        )

        guard let eventTap = eventTap else {
            throw NSError(domain: "HotkeyListener", code: 1,
                         userInfo: [NSLocalizedDescriptionKey: "无法创建事件拦截器"])
        }

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)

        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    /// 销毁事件拦截器
    private func destroyEventTap() {
        if let eventTap = eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
            self.eventTap = nil
        }

        if let runLoopSource = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
            self.runLoopSource = nil
        }
    }

    /// 处理事件
    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // 检查是否是我们关心的事件类型
        guard type == .keyDown ||
              type == .leftMouseDown ||
              type == .rightMouseDown ||
              type == .otherMouseDown else {
            return Unmanaged.passUnretained(event)
        }

        // 查找匹配的按钮绑定
        for binding in buttonBindings {
            if binding.triggerEvent.matches(event) {
                // 异步触发系统快捷键，避免阻塞事件处理
                DispatchQueue.global(qos: .userInitiated).async {
                    self.triggerSystemShortcut(binding)
                }
                // 拦截原事件，防止传递给其他应用
                return nil
            }
        }

        // 没有匹配的绑定，让事件继续传递
        return Unmanaged.passUnretained(event)
    }

    /// 触发系统快捷键
    private func triggerSystemShortcut(_ binding: ButtonBinding) {
        guard let shortcut = binding.systemShortcut else {
            NSLog("[HotkeyListener] 无法获取系统快捷键: \(binding.systemShortcutName)")
            return
        }

        NSLog("[HotkeyListener] 执行系统快捷键: \(shortcut.displayName)")

        ShortcutManager.shared.triggerShortcut(shortcut) { success in
            if success {
                NSLog("[HotkeyListener] 快捷键执行成功: \(shortcut.displayName)")
            } else {
                NSLog("[HotkeyListener] 快捷键执行失败: \(shortcut.displayName)")
            }
        }
    }
}

// MARK: - 扩展：方便的绑定管理方法
extension HotkeyListener {

    /// 从 UserDefaults 加载按钮绑定
    func loadBindingsFromUserDefaults() {
        // TODO: 实现从 UserDefaults 加载绑定的逻辑
        NSLog("[HotkeyListener] 从 UserDefaults 加载按钮绑定")
    }

    /// 保存按钮绑定到 UserDefaults
    func saveBindingsToUserDefaults() {
        // TODO: 实现保存绑定到 UserDefaults 的逻辑
        NSLog("[HotkeyListener] 保存按钮绑定到 UserDefaults")
    }
}
