//
//  PreferencesButtonsViewController.swift
//  Mos
//  按钮绑定配置界面
//  Created by Claude on 2025/8/10.
//  Copyright © 2025年 Caldis. All rights reserved.
//

import Cocoa

class PreferencesButtonsViewController: NSViewController {
    
    // MARK: - UI Elements
    // 表格
    @IBOutlet weak var tableHead: NSVisualEffectView!
    @IBOutlet weak var tableEmpty: NSView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // 读取设置
        syncViewWithOptions()
    }
}

/**
 * 设置同步
 **/
extension PreferencesButtonsViewController {
    // 同步界面与设置
    func syncViewWithOptions() {
        // TODO: 实现按钮相关设置的同步逻辑
    }
}

/**
 * 表格区域渲染及操作
 **/
extension PreferencesButtonsViewController {
    // 切换无数据显示
    func toggleNoDataHint(animate: Bool = true) {
//        let hasData = Options.shared.application.applications.count != 0
//        if animate {
//            tableEmpty.isHidden = hasData
//            tableEmpty.animator().alphaValue = hasData ? 0 : 1
//            tableHead.isHidden = !hasData
//            tableHead.animator().alphaValue = hasData ? 1 : 0
//        } else {
//            tableEmpty.isHidden = hasData
//            tableEmpty.alphaValue = hasData ? 0 : 1
//            tableHead.isHidden = !hasData
//            tableHead.alphaValue = hasData ? 1 : 0
//        }
    }
}
