#import <Cocoa/Cocoa.h>
#import <ghostty.h>
#import "KobaApp.h"

static NSMenu *KobaMainMenu(void) {
    NSMenu *menubar = [[NSMenu alloc] init];

    NSMenuItem *appItem = [menubar addItemWithTitle:@"" action:nil keyEquivalent:@""];
    NSMenu *appMenu = [[NSMenu alloc] init];
    [appMenu addItemWithTitle:@"Quit Koba" action:@selector(terminate:) keyEquivalent:@"q"];
    appItem.submenu = appMenu;

    NSMenuItem *fileItem = [menubar addItemWithTitle:@"" action:nil keyEquivalent:@""];
    NSMenu *fileMenu = [[NSMenu alloc] initWithTitle:@"File"];
    [fileMenu addItemWithTitle:@"New Workspace" action:@selector(newWorkspace:) keyEquivalent:@"n"];
    [fileMenu addItemWithTitle:@"Close Workspace" action:@selector(closeWorkspace:) keyEquivalent:@"w"];
    fileItem.submenu = fileMenu;

    // The bracket shortcuts are handled by a key event monitor in KobaApp;
    // these items exist for discoverability. Shifted equivalents use the
    // shifted character with shift implied.
    NSMenuItem *viewItem = [menubar addItemWithTitle:@"" action:nil keyEquivalent:@""];
    NSMenu *viewMenu = [[NSMenu alloc] initWithTitle:@"View"];
    NSMenuItem *nextPane = [viewMenu addItemWithTitle:@"Next Pane"
                                               action:@selector(cycleNextPane:)
                                        keyEquivalent:@"}"];
    nextPane.keyEquivalentModifierMask = NSEventModifierFlagCommand;
    NSMenuItem *previousPane = [viewMenu addItemWithTitle:@"Previous Pane"
                                                   action:@selector(cyclePreviousPane:)
                                            keyEquivalent:@"{"];
    previousPane.keyEquivalentModifierMask = NSEventModifierFlagCommand;
    [viewMenu addItem:NSMenuItem.separatorItem];
    [viewMenu addItemWithTitle:@"Next Workspace"
                        action:@selector(cycleNextWorkspace:)
                 keyEquivalent:@"]"];
    [viewMenu addItemWithTitle:@"Previous Workspace"
                        action:@selector(cyclePreviousWorkspace:)
                 keyEquivalent:@"["];
    viewItem.submenu = viewMenu;

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
        app.mainMenu = KobaMainMenu();

        KobaApp *delegate = [[KobaApp alloc] init];
        app.delegate = delegate;

        [app run];
    }
    return 0;
}
