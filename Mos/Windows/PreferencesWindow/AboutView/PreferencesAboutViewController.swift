//
//  PreferencesAboutViewController.swift
//  Mos
//  关于界面
//  Created by Caldis on 2017/1/21.
//  Copyright © 2017年 Caldis. All rights reserved.
//

import Cocoa

class PreferencesAboutViewController: NSViewController {
    
    // UI Elements
    @IBOutlet weak var homePageButton: NSButtonCell!
    @IBOutlet weak var githubButton: NSButton!
    @IBOutlet weak var donateButton: NSButton!
    // Constants
    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")!
    
    // 主页
    @IBAction func homepageButtonClick(_ sender: NSButton) {
        let homePageUrl = "http://mos.caldis.me?from=MosApplication&version=\(version as! String)"
        NSWorkspace.shared.open(URL(string:homePageUrl)!)
    }
    // 项目
    @IBAction func githubButtonClick(_ sender: NSButton) {
        NSWorkspace.shared.open(URL(string: "https://github.com/Caldis/Mos?from=MosApplication&version=\(version as! String)")!)
    }
    // 贡献
    @IBAction func contributorsListClick(_ sender: NSButtonCell) {
        NSWorkspace.shared.open(URL(string: "https://github.com/Caldis/Mos/graphs/contributors?from=MosApplication&version=\(version as! String)")!)
    }
    // 帮助
    @IBAction func helpButtonClick(_ sender: NSButton) {
        NSWorkspace.shared.open(URL(string: "https://github.com/Caldis/Mos/wiki?from=MosApplication&version=\(version as! String)")!)
    }
    // 欢迎
    @IBAction func welcomeWindowButtonClick(_ sender: NSButton) {
        // 显示窗口
        WindowManager.shared.showWindow(withIdentifier: WINDOW_IDENTIFIER.introductionWindowController, withTitle: "")
        // 设置为手动打开标识，避免权限检查导致窗口自动关闭
        if let windowController = WindowManager.shared.refs[WINDOW_IDENTIFIER.introductionWindowController] as? IntroductionWindowController,
           let viewController = windowController.contentViewController as? IntroductionViewController {
            viewController.setManuallyOpened(true)
        }
    }
    
}
