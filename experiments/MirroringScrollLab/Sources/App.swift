// App 入口: 申请辅助功能权限, 启动窗口定位与 tap 线程, 并响应配置变化
// (tap 位置变化时重建 tap, 模式变化时复位手势, 按需创建虚拟设备)

import SwiftUI
import ApplicationServices

@main
enum LabEntry {
    static func main() {
        if CommandLine.arguments.contains("--selftest") { exit(SelfTest.run()) }
        ScrollLabApp.main()
    }
}

struct ScrollLabApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("Mirroring Scroll Lab") {
            ContentView()
                .environmentObject(ConfigStore.shared)
                .frame(minWidth: 1000, minHeight: 700)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var retryTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
        MirroringLocator.shared.start()
        Lab.diagnosticsEnabled = ConfigStore.shared.config.diagnostics
        ConfigStore.shared.onChange = { old, new in
            Recorder.shared.configChanged(new)
            Lab.diagnosticsEnabled = new.diagnostics
            if old.tapLocation != new.tapLocation || old.tapPlacement != new.tapPlacement { TapController.shared.reinstall() }
            if old.mode != new.mode || old.enabled != new.enabled { ScrollEngine.shared.resetGestureState() }
            Self.prepareDevices(for: new)
        }
        TapController.shared.start()
        Self.prepareDevices(for: ConfigStore.shared.config)
        // 辅助功能授权之前无法创建 tap, 因此定时重试直到成功
        retryTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            if !TapController.shared.active.get() && AXIsProcessTrusted() { TapController.shared.reinstall() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) { Recorder.shared.stop() }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    static func prepareDevices(for cfg: LabConfig) {
        if cfg.mode == .virtualMouse { VirtualMouse.shared.ensure() }
        if cfg.mode == .virtualTouchpad { VirtualTouchpad.shared.ensure() }
        if cfg.mode == .magicTrackpad || cfg.sender == .virtualMagicTrackpad { VirtualMagicTrackpad.shared.ensure() }
    }
}
