#import "HerdrApp.h"
#import "KobaClipboard.h"
#import "KobaColors.h"
#import "KobaSurfaceView.h"
#import <Carbon/Carbon.h>
#import <WebKit/WebKit.h>

// Finds the herdr binary without starting a shell; an interactive shell
// would draw its prompt before herdr takes over the screen. Apps launched
// from Finder get a minimal PATH, so the usual install locations are checked
// too.
static NSString *HerdrExecutablePath(void) {
    NSString *home = NSHomeDirectory();
    NSMutableArray<NSString *> *directories = [NSMutableArray array];
    NSString *path = NSProcessInfo.processInfo.environment[@"PATH"];
    if (path.length > 0) [directories addObjectsFromArray:[path componentsSeparatedByString:@":"]];
    [directories addObjectsFromArray:@[
        @"/opt/homebrew/bin",
        @"/usr/local/bin",
        [home stringByAppendingPathComponent:@".local/bin"],
        [home stringByAppendingPathComponent:@".cargo/bin"],
        [home stringByAppendingPathComponent:@".local/share/mise/shims"],
    ]];

    for (NSString *directory in directories) {
        NSString *candidate = [directory stringByAppendingPathComponent:@"herdr"];
        if ([NSFileManager.defaultManager isExecutableFileAtPath:candidate]) return candidate;
    }
    return nil;
}

static const NSTimeInterval HerdrStatusInterval = 3;
static const NSTimeInterval HerdrFullRefreshInterval = 120;

#pragma mark - libghostty runtime callbacks

// Wakeup may be called from any thread; ticks must run on the main thread.
static void herdr_wakeup(void *userdata) {
    HerdrApp *app = (__bridge HerdrApp *)userdata;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (app.ghosttyApp) ghostty_app_tick(app.ghosttyApp);
    });
}

static bool herdr_action(ghostty_app_t app,
                         ghostty_target_s target,
                         ghostty_action_s action) {
    switch (action.tag) {
        case GHOSTTY_ACTION_RING_BELL: {
            dispatch_async(dispatch_get_main_queue(), ^{ NSBeep(); });
            return true;
        }

        case GHOSTTY_ACTION_QUIT: {
            dispatch_async(dispatch_get_main_queue(), ^{
                [NSApp terminate:nil];
            });
            return true;
        }

        // The window is always "Herdr"; tabs, splits, and new windows are
        // herdr's job, so ghostty's own versions are swallowed.
        case GHOSTTY_ACTION_SET_TITLE:
        case GHOSTTY_ACTION_NEW_WINDOW:
        case GHOSTTY_ACTION_NEW_TAB:
        case GHOSTTY_ACTION_NEW_SPLIT:
        case GHOSTTY_ACTION_CLOSE_WINDOW:
        case GHOSTTY_ACTION_GOTO_TAB:
        case GHOSTTY_ACTION_RENDER:
        case GHOSTTY_ACTION_CELL_SIZE:
        case GHOSTTY_ACTION_INITIAL_SIZE:
        case GHOSTTY_ACTION_SIZE_LIMIT:
        case GHOSTTY_ACTION_MOUSE_SHAPE:
        case GHOSTTY_ACTION_MOUSE_VISIBILITY:
        case GHOSTTY_ACTION_MOUSE_OVER_LINK:
        case GHOSTTY_ACTION_CONFIG_CHANGE:
        case GHOSTTY_ACTION_PWD:
        case GHOSTTY_ACTION_PROGRESS_REPORT:
            return true;

        default:
            return false;
    }
}

// Herdr exiting (detach) ends the app.
static void herdr_close_surface(void *userdata, bool processAlive) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [NSApp terminate:nil];
    });
}

#pragma mark - HerdrApp

@interface HerdrApp () <WKNavigationDelegate>
@end

@implementation HerdrApp {
    ghostty_config_t _config;
    NSWindow *_window;
    KobaSurfaceView *_surfaceView;
    NSString *_herdrPath;
    NSTask *_statusTask;
    NSTimer *_statusTimer;
    NSDate *_lastFullRefresh;
    BOOL _fullRefreshDue;
    NSView *_content;
    WKWebView *_page;
    NSURL *_pendingPage;
    id _keyMonitor;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    _herdrPath = HerdrExecutablePath();
    if (_herdrPath == nil) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"herdr not found";
        alert.informativeText = @"Install it with: brew install herdr";
        [alert runModal];
        [NSApp terminate:nil];
        return;
    }

    // A fresh herdr server inherits this environment; keep herdr's own
    // directory on PATH so tools installed alongside it resolve.
    NSString *path = NSProcessInfo.processInfo.environment[@"PATH"] ?: @"/usr/bin:/bin";
    NSString *herdrDirectory = _herdrPath.stringByDeletingLastPathComponent;
    setenv("PATH", [herdrDirectory stringByAppendingFormat:@":%@", path].UTF8String, 1);

    // Respects the user's regular ghostty config (fonts, theme, keybinds),
    // then the bundled one frees the chords herdr binds.
    _config = ghostty_config_new();
    ghostty_config_load_default_files(_config);
    NSString *bundled = [NSBundle.mainBundle pathForResource:@"herdr" ofType:@"ghostty"];
    if (bundled) ghostty_config_load_file(_config, bundled.fileSystemRepresentation);
    ghostty_config_finalize(_config);

    ghostty_config_color_s bg = {0};
    ghostty_config_color_s fg = {0};
    if (ghostty_config_get(_config, &bg, "background", strlen("background")) &&
        ghostty_config_get(_config, &fg, "foreground", strlen("foreground"))) {
        KobaColorsInitialize(
            [NSColor colorWithSRGBRed:bg.r / 255.0 green:bg.g / 255.0 blue:bg.b / 255.0 alpha:1],
            [NSColor colorWithSRGBRed:fg.r / 255.0 green:fg.g / 255.0 blue:fg.b / 255.0 alpha:1]);
    }

    ghostty_runtime_config_s runtime = {
        .userdata = (__bridge void *)self,
        .supports_selection_clipboard = false,
        .wakeup_cb = herdr_wakeup,
        .action_cb = herdr_action,
        .read_clipboard_cb = KobaReadClipboard,
        .confirm_read_clipboard_cb = KobaConfirmReadClipboard,
        .write_clipboard_cb = KobaWriteClipboard,
        .close_surface_cb = herdr_close_surface,
    };

    _ghosttyApp = ghostty_app_new(&runtime, _config);
    if (_ghosttyApp == NULL) {
        NSLog(@"ghostty_app_new failed");
        [NSApp terminate:nil];
        return;
    }

    ghostty_app_set_focus(_ghosttyApp, NSApp.isActive);

    [self createWindow];

    // Esc closes an open page; the page would otherwise swallow it.
    _keyMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown
                                                        handler:^NSEvent *(NSEvent *event) {
        if (self->_page == nil || event.keyCode != kVK_Escape) return event;
        [self closePage];
        return nil;
    }];

    // The sidebar's ticket and PR tokens follow each space's branch, which
    // changes inside herdr where the app can't see it, so poll. Ticks are
    // cheap; GitHub is only asked on a branch change or a full refresh. The
    // first run is full, so tokens left by a previous launch are corrected.
    _fullRefreshDue = YES;
    _statusTimer = [NSTimer scheduledTimerWithTimeInterval:HerdrStatusInterval
                                                   repeats:YES
                                                     block:^(NSTimer *timer) {
        [self refreshStatus];
    }];
}

// Runs the bundled herdr-pr-status script unless a run is still going. A full
// refresh re-checks every PR, since they merge and close on GitHub.
- (void)refreshStatus {
    if (_statusTask.isRunning) return;
    NSString *script = [NSBundle.mainBundle pathForResource:@"herdr-pr-status"
                                                     ofType:nil
                                                inDirectory:@"scripts"];
    if (script == nil) return;

    BOOL full = _fullRefreshDue ||
        -_lastFullRefresh.timeIntervalSinceNow >= HerdrFullRefreshInterval;
    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:@"/usr/bin/env"];
    task.arguments = full ? @[ @"bash", script, @"--full" ] : @[ @"bash", script ];
    task.standardOutput = NSFileHandle.fileHandleWithNullDevice;
    task.standardError = NSFileHandle.fileHandleWithNullDevice;
    if (![task launchAndReturnError:nil]) return;

    _statusTask = task;
    if (full) {
        _fullRefreshDue = NO;
        _lastFullRefresh = NSDate.date;
    }
}

- (void)createWindow {
    NSRect frame = NSMakeRect(0, 0, 1200, 800);
    _window = [[NSWindow alloc]
        initWithContentRect:frame
                  styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                            NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable
                    backing:NSBackingStoreBuffered
                      defer:NO];
    _window.title =
        [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleName"] ?: @"Herdr";
    _window.releasedWhenClosed = NO;
    _window.delegate = self;
    _window.tabbingMode = NSWindowTabbingModeDisallowed;
    _window.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
    _window.backgroundColor = KobaColorAppBackground();

    _surfaceView = [[KobaSurfaceView alloc] initWithGhosttyApp:_ghosttyApp
                                              workingDirectory:NSHomeDirectory()
                                                       command:KobaShellEscape(_herdrPath)];
    if (_surfaceView == nil) {
        NSLog(@"ghostty_surface_new failed");
        [NSApp terminate:nil];
        return;
    }
    _surfaceView.showsFocusBorder = NO;
    _surfaceView.frame = frame;
    _surfaceView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

    // Pages opened in the app sit above the terminal in this container.
    _content = [[NSView alloc] initWithFrame:frame];
    [_content addSubview:_surfaceView];
    _window.contentView = _content;

    // Restore last session's size and position; center only on first run.
    BOOL restored = [_window setFrameUsingName:@"HerdrMain"];
    _window.frameAutosaveName = @"HerdrMain";
    if (!restored) [_window center];

    [_window makeKeyAndOrderFront:nil];
    [_window makeFirstResponder:_surfaceView];

    if (_pendingPage) {
        [self showPage:_pendingPage];
        _pendingPage = nil;
    }
}

#pragma mark - Pages

// `open -a Herdr page.html` lands here, possibly before the window exists.
- (void)application:(NSApplication *)application openURLs:(NSArray<NSURL *> *)urls {
    if (_window == nil) {
        _pendingPage = urls.lastObject;
        return;
    }
    [self showPage:urls.lastObject];
}

// Shows a page over the terminal, replacing any open one. Esc closes it.
- (void)showPage:(NSURL *)url {
    if (_page == nil) {
        _page = [[WKWebView alloc] initWithFrame:_content.bounds
                                   configuration:[[WKWebViewConfiguration alloc] init]];
        _page.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        _page.navigationDelegate = self;
        [_content addSubview:_page];
    }
    if (url.isFileURL) {
        // Relative assets next to the file (images, CSS) load too.
        [_page loadFileURL:url allowingReadAccessToURL:url.URLByDeletingLastPathComponent];
    } else {
        [_page loadRequest:[NSURLRequest requestWithURL:url]];
    }
    [NSApp activateIgnoringOtherApps:YES];
    [_window makeKeyAndOrderFront:nil];
    [_window makeFirstResponder:_page];
}

- (void)closePage {
    [_page removeFromSuperview];
    _page = nil;
    [_window makeFirstResponder:_surfaceView];
}

// Links out of the page open in the default browser rather than replacing it.
- (void)webView:(WKWebView *)webView
    decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction
                    decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    NSURL *url = navigationAction.request.URL;
    if (navigationAction.navigationType == WKNavigationTypeLinkActivated && !url.isFileURL) {
        [NSWorkspace.sharedWorkspace openURL:url];
        decisionHandler(WKNavigationActionPolicyCancel);
        return;
    }
    decisionHandler(WKNavigationActionPolicyAllow);
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return YES;
}

- (void)applicationDidBecomeActive:(NSNotification *)notification {
    if (_ghosttyApp) ghostty_app_set_focus(_ghosttyApp, true);
    // A PR is usually merged in the browser; catch up the moment the user
    // comes back rather than waiting for the timer.
    _fullRefreshDue = YES;
    [self refreshStatus];
}

- (void)applicationDidResignActive:(NSNotification *)notification {
    if (_ghosttyApp) ghostty_app_set_focus(_ghosttyApp, false);
}

- (void)windowWillClose:(NSNotification *)notification {
    [_surfaceView closeSurface];
    _surfaceView = nil;
}

@end
