//
//  Filter.swift
//  Mos
//  曲线峰值滤波
//  Created by Caldis on 2018/3/21.
//  Copyright © 2018年 Caldis. All rights reserved.
//

import Cocoa

class ScrollFiller {
    
    var windowY = [0.0, 0.0]
    var windowX = [0.0, 0.0]
    
    // 更新值
    func fillIn(with nextValue: ( y: Double, x: Double )) -> ( y: Double, x: Double ) {
        windowY = smooth(windowY, with: nextValue.y)
        windowX = smooth(windowX, with: nextValue.x)
        return value()
    }
    // 曲线光顺
    // 取窗口数组首位, 并计算与 nextValue 的距离, 用定长的非线性数列填充以光顺曲线
    // 例如数组首位为 1, nextValue 为 2
    // 则生成数列 [1, 1.2, 1.5, 1.8, 2]
    private func smooth(_ array: [Double], with nextValue: Double) -> [Double] {
        let first = array[1]
        let diff = nextValue - first
        return [first, first+0.23*diff, first+0.5*diff, first+0.77*diff, nextValue]
    }
    
    // 获取值
    func value() -> ( y: Double, x: Double ) {
        return ( y: windowY[0], x: windowX[0] )
    }
    // 清空
    func clean() {
        windowY = [0.0, 0.0]
        windowX = [0.0, 0.0]
    }

}
