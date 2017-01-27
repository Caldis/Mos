//
//  PreferencesAboutViewController.swift
//  Mos
//
//  Created by Cb on 2017/1/21.
//  Copyright © 2017年 Cb. All rights reserved.
//

import Cocoa

class PreferencesAboutViewController: NSViewController {

    // 国际化相关
    let HomePageButtonTitle = NSLocalizedString("HomePage", comment: "")
    let GithubButtonTitle = NSLocalizedString("Github", comment: "")
    let DonateButtonTitle = NSLocalizedString("Donate", comment: "")
    
    @IBOutlet weak var homePageButton: NSButtonCell!
    @IBOutlet weak var githubButton: NSButton!
    @IBOutlet weak var donateButton: NSButton!
    @IBOutlet weak var helpButton: NSButton!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // 设置按钮属性
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        homePageButton.attributedTitle = NSAttributedString(string: HomePageButtonTitle, attributes: [NSForegroundColorAttributeName : NSColor.white, NSParagraphStyleAttributeName : paragraphStyle])
        githubButton.attributedTitle = NSAttributedString(string: GithubButtonTitle, attributes: [NSForegroundColorAttributeName : NSColor.white, NSParagraphStyleAttributeName : paragraphStyle])
        donateButton.attributedTitle = NSAttributedString(string: DonateButtonTitle, attributes: [NSForegroundColorAttributeName : NSColor.white, NSParagraphStyleAttributeName : paragraphStyle])
    }
    
    @IBAction func homepageButtonClick(_ sender: NSButton) {
        NSWorkspace.shared().open(URL(string: "https://github.com/Caldis/Mos")!)
    }
    @IBAction func githubButtonClick(_ sender: NSButton) {
        NSWorkspace.shared().open(URL(string: "https://github.com/Caldis/Mos")!)
    }
}
