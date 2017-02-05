#import "MASShortcutMonitor.h"

@interface MASShortcutMonitorTests : XCTestCase
@end

@implementation MASShortcutMonitorTests

- (void) testMonitorCreation
{
    XCTAssertNotNil([MASShortcutMonitor sharedMonitor], @"Create a shared shortcut monitor.");
}

- (void) testShortcutRegistration
{
    MASShortcutMonitor *monitor = [MASShortcutMonitor sharedMonitor];
    MASShortcut *shortcut = [MASShortcut shortcutWithKeyCode:kVK_ANSI_H modifierFlags:NSCommandKeyMask|NSAlternateKeyMask];
    XCTAssertTrue([monitor registerShortcut:shortcut withAction:NULL], @"Register a shortcut.");
    XCTAssertTrue([monitor isShortcutRegistered:shortcut], @"Remember a previously registered shortcut.");
    [monitor unregisterShortcut:shortcut];
    XCTAssertFalse([monitor isShortcutRegistered:shortcut], @"Forget shortcut after unregistering.");
}

@end
