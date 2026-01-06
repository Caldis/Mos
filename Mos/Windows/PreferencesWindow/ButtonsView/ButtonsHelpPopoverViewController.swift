//
//  ButtonsHelpPopoverViewController.swift
//  Mos
//  按钮绑定帮助信息弹出窗口
//  Created by Claude on 2025/1/6.
//  Copyright © 2025年 Caldis. All rights reserved.
//

import Cocoa

class ButtonsHelpPopoverViewController: NSViewController {
    
    private var helpTextField: NSTextField!
    
    override func loadView() {
        self.view = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 200))
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }
    
    private func setupUI() {
        helpTextField = NSTextField(wrappingLabelWithString: NSLocalizedString("button.help.message", comment: ""))
        helpTextField.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        helpTextField.textColor = NSColor.labelColor
        helpTextField.alignment = .left
        helpTextField.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(helpTextField)
        
        NSLayoutConstraint.activate([
            helpTextField.topAnchor.constraint(equalTo: view.topAnchor, constant: 10),
            helpTextField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            helpTextField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            helpTextField.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -10),
        ])
    }
}

