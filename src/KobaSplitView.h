#import <Cocoa/Cocoa.h>

// A fixed 50/50 vertical split of two panes with a 1pt divider gap.
// Deliberately not an NSSplitView: no divider dragging, no auto layout,
// no deferred layout races. Frames are tiled synchronously on every resize.
@interface KobaSplitView : NSView

- (instancetype)initWithLeft:(NSView *)left right:(NSView *)right;

// Swaps the right pane for a new view, retiling immediately.
- (void)replaceRightView:(NSView *)view;

@end
