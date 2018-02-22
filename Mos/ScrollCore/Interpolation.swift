//
//  Interpolation.swift
//  Mos
//  线性插值函数
//  Created by Caldis on 2018/2/19.
//  Copyright © 2018年 Caldis. All rights reserved.
//

import Cocoa

class Interpolation: NSObject {
    
    class func lerp(src: Double, dest: Double) -> Double {
        return (dest - src) * Options.shared.current.advanced.transition
    }
    
}
