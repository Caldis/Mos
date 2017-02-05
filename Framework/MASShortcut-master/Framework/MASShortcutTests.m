@interface MASShortcutTests : XCTestCase
@end

@implementation MASShortcutTests

- (void) testEquality
{
    MASShortcut *keyA = [MASShortcut shortcutWithKeyCode:1 modifierFlags:NSControlKeyMask];
    MASShortcut *keyB = [MASShortcut shortcutWithKeyCode:2 modifierFlags:NSControlKeyMask];
    MASShortcut *keyC = [MASShortcut shortcutWithKeyCode:1 modifierFlags:NSAlternateKeyMask];
    MASShortcut *keyD = [MASShortcut shortcutWithKeyCode:1 modifierFlags:NSControlKeyMask];
    XCTAssertTrue([keyA isEqual:keyA], @"Shortcut is equal to itself.");
    XCTAssertTrue([keyA isEqual:[keyA copy]], @"Shortcut is equal to its copy.");
    XCTAssertFalse([keyA isEqual:keyB], @"Shortcuts not equal when key codes differ.");
    XCTAssertFalse([keyA isEqual:keyC], @"Shortcuts not equal when modifier flags differ.");
    XCTAssertTrue([keyA isEqual:keyD], @"Shortcuts are equal when key codes and modifiers are.");
    XCTAssertFalse([keyA isEqual:@"foo"], @"Shortcut not equal to an object of a different class.");
}

- (void) testShortcutRecorderCompatibility
{
    MASShortcut *key = [MASShortcut shortcutWithKeyCode:87 modifierFlags:1048576];
    XCTAssertEqualObjects([key description], @"⌘5", @"Basic compatibility with the keycode & modifier combination used by Shortcut Recorder.");
}

@end
