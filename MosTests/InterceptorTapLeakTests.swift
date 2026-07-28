import XCTest
@testable import Mos_Debug

/// Interceptor 销毁后 WindowServer 侧 event tap 注册的回归测试.
/// 场景背景: CGEventTapCreate 返回的 CFMachPort 被 CoreGraphics 内部持有引用, 仅释放
/// 引用不会销毁它; deinit 若不调用 CFMachPortInvalidate, WindowServer 会保留 (已禁用的)
/// tap 注册直到进程退出。ScrollCore/ButtonCore 每次休眠唤醒都会重建 Interceptor, 泄漏
/// 会累积成上千僵尸注册, 拖慢全系统输入 (#970)。
final class InterceptorTapLeakTests: XCTestCase {

    /// 当前进程在 WindowServer tap 表中持有的注册数
    private func ownTapCount() -> Int {
        var count: UInt32 = 0
        CGGetEventTapList(0, nil, &count)
        var taps = [CGEventTapInformation](repeating: CGEventTapInformation(), count: Int(count) + 16)
        var actual: UInt32 = 0
        CGGetEventTapList(UInt32(taps.count), &taps, &actual)
        let pid = getpid()
        return taps.prefix(Int(actual)).filter { $0.tappingProcess == pid }.count
    }

    func testDeinitReleasesWindowServerRegistration() throws {
        let baseline = ownTapCount()

        // init 在 start() 的辅助功能权限检查之前就已创建 tap, 所以即使 init 抛错
        // (无权限环境, 例如 CI), tap 也已在 WindowServer 注册过、并已随抛错时的 deinit
        // 销毁 —— 两条路径都必须回到基线, 泄漏断言对两者同样有效。
        let callback: CGEventTapCallBack = { _, _, event, _ in Unmanaged.passUnretained(event) }
        var interceptor: Interceptor?
        do {
            interceptor = try Interceptor(
                event: CGEventMask(1 << CGEventType.scrollWheel.rawValue),
                handleBy: callback,
                listenOn: .cgAnnotatedSessionEventTap,
                placeAt: .tailAppendEventTap,
                for: .listenOnly
            )
        } catch Interceptor.InterceptorError.eventTapCreationFailed {
            // 连 tap 都创建不了 (受限沙箱等), 无法验证泄漏, 跳过而非误报
            throw XCTSkip("无法创建 event tap")
        } catch {
            // 权限检查抛错: tap 曾被创建, deinit 已运行 —— 直接验证没有残留注册
            XCTAssertEqual(baseline, ownTapCount())
            return
        }

        XCTAssertNotNil(interceptor)
        XCTAssertEqual(baseline + 1, ownTapCount())

        interceptor = nil
        XCTAssertEqual(baseline, ownTapCount())
    }
}
