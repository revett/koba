#import <Cocoa/Cocoa.h>
#import <ghostty.h>

// Application delegate for Herdr.app: a dedicated window whose only content
// is a herdr client. Herdr owns workspaces, tabs, panes, and agents; quitting
// the app detaches the client and the herdr server keeps agents running.
@interface HerdrApp : NSObject <NSApplicationDelegate, NSWindowDelegate>

@property (nonatomic, readonly) ghostty_app_t ghosttyApp;

@end
