//
//  Interpolation.swift
//  Mos
//  插值函数集
//  Created by Caldis on 2018/2/19.
//  Copyright © 2018年 Caldis. All rights reserved.
//

import Cocoa

class Interpolation: NSObject {
    
    // Bacic property
    private let step = Options.shared.current.const.fps * Options.shared.current.advanced.duration
    
    // Liner Interpolation
    class func lerp(src: Double, dest: Double) -> Double {
        let x = dest - src
        return x * 0.12 // 1 / Options.shared.current.advanced.duration * 5
    }
    
    // SmoothStep (2rd-order equation)
    class func smoothStep2(src: Double, dest: Double) -> Double {
        let x = src / (dest - src)
        return x * x * (3 - 2 * x)
    }
    
    // SmoothStep (3rd-order equation)
    class func smoothStep3(src: Double, dest: Double) -> Double {
        let x = (dest - src) / dest
        return x * x * x * (x * (x * 6 - 15) + 10)
    }
    
}
