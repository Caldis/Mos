//
//  PreferencesAboutViewController.swift
//  Mos
//
//  Created by Cb on 2017/1/21.
//  Copyright © 2017年 Cb. All rights reserved.
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
    
    @IBAction func homepageButtonClick(_ sender: NSButton) {
        let homePageUrl = ScrollCore.appLanguageIsCN ? "http://mos.u2sk.com/indexCN.html" : "http://mos.u2sk.com"
        NSWorkspace.shared.open(URL(string:homePageUrl)!)
    }
    @IBAction func githubButtonClick(_ sender: NSButton) {
        NSWorkspace.shared.open(URL(string: "https://github.com/Caldis/Mos")!)
    }
    @IBAction func helpButtonClick(_ sender: NSButton) {
        NSWorkspace.shared.open(URL(string: "https://github.com/Caldis/Mos/wiki")!)
    }
}
