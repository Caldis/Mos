//
//  Tween.swift
//  Mos
//
//  Created by Xiaojun Zhou on 2024/4/29.
//  Copyright © 2024 Caldis. All rights reserved.
//

import Cocoa

class Tween: NSObject {
    class func easeOutExpo(x: Double) -> Double {
        return x == 1 ? 1 : 1 - pow(2, -10 * x)
    }
}
