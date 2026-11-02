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

// Forward only the scroll wheel to the terminal: clicks, drags and hovering
// are dropped. Defaults to NO.
@property (nonatomic) BOOL mouseScrollOnly;

// Runs the given command in the given directory.
- (instancetype)initWithGhosttyApp:(ghostty_app_t)app
                  workingDirectory:(nullable NSString *)workingDirectory
                           command:(nullable NSString *)command;

// Frees the underlying ghostty surface. The view is inert afterwards.
- (void)closeSurface;

@end

NS_ASSUME_NONNULL_END
