#import <Cocoa/Cocoa.h>

// The workspace switcher strip: one informational card per workspace with
// the selected one highlighted. Display only; switching is keyboard driven.
@interface KobaWorkspaceStrip : NSView

// One entry per workspace: the lines shown under that card's "#N" line
// (directory name, then optionally an open PR reference).
- (void)updateWithLines:(NSArray<NSArray<NSString *> *> *)lines
          selectedIndex:(NSInteger)selectedIndex;

@end
