import Cocoa

// Resolve the probe before AppKit starts or checks for another Mos instance.
if CommandLine.arguments.count == 2, CommandLine.arguments[1] == InputPermissionProbe.argument {
    _exit(InputPermissionProbe.checkCurrentProcess() ? EXIT_SUCCESS : EXIT_FAILURE)
}

_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
