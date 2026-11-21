//
//  UpdateManager.swift
//  Mos
//  Updates management via Sparkle
//

import Cocoa
import Sparkle

final class UpdateManager: NSObject {

    static let shared = UpdateManager()
    /// 本 fork 独立更新源，不走原项目 mos.caldis.me
    static let forkAppcastURL = "https://github.com/ZHOUSJ6/Mos/releases/download/sparkle-feed/appcast.xml"

    private lazy var updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: self,
        userDriverDelegate: nil
    )

    private override init() {
        super.init()
        NSLog("Module initialized: UpdateManager")
    }
}

extension UpdateManager {

    func scheduleCheckOnAppStartIfNeeded() {
        guard Options.shared.update.checkOnAppStart else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.checkForUpdatesInBackground()
        }
    }

    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }

    func checkForUpdatesInBackground() {
        updaterController.updater.checkForUpdatesInBackground()
    }
}

extension UpdateManager: SPUUpdaterDelegate {

    func feedURLString(for updater: SPUUpdater) -> String? {
        return UpdateManager.forkAppcastURL
    }

    func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        Options.shared.update.includingBetaVersion ? ["beta"] : []
    }
}

