//
//  PreferencesTabViewController.swift
//  Mos
//  偏好设置的 TabViewController 容器
//  Created by Caldis on 2017/1/20.
//  Copyright © 2017年 Caldis. All rights reserved.
//

//  Transition 踩坑指南
//  1. NSTabViewController 的层级构成
//  NSTabViewController - NSView - NSTabView - [tabViewItem]
//  NSTabViewController 的尺寸适应规则
//  由于 NSTabViewController 完全适配了 AutoLayout,
//  如果 tabViewItem 使用了 AutoLayout, 且对应宽或高不存在 ambiguous 的情况下, 由于整个 NSTabViewController 内的 view 都设置了对应的  AutoLayout, 因此, 最终的尺寸将自动 pin 至其 tabViewItem 的大小, 且整个 NSWindow 都会自动 Resize
//  如果 tabViewItem 其没有以 AutoLayout 指定尺寸, 则默认为 500,500
//  2. NSTabViewController 的动画适配
//  2.1 tabViewItem 使用了 AutoLayout
//  在切换 Tab 时, NSTabViewController 使用了 transition(from:to:options:completionHandler:) 方法 (方法可能经过重写, 无法通过对应 Protocol 设定其动画, 只能通过 transitionOptions 参数), 在这种情况下无法触发其 transition 动画, 仅能通过手动触发
//  这里 (在 viewDidAppear 中操作可以利用 View 出现时的自动布局, 避免第一次界面错位) 将 NSTabViewController 下的第一级 NSView 的  constraints 全部移除, 然后手动添加, 仅将其 Pin 至 top 和 left 位置 (设置 top 可以让 size 的 transition 出现在底部), 然后在  tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) 方法中获取当前 tabViewItem 的大小, 将其计算偏移量后 apply  到 NSWindow 上
//  2.2 tabViewItem 没有使用 AutoLayout
//  与上述操作类似, 只需要跳过移除已有的 constraints 步骤即可
//  3. 避免动画切换时窗口底部颜色不一致
//  于 NSTabViewController 下的 NSView 额外叠加一层 NSVisualEffectView, 并固定于界面下方, 避免切换时窗口底部颜色不一致

import Cocoa

class PreferencesTabViewController: NSTabViewController {
    
    let backgroundVisualEffectView = NSVisualEffectView()
    
    override func viewDidAppear() {
        // 移除已有约束
        view.removeConstraints(view.constraints)
        // 将 tabView 固定于界面左上
        tabView.topAnchor.constraint(equalTo: view.topAnchor, constant: 0).isActive = true
        tabView.leftAnchor.constraint(equalTo: view.leftAnchor, constant: 0).isActive = true
        // 额外叠加一层 NSVisualEffectView, 并固定于界面下方, 避免切换时窗口底部颜色不一致
        backgroundVisualEffectView.blendingMode = NSVisualEffectView.BlendingMode.behindWindow
        if #available(OSX 10.14, *) { backgroundVisualEffectView.material = NSVisualEffectView.Material.toolTip }
        view.addSubview(backgroundVisualEffectView, positioned: NSWindow.OrderingMode.below, relativeTo: tabView)
        backgroundVisualEffectView.frame.size = NSSize(width: 1000, height: 1000) // 只要比预期内容大就行, 不会有额外占用
        backgroundVisualEffectView.leftAnchor.constraint(equalTo: view.leftAnchor, constant: 0).isActive = true
        backgroundVisualEffectView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: 0).isActive = true        
    }

    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        // Tab 切换后同步窗口尺寸
        if let currentWindow = view.window, let currentContentView = tabView.subviews.first {
            let windowSize = currentWindow.frame.size
            let contentSize = currentContentView.frame.size
            let heightDiff = contentSize.height + TOOLBAR_HEIGHT + MACOS_TAHOE_COMPENSATE - windowSize.height
            let targetOrigin = NSPoint(x: currentWindow.frame.origin.x, y: currentWindow.frame.origin.y - heightDiff)
            let targetSize = NSSize(width: contentSize.width, height: contentSize.height + TOOLBAR_HEIGHT + MACOS_TAHOE_COMPENSATE)
            let targetRect = NSRect(origin: targetOrigin, size: targetSize)
            Utils.groupAnimatorContainer({(context) in
                currentWindow.setFrame(targetRect, display: true)
            })
        }
    }
}
