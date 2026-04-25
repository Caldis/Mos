//
//  SettingsBackupManager.swift
//  Mos
//  设置备份导入导出管理器
//  Created by Mos on 2026/4/25.
//

import Cocoa

struct SettingsBackup: Codable {
    let version: Int
    let timestamp: Date
    
    let general: GeneralBackup
    let update: UpdateBackup
    let scroll: ScrollBackup
    let buttons: ButtonsBackup
    let application: ApplicationBackup
    let mouse: MouseBackup
    
    struct GeneralBackup: Codable {
        let hideStatusItem: Bool
    }
    
    struct UpdateBackup: Codable {
        let checkOnAppStart: Bool
        let includingBetaVersion: Bool
    }
    
    struct ScrollBackup: Codable {
        let smooth: Bool
        let reverse: Bool
        let reverseVertical: Bool
        let reverseHorizontal: Bool
        let dash: ScrollHotkey?
        let toggle: ScrollHotkey?
        let block: ScrollHotkey?
        let step: Double
        let speed: Double
        let duration: Double
        let deadZone: Double
        let smoothSimTrackpad: Bool
        let smoothVertical: Bool
        let smoothHorizontal: Bool
        let durationBeforeSimTrackpadLock: Double?
    }
    
    struct ButtonsBackup: Codable {
        let binding: [ButtonBinding]
    }
    
    struct ApplicationBackup: Codable {
        let allowlist: Bool
        let applications: [Application]
    }
    
    struct MouseBackup: Codable {
        let enableSensitivity: Bool
        let sensitivity: Double
    }
}

class SettingsBackupManager {
    static let shared = SettingsBackupManager()
    
    private let currentVersion = 1
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    
    init() {
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }
    
    func exportSettings() -> Bool {
        let backup = createBackup()
        
        let savePanel = NSSavePanel()
        savePanel.canCreateDirectories = true
        savePanel.nameFieldStringValue = generateDefaultFilename()
        // 兼容 macOS 10.13: allowedContentTypes 是 macOS 11.0+ 的 API
        // 使用 allowedFileTypes 替代
        savePanel.allowedFileTypes = ["json"]
        
        let response = savePanel.runModal()
        
        guard response == .OK, let url = savePanel.url else {
            return false
        }
        
        do {
            let data = try encoder.encode(backup)
            try data.write(to: url)
            
            Toast.show(
                NSLocalizedString("Settings exported successfully", comment: ""),
                style: .success,
                duration: 3.0
            )
            
            return true
        } catch {
            NSLog("Failed to export settings: \(error)")
            
            Toast.show(
                NSLocalizedString("Failed to export settings", comment: ""),
                style: .error,
                duration: 3.0
            )
            
            return false
        }
    }
    
    func importSettings() -> Bool {
        let openPanel = NSOpenPanel()
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = false
        openPanel.allowsMultipleSelection = false
        // 兼容 macOS 10.13: allowedContentTypes 是 macOS 11.0+ 的 API
        // 使用 allowedFileTypes 替代
        openPanel.allowedFileTypes = ["json"]
        
        let response = openPanel.runModal()
        
        guard response == .OK, let url = openPanel.url else {
            return false
        }
        
        do {
            let data = try Data(contentsOf: url)
            let backup = try decoder.decode(SettingsBackup.self, from: data)
            
            applyBackup(backup)
            
            Toast.show(
                NSLocalizedString("Settings imported successfully", comment: ""),
                style: .success,
                duration: 3.0
            )
            
            return true
        } catch {
            NSLog("Failed to import settings: \(error)")
            
            Toast.show(
                NSLocalizedString("Failed to import settings", comment: ""),
                style: .error,
                duration: 3.0
            )
            
            return false
        }
    }
    
    private func createBackup() -> SettingsBackup {
        return SettingsBackup(
            version: currentVersion,
            timestamp: Date(),
            general: SettingsBackup.GeneralBackup(
                hideStatusItem: Options.shared.general.hideStatusItem
            ),
            update: SettingsBackup.UpdateBackup(
                checkOnAppStart: Options.shared.update.checkOnAppStart,
                includingBetaVersion: Options.shared.update.includingBetaVersion
            ),
            scroll: SettingsBackup.ScrollBackup(
                smooth: Options.shared.scroll.smooth,
                reverse: Options.shared.scroll.reverse,
                reverseVertical: Options.shared.scroll.reverseVertical,
                reverseHorizontal: Options.shared.scroll.reverseHorizontal,
                dash: Options.shared.scroll.dash,
                toggle: Options.shared.scroll.toggle,
                block: Options.shared.scroll.block,
                step: Options.shared.scroll.step,
                speed: Options.shared.scroll.speed,
                duration: Options.shared.scroll.duration,
                deadZone: Options.shared.scroll.deadZone,
                smoothSimTrackpad: Options.shared.scroll.smoothSimTrackpad,
                smoothVertical: Options.shared.scroll.smoothVertical,
                smoothHorizontal: Options.shared.scroll.smoothHorizontal,
                durationBeforeSimTrackpadLock: Options.shared.scroll.durationBeforeSimTrackpadLock
            ),
            buttons: SettingsBackup.ButtonsBackup(
                binding: Options.shared.buttons.binding
            ),
            application: SettingsBackup.ApplicationBackup(
                allowlist: Options.shared.application.allowlist,
                applications: Options.shared.application.applications.allElements
            ),
            mouse: SettingsBackup.MouseBackup(
                enableSensitivity: Options.shared.mouse.enableSensitivity,
                sensitivity: Options.shared.mouse.sensitivity
            )
        )
    }
    
    private func applyBackup(_ backup: SettingsBackup) {
        Options.shared.general.hideStatusItem = backup.general.hideStatusItem
        Options.shared.update.checkOnAppStart = backup.update.checkOnAppStart
        Options.shared.update.includingBetaVersion = backup.update.includingBetaVersion
        
        Options.shared.scroll.smooth = backup.scroll.smooth
        Options.shared.scroll.reverse = backup.scroll.reverse
        Options.shared.scroll.reverseVertical = backup.scroll.reverseVertical
        Options.shared.scroll.reverseHorizontal = backup.scroll.reverseHorizontal
        Options.shared.scroll.dash = backup.scroll.dash
        Options.shared.scroll.toggle = backup.scroll.toggle
        Options.shared.scroll.block = backup.scroll.block
        Options.shared.scroll.step = backup.scroll.step
        Options.shared.scroll.speed = backup.scroll.speed
        Options.shared.scroll.duration = backup.scroll.duration
        Options.shared.scroll.deadZone = backup.scroll.deadZone
        Options.shared.scroll.smoothSimTrackpad = backup.scroll.smoothSimTrackpad
        Options.shared.scroll.smoothVertical = backup.scroll.smoothVertical
        Options.shared.scroll.smoothHorizontal = backup.scroll.smoothHorizontal
        Options.shared.scroll.durationBeforeSimTrackpadLock = backup.scroll.durationBeforeSimTrackpadLock
        
        Options.shared.buttons.binding = backup.buttons.binding
        
        Options.shared.application.allowlist = backup.application.allowlist
        Options.shared.application.applications = EnhanceArray(
            withArray: backup.application.applications,
            matchKey: "path",
            forObserver: { Options.shared.saveOptions() }
        )
        
        Options.shared.mouse.enableSensitivity = backup.mouse.enableSensitivity
        Options.shared.mouse.sensitivity = backup.mouse.sensitivity
        
        Options.shared.saveOptions()
        
        MouseSensitivityManager.shared.refresh()
        LogitechHIDManager.shared.syncDivertWithBindings()
        
        NotificationCenter.default.post(name: .mosSettingsImported, object: nil)
    }
    
    private func generateDefaultFilename() -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd-HHmmss"
        let dateString = dateFormatter.string(from: Date())
        return "mos-settings-backup-\(dateString)"
    }
}

extension Notification.Name {
    static let mosSettingsImported = Notification.Name("mosSettingsImported")
}
