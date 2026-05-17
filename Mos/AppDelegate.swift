//
//  AppDelegate.swift
//  Mos
//
//  Created by Caldis on 2017/1/10.
//  Copyright © 2017年 Caldis. All rights reserved.
//

import Cocoa

enum AppRuntime {
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
    private var permissionRecoveryTimer: Timer?

    // 运行前预处理
    func applicationWillFinishLaunching(_ notification: Notification) {
        // 必须最早调用: 从 Mos 自身 env 移除 DYLD_INSERT_LIBRARIES / __XPC_DYLD_* 等
        // Xcode 调试器注入的 vars. 这些 vars 会沿 XPC 链路传到 launchservicesd 再传到
        // 任何 Mos 启动的子 App, 导致依赖 AVKit 的 system app (Maps/FindMy/Podcasts)
        // 加载 libViewDebuggerSupport 时找不到符号 → dyld halt. Mos 自身进程已加载完
        // 依赖, unsetenv 不影响自身, 只让之后启动的子进程拿到干净 env.
        ShortcutExecutor.sanitizeOwnLaunchEnvironment()

        guard AppRuntime.shouldRunAppStartupSideEffects else {
            NSLog("Running under XCTest; skipping app startup side effects")
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
            name: .mosAccessibilityPermissionLost,
            object: nil
        )
    }
    // 运行后启动滚动处理
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        guard AppRuntime.shouldRunAppStartupSideEffects else { return }
        LogiCenter.shared.installBridge(LogiIntegrationBridge.shared)
        LogiUsageBootstrap.refreshAll()
        startWithAccessibilityPermissionsChecker(nil)
        UpdateManager.shared.scheduleCheckOnAppStartIfNeeded()
    }

    // 用户双击打开应用程序
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !flag else {
            return true
        }
        if Utils.isHadAccessibilityPermissions() {
            WindowManager.shared.showWindow(withIdentifier: WINDOW_IDENTIFIER.preferencesWindowController)
        }
        return false
    }
    
    // 关闭前停止滚动处理
    func applicationWillTerminate(_ aNotification: Notification) {
        guard AppRuntime.shouldRunAppStartupSideEffects else { return }
        LogiCenter.shared.stop()
        ScrollCore.shared.disable()
        ButtonCore.shared.disable()
    }
    
    // 检查是否有访问 accessibility 权限, 如果有则启动滚动处理, 并结束计时器
    // 10.14(Mojave) 后, 若无该权限会直接在创建 eventTap 时报错 (https://developer.apple.com/videos/play/wwdc2018/702/)
    @objc func startWithAccessibilityPermissionsChecker(_ timer: Timer?) {
        if let validTimer = timer {
            // 开启辅助权限后, 关闭定时器, 开始处理
            if Utils.isHadAccessibilityPermissions() {
                validTimer.invalidate()
                permissionRecoveryTimer = nil
                NSLog("First Initialization (Accessibility Authorization Needed)")
                ScrollCore.shared.enable()
                ButtonCore.shared.enable()
                LogiCenter.shared.start()
            }
        } else {
            if Utils.isHadAccessibilityPermissions() {
                NSLog("Regular Initialization")
                ScrollCore.shared.enable()
                ButtonCore.shared.enable()
                LogiCenter.shared.start()
            } else {
                // 如果应用不在辅助权限列表内, 则弹出欢迎窗口
                WindowManager.shared.showWindow(withIdentifier: WINDOW_IDENTIFIER.introductionWindowController, withTitle: "")
                // 启动定时器检测权限, 当拥有授权时启动滚动处理
                Timer.scheduledTimer(
                    timeInterval: 10.0,
                    target: self,
                    selector: #selector(startWithAccessibilityPermissionsChecker(_:)),
                    userInfo: nil,
                    repeats: true
                )
            }
        }
    }
    
    // 在切换用户时停止滚动处理
    @objc func sessionDidActive(notification: NSNotification){
        startWithAccessibilityPermissionsChecker(nil)
    }
    @objc func sessionDidResign(notification: NSNotification){
        permissionRecoveryTimer?.invalidate()
        permissionRecoveryTimer = nil
        LogiCenter.shared.stop()
        ScrollCore.shared.disable()
        ButtonCore.shared.disable()
    }
    // 辅助功能权限在运行时被撤销 (可能由多个 Interceptor 同时触发, 此方法必须幂等)
    @objc func handleAccessibilityPermissionLost() {
        // 避免多个 Interceptor 同时触发导致重复处理
        guard ScrollCore.shared.isActive || ButtonCore.shared.isActive else { return }
        NSLog("Accessibility permission lost at runtime, disabling cores")
        LogiCenter.shared.stop()
        ScrollCore.shared.disable()
        ButtonCore.shared.disable()
        Toast.show(
            NSLocalizedString("Accessibility permission lost, Mos has been paused", comment: ""),
            style: .warning,
            duration: 5.0
        )
        // 启动定时器检测权限恢复
        permissionRecoveryTimer?.invalidate()
        permissionRecoveryTimer = Timer.scheduledTimer(
            timeInterval: 2.0,
            target: self,
            selector: #selector(startWithAccessibilityPermissionsChecker(_:)),
            userInfo: nil,
            repeats: true
        )
    }
}
