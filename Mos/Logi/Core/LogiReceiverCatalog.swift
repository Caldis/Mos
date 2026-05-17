//
//  LogiReceiverCatalog.swift
//  Mos
//  Logitech 接收器 (USB dongle) 型号识别
//
//  数据来源: Solaar 项目
//  https://github.com/pwr-Solaar/Solaar
//  文件: lib/logitech_receiver/base_usb.py
//  Commit: ff9324d34693d6bb390c4dad4f5a0e731d2e9bd1
//  Solaar 项目采用 GPL-2.0 许可证
//
//  Created by Mos on 2026/4/23.
//  Copyright © 2026 Caldis. All rights reserved.
//

import Foundation

/// Logitech 接收器型号注册表: PID -> 接收器类型
/// 用于在调试面板等 UI 处显示准确的接收器类型名 (Bolt / Unifying / Lightspeed / Nano / EX100)
struct LogiReceiverCatalog {

    enum Kind: String {
        case bolt        = "Bolt Receiver"
        case unifying    = "Unifying Receiver"
        case lightspeed  = "Lightspeed Receiver"
        case nano        = "Nano Receiver"
        case ex100       = "EX100 Receiver (27 MHz)"
    }

    // MARK: - PID -> Kind 映射 (源自 Solaar base_usb.py KNOWN_RECEIVERS)

    private static let kindByPID: [UInt16: Kind] = [
        // Bolt
        0xC548: .bolt,

        // Unifying
        0xC52B: .unifying,
        0xC532: .unifying,

        // Nano
        0xC52F: .nano,
        0xC518: .nano,
        0xC51A: .nano,
        0xC51B: .nano,
        0xC521: .nano,
        0xC525: .nano,
        0xC526: .nano,
        0xC52E: .nano,
        0xC531: .nano,
        0xC534: .nano,
        0xC535: .nano,
        0xC537: .nano,

        // Lightspeed
        0xC539: .lightspeed,
        0xC53A: .lightspeed,
        0xC53D: .lightspeed,
        0xC53F: .lightspeed,
        0xC541: .lightspeed,
        0xC545: .lightspeed,
        0xC547: .lightspeed,
        0xC54D: .lightspeed,

        // EX100 (27 MHz, 前 Unifying 时代)
        0xC517: .ex100,
    ]

    // MARK: - Public API

    /// 根据 PID 返回接收器类型 (已知型号); 未知返回 nil
    static func kind(forPID pid: UInt16) -> Kind? {
        return kindByPID[pid]
    }

    /// 返回对用户展示的接收器名称; 未知 PID 回退到 "USB Receiver"
    static func displayName(forPID pid: UInt16) -> String {
        return kindByPID[pid]?.rawValue ?? "USB Receiver"
    }
}
