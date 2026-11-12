//
//  ModifierFlagsProviding.swift
//  Mos
//  修饰键端口: 解耦 ShortcutExecutor 对 InputProcessor 的具体依赖
//

import Cocoa

/// ShortcutExecutor 合成键鼠事件时, 通过此协议获取 (物理 + 虚拟) 合并修饰键,
/// 不直接依赖 InputProcessor, 从而切断 ShortcutExecutor↔InputProcessor 双向边,
/// 使 executor 仅依赖协议 (配合 ScrollActionPort) 完全无环。
/// InputProcessor 实现此协议, 由启动期 (AppDelegate / 测试 setUp) 注入。
protocol ModifierFlagsProviding: AnyObject {
    func combinedModifierFlags(physicalModifiers: CGEventFlags?) -> CGEventFlags
}
