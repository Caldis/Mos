//
//  Filter.swift
//  Mos
//  曲线峰值滤波, 用于去除滚动的起始抖动
//  Created by Caldis on 2018/3/21.
//  Copyright © 2018年 Caldis. All rights reserved.
//

import Cocoa

class ScrollFilter {

    // 一阶平滑递推 (系数 0.23), 输出滞后一帧:
    //   output(n) = s(n-1);  s(n) = s(n-1) + 0.23 * (input - s(n-1))
    // 与旧版 5 元素曲线窗口的可观察行为完全一致 —— 窗口的 [2][3][4] 从未被
    // 消费, 属每帧死计算; 本类运行在 CVDisplayLink 热路径, 避免每帧堆分配数组
    private var currentY = 0.0
    private var smoothedY = 0.0
    private var currentX = 0.0
    private var smoothedX = 0.0

    // 填充值
    public func fill(with nextValue: ( y: Double, x: Double )) -> ( y: Double, x: Double ) {
        currentY = smoothedY
        smoothedY += 0.23 * (nextValue.y - smoothedY)
        currentX = smoothedX
        smoothedX += 0.23 * (nextValue.x - smoothedX)
        return value()
    }
    // 获取值
    public func value() -> ( y: Double, x: Double ) {
        return ( y: currentY, x: currentX )
    }
    // 清空
    public func reset() {
        currentY = 0.0
        smoothedY = 0.0
        currentX = 0.0
        smoothedX = 0.0
    }

}
