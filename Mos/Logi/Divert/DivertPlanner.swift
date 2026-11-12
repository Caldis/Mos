//
//  LogiDivertPlanner.swift
//  Mos
//  HID++ divert 决策纯函数 - 只触碰 Mos 自己关心的 CID, 不扫第三方 (如 Logitech Options+) 可能 divert 的其它 CID.
//  Created by Mos on 2026/4/20.
//  Copyright © 2026 Caldis. All rights reserved.
//

import Foundation

/// Logitech HID++ divert 决策纯函数
///
/// 给定 (当前绑定的 MosCode, 本进程已 divert 的 CID, 设备上声明为 divertable 的 CID),
/// 计算出本次需要切换的 CID 集合. 原则:
///   1. 只 divert 用户绑定过且设备支持的按键.
///   2. 只 undivert Mos 本进程自己曾 divert 过、且已不再绑定的按键.
///   3. 其它 CID 完全不触碰 (Options+ 等第三方进程可能在 divert 它们).
struct LogiDivertPlanner {

    struct Plan: Equatable {
        let toDivert: [UInt16]
        let toUndivert: [UInt16]
    }

    static func plan(
        boundMosCodes: Set<UInt16>,
        alreadyDiverted: Set<UInt16>,
        divertableCIDs: Set<UInt16>
    ) -> Plan {
        var toDivert: [UInt16] = []
        for code in boundMosCodes {
            guard let cid = LogiCIDDirectory.toCID(code) else { continue }
            guard divertableCIDs.contains(cid) else { continue }
            guard !alreadyDiverted.contains(cid) else { continue }
            toDivert.append(cid)
        }

        var toUndivert: [UInt16] = []
        for cid in alreadyDiverted {
            let code = LogiCIDDirectory.toMosCode(cid)
            if !boundMosCodes.contains(code) {
                toUndivert.append(cid)
            }
        }

        return Plan(
            toDivert: toDivert.sorted(),
            toUndivert: toUndivert.sorted()
        )
    }
}
