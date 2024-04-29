//
//  Extensions.swift
//  Mos
//
//  Created by Xiaojun Zhou on 2024/4/28.
//  Copyright © 2024 Caldis. All rights reserved.
//

extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        return min(max(self, limits.lowerBound), limits.upperBound)
    }
}

extension Strideable where Stride: SignedInteger {
    func clamped(to limits: CountableClosedRange<Self>) -> Self {
        return min(max(self, limits.lowerBound), limits.upperBound)
    }
}
