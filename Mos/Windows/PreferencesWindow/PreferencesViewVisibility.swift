//
//  PreferencesViewVisibility.swift
//  Mos
//  偏好设置列表页共用的视图显隐切换 (按键页/应用页的空态提示等)
//

import Cocoa

extension NSViewController {
    /// 淡入淡出切换视图可见性。
    /// 显示: 先取消隐藏再淡入; 隐藏: 动画完成后才真正 isHidden
    /// (若先 isHidden 再动画, 隐藏路径的淡出永远不可见)
    func updateViewVisibility(view: NSView, visible: Bool) {
        if visible {
            view.isHidden = false
            view.animator().alphaValue = 1
        } else {
            NSAnimationContext.runAnimationGroup({ _ in
                view.animator().alphaValue = 0
            }, completionHandler: {
                view.isHidden = true
            })
        }
    }
}
