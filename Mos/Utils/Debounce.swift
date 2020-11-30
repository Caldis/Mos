//
//  Debounce.swift
//  Mos
//
//  Created by 陈标 on 2020/11/30.
//  Copyright © 2020 Caldis. All rights reserved.
//

import Foundation

class Debounce: NSObject {
    
    var callback: (() -> ())
    var delay: Double
    weak var timer: Timer?

    init(delay: Double, callback: @escaping (() -> ())) {
        self.delay = delay
        self.callback = callback
    }

    @objc func call() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(timeInterval: delay, target: self, selector: #selector(self.fireNow), userInfo: nil, repeats: false)
    }

    @objc func fireNow() {
        self.callback()
    }
}
