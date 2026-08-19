#import "KobaWorkspace.h"

@implementation KobaWorkspace {
    ghostty_app_t _app;
    KobaSurfaceView *_terminal;
    KobaSurfaceView *_agent;
    NSString *_initialDirectory;
}

- (instancetype)initWithGhosttyApp:(ghostty_app_t)app {
    return [self initWithGhosttyApp:app workingDirectory:nil];
}

- (instancetype)initWithGhosttyApp:(ghostty_app_t)app
                  workingDirectory:(NSString *)workingDirectory {
    self = [super init];
    if (!self) return nil;

    _app = app;
    _initialDirectory = [workingDirectory copy];
    _terminal = [[KobaSurfaceView alloc] initWithGhosttyApp:app
                                          workingDirectory:workingDirectory];
    _agent = [[KobaSurfaceView alloc] initWithGhosttyApp:app
                                       workingDirectory:workingDirectory];
    _view = [[KobaSplitView alloc] initWithLeft:_terminal right:_agent];

    _focusedPane = _terminal;
    return self;
}

- (void)resetAgentPaneInRootDirectory {
    [_agent closeSurface];
    _agent = [[KobaSurfaceView alloc] initWithGhosttyApp:_app
                                        workingDirectory:[self rootDirectory]];
    [self.view replaceRightView:_agent];
    self.focusedPane = _agent;
}

- (NSArray<KobaSurfaceView *> *)panes {
    return @[ _terminal, _agent ];
}

- (KobaSurfaceView *)terminalPane {
    return _terminal;
}

- (KobaSurfaceView *)agentPane {
    return _agent;
}

// The git repository root containing the Terminal pane's working directory,
// or the working directory itself outside a repository. Nil until the shell
// reports a directory.
- (NSString *)rootDirectory {
    NSString *pwd = _terminal.pwd;
    if (pwd.length == 0) return nil;

    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *dir = pwd;
    while (dir.length > 1) {
        if ([fm fileExistsAtPath:[dir stringByAppendingPathComponent:@".git"]]) {
            return dir;
        }
        dir = dir.stringByDeletingLastPathComponent;
    }
    return pwd;
}

- (NSString *)directoryLabel {
    NSString *root = [self rootDirectory];
    if (root == nil || [root isEqualToString:NSHomeDirectory()]) return @"~";
    return root.lastPathComponent;
}

- (NSString *)persistedDirectory {
    return [self rootDirectory] ?: _initialDirectory ?: NSHomeDirectory();
}

- (void)closeAllSurfaces {
    for (KobaSurfaceView *pane in self.panes) {
        [pane closeSurface];
    }
}

@end
