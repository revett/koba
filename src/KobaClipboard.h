#import <Cocoa/Cocoa.h>
#import <ghostty.h>

// libghostty clipboard callbacks, shared by every app built on
// KobaSurfaceView. Userdata is the requesting KobaSurfaceView.

bool KobaReadClipboard(void *userdata, ghostty_clipboard_e location, void *state);

void KobaConfirmReadClipboard(void *userdata,
                              const char *string,
                              void *state,
                              ghostty_clipboard_request_e request);

void KobaWriteClipboard(void *userdata,
                        ghostty_clipboard_e location,
                        const ghostty_clipboard_content_s *content,
                        size_t len,
                        bool confirm);
