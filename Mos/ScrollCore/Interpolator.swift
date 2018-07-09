//
//  Interpolator.swift
//  Mos
//  插值函数集
//  Created by Caldis on 2018/2/19.
//  Copyright © 2018年 Caldis. All rights reserved.
//

import Cocoa

class Interpolator: NSObject {
    
    // Liner Interpolation
    class func lerp(src: Double, dest: Double) -> Double {
        let x = dest - src
        return x * Options.shared.advanced.durationTransition
    }
    
    // SmoothStep (Need clamp 0-1) (2rd-order equation)
    class func smoothStep2(src: Double, dest: Double) -> Double {
        let x = (dest - src) / dest
        return x * x * (3 - 2 * x)
    }
    
    // SmoothStep (Need clamp 0-1) (3rd-order equation)
    class func smoothStep3(src: Double, dest: Double) -> Double {
        let x = (dest - src) / dest
        return x * x * x * (x * (x * 6 - 15) + 10)
    }
    
}
