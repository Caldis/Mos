//
//  Filter.swift
//  Mos
//  曲线峰值滤波
//  Created by Caldis on 2018/3/21.
//  Copyright © 2018年 Caldis. All rights reserved.
//

import Cocoa

class ScrollFiller {
    
    var size = 4
    var windowY = [0.0]
    var windowX = [0.0]
    
    // 更新值
    func fillIn(with nextValue: ( y: Double, x: Double )) {
        // Y 轴
        if windowY.count<size {
            windowY = fill(in: windowY, to: nextValue.y)
        } else {
            windowY = fill(in: windowY, to: nextValue.y)
            windowY.append(nextValue.y)
            windowY.removeFirst()
        }
        // X 轴
        if windowX.count<size {
            windowX = fill(in: windowX, to: nextValue.x)
        } else {
            windowX = fill(in: windowX, to: nextValue.x)
            windowX.append(nextValue.x)
            windowX.removeFirst()
        }
    }
    // 填平凹点
    private func fill(in array: [Double], to nextValue: Double) -> [Double] {
        let first = array.first!
        let diff = nextValue-first
        // length = 4
        // 1, 1.02, 1.05, 1.08, 2
        return [first, first+0.2*diff, first+0.5*diff, first+0.8*diff]
    }
    
    // 获取值
    func value() -> ( y: Double, x: Double ) {
        return ( y: windowY.first!, x: windowX.first! )
    }
    // 清空
    func clean() {
        windowY = [0.0]
        windowX = [0.0]
    }

}
