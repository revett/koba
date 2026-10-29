#import <Cocoa/Cocoa.h>
#import <ghostty.h>

NS_ASSUME_NONNULL_BEGIN

// Backslash-escapes shell-sensitive characters so a path survives being
// pasted into a live terminal buffer. Mirrors Ghostty.Shell.escape.
NSString *KobaShellEscape(NSString *string);

// A single terminal pane. libghostty attaches its own rendering layer to
// this view and drives all drawing; we forward input, size, and focus.
@interface KobaSurfaceView : NSView

@property (nonatomic, readonly) ghostty_surface_t surface;

// Current working directory as reported by the shell (OSC 7 via ghostty's
// shell integration). Nil until the first prompt.
@property (nonatomic, copy, nullable) NSString *pwd;

// Whether a bar along the top edge marks this pane while focused. Defaults
// to YES; pointless when a window holds a single pane.
@property (nonatomic) BOOL showsFocusBorder;

- (instancetype)initWithGhosttyApp:(ghostty_app_t)app;

// Spawns the surface's shell in the given directory instead of the default.
- (instancetype)initWithGhosttyApp:(ghostty_app_t)app
                  workingDirectory:(nullable NSString *)workingDirectory;

// Runs the given command instead of the default shell.
- (instancetype)initWithGhosttyApp:(ghostty_app_t)app
                  workingDirectory:(nullable NSString *)workingDirectory
                           command:(nullable NSString *)command;

// Frees the underlying ghostty surface. The view is inert afterwards.
- (void)closeSurface;

@end

NS_ASSUME_NONNULL_END
