//
//  HideStatusItemViewController.swift
//  Mos
//  隐藏图标提示窗口
//  Created by Caldis on 2018/3/23.
//  Copyright © 2018年 Caldis. All rights reserved.
//

import Cocoa

class HideStatusItemViewController: NSViewController {
    
    override func viewDidLoad() {
        super.viewDidLoad()
    }
    
    @IBAction func hideStatusItemClick(_ sender: NSButton) {
        // 设置隐藏
        Options.shared.others.hideStatusItem = true
        // 关闭窗口
        WindowManager.shared.refs[WindowManager.shared.identifier.hideStatusItemWindowController]?.close()
    }

    @IBAction func cancelClick(_ sender: NSButton) {
        // 关闭窗口
        WindowManager.shared.refs[WindowManager.shared.identifier.hideStatusItemWindowController]?.close()
    }

}
