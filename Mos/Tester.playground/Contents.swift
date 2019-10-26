import Cocoa

enum WINDOW_IDENTIFIER: String {
    case welcomeWindowController
    case monitorWindowController
    case preferencesWindowController
    case hideStatusItemWindowController
}

print(WINDOW_IDENTIFIER.welcomeWindowController.rawValue)

class TestWindowController: NSWindowController, NSWindowDelegate {
    override func windowDidLoad() {
        super.windowDidLoad()
        print("sdfsdf", window?.frame.size)
    }
}
