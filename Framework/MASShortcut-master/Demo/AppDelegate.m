#import "AppDelegate.h"

static NSString *const MASCustomShortcutKey = @"customShortcut";
static NSString *const MASCustomShortcutEnabledKey = @"customShortcutEnabled";
static NSString *const MASHardcodedShortcutEnabledKey = @"hardcodedShortcutEnabled";

static void *MASObservingContext = &MASObservingContext;

@interface AppDelegate ()
@property(strong) IBOutlet MASShortcutView *customShortcutView;
@property(strong) IBOutlet NSTextField *feedbackTextField;
@end

@implementation AppDelegate

- (void) awakeFromNib
{
    [super awakeFromNib];

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

	// Most apps need default shortcut, delete these lines if this is not your case
	MASShortcut *firstLaunchShortcut = [MASShortcut shortcutWithKeyCode:kVK_F1 modifierFlags:NSEventModifierFlagCommand];
	NSData *firstLaunchShortcutData = [NSKeyedArchiver archivedDataWithRootObject:firstLaunchShortcut];

    // Register default values to be used for the first app start
    [defaults registerDefaults:@{
        MASHardcodedShortcutEnabledKey : @YES,
        MASCustomShortcutEnabledKey : @YES,
		MASCustomShortcutKey : firstLaunchShortcutData
    }];

    // Bind the shortcut recorder view’s value to user defaults.
    // Run “defaults read com.shpakovski.mac.Demo” to see what’s stored
    // in user defaults.
    [_customShortcutView setAssociatedUserDefaultsKey:MASCustomShortcutKey];

    // Enable or disable the recorder view according to the first checkbox state
    [_customShortcutView bind:@"enabled" toObject:defaults
        withKeyPath:MASCustomShortcutEnabledKey options:nil];

    // Watch user defaults for changes in the checkbox states
    [defaults addObserver:self forKeyPath:MASCustomShortcutEnabledKey
        options:NSKeyValueObservingOptionInitial|NSKeyValueObservingOptionNew
        context:MASObservingContext];
    [defaults addObserver:self forKeyPath:MASHardcodedShortcutEnabledKey
        options:NSKeyValueObservingOptionInitial|NSKeyValueObservingOptionNew
        context:MASObservingContext];
}

- (void)playShortcutFeedback
{
    [[NSSound soundNamed:@"Ping"] play];
    [_feedbackTextField setStringValue:NSLocalizedString(@"Shortcut pressed!", @"Feedback that’s displayed when user presses the sample shortcut.")];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [_feedbackTextField setStringValue:@""];
    });
}

// Handle changes in user defaults. We have to check keyPath here to see which of the
// two checkboxes was changed. This is not very elegant, in practice you could use something
// like https://github.com/facebook/KVOController with a nicer API.
- (void) observeValueForKeyPath: (NSString*) keyPath ofObject: (id) object change: (NSDictionary*) change context: (void*) context
{
    if (context != MASObservingContext) {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
        return;
    }

    BOOL newValue = [[change objectForKey:NSKeyValueChangeNewKey] boolValue];
    if ([keyPath isEqualToString:MASCustomShortcutEnabledKey]) {
        [self setCustomShortcutEnabled:newValue];
    } else if ([keyPath isEqualToString:MASHardcodedShortcutEnabledKey]) {
        [self setHardcodedShortcutEnabled:newValue];
    }
}

- (void) setCustomShortcutEnabled: (BOOL) enabled
{
    if (enabled) {
        [[MASShortcutBinder sharedBinder] bindShortcutWithDefaultsKey:MASCustomShortcutKey toAction:^{
            [self playShortcutFeedback];
        }];
    } else {
        [[MASShortcutBinder sharedBinder] breakBindingWithDefaultsKey:MASCustomShortcutKey];
    }
}

- (void) setHardcodedShortcutEnabled: (BOOL) enabled
{
    MASShortcut *shortcut = [MASShortcut shortcutWithKeyCode:kVK_F2 modifierFlags:NSEventModifierFlagCommand];
    if (enabled) {
        [[MASShortcutMonitor sharedMonitor] registerShortcut:shortcut withAction:^{
            [self playShortcutFeedback];
        }];
    } else {
        [[MASShortcutMonitor sharedMonitor] unregisterShortcut:shortcut];
    }
}

#pragma mark NSApplicationDelegate

- (BOOL) applicationShouldTerminateAfterLastWindowClosed: (NSApplication*) sender
{
    return YES;
}

@end
