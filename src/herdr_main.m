#import <Cocoa/Cocoa.h>
#import <ghostty.h>
#import "HerdrApp.h"

static NSMenu *HerdrMainMenu(void) {
    NSMenu *menubar = [[NSMenu alloc] init];

    NSMenuItem *appItem = [menubar addItemWithTitle:@"" action:nil keyEquivalent:@""];
    NSMenu *appMenu = [[NSMenu alloc] init];
    [appMenu addItemWithTitle:@"Quit Herdr" action:@selector(terminate:) keyEquivalent:@"q"];
    appItem.submenu = appMenu;

    return menubar;
}

// Launched from inside a herdr pane (e.g. `make reload-herdr`), the app
// inherits that pane's HERDR_* variables and herdr refuses to start as a
// nested client. The app is always the outermost client, so drop them.
static void HerdrClearInheritedEnvironment(void) {
    for (NSString *name in NSProcessInfo.processInfo.environment) {
        if ([name hasPrefix:@"HERDR_"]) unsetenv(name.UTF8String);
    }
}

int main(int argc, char **argv) {
    @autoreleasepool {
        HerdrClearInheritedEnvironment();

        // libghostty locates terminfo, shell integration, and themes through
        // this. Set before ghostty_init.
        NSString *resources =
            [NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:@"ghostty"];
        setenv("GHOSTTY_RESOURCES_DIR", resources.fileSystemRepresentation, 1);

        if (ghostty_init((uintptr_t)argc, argv) != 0) {
            NSLog(@"ghostty_init failed");
            return 1;
        }

        NSApplication *app = NSApplication.sharedApplication;
        app.activationPolicy = NSApplicationActivationPolicyRegular;
        app.mainMenu = HerdrMainMenu();

        HerdrApp *delegate = [[HerdrApp alloc] init];
        app.delegate = delegate;

        [app run];
    }
    return 0;
}
