//
//  Filter.swift
//  Mos
//  曲线峰值滤波, 用于去除滚动的起始抖动
//  Created by Caldis on 2018/3/21.
//  Copyright © 2018年 Caldis. All rights reserved.
//

import Cocoa

class ScrollFilter {

    private var output = (y: 0.0, x: 0.0)
    private var next = (y: 0.0, x: 0.0)
    private var previousFrameScale = 1.0

    func fill(with nextValue: (y: Double, x: Double), timing: FrameTiming = .legacy) -> (y: Double, x: Double) {
        // The previous window's second sample is the only sample used by the next frame.
        // Rescale the displacement to preserve its velocity across a change in frame interval.
        let rescale = timing.scale / previousFrameScale
        previousFrameScale = timing.scale
        let y = next.y * rescale
        let x = next.x * rescale
        let weight = timing.fraction(0.23)
        output = (y, x)
        next = (y + weight * (nextValue.y - y), x + weight * (nextValue.x - x))
        return output
    }

    public func value() -> (y: Double, x: Double) {
        return output
    }

    public func reset() {
        output = (0, 0)
        next = (0, 0)
        previousFrameScale = 1
    }
}
