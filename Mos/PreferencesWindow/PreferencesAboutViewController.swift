//
//  PreferencesAboutViewController.swift
//  Mos
//  关于界面
//  Created by Caldis on 2017/1/21.
//  Copyright © 2017年 Caldis. All rights reserved.
//

import Cocoa

class PreferencesAboutViewController: NSViewController {
    
    @IBOutlet weak var homePageButton: NSButtonCell!
    @IBOutlet weak var githubButton: NSButton!
    @IBOutlet weak var donateButton: NSButton!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // 设置按钮文字颜色
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        homePageButton.attributedTitle = NSAttributedString(string: homePageButton.title, attributes: [NSAttributedStringKey.foregroundColor : NSColor.white, NSAttributedStringKey.paragraphStyle : paragraphStyle])
        githubButton.attributedTitle = NSAttributedString(string: githubButton.title, attributes: [NSAttributedStringKey.foregroundColor : NSColor.white, NSAttributedStringKey.paragraphStyle : paragraphStyle])
        donateButton.attributedTitle = NSAttributedString(string: donateButton.title, attributes: [NSAttributedStringKey.foregroundColor : NSColor.white, NSAttributedStringKey.paragraphStyle : paragraphStyle])
    }
    
    // 主页
    @IBAction func homepageButtonClick(_ sender: NSButton) {
        let homePageUrl = "http://mos.caldis.me"
        NSWorkspace.shared.open(URL(string:homePageUrl)!)
    }
    // 项目
    @IBAction func githubButtonClick(_ sender: NSButton) {
        NSWorkspace.shared.open(URL(string: "https://github.com/Caldis/Mos")!)
    }
    // 帮助
    @IBAction func helpButtonClick(_ sender: NSButton) {
        NSWorkspace.shared.open(URL(string: "https://github.com/Caldis/Mos/wiki")!)
    }
    // 欢迎
    @IBAction func welcomeWindowButtonClick(_ sender: NSButton) {
        WindowManager.shared.showWindow(withIdentifier: WindowManager.shared.identifier.welcomeWindowController, withTitle: "")
    }
    
}
