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

int main(int argc, char **argv) {
    @autoreleasepool {
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
