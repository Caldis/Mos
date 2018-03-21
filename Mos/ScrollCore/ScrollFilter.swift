//
//  Filter.swift
//  Mos
//  曲线峰值滤波
//  Created by Caldis on 2018/3/21.
//  Copyright © 2018年 Caldis. All rights reserved.
//

import Cocoa

class ScrollFilter {
    
    var size = 4
    var windowY = [Double]()
    var windowX = [Double]()
    
    // 更新窗口值
    func update(with nextValue: ( y: Double, x: Double )) {
        // Y 轴
        if windowY.count<size {
            windowY.append(nextValue.y)
        } else {
            windowY = fillPeak(in: windowY, to: nextValue.y)
            windowY.append(nextValue.y)
            windowY.removeFirst()
        }
        // X 轴
        if windowX.count<size {
            windowX.append(nextValue.x)
        } else {
            windowX = fillPeak(in: windowX, to: nextValue.x)
            windowX.append(nextValue.x)
            windowX.removeFirst()
        }
    }
    // 填平跃点
    private func fillPeak(in array: [Double], to nextValue: Double) -> [Double] {
        let first = array.first!
        let diff = nextValue-first
        return [first, first+0.2*diff, first+0.5*diff, first+0.8*diff]
    }

    // 获取运行状态
    func onRunningState() -> Bool {
        return windowY.count>=size
    }
    // 获取最新数值
    func value() -> ( y: Double, x: Double ) {
        return ( y: windowY.first!, x: windowX.first! )
    }
    // 清空内容
    func clean() {
        windowY = [Double]()
        windowX = [Double]()
    }

}
