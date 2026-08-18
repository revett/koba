#import <Cocoa/Cocoa.h>
#import <ghostty.h>

// Application delegate. Owns the ghostty app handle, the single Koba window,
// and its workspaces. A workspace is a Terminal + Agent pane pair shown in
// the window; a card strip along the top shows all workspaces.
@interface KobaApp : NSObject <NSApplicationDelegate, NSWindowDelegate>

@property (nonatomic, readonly) ghostty_app_t ghosttyApp;

- (IBAction)newWorkspace:(id)sender;
- (IBAction)closeWorkspace:(id)sender;
- (IBAction)cycleNextPane:(id)sender;
- (IBAction)cyclePreviousPane:(id)sender;
- (IBAction)cycleNextWorkspace:(id)sender;
- (IBAction)cyclePreviousWorkspace:(id)sender;

@end
