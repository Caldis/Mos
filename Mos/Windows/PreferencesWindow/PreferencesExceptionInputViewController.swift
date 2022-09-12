//
//  PreferencesExceptionInputViewController.swift
//  Mos
//  自定义例外应用输入面板
//  Created by Caldis on 2019/10/24.
//  Copyright © 2019 Caldis. All rights reserved.
//

import Cocoa

class PreferencesExceptionInputViewController: NSViewController, NSTextFieldDelegate {
    
    // UI Elements
    @IBOutlet weak var applicationNameTextField: NSTextField!
    @IBOutlet weak var bundleIdTextField: NSTextField!
    @IBOutlet weak var confirmButton: NSButton!
    
    override func viewDidLoad() {
        applicationNameTextField.delegate = self
        bundleIdTextField.delegate = self
    }
    
    @IBAction func applicationNameTextFieldChange(_ sender: NSTextField) {
        submit()
    }
    @IBAction func bundleIdTextFieldChange(_ sender: NSTextField) {
        submit()
    }
    
    @IBAction func cancelClick(_ sender: NSButton) {
        dismiss(nil)
    }
    @IBAction func confirmClick(_ sender: NSButton) {
        submit()
    }
}

extension PreferencesExceptionInputViewController {
    
    // 数据变化同步按钮状态
    func controlTextDidChange(_ obj: Notification) {
        let name = applicationNameTextField.stringValue
        let bundleId = bundleIdTextField.stringValue
        if name.count>0 && bundleId.count>0 {
            confirmButton.isEnabled = true
        } else {
            confirmButton.isEnabled = false
        }
    }
    // 提交数据
    func submit() {
        if confirmButton.isEnabled {
            // 防止重复点击
            confirmButton.isEnabled = false
            // 回传数据
//            if let presenting = presentingViewController as? PreferencesExceptionViewController {
//                presenting.appendApplicationWith(name:applicationNameTextField.stringValue, bundleId:bundleIdTextField.stringValue)
//                dismiss(nil)
//            }
        }
    }
    
}
