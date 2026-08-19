#import "KobaApp.h"
#import "KobaColors.h"
#import "KobaCommandPalette.h"
#import "KobaConfig.h"
#import "KobaSurfaceView.h"
#import "KobaWorkspace.h"
#import "KobaWorkspaceStrip.h"
#import <Carbon/Carbon.h>

static const CGFloat KobaStripHeight = 96;

@interface KobaApp ()
- (void)closeWorkspaceContainingPane:(KobaSurfaceView *)view;
- (void)updateClaudeStatusForPane:(KobaSurfaceView *)view
                    progressState:(ghostty_action_progress_report_state_e)state;
- (void)selectWorkspaceAtIndex:(NSInteger)index;
- (void)toggleOverview;
- (void)selectWorkspaceForGotoTab:(NSInteger)which;
- (void)refreshStrip;
- (void)refreshPRForWorkspaceContainingPane:(KobaSurfaceView *)view;
- (void)newWorkspaceInDirectory:(nullable NSString *)directory;
- (void)dismissPalette;
- (void)ensureWindow;
- (void)showRepoPickerMandatory:(BOOL)mandatory
                 includeRestore:(BOOL)includeRestore
                     withAction:(void (^)(NSString *directory))perform;
- (NSUInteger)restorableWorkspaceCount;
- (BOOL)restoreState;
@end

static NSString *KobaRunCommand(NSString *gh, NSString *pwd, NSArray<NSString *> *arguments);
static NSString *KobaTicketFromBranch(NSString *branch);
static NSFont *KobaHelpDescFont(void);

static KobaApp *KobaAppFrom(void *userdata) {
    return (__bridge KobaApp *)userdata;
}

static KobaSurfaceView *KobaViewFrom(void *userdata) {
    return (__bridge KobaSurfaceView *)userdata;
}

static KobaSurfaceView *KobaViewFromSurface(ghostty_surface_t surface) {
    void *userdata = ghostty_surface_userdata(surface);
    return userdata ? (__bridge KobaSurfaceView *)userdata : nil;
}

#pragma mark - libghostty runtime callbacks

// Wakeup may be called from any thread; ticks must run on the main thread.
static void koba_wakeup(void *userdata) {
    KobaApp *app = KobaAppFrom(userdata);
    dispatch_async(dispatch_get_main_queue(), ^{
        if (app.ghosttyApp) ghostty_app_tick(app.ghosttyApp);
    });
}

static bool koba_action(ghostty_app_t app,
                        ghostty_target_s target,
                        ghostty_action_s action) {
    KobaApp *koba = KobaAppFrom(ghostty_app_userdata(app));

    switch (action.tag) {
        case GHOSTTY_ACTION_NEW_WINDOW: {
            dispatch_async(dispatch_get_main_queue(), ^{
                [koba newWorkspace:nil];
            });
            return true;
        }

        case GHOSTTY_ACTION_CLOSE_WINDOW: {
            dispatch_async(dispatch_get_main_queue(), ^{
                [koba closeWorkspace:nil];
            });
            return true;
        }

        // Shells may not retitle the window; it is always "Koba".
        case GHOSTTY_ACTION_SET_TITLE:
            return true;

        // ghostty's default tab bindings (cmd+1..9, ctrl+tab, ...) drive
        // workspace switching.
        case GHOSTTY_ACTION_GOTO_TAB: {
            NSInteger which = action.action.goto_tab;
            dispatch_async(dispatch_get_main_queue(), ^{
                [koba selectWorkspaceForGotoTab:which];
            });
            return true;
        }

        // The shell reports its working directory; the workspace card shows
        // the containing repository (or directory) name.
        case GHOSTTY_ACTION_PWD: {
            if (target.tag != GHOSTTY_TARGET_SURFACE) return false;
            KobaSurfaceView *view = KobaViewFromSurface(target.target.surface);
            NSString *pwd = action.action.pwd.pwd
                ? [NSString stringWithUTF8String:action.action.pwd.pwd]
                : nil;
            dispatch_async(dispatch_get_main_queue(), ^{
                view.pwd = pwd;
                [koba refreshStrip];
                [koba refreshPRForWorkspaceContainingPane:view];
            });
            return true;
        }

        // Progress reports (OSC 9;4) from the Agent pane drive the card's
        // Claude status. Only the main Claude session writes these, so
        // subagent activity never flickers the border.
        case GHOSTTY_ACTION_PROGRESS_REPORT: {
            if (target.tag != GHOSTTY_TARGET_SURFACE) return false;
            KobaSurfaceView *view = KobaViewFromSurface(target.target.surface);
            ghostty_action_progress_report_state_e state = action.action.progress_report.state;
            dispatch_async(dispatch_get_main_queue(), ^{
                [koba updateClaudeStatusForPane:view progressState:state];
            });
            return true;
        }

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

        // Informational actions we deliberately accept and ignore so ghostty
        // doesn't log them as unsupported.
        case GHOSTTY_ACTION_RENDER:
        case GHOSTTY_ACTION_CELL_SIZE:
        case GHOSTTY_ACTION_INITIAL_SIZE:
        case GHOSTTY_ACTION_SIZE_LIMIT:
        case GHOSTTY_ACTION_MOUSE_SHAPE:
        case GHOSTTY_ACTION_MOUSE_VISIBILITY:
        case GHOSTTY_ACTION_MOUSE_OVER_LINK:
        case GHOSTTY_ACTION_CONFIG_CHANGE:
            return true;

        default:
            return false;
    }
}

static bool koba_read_clipboard(void *userdata, ghostty_clipboard_e location, void *state) {
    KobaSurfaceView *view = KobaViewFrom(userdata);
    if (view.surface == NULL) return false;
    NSString *string = [NSPasteboard.generalPasteboard stringForType:NSPasteboardTypeString];
    if (string == nil) return false;
    ghostty_surface_complete_clipboard_request(view.surface, string.UTF8String, state, false);
    return true;
}

// Paste confirmation (e.g. pasting text with control characters). We skip
// the dialog and confirm directly.
static void koba_confirm_read_clipboard(void *userdata,
                                        const char *string,
                                        void *state,
                                        ghostty_clipboard_request_e request) {
    KobaSurfaceView *view = KobaViewFrom(userdata);
    if (view.surface == NULL || string == NULL) return;
    ghostty_surface_complete_clipboard_request(view.surface, string, state, true);
}

static void koba_write_clipboard(void *userdata,
                                 ghostty_clipboard_e location,
                                 const ghostty_clipboard_content_s *content,
                                 size_t len,
                                 bool confirm) {
    for (size_t i = 0; i < len; i++) {
        if (content[i].mime == NULL || content[i].data == NULL) continue;
        if (strcmp(content[i].mime, "text/plain") != 0) continue;
        NSString *string = [NSString stringWithUTF8String:content[i].data];
        if (string == nil) continue;
        NSPasteboard *pasteboard = NSPasteboard.generalPasteboard;
        [pasteboard clearContents];
        [pasteboard setString:string forType:NSPasteboardTypeString];
        return;
    }
}

// Panes are pinned: a workspace is always Terminal + Agent. Any surface
// close (cmd+w binding, shell exit) closes its whole workspace.
static void koba_close_surface(void *userdata, bool processAlive) {
    KobaSurfaceView *view = KobaViewFrom(userdata);
    dispatch_async(dispatch_get_main_queue(), ^{
        KobaApp *koba = (KobaApp *)NSApp.delegate;
        [koba closeWorkspaceContainingPane:view];
    });
}

#pragma mark - KobaApp

@implementation KobaApp {
    ghostty_config_t _config;
    NSWindow *_window;
    NSView *_workspaceContainer;
    KobaWorkspaceStrip *_strip;
    NSMutableArray<KobaWorkspace *> *_workspaces;
    NSInteger _selectedIndex;
    NSInteger _indexBeforeOverview;
    id _keyMonitor;
    NSView *_keybindingsOverlay;
    NSView *_paletteOverlay;
    KobaCommandPalette *_palette;
    NSArray<void (^)(void)> *_paletteActions;
    void (^_paletteInputHandler)(NSString *);
    BOOL _paletteMandatory;
    KobaConfig *_kobaConfig;
}

- (instancetype)init {
    self = [super init];
    if (!self) return nil;
    _workspaces = [NSMutableArray array];
    _selectedIndex = -1;
    return self;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    // koba.json is required; a default is written on first run. Refuse to
    // run without a valid one.
    NSError *configError;
    _kobaConfig = [KobaConfig loadWithError:&configError];
    if (_kobaConfig == nil) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Invalid koba.json";
        alert.informativeText = [NSString stringWithFormat:@"%@\n\n%@",
                                 configError.localizedDescription, KobaConfig.path];
        [alert runModal];
        [NSApp terminate:nil];
        return;
    }

    // Respects the user's regular ghostty config (fonts, theme, keybinds).
    _config = ghostty_config_new();
    ghostty_config_load_default_files(_config);
    ghostty_config_finalize(_config);

    // Koba's chrome palette derives from the theme's background/foreground
    // so the app always matches the terminal.
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
        .wakeup_cb = koba_wakeup,
        .action_cb = koba_action,
        .read_clipboard_cb = koba_read_clipboard,
        .confirm_read_clipboard_cb = koba_confirm_read_clipboard,
        .write_clipboard_cb = koba_write_clipboard,
        .close_surface_cb = koba_close_surface,
    };

    _ghosttyApp = ghostty_app_new(&runtime, _config);
    if (_ghosttyApp == NULL) {
        NSLog(@"ghostty_app_new failed");
        [NSApp terminate:nil];
        return;
    }

    ghostty_app_set_focus(_ghosttyApp, NSApp.isActive);

    // Pane and workspace switching is keyboard only, and these shortcuts may
    // not reach ghostty (it binds them to its own actions). A local monitor
    // sees every key event before anything else can consume it.
    _keyMonitor = [NSEvent
        addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown
                                     handler:^NSEvent *(NSEvent *event) {
        NSEventModifierFlags mods =
            event.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask;

        // While the keybindings overlay is up, any key dismisses it. Quit
        // still works: close the overlay and let the menu handle cmd+q.
        if (self->_keybindingsOverlay != nil) {
            [self toggleKeybindings];
            if (mods == NSEventModifierFlagCommand && event.keyCode == kVK_ANSI_Q) {
                return event;
            }
            return nil;
        }

        // The command palette owns the keyboard while open. A mandatory
        // palette (the launch repo picker) can only be answered, not closed.
        if (self->_paletteOverlay != nil) {
            switch (event.keyCode) {
                case kVK_DownArrow: [self->_palette moveSelection:1]; break;
                case kVK_UpArrow: [self->_palette moveSelection:-1]; break;
                case kVK_Return:
                case kVK_ANSI_KeypadEnter: {
                    if (self->_paletteInputHandler != nil) {
                        void (^handler)(NSString *) = self->_paletteInputHandler;
                        NSString *text = self->_palette.query;
                        [self dismissPalette];
                        handler(text);
                        break;
                    }
                    NSInteger index = self->_palette.selectedIndex;
                    NSArray<void (^)(void)> *actions = self->_paletteActions;
                    [self dismissPalette];
                    if (index >= 0 && index < (NSInteger)actions.count) {
                        actions[(NSUInteger)index]();
                    }
                    break;
                }
                case kVK_Escape:
                    if (!self->_paletteMandatory) [self dismissPalette];
                    break;
                case kVK_ANSI_P:
                    if (mods == (NSEventModifierFlagCommand | NSEventModifierFlagShift) &&
                        !self->_paletteMandatory) {
                        [self dismissPalette];
                        break;
                    }
                    // fallthrough: plain p filters
                default: {
                    // Quit must keep working even under a mandatory
                    // palette; let the menu handle it.
                    if (mods == NSEventModifierFlagCommand && event.keyCode == kVK_ANSI_Q) {
                        return event;
                    }
                    if (event.keyCode == kVK_Delete) {
                        [self->_palette deleteQueryCharacter];
                        break;
                    }
                    // Printable characters filter the list.
                    if (!(event.modifierFlags &
                          (NSEventModifierFlagCommand | NSEventModifierFlagControl))) {
                        NSString *characters = event.characters;
                        if (characters.length > 0) {
                            unichar first = [characters characterAtIndex:0];
                            if (first >= 0x20 && first != 0x7F &&
                                !(first >= 0xF700 && first <= 0xF8FF)) {
                                [self->_palette appendQuery:characters];
                            }
                        }
                    }
                    break;
                }
            }
            return nil;
        }

        if (mods == NSEventModifierFlagCommand && event.keyCode == kVK_ISO_Section) {
            [self toggleOverview];
            return nil;
        }

        // ghostty's cmd+1..9 binding is delivered by the focused surface, and
        // the overview has none; handle the digits here instead.
        if (self->_selectedIndex < 0 && mods == NSEventModifierFlagCommand) {
            NSString *characters = event.charactersIgnoringModifiers;
            unichar digit = characters.length == 1 ? [characters characterAtIndex:0] : 0;
            if (digit >= '1' && digit <= '9') {
                [self selectWorkspaceForGotoTab:digit - '0'];
                return nil;
            }
        }

        if (mods == (NSEventModifierFlagCommand | NSEventModifierFlagShift)) {
            if (event.keyCode == kVK_ANSI_Slash) {
                [self toggleKeybindings];
                return nil;
            }
            if (event.keyCode == kVK_ANSI_P) {
                [self toggleCommandPalette];
                return nil;
            }
        }

        BOOL bracketRight = event.keyCode == kVK_ANSI_RightBracket;
        BOOL bracketLeft = event.keyCode == kVK_ANSI_LeftBracket;
        if (!bracketRight && !bracketLeft) return event;

        if (mods == (NSEventModifierFlagCommand | NSEventModifierFlagShift)) {
            bracketRight ? [self cycleNextPane:nil] : [self cyclePreviousPane:nil];
            return nil;
        }
        if (mods == NSEventModifierFlagCommand) {
            bracketRight ? [self cycleNextWorkspace:nil] : [self cyclePreviousWorkspace:nil];
            return nil;
        }
        return event;
    }];

    // Restoring the previous session is offered on the launch picker, not
    // done automatically.
    [self ensureWindow];
    [self showRepoPickerMandatory:YES
                   includeRestore:YES
                       withAction:^(NSString *directory) {
        [self newWorkspaceInDirectory:directory];
    }];

    // PRs open and close outside the app; poll to keep cards honest.
    [NSTimer scheduledTimerWithTimeInterval:60
                                    repeats:YES
                                      block:^(NSTimer *timer) {
        [self refreshAllPRs];
    }];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return NO;
}

- (void)applicationDidBecomeActive:(NSNotification *)notification {
    if (_ghosttyApp) ghostty_app_set_focus(_ghosttyApp, true);
}

- (void)applicationDidResignActive:(NSNotification *)notification {
    if (_ghosttyApp) ghostty_app_set_focus(_ghosttyApp, false);
}

#pragma mark - Window

- (void)ensureWindow {
    if (_window != nil) return;

    NSRect frame = NSMakeRect(0, 0, 1200, 700 + KobaStripHeight);
    _window = [[NSWindow alloc]
        initWithContentRect:frame
                  styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                            NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable
                    backing:NSBackingStoreBuffered
                      defer:NO];
    _window.title =
        [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleName"] ?: @"Koba";
    _window.releasedWhenClosed = NO;
    _window.delegate = self;
    _window.tabbingMode = NSWindowTabbingModeDisallowed;

    // The chrome palette is dark-only stone; pin the appearance so system
    // drawn parts (titlebar) match.
    _window.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
    _window.backgroundColor = KobaColorAppBackground();

    NSView *content = [[NSView alloc] initWithFrame:frame];

    _strip = [[KobaWorkspaceStrip alloc]
        initWithFrame:NSMakeRect(0, NSHeight(frame) - KobaStripHeight,
                                 NSWidth(frame), KobaStripHeight)];
    _strip.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
    [content addSubview:_strip];

    _workspaceContainer = [[NSView alloc]
        initWithFrame:NSMakeRect(0, 0, NSWidth(frame), NSHeight(frame) - KobaStripHeight)];
    _workspaceContainer.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [content addSubview:_workspaceContainer];

    _window.contentView = content;

    // Restore last session's size and position; center only on first run.
    BOOL restored = [_window setFrameUsingName:@"KobaMain"];
    _window.frameAutosaveName = @"KobaMain";
    if (!restored) [_window center];

    [_window makeKeyAndOrderFront:nil];
}

- (void)windowWillClose:(NSNotification *)notification {
    [self dismissPalette];
    for (KobaWorkspace *workspace in _workspaces) {
        [workspace closeAllSurfaces];
    }
    [_workspaces removeAllObjects];
    _selectedIndex = -1;
    _window = nil;
    _strip = nil;
    _workspaceContainer = nil;
}

#pragma mark - Workspaces

- (KobaWorkspace *)selectedWorkspace {
    if (_selectedIndex < 0 || _selectedIndex >= (NSInteger)_workspaces.count) return nil;
    return _workspaces[_selectedIndex];
}

// Creating a workspace always goes through the repo picker. It is mandatory
// only when there is nothing to fall back to (launch, or all closed).
- (IBAction)newWorkspace:(id)sender {
    [self ensureWindow];
    if (_paletteOverlay != nil) return;
    [self showRepoPickerMandatory:_workspaces.count == 0
                   includeRestore:NO
                       withAction:^(NSString *directory) {
        [self newWorkspaceInDirectory:directory];
    }];
}

// Re-points the selected workspace at a different directory: both panes
// respawn there.
- (void)switchWorkspaceDirectory:(NSString *)directory {
    if ([self selectedWorkspace] == nil) return;
    KobaWorkspace *old = _workspaces[(NSUInteger)_selectedIndex];
    [old closeAllSurfaces];
    [old.view removeFromSuperview];
    _workspaces[(NSUInteger)_selectedIndex] =
        [[KobaWorkspace alloc] initWithGhosttyApp:_ghosttyApp workingDirectory:directory];
    [self selectWorkspaceAtIndex:_selectedIndex];
}

- (void)newWorkspaceInDirectory:(NSString *)directory {
    [self ensureWindow];

    KobaWorkspace *workspace = [[KobaWorkspace alloc] initWithGhosttyApp:_ghosttyApp
                                                        workingDirectory:directory];
    [_workspaces addObject:workspace];
    [self selectWorkspaceAtIndex:(NSInteger)_workspaces.count - 1];
}

- (IBAction)closeWorkspace:(id)sender {
    KobaWorkspace *workspace = [self selectedWorkspace];
    if (workspace == nil) return;
    [workspace closeAllSurfaces];
    [self dropWorkspace:workspace];
}

// Remove a workspace whose surfaces are already closed.
- (void)dropWorkspace:(KobaWorkspace *)workspace {
    NSInteger index = (NSInteger)[_workspaces indexOfObjectIdenticalTo:workspace];
    if (index == NSNotFound) return;
    [workspace.view removeFromSuperview];
    [_workspaces removeObjectAtIndex:(NSUInteger)index];

    // Closing the last workspace returns to the launch state: an empty
    // window with the mandatory repo picker.
    if (_workspaces.count == 0) {
        _selectedIndex = -1;
        [self refreshStrip];
        [self newWorkspace:nil];
        return;
    }
    // A shell exiting elsewhere must not drag the overview into a workspace.
    if (_selectedIndex < 0) {
        _indexBeforeOverview = MIN(_indexBeforeOverview,
                                   (NSInteger)_workspaces.count - 1);
        [self showOverviewCanvas];
        [self refreshStrip];
        return;
    }
    [self selectWorkspaceAtIndex:MIN(MAX(_selectedIndex - (index <= _selectedIndex), 0),
                                     (NSInteger)_workspaces.count - 1)];
}

- (void)selectWorkspaceAtIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)_workspaces.count) return;
    _selectedIndex = index;

    KobaWorkspace *workspace = _workspaces[index];
    [_workspaceContainer.subviews.copy
        makeObjectsPerformSelector:@selector(removeFromSuperview)];
    workspace.view.frame = _workspaceContainer.bounds;
    workspace.view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [_workspaceContainer addSubview:workspace.view];

    [self refreshStrip];

    KobaSurfaceView *pane = workspace.focusedPane ?: workspace.panes.firstObject;
    if (pane != nil) [_window makeFirstResponder:pane];
    [self acknowledgeClaudeStatusIfFocused:workspace];
}

#pragma mark - Overview

// The overview is the app with no workspace selected: an empty canvas below
// the strip, which keeps showing every workspace and its Claude status.
// Somewhere to sit while agents work, with no pane holding the keyboard.
- (void)toggleOverview {
    if (_selectedIndex >= 0) {
        _indexBeforeOverview = _selectedIndex;
        _selectedIndex = -1;
        [self showOverviewCanvas];
        [_window makeFirstResponder:nil];
        [self refreshStrip];
        return;
    }

    // Back to the workspace cmd+section was pressed in, or the last one left
    // if it has since closed.
    [self selectWorkspaceAtIndex:MIN(_indexBeforeOverview,
                                     (NSInteger)_workspaces.count - 1)];
}

// The overview canvas: the space the panes normally fill, holding only a
// count of the workspaces in flight.
- (void)showOverviewCanvas {
    [_workspaceContainer.subviews.copy
        makeObjectsPerformSelector:@selector(removeFromSuperview)];

    unsigned long count = (unsigned long)_workspaces.count;
    NSTextField *label = [NSTextField labelWithString:
        [NSString stringWithFormat:@"%lu stream%@ of work",
                                   count, count == 1 ? @"" : @"s"]];
    label.font = [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular];
    label.textColor = KobaColorTextSecondary();
    [label sizeToFit];

    NSRect bounds = _workspaceContainer.bounds;
    label.frame = NSMakeRect(floor((NSWidth(bounds) - NSWidth(label.frame)) / 2),
                             floor((NSHeight(bounds) - NSHeight(label.frame)) / 2),
                             NSWidth(label.frame), NSHeight(label.frame));
    label.autoresizingMask = NSViewMinXMargin | NSViewMaxXMargin |
                             NSViewMinYMargin | NSViewMaxYMargin;
    [_workspaceContainer addSubview:label];
}

#pragma mark - State persistence

// Workspace state (directories, titles, selection) survives restarts via
// ~/.config/koba/state.json. Shells themselves are not restored.
- (void)saveState {
    NSMutableArray<NSDictionary *> *workspaces = [NSMutableArray array];
    for (KobaWorkspace *workspace in _workspaces) {
        NSMutableDictionary *entry =
            [NSMutableDictionary dictionaryWithObject:workspace.persistedDirectory
                                               forKey:@"directory"];
        if (workspace.customTitle != nil) entry[@"title"] = workspace.customTitle;
        [workspaces addObject:entry];
    }

    NSDictionary *state = @{
        @"selectedIndex" : @(_selectedIndex),
        @"workspaces" : workspaces,
    };
    NSData *data = [NSJSONSerialization dataWithJSONObject:state
                                                   options:NSJSONWritingPrettyPrinted
                                                     error:nil];
    [data writeToFile:KobaConfig.statePath options:NSDataWritingAtomic error:nil];
}

// How many workspaces in state.json point at directories that still exist.
- (NSUInteger)restorableWorkspaceCount {
    NSData *data = [NSData dataWithContentsOfFile:KobaConfig.statePath];
    if (data == nil) return 0;
    NSDictionary *state = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![state isKindOfClass:NSDictionary.class]) return 0;
    NSArray *workspaces = state[@"workspaces"];
    if (![workspaces isKindOfClass:NSArray.class]) return 0;

    NSFileManager *fm = NSFileManager.defaultManager;
    NSUInteger count = 0;
    for (NSDictionary *entry in workspaces) {
        if (![entry isKindOfClass:NSDictionary.class]) continue;
        NSString *directory = entry[@"directory"];
        if (![directory isKindOfClass:NSString.class]) continue;
        BOOL isDirectory = NO;
        if ([fm fileExistsAtPath:directory isDirectory:&isDirectory] && isDirectory) count++;
    }
    return count;
}

// Recreates workspaces from state.json. Returns NO when there is nothing
// usable to restore.
- (BOOL)restoreState {
    NSData *data = [NSData dataWithContentsOfFile:KobaConfig.statePath];
    if (data == nil) return NO;
    NSDictionary *state = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![state isKindOfClass:NSDictionary.class]) return NO;
    NSArray *workspaces = state[@"workspaces"];
    if (![workspaces isKindOfClass:NSArray.class]) return NO;

    NSFileManager *fm = NSFileManager.defaultManager;
    for (NSDictionary *entry in workspaces) {
        if (![entry isKindOfClass:NSDictionary.class]) continue;
        NSString *directory = entry[@"directory"];
        if (![directory isKindOfClass:NSString.class]) continue;
        BOOL isDirectory = NO;
        if (![fm fileExistsAtPath:directory isDirectory:&isDirectory] || !isDirectory) continue;

        [self newWorkspaceInDirectory:directory];
        NSString *title = entry[@"title"];
        if ([title isKindOfClass:NSString.class]) {
            _workspaces.lastObject.customTitle = title;
        }
    }
    if (_workspaces.count == 0) return NO;

    NSInteger selectedIndex = [state[@"selectedIndex"] integerValue];
    [self selectWorkspaceAtIndex:MIN(MAX(selectedIndex, 0),
                                     (NSInteger)_workspaces.count - 1)];
    return YES;
}

- (void)refreshStrip {
    [self saveState];
    NSMutableArray<NSString *> *topLines = [NSMutableArray array];
    NSMutableArray<NSArray<NSString *> *> *lines = [NSMutableArray array];
    NSMutableArray<NSNumber *> *statuses = [NSMutableArray array];
    for (NSUInteger i = 0; i < _workspaces.count; i++) {
        KobaWorkspace *workspace = _workspaces[i];
        [topLines addObject:workspace.customTitle != nil
            ? [NSString stringWithFormat:@"#%lu %@", i + 1, workspace.customTitle]
            : [NSString stringWithFormat:@"#%lu", i + 1]];

        NSMutableArray<NSString *> *cardLines =
            [NSMutableArray arrayWithObject:workspace.directoryLabel];
        if (workspace.ticketLabel != nil) [cardLines addObject:workspace.ticketLabel];
        if (workspace.prLabel != nil) [cardLines addObject:workspace.prLabel];
        [lines addObject:cardLines];
        [statuses addObject:@(workspace.claudeStatus)];
    }
    [_strip updateWithTopLines:topLines lines:lines statuses:statuses
                 selectedIndex:_selectedIndex];
}

#pragma mark - GitHub PR lookups

static NSString *KobaGhPath(void) {
    static NSString *path;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        for (NSString *candidate in
             @[ @"/opt/homebrew/bin/gh", @"/usr/local/bin/gh", @"/usr/bin/gh" ]) {
            if ([NSFileManager.defaultManager isExecutableFileAtPath:candidate]) {
                path = candidate;
                break;
            }
        }
    });
    return path;
}

// Asks `gh` whether the branch checked out in the workspace's directory has
// an open PR. Runs off the main thread; the strip refreshes when it lands.
- (void)refreshPRForWorkspace:(KobaWorkspace *)workspace {
    NSString *gh = KobaGhPath();
    NSString *pwd = workspace.terminalPane.pwd;
    if (gh == nil || pwd.length == 0) return;

    __weak KobaWorkspace *weakWorkspace = workspace;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSString *branch = KobaRunCommand(@"/usr/bin/git", pwd,
                                          @[ @"rev-parse", @"--abbrev-ref", @"HEAD" ]);
        NSString *ticket = KobaTicketFromBranch(branch);

        NSString *prOutput = KobaRunCommand(gh, pwd, @[
            @"pr", @"view", @"--json", @"number,state,url",
            @"--jq", @"select(.state == \"OPEN\") | \"\\(.number) \\(.url)\"",
        ]);
        NSString *label = nil;
        NSString *url = nil;
        NSArray<NSString *> *parts = [prOutput componentsSeparatedByString:@" "];
        if (parts.count == 2) {
            label = [NSString stringWithFormat:@"PR #%@", parts[0]];
            url = parts[1];
        }

        NSString *repoURL = KobaRunCommand(gh, pwd, @[
            @"repo", @"view", @"--json", @"url", @"--jq", @".url",
        ]);

        dispatch_async(dispatch_get_main_queue(), ^{
            KobaWorkspace *strongWorkspace = weakWorkspace;
            if (strongWorkspace == nil) return;
            strongWorkspace.prURL = url;
            strongWorkspace.repoURL = repoURL;
            strongWorkspace.prLabel = label;
            strongWorkspace.ticketLabel = ticket;
            [self refreshStrip];
        });
    });
}

// Extracts a ticket key (e.g. "ABC-123") from a branch name. Matches
// LETTERS-DIGITS at the start of the branch's last path component, which
// covers Linear/Jira conventions like "abc-123-fix-thing" and
// "alice/abc-123-fix-thing" without firing on words mid-branch.
static NSString *KobaTicketFromBranch(NSString *branch) {
    if (branch.length == 0) return nil;
    NSString *name = branch.lastPathComponent;

    static NSRegularExpression *regex;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        regex = [NSRegularExpression
            regularExpressionWithPattern:@"^([A-Za-z]{2,10})-([0-9]{1,6})(?:[-_]|$)"
                                 options:0
                                   error:nil];
    });

    NSTextCheckingResult *match =
        [regex firstMatchInString:name
                          options:0
                            range:NSMakeRange(0, name.length)];
    if (match == nil) return nil;

    NSString *prefix = [[name substringWithRange:[match rangeAtIndex:1]] uppercaseString];
    NSString *number = [name substringWithRange:[match rangeAtIndex:2]];
    return [NSString stringWithFormat:@"%@-%@", prefix, number];
}

// Runs a command in a directory and returns trimmed stdout, or nil on
// failure or empty output.
static NSString *KobaRunCommand(NSString *gh, NSString *pwd, NSArray<NSString *> *arguments) {
    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:gh];
    task.arguments = arguments;
    task.currentDirectoryURL = [NSURL fileURLWithPath:pwd];
    NSPipe *stdoutPipe = [NSPipe pipe];
    task.standardOutput = stdoutPipe;
    task.standardError = [NSPipe pipe];

    if (![task launchAndReturnError:nil]) return nil;
    NSData *data = [stdoutPipe.fileHandleForReading readDataToEndOfFile];
    [task waitUntilExit];
    if (task.terminationStatus != 0) return nil;

    NSString *output = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]
        stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return output.length > 0 ? output : nil;
}

- (void)refreshAllPRs {
    for (KobaWorkspace *workspace in _workspaces) {
        [self refreshPRForWorkspace:workspace];
    }
}

- (void)refreshPRForWorkspaceContainingPane:(KobaSurfaceView *)view {
    for (KobaWorkspace *workspace in _workspaces) {
        if ([workspace.panes containsObject:view]) {
            [self refreshPRForWorkspace:workspace];
            return;
        }
    }
}

- (void)selectWorkspaceForGotoTab:(NSInteger)which {
    NSInteger count = (NSInteger)_workspaces.count;
    if (count == 0) return;
    switch (which) {
        case GHOSTTY_GOTO_TAB_PREVIOUS:
            // From the overview, step back into the last workspace.
            [self selectWorkspaceAtIndex:_selectedIndex < 0
                ? count - 1
                : (_selectedIndex - 1 + count) % count];
            break;
        case GHOSTTY_GOTO_TAB_NEXT:
            [self selectWorkspaceAtIndex:(_selectedIndex + 1) % count];
            break;
        case GHOSTTY_GOTO_TAB_LAST:
            [self selectWorkspaceAtIndex:count - 1];
            break;
        default:
            // Positive values are a 1-based workspace index.
            if (which >= 1 && which <= count) [self selectWorkspaceAtIndex:which - 1];
    }
}

- (IBAction)cycleNextWorkspace:(id)sender {
    [self selectWorkspaceForGotoTab:GHOSTTY_GOTO_TAB_NEXT];
}

- (IBAction)cyclePreviousWorkspace:(id)sender {
    [self selectWorkspaceForGotoTab:GHOSTTY_GOTO_TAB_PREVIOUS];
}

#pragma mark - Command palette

- (void)dismissPalette {
    [_paletteOverlay removeFromSuperview];
    _paletteOverlay = nil;
    _palette = nil;
    _paletteActions = nil;
    _paletteInputHandler = nil;
    _paletteMandatory = NO;
}

- (void)toggleCommandPalette {
    if (_paletteOverlay != nil) {
        if (!_paletteMandatory) [self dismissPalette];
        return;
    }
    if (_window == nil) return;

    // Commands available right now, palette order matters.
    NSMutableArray<NSString *> *titles = [NSMutableArray array];
    NSMutableArray<void (^)(void)> *actions = [NSMutableArray array];

    NSString *prURL = [self selectedWorkspace].prURL;
    if (prURL != nil) {
        [titles addObject:@"GitHub → Open PR"];
        [actions addObject:^{
            [NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:prURL]];
        }];
    }

    NSString *repoURL = [self selectedWorkspace].repoURL;
    if (repoURL != nil) {
        [titles addObject:@"GitHub → Open Repo"];
        [actions addObject:^{
            [NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:repoURL]];
        }];
    }

    // Workspace commands need a workspace; the overview has none.
    if ([self selectedWorkspace] != nil) {
        [titles addObject:@"Workspace → Change Directory"];
        [actions addObject:^{
            [self showRepoPickerMandatory:NO
                           includeRestore:NO
                               withAction:^(NSString *directory) {
                [self switchWorkspaceDirectory:directory];
            }];
        }];

        [titles addObject:@"Workspace → Update Title"];
        [actions addObject:^{
            [self showAmendTitleInput];
        }];
    }

    [titles addObject:@"Window → Switch Workspace"];
    [actions addObject:^{
        [self showWorkspaceSwitcher];
    }];

    // Resetting the Agent pane is only offered from the Agent pane itself,
    // and only when it has drifted from the Terminal pane's directory.
    KobaWorkspace *workspace = [self selectedWorkspace];
    NSString *terminalPwd = workspace.terminalPane.pwd;
    BOOL onAgentPane = workspace.focusedPane == workspace.agentPane;
    if (onAgentPane && terminalPwd.length > 0 &&
        ![workspace.agentPane.pwd isEqualToString:terminalPwd]) {
        [titles addObject:@"Pane → Reset using Root Directory"];
        [actions addObject:^{
            [workspace resetAgentPaneInRootDirectory];
            [self->_window makeFirstResponder:workspace.focusedPane];
        }];
    }

    NSString *ticket = [self selectedWorkspace].ticketLabel;
    if (ticket != nil) {
        [titles addObject:@"Linear → Open Ticket"];
        [actions addObject:^{
            // linear.app resolves /issue/<key> to the signed-in workspace.
            NSString *url = [NSString stringWithFormat:@"https://linear.app/issue/%@", ticket];
            [NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:url]];
        }];
    }

    [self presentPaletteWithTitles:titles actions:actions note:nil mandatory:NO blank:NO];
}

- (void)presentPaletteWithTitles:(NSArray<NSString *> *)titles
                         actions:(NSArray<void (^)(void)> *)actions
                            note:(NSAttributedString *)note
                       mandatory:(BOOL)mandatory
                           blank:(BOOL)blank {
    _paletteActions = actions;
    _palette = [[KobaCommandPalette alloc] initWithCommands:titles note:note];
    [self mountPalette:_palette mandatory:mandatory blank:blank];
}

- (void)mountPalette:(KobaCommandPalette *)palette
           mandatory:(BOOL)mandatory
               blank:(BOOL)blank {
    _paletteMandatory = mandatory;

    NSView *content = _window.contentView;
    NSView *overlay = [[NSView alloc] initWithFrame:content.bounds];
    overlay.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    overlay.wantsLayer = YES;
    // The repo picker fully hides the workspace behind it (the card floats
    // on the app background); the command palette just dims what's behind.
    overlay.layer.backgroundColor = blank
        ? KobaColorAppBackground().CGColor
        : KobaColorScrim().CGColor;

    NSRect paletteFrame = _palette.frame;
    _palette.frame = NSMakeRect(
        floor((NSWidth(content.bounds) - NSWidth(paletteFrame)) / 2),
        floor((NSHeight(content.bounds) - NSHeight(paletteFrame)) / 2),
        NSWidth(paletteFrame), NSHeight(paletteFrame));
    _palette.autoresizingMask = NSViewMinXMargin | NSViewMaxXMargin |
                                NSViewMinYMargin | NSViewMaxYMargin;

    [overlay addSubview:_palette];
    [content addSubview:overlay];
    _paletteOverlay = overlay;
}

// A palette listing every open workspace, as an alternative to cmd+[ and
// cmd+1..9 navigation.
- (void)showWorkspaceSwitcher {
    NSMutableArray<NSString *> *titles = [NSMutableArray array];
    NSMutableArray<void (^)(void)> *actions = [NSMutableArray array];

    for (NSUInteger i = 0; i < _workspaces.count; i++) {
        KobaWorkspace *workspace = _workspaces[i];
        NSString *title = workspace.customTitle != nil
            ? [NSString stringWithFormat:@"#%lu %@ · %@",
               i + 1, workspace.customTitle, workspace.directoryLabel]
            : [NSString stringWithFormat:@"#%lu %@", i + 1, workspace.directoryLabel];
        [titles addObject:title];

        NSInteger index = (NSInteger)i;
        [actions addObject:^{ [self selectWorkspaceAtIndex:index]; }];
    }

    [self presentPaletteWithTitles:titles actions:actions note:nil mandatory:NO blank:NO];
}

// Fits on the card's top line next to "#N".
static const NSInteger KobaWorkspaceTitleMaxLength = 11;

- (void)showAmendTitleInput {
    KobaWorkspace *workspace = [self selectedWorkspace];
    if (workspace == nil) return;

    NSAttributedString *note = [[NSAttributedString alloc]
        initWithString:[NSString stringWithFormat:@"Max %ld characters, empty clears the title",
                        (long)KobaWorkspaceTitleMaxLength]
            attributes:@{
                NSFontAttributeName :
                    [NSFont monospacedSystemFontOfSize:10 weight:NSFontWeightRegular],
                NSForegroundColorAttributeName : KobaColorTextMuted(),
            }];

    _palette = [[KobaCommandPalette alloc]
        initForTextInputWithPlaceholder:@"Workspace title…"
                                   note:note
                              maxLength:KobaWorkspaceTitleMaxLength];
    if (workspace.customTitle != nil) [_palette appendQuery:workspace.customTitle];
    _paletteInputHandler = ^(NSString *text) {
        workspace.customTitle = text.length > 0 ? text : nil;
        [(KobaApp *)NSApp.delegate refreshStrip];
    };
    [self mountPalette:_palette mandatory:NO blank:NO];
}

#pragma mark - Repo picker

// Immediate children of the configured workingDirectories that are git
// repositories.
- (NSArray<NSString *> *)discoverRepos {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSMutableArray<NSString *> *repos = [NSMutableArray array];
    for (NSString *raw in _kobaConfig.workingDirectories) {
        NSString *base = raw.stringByExpandingTildeInPath;
        for (NSString *child in [fm contentsOfDirectoryAtPath:base error:nil]) {
            NSString *path = [base stringByAppendingPathComponent:child];
            if ([fm fileExistsAtPath:[path stringByAppendingPathComponent:@".git"]]) {
                [repos addObject:path];
            }
        }
    }
    [repos sortUsingSelector:@selector(localizedStandardCompare:)];
    return repos;
}

// Pick a git repository, then hand the chosen path to `perform`. At launch
// (includeRestore) the previous session, if any, is offered as the first row.
- (void)showRepoPickerMandatory:(BOOL)mandatory
                 includeRestore:(BOOL)includeRestore
                     withAction:(void (^)(NSString *directory))perform {
    NSArray<NSString *> *repos = [self discoverRepos];

    NSMutableArray<NSString *> *titles = [NSMutableArray array];
    NSMutableArray<void (^)(void)> *actions = [NSMutableArray array];
    NSAttributedString *note = nil;

    NSUInteger restorable = includeRestore ? [self restorableWorkspaceCount] : 0;
    if (restorable > 0) {
        [titles addObject:[NSString stringWithFormat:@"Restore Previous Session (%lu workspace%@)",
                           restorable, restorable == 1 ? @"" : @"s"]];
        [actions addObject:^{
            if (![self restoreState]) [self newWorkspace:nil];
        }];
    }

    if (repos.count == 0) {
        [titles addObject:@"~"];
        [actions addObject:^{ perform(NSHomeDirectory()); }];

        NSString *text = [NSString
            stringWithFormat:@"No git repos found in workingDirectories (see %@)",
                             KobaConfig.path.stringByAbbreviatingWithTildeInPath];
        NSMutableAttributedString *warning = [[NSMutableAttributedString alloc]
            initWithString:text
                attributes:@{
                    NSFontAttributeName :
                        [NSFont monospacedSystemFontOfSize:10 weight:NSFontWeightRegular],
                    NSForegroundColorAttributeName : KobaColorWarning(),
                }];
        [warning addAttributes:@{
            NSFontAttributeName :
                [NSFont monospacedSystemFontOfSize:10 weight:NSFontWeightBold],
        } range:[text rangeOfString:@"workingDirectories"]];
        note = warning;
    } else {
        for (NSString *repo in repos) {
            // "org/repo" form: the parent directory disambiguates repos with
            // the same name across workingDirectories.
            [titles addObject:[NSString stringWithFormat:@"%@/%@",
                repo.stringByDeletingLastPathComponent.lastPathComponent,
                repo.lastPathComponent]];
            [actions addObject:^{ perform(repo); }];
        }
    }

    [self presentPaletteWithTitles:titles actions:actions note:note mandatory:mandatory blank:YES];
}

#pragma mark - Keybindings overlay

// The user's global Claude skills (~/.claude/skills), as name/description
// pairs read from each SKILL.md's frontmatter.
- (NSArray<NSArray<NSString *> *> *)claudeSkills {
    NSString *skillsDir = [NSHomeDirectory() stringByAppendingPathComponent:@".claude/skills"];
    NSFileManager *fm = NSFileManager.defaultManager;
    NSArray<NSString *> *names = [[fm contentsOfDirectoryAtPath:skillsDir error:nil]
        sortedArrayUsingSelector:@selector(localizedStandardCompare:)];

    NSMutableArray<NSArray<NSString *> *> *skills = [NSMutableArray array];
    for (NSString *name in names) {
        NSString *skillPath = [skillsDir stringByAppendingPathComponent:
            [name stringByAppendingPathComponent:@"SKILL.md"]];
        NSString *contents = [NSString stringWithContentsOfFile:skillPath
                                                       encoding:NSUTF8StringEncoding
                                                          error:nil];
        if (contents == nil) continue;

        [skills addObject:@[ [@"/" stringByAppendingString:name], @"" ]];
    }
    return skills;
}

- (void)toggleKeybindings {
    if (_keybindingsOverlay != nil) {
        [_keybindingsOverlay removeFromSuperview];
        _keybindingsOverlay = nil;
        return;
    }
    if (_window == nil) return;

    NSArray<NSArray<NSString *> *> *bindings = @[
        @[ @"cmd+n", @"New workspace" ],
        @[ @"cmd+w", @"Close workspace" ],
        @[ @"cmd+]", @"Next workspace" ],
        @[ @"cmd+[", @"Previous workspace" ],
        @[ @"cmd+1..9", @"Go to workspace" ],
        @[ @"cmd+§", @"Toggle overview" ],
        @[ @"cmd+shift+]", @"Next pane" ],
        @[ @"cmd+shift+[", @"Previous pane" ],
        @[ @"cmd+shift+p", @"Command palette" ],
        @[ @"cmd+?", @"Toggle this help" ],
        @[ @"cmd+q", @"Quit" ],
    ];
    NSArray<NSArray<NSString *> *> *skills = [self claudeSkills];

    const CGFloat rowHeight = 22;
    const CGFloat padding = 20;
    const CGFloat titleHeight = 18;
    const CGFloat titleGap = 14;
    const CGFloat sectionGap = 48;
    const CGFloat maxDescWidth = 420;

    // Both sections are the same total width and share the same key column
    // width; skills are names only but still occupy a full-width section.
    CGFloat keyWidth = MAX([self helpKeyWidth:bindings], [self helpKeyWidth:skills]);
    CGFloat descWidth = MIN(maxDescWidth, [self helpDescWidth:bindings]);
    CGFloat sectionWidth = keyWidth + 12 + descWidth;
    CGFloat cardWidth = padding + sectionWidth + padding;
    if (skills.count > 0) cardWidth += sectionGap + sectionWidth;

    NSUInteger tallest = MAX(bindings.count, skills.count);
    // The last row carries ~6pt of internal line slack below its glyphs;
    // trim it from the bottom padding so top and bottom read equal.
    CGFloat cardHeight = padding + titleHeight + titleGap + tallest * rowHeight + padding - 6;

    NSView *content = _window.contentView;
    NSView *overlay = [[NSView alloc] initWithFrame:content.bounds];
    overlay.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    overlay.wantsLayer = YES;
    overlay.layer.backgroundColor = KobaColorScrim().CGColor;

    NSView *card = [[NSView alloc] initWithFrame:
        NSMakeRect(floor((NSWidth(content.bounds) - cardWidth) / 2),
                   floor((NSHeight(content.bounds) - cardHeight) / 2),
                   cardWidth, cardHeight)];
    card.autoresizingMask = NSViewMinXMargin | NSViewMaxXMargin |
                            NSViewMinYMargin | NSViewMaxYMargin;
    card.wantsLayer = YES;
    card.layer.backgroundColor = KobaColorCardBackground().CGColor;
    card.layer.borderWidth = 1;
    card.layer.borderColor = KobaColorBorder().CGColor;

    CGFloat topY = cardHeight - padding;
    [self addHelpSection:@"Keybindings" rows:bindings toCard:card
                  atTopY:topY x:padding keyWidth:keyWidth width:sectionWidth
                 keyFont:KobaHelpDescFont()
               rowHeight:rowHeight titleHeight:titleHeight titleGap:titleGap];
    if (skills.count > 0) {
        [self addHelpSection:@"Claude Skills" rows:skills toCard:card
                      atTopY:topY x:padding + sectionWidth + sectionGap
                      keyWidth:keyWidth width:sectionWidth
                     keyFont:KobaHelpDescFont()
                   rowHeight:rowHeight titleHeight:titleHeight titleGap:titleGap];
    }

    [overlay addSubview:card];
    [content addSubview:overlay];
    _keybindingsOverlay = overlay;
}

static NSFont *KobaHelpDescFont(void) {
    return [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular];
}

static CGFloat KobaTextWidth(NSString *text, NSFont *font) {
    // +6 covers NSTextField's cell padding so measured text never clips.
    return ceil([text sizeWithAttributes:@{ NSFontAttributeName : font }].width) + 6;
}

// Widest key column of a section, used to place descriptions 12pt after it.
- (CGFloat)helpKeyWidth:(NSArray<NSArray<NSString *> *> *)rows {
    CGFloat width = 0;
    for (NSArray<NSString *> *row in rows) {
        width = MAX(width, KobaTextWidth(row[0], KobaHelpDescFont()));
    }
    return width;
}

// Widest description of a section.
- (CGFloat)helpDescWidth:(NSArray<NSArray<NSString *> *> *)rows {
    CGFloat width = 0;
    for (NSArray<NSString *> *row in rows) {
        width = MAX(width, KobaTextWidth(row[1], KobaHelpDescFont()));
    }
    return width;
}

// Renders a titled key/description list in a column of the given width.
- (void)addHelpSection:(NSString *)sectionTitle
                  rows:(NSArray<NSArray<NSString *> *> *)rows
                toCard:(NSView *)card
                atTopY:(CGFloat)topY
                     x:(CGFloat)x
              keyWidth:(CGFloat)keyWidth
                 width:(CGFloat)columnWidth
               keyFont:(NSFont *)keyFont
             rowHeight:(CGFloat)rowHeight
           titleHeight:(CGFloat)titleHeight
              titleGap:(CGFloat)titleGap {
    NSTextField *title = [NSTextField labelWithString:sectionTitle];
    title.font = [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightSemibold];
    title.textColor = KobaColorTextPrimary();
    [title sizeToFit];
    title.frame = NSMakeRect(x, topY - titleHeight, columnWidth, titleHeight);
    [card addSubview:title];

    for (NSUInteger i = 0; i < rows.count; i++) {
        CGFloat y = topY - titleHeight - titleGap - (i + 1) * rowHeight;

        NSTextField *key = [NSTextField labelWithString:rows[i][0]];
        key.font = keyFont;
        key.textColor = KobaColorTextPrimary();
        key.frame = NSMakeRect(x, y, keyWidth, rowHeight);
        [card addSubview:key];

        NSTextField *desc = [NSTextField labelWithString:rows[i][1]];
        desc.font = KobaHelpDescFont();
        desc.textColor = KobaColorTextSecondary();
        desc.lineBreakMode = NSLineBreakByTruncatingTail;
        desc.frame = NSMakeRect(x + keyWidth + 12, y,
                                columnWidth - keyWidth - 12, rowHeight);
        [card addSubview:desc];
    }
}

#pragma mark - Panes

- (IBAction)cycleNextPane:(id)sender {
    [self cyclePane:1];
}

- (IBAction)cyclePreviousPane:(id)sender {
    [self cyclePane:-1];
}

- (void)cyclePane:(NSInteger)direction {
    KobaWorkspace *workspace = [self selectedWorkspace];
    NSArray<KobaSurfaceView *> *panes = workspace.panes;
    NSInteger count = (NSInteger)panes.count;
    if (count < 2) return;

    NSInteger current = (NSInteger)[panes indexOfObjectIdenticalTo:workspace.focusedPane];
    if (current == NSNotFound) current = 0;
    KobaSurfaceView *next = panes[(current + direction + count) % count];
    workspace.focusedPane = next;
    [_window makeFirstResponder:next];
    [self acknowledgeClaudeStatusIfFocused:workspace];
}

#pragma mark - Claude status

- (void)updateClaudeStatusForPane:(KobaSurfaceView *)view
                    progressState:(ghostty_action_progress_report_state_e)state {
    for (KobaWorkspace *workspace in _workspaces) {
        // Only the Agent pane means Claude; Terminal pane progress is noise.
        if (workspace.agentPane != view) continue;

        KobaClaudeStatus status = workspace.claudeStatus;
        switch (state) {
            case GHOSTTY_PROGRESS_STATE_SET:
            case GHOSTTY_PROGRESS_STATE_INDETERMINATE:
            case GHOSTTY_PROGRESS_STATE_PAUSE:
                status = KobaClaudeStatusWorking;
                break;
            case GHOSTTY_PROGRESS_STATE_ERROR:
                status = KobaClaudeStatusError;
                break;
            case GHOSTTY_PROGRESS_STATE_REMOVE:
                // Errors stick until acknowledged; a finished run shows Done.
                if (status == KobaClaudeStatusWorking) status = KobaClaudeStatusDone;
                break;
        }

        if (status != workspace.claudeStatus) {
            workspace.claudeStatus = status;
            [self refreshStrip];
        }
        return;
    }
}

// Focusing the Agent pane acknowledges a finished or failed run.
- (void)acknowledgeClaudeStatusIfFocused:(KobaWorkspace *)workspace {
    if (workspace.focusedPane != workspace.agentPane) return;
    if (workspace.claudeStatus != KobaClaudeStatusDone &&
        workspace.claudeStatus != KobaClaudeStatusError) return;
    workspace.claudeStatus = KobaClaudeStatusIdle;
    [self refreshStrip];
}

- (void)closeWorkspaceContainingPane:(KobaSurfaceView *)view {
    for (KobaWorkspace *workspace in _workspaces.copy) {
        if (![workspace.panes containsObject:view]) continue;
        [workspace closeAllSurfaces];
        [self dropWorkspace:workspace];
        return;
    }
}

@end
