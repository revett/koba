#import <Cocoa/Cocoa.h>

// The workspace switcher strip: one informational card per workspace with
// the selected one highlighted. Display only; switching is keyboard driven.
@interface KobaWorkspaceStrip : NSView

// One entry per workspace: the card's top line (e.g. "#1" or "#1 spike")
// and the lines shown under it (directory name, ticket, PR reference).
- (void)updateWithTopLines:(NSArray<NSString *> *)topLines
                     lines:(NSArray<NSArray<NSString *> *> *)lines
             selectedIndex:(NSInteger)selectedIndex;

@end
