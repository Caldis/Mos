//
//  Tween.swift
//  Mos
//
//  Created by Xiaojun Zhou on 2024/4/29.
//  Copyright © 2024 Caldis. All rights reserved.
//

import Cocoa

class Tween: NSObject {
    class func easeOutQuint(x: Double) -> Double {
        return 1 - pow(1 - x, 5)
    }
}
