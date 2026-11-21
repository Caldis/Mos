import ApplicationServices
import Darwin
import Foundation
import IOKit.hidsystem

enum InputPermissionProbe {
    static let argument = "--mos-check-input-permission"

    static func checkCurrentProcess() -> Bool {
        if #available(macOS 10.15, *) {
            return IOHIDCheckAccess(kIOHIDRequestTypePostEvent) == kIOHIDAccessTypeGranted
        }
        return AXIsProcessTrusted()
    }

    static func sample() -> Bool {
        guard let executable = Bundle.main.executableURL else { return false }
        // A running process can retain an old TCC decision after both revoke and grant.
        return run(executable: executable, arguments: [argument], timeout: .milliseconds(900))
    }

    static func run(executable: URL, arguments: [String], timeout: DispatchTimeInterval) -> Bool {
        let path = executable.path
        var argv = ([path] + arguments).map { strdup($0) }
        defer { argv.forEach { free($0) } }
        guard argv.allSatisfy({ $0 != nil }) else { return false }
        argv.append(nil)

        var pid: pid_t = 0
        guard posix_spawn(&pid, path, nil, nil, &argv, environ) == 0 else { return false }

        let exited = DispatchSemaphore(value: 0)
        let observer = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: .global(qos: .utility))
        observer.setEventHandler { exited.signal() }
        observer.resume()
        defer { observer.cancel() }

        var status: CInt = 0
        var result: pid_t
        repeat { result = waitpid(pid, &status, WNOHANG) } while result == -1 && errno == EINTR
        if result == pid { return status == 0 }
        guard result == 0 else { return false }

        let timedOut = exited.wait(timeout: .now() + timeout) == .timedOut
        if timedOut {
            // The PID cannot be reused before we reap this child.
            kill(pid, SIGKILL)
        }
        repeat { result = waitpid(pid, &status, 0) } while result == -1 && errno == EINTR
        return !timedOut && result == pid && status == 0
    }
}
