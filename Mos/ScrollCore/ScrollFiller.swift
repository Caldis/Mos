//
//  Filter.swift
//  Mos
//  曲线峰值滤波, 用于去除滚动的起始抖动
//  Created by Caldis on 2018/3/21.
//  Copyright © 2018年 Caldis. All rights reserved.
//

import Cocoa

class ScrollFiller {
    
    var windowY = [0.0, 0.0]
    var windowX = [0.0, 0.0]
    
    // 更新值
    public func fill(with nextValue: ( y: Double, x: Double )) -> ( y: Double, x: Double ) {
        windowY = smooth(windowY, with: nextValue.y)
        windowX = smooth(windowX, with: nextValue.x)
        return value()
    }
    // 获取值
    public func value() -> ( y: Double, x: Double ) {
        return ( y: windowY[0], x: windowX[0] )
    }
    // 清空
    public func reset() {
        windowY = [0.0, 0.0]
        windowX = [0.0, 0.0]
    }

}

extension ScrollFiller {
    // 曲线平滑
    // 取窗口数组首位, 并计算与 nextValue 的距离, 用定长的非线性数列填充以光顺曲线
    // 例如数组首位为 1, nextValue 为 2, 则生成数列 [1.00, 1.23, 1.50, 1.77, 2.00]
    private func smooth(_ array: [Double], with nextValue: Double) -> [Double] {
        let first = array[1]
        let diff = nextValue - first
        return [first, first+0.23*diff, first+0.5*diff, first+0.77*diff, nextValue]
    }
}
