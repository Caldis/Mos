//
//  PopoverViewController.swift
//  Mos
//  弹出面板容器 Popover
//  Created by Caldis on 2018/2/24.
//  Copyright © 2018年 Caldis. All rights reserved.
//

import Foundation

class PopoverViewController: NSViewController {

}


extension PopoverViewController {
    // MARK: Storyboard instantiation
    static func freshController() -> PopoverViewController {
        let storyboard = NSStoryboard(name: NSStoryboard.Name(rawValue: "Main"), bundle: nil)
        let identifier = NSStoryboard.SceneIdentifier(rawValue: "PopoverViewController")
        guard let viewcontroller = storyboard.instantiateController(withIdentifier: identifier) as? PopoverViewController else {
            fatalError("PopoverViewController instantiatily error")
        }
        return viewcontroller
    }
}
