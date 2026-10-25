//
//  AppDelegate.swift
//  Mos
//
//  Created by Caldis on 2017/1/10.
//  Copyright © 2017年 Caldis. All rights reserved.
//

import Cocoa

enum AppRuntime {
    static var isOnboardingPreview: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("--mos-onboarding-preview")
        #else
        return false
        #endif
    }

    static var isRunningXCTest: Bool {
        isRunningXCTest(environment: ProcessInfo.processInfo.environment) || isXCTestLoaded
    }

    static func isRunningXCTest(environment: [String: String]) -> Bool {
        environment["XCTestConfigurationFilePath"] != nil ||
        environment["XCTestBundlePath"] != nil ||
        environment.keys.contains { $0.hasPrefix("XCTest") }
    }

    static var shouldRunAppStartupSideEffects: Bool {
        shouldRunAppStartupSideEffects(
            environment: ProcessInfo.processInfo.environment,
            isXCTestLoaded: isXCTestLoaded
        )
    }

    static func shouldRunAppStartupSideEffects(
        environment: [String: String],
        isXCTestLoaded: Bool = false
    ) -> Bool {
        let isRunningTests = isRunningXCTest(environment: environment) || isXCTestLoaded
        guard isRunningTests else { return true }
        return environment["MOS_TEST_ENABLE_APP_STARTUP"] == "1"
    }

    private static var isXCTestLoaded: Bool {
        NSClassFromString("XCTestCase") != nil ||
        NSClassFromString("XCTest.XCTestCase") != nil
    }
}

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    // 防抖定时器: 显示器参数变化通知
    private var screenChangeTimer: Timer?
    // 权限恢复轮询定时器
    private var sessionIsActive = true

    // 运行前预处理
    func applicationWillFinishLaunching(_ notification: Notification) {
        // 必须最早调用: 从 Mos 自身 env 移除 DYLD_INSERT_LIBRARIES / __XPC_DYLD_* 等
        // Xcode 调试器注入的 vars. 这些 vars 会沿 XPC 链路传到 launchservicesd 再传到
        // 任何 Mos 启动的子 App, 导致依赖 AVKit 的 system app (Maps/FindMy/Podcasts)
        // 加载 libViewDebuggerSupport 时找不到符号 → dyld halt. Mos 自身进程已加载完
        // 依赖, unsetenv 不影响自身, 只让之后启动的子进程拿到干净 env.
        ShortcutExecutor.sanitizeOwnLaunchEnvironment()

        guard AppRuntime.shouldRunAppStartupSideEffects, !AppRuntime.isOnboardingPreview else {
            NSLog("Test or onboarding preview; skipping app startup side effects")
            return
        }

        // 禁止重复运行, 结束正在运行的实例
        Utils.preventMultiRunning(killExist: true)
        
        // DEBUG: 清空用户设置
        // UserDefaults.standard.removePersistentDomain(forName: Bundle.main.bundleIdentifier!)
        
        // 读取用户设置
        Options.shared.readOptions()
        
        // DEBUG: 直接弹出设置窗口
        #if DEBUG
        WindowManager.shared.showWindow(withIdentifier: WINDOW_IDENTIFIER.preferencesWindowController)
        #endif

        // 监听用户切换, 在切换用户 session 时停止运行
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(AppDelegate.sessionDidActive),
            name: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(AppDelegate.sessionDidResign),
            name: NSWorkspace.sessionDidResignActiveNotification,
            object: nil
        )
        // 监听系统休眠/唤醒, 复用 session 生命周期方法
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(AppDelegate.sessionDidResign),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(AppDelegate.sessionDidActive),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        // 监听显示器参数变化 (热插拔/分辨率/显示器休眠唤醒), 延迟重建 CVDisplayLink
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.screenChangeTimer?.invalidate()
            self?.screenChangeTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { _ in
                ScrollPoster.shared.recreateDisplayLink()
            }
        }
        // 监听辅助功能权限在运行时被撤销
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAccessibilityPermissionLost),
            name: .mosInputPermissionChanged,
            object: nil
        )
    }
    // 运行后启动滚动处理
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        if AppRuntime.isOnboardingPreview {
            if #available(macOS 10.14, *), ProcessInfo.processInfo.arguments.contains("--mos-preview-light") {
                NSApp.appearance = NSAppearance(named: .aqua)
            }
            WindowManager.shared.showWindow(withIdentifier: WINDOW_IDENTIFIER.introductionWindowController)
            return
        }
        guard AppRuntime.shouldRunAppStartupSideEffects else { return }
        LogiCenter.shared.installBridge(LogiIntegrationBridge.shared)
        ShortcutExecutor.shared.scrollActionPort = ScrollCore.shared
        ShortcutExecutor.shared.modifierFlagsProvider = InputProcessor.shared
        LogiUsageBootstrap.installOptionsObservers()
        LogiUsageBootstrap.refreshAll()
        InputPermissionMonitor.shared.start()
        UpdateManager.shared.scheduleCheckOnAppStartIfNeeded()
    }

    // 用户双击打开应用程序
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !flag else {
            return true
        }
        let identifier = Utils.isHadAccessibilityPermissions()
            ? WINDOW_IDENTIFIER.preferencesWindowController : WINDOW_IDENTIFIER.introductionWindowController
        WindowManager.shared.showWindow(withIdentifier: identifier)
        return true
    }
    
    // 关闭前停止滚动处理
    func applicationWillTerminate(_ aNotification: Notification) {
        guard AppRuntime.shouldRunAppStartupSideEffects, !AppRuntime.isOnboardingPreview else { return }
        InputPermissionMonitor.shared.stop()
        LogiCenter.shared.stop()
        ScrollCore.shared.disable()
        ButtonCore.shared.disable()
        // 写入尚未 flush 的脏配置组
        Options.shared.flushPendingSaves()
    }
    
    @objc func startWithAccessibilityPermissionsChecker(_ timer: Timer?) {
        guard sessionIsActive else { return }
        if InputPermissionMonitor.shared.isAuthorized {
            ScrollCore.shared.enable()
            ButtonCore.shared.enable()
            LogiCenter.shared.start()
        } else {
            WindowManager.shared.showWindow(withIdentifier: WINDOW_IDENTIFIER.introductionWindowController)
        }
    }

    @objc func sessionDidActive(notification: NSNotification) {
        sessionIsActive = true
        startWithAccessibilityPermissionsChecker(nil)
    }

    @objc func sessionDidResign(notification: NSNotification) {
        sessionIsActive = false
        stopInputServices()
    }

    private func stopInputServices() {
        // Recorders also exist when both cores are inactive.
        NotificationCenter.default.post(name: .mosAccessibilityPermissionLost, object: nil)
        ScrollCore.shared.disable()
        ButtonCore.shared.disable()
        InputProcessor.shared.clearActiveBindings()
        LogiCenter.shared.stop()
    }

    @objc func handleAccessibilityPermissionLost() {
        // Every lease transition discards old resources, including a quick revoke/regrant.
        stopInputServices()
        startWithAccessibilityPermissionsChecker(nil)
    }
}
