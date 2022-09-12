//
//  Filter.swift
//  Mos
//  曲线峰值滤波, 用于去除滚动的起始抖动
//  Created by Caldis on 2018/3/21.
//  Copyright © 2018年 Caldis. All rights reserved.
//

import Cocoa

class ScrollFilter {
    
    var curveWindowY = [0.0, 0.0]
    var curveWindowX = [0.0, 0.0]
    
    // 填充值
    public func fill(with nextValue: ( y: Double, x: Double )) -> ( y: Double, x: Double ) {
        curveWindowY = polish(curveWindowY, with: nextValue.y)
        curveWindowX = polish(curveWindowX, with: nextValue.x)
        return value()
    }
    // 获取值
    public func value() -> ( y: Double, x: Double ) {
        return ( y: curveWindowY[0], x: curveWindowX[0] )
    }
    // 清空
    public func reset() {
        curveWindowY = [0.0, 0.0]
        curveWindowX = [0.0, 0.0]
    }

}

extension ScrollFilter {
    // 曲线平滑
    // 计算曲线窗口数组首位与 nextValue 的距离, 用定长的非线性数列填充以平滑曲线
    // 例如: 数组首位为 1, nextValue 为 2, 则生成数列 [1.00, 1.23, 1.50, 1.77, 2.00]
    private func polish(_ array: [Double], with nextValue: Double) -> [Double] {
        let first = array[1]
        let diff = nextValue - first
        return [first, first+0.23*diff, first+0.5*diff, first+0.77*diff, nextValue]
    }
}
