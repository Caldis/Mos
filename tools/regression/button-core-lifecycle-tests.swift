// 仅编译实际 ButtonCore.swift, 其依赖使用替身, 不安装全局监听或发送按键。
// 运行命令见 tools/README.md。

import Cocoa

enum OptionsGroup: Hashable { case buttons }
struct Binding { var isEnabled: Bool }
final class Buttons {
    var binding: [Binding] = [] { didSet { Options.shared.changed() } }
}
final class Options {
    static let shared = Options()
    let buttons = Buttons()
    var observers: [(OptionsGroup) -> Void] = []
    func observe(_ groups: Set<OptionsGroup>, handler: @escaping (OptionsGroup) -> Void) {
        observers.append(handler)
    }
    func changed() { for observer in observers { observer(.buttons) } }
}
struct InputEvent { init(fromCGEvent: CGEvent) {} }
enum InputResult { case consumed, passthrough }
enum MosEventMarker { static let syntheticCustom: Int64 = 123 }
final class InputProcessor {
    static let shared = InputProcessor()
    var activeModifierFlags: UInt64 = 0
    var clearCount = 0
    func process(_ event: InputEvent) -> InputResult { .passthrough }
    func clearActiveBindings() { clearCount += 1; activeModifierFlags = 0 }
}
final class Interceptor {
    static var created = 0
    static var stopped = 0
    static var live = 0
    static var failNext = false
    var onRestart: (() -> Void)?
    enum Failure: Error { case requested }
    init(event: CGEventMask, handleBy: @escaping CGEventTapCallBack,
         listenOn: CGEventTapLocation, placeAt: CGEventTapPlacement,
         for behavior: CGEventTapOptions) throws {
        if Self.failNext { Self.failNext = false; throw Failure.requested }
        Self.created += 1
        Self.live += 1
    }
    func stop() { Self.stopped += 1 }
    deinit { Self.live -= 1 }
}

@main
struct LifecycleRegression {
    static var assertions = 0
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        assertions += 1
        guard condition() else { fputs("FAIL: \(message)\n", stderr); exit(1) }
    }
    static func main() {
        let core = ButtonCore()
        core.enable()
        expect(core.isActive, "empty configuration keeps module enabled")
        expect(Interceptor.created == 0, "no tap with empty bindings")

        Options.shared.buttons.binding = [Binding(isEnabled: false)]
        expect(Interceptor.created == 0, "disabled bindings do not install a tap")

        Options.shared.buttons.binding[0].isEnabled = true
        expect(Interceptor.created == 1 && Interceptor.live == 1, "enabling first binding creates a tap")
        let firstTap = core.dispatchInterceptor
        Options.shared.buttons.binding.append(Binding(isEnabled: true))
        core.enable()
        expect(core.dispatchInterceptor === firstTap && Interceptor.created == 1,
               "binding edits and repeated enable preserve the existing tap")

        InputProcessor.shared.activeModifierFlags = CGEventFlags.maskShift.rawValue
        let clears = InputProcessor.shared.clearCount
        Options.shared.buttons.binding = []
        expect(core.dispatchInterceptor == nil && Interceptor.stopped == 1, "removing last binding stops tap")
        expect(InputProcessor.shared.activeModifierFlags == 0 && InputProcessor.shared.clearCount == clears + 1,
               "removing last binding releases held state")
        expect(core.isActive, "empty configuration still observes later changes")

        Options.shared.buttons.binding = [Binding(isEnabled: true)]
        expect(Interceptor.created == 2 && core.dispatchInterceptor != nil, "re-adding a binding restores tap")
        Options.shared.buttons.binding[0].isEnabled = false
        expect(core.dispatchInterceptor == nil && Interceptor.stopped == 2, "disabling last binding stops tap")

        core.disable()
        Options.shared.buttons.binding[0].isEnabled = true
        expect(!core.isActive && Interceptor.created == 2, "configuration changes cannot restart disabled module")
        core.enable()
        expect(core.isActive && Interceptor.created == 3, "explicit re-enable restores configured tap")
        core.disable()
        expect(core.dispatchInterceptor == nil && Interceptor.stopped == 3, "explicit disable stops tap")

        Interceptor.failNext = true
        core.enable()
        expect(!core.isActive && core.dispatchInterceptor == nil, "creation error leaves module inactive")
        core.enable()
        expect(core.isActive && Interceptor.created == 4, "explicit enable retries after creation error")
        core.disable()

        let key = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true)!
        key.flags = []
        let proxy = OpaquePointer(bitPattern: 1)!
        let returned = core.buttonEventCallBack(proxy, .keyDown, key, nil)?.takeUnretainedValue()
        expect(returned === key, "unbound keyboard event passes through unchanged")
        expect(key.flags == [], "passthrough does not inject modifiers")
        print("PASS: \(assertions) lifecycle assertions; Interceptor replaced with a test double, no global taps installed")
    }
}
