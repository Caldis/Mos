import Cocoa

enum WINDOW_IDENTIFIER: String {
    case welcomeWindowController
    case monitorWindowController
    case preferencesWindowController
    case hideStatusItemWindowController
}

print(WINDOW_IDENTIFIER.welcomeWindowController.rawValue)
