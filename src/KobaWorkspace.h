#import <Cocoa/Cocoa.h>
#import <ghostty.h>
#import "KobaSplitView.h"
#import "KobaSurfaceView.h"

NS_ASSUME_NONNULL_BEGIN

// One workspace: a fixed split holding the Terminal and Agent panes.
@interface KobaWorkspace : NSObject

@property (nonatomic, readonly) KobaSplitView *view;
@property (nonatomic, readonly) NSArray<KobaSurfaceView *> *panes;
@property (nonatomic, readonly) KobaSurfaceView *terminalPane;
@property (nonatomic, readonly) KobaSurfaceView *agentPane;
@property (nonatomic, weak) KobaSurfaceView *focusedPane;

// Ticket key detected in the current branch name (e.g. "ABC-123").
@property (nonatomic, copy, nullable) NSString *ticketLabel;

// "PR #123" when the Terminal pane's repo branch has an open GitHub PR.
@property (nonatomic, copy, nullable) NSString *prLabel;

// Browser URL of that PR.
@property (nonatomic, copy, nullable) NSString *prURL;

// Browser URL of the GitHub repository containing the Terminal pane's
// working directory, when there is one.
@property (nonatomic, copy, nullable) NSString *repoURL;

- (instancetype)initWithGhosttyApp:(ghostty_app_t)app;

// Both panes spawn their shells in the given directory.
- (instancetype)initWithGhosttyApp:(ghostty_app_t)app
                  workingDirectory:(nullable NSString *)workingDirectory;

// Display name for the workspace card: git repository root name if the
// Terminal pane is inside a repository, otherwise the directory name.
- (NSString *)directoryLabel;

// Replaces the Agent pane with a fresh shell spawned in the workspace's
// root directory (git root of the Terminal pane's cwd, else the cwd). The
// new pane becomes the focused pane.
- (void)resetAgentPaneInRootDirectory;

- (void)closeAllSurfaces;

@end

NS_ASSUME_NONNULL_END
