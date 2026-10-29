#import "KobaClipboard.h"
#import "KobaConfig.h"
#import "KobaSurfaceView.h"

// Writes clipboard image data out as a PNG and returns its path. OSC 52
// carries text only and has no way to describe a content type, so an image
// can only reach the program reading the clipboard as a path it can open.
// Screenshots (cmd+ctrl+shift+4) arrive as image data with no text, which is
// why they otherwise paste as nothing.
static NSString *KobaStageClipboardImage(NSPasteboard *pasteboard) {
    NSData *png = [pasteboard dataForType:NSPasteboardTypePNG];
    if (png == nil) {
        NSData *tiff = [pasteboard dataForType:NSPasteboardTypeTIFF];
        if (tiff == nil) return nil;
        NSBitmapImageRep *rep = [NSBitmapImageRep imageRepWithData:tiff];
        png = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
        if (png == nil) return nil;
    }

    NSString *directory = KobaConfig.clipboardDirectory;
    if (![NSFileManager.defaultManager createDirectoryAtPath:directory
                                withIntermediateDirectories:YES
                                                 attributes:nil
                                                      error:nil]) return nil;

    NSString *path = [directory stringByAppendingPathComponent:
        [NSString stringWithFormat:@"%@.png", NSUUID.UUID.UUIDString]];
    if (![png writeToFile:path options:NSDataWritingAtomic error:nil]) return nil;
    return path;
}

// What a clipboard read should return. Mirrors ghostty's own handler, which
// prefers file paths over text, then falls back to staging image data. Unlike
// ghostty we only read file URLs, because reading every URL class lets
// AppKit coerce ordinary copied text into a URL.
static NSString *KobaClipboardContents(void) {
    NSPasteboard *pasteboard = NSPasteboard.generalPasteboard;

    NSArray<NSURL *> *urls = [pasteboard
        readObjectsForClasses:@[ NSURL.class ]
                      options:@{ NSPasteboardURLReadingFileURLsOnlyKey : @YES }];
    if (urls.count > 0) {
        NSMutableArray<NSString *> *paths = [NSMutableArray array];
        for (NSURL *url in urls) [paths addObject:KobaShellEscape(url.path)];
        return [paths componentsJoinedByString:@" "];
    }

    NSString *string = [pasteboard stringForType:NSPasteboardTypeString];
    if (string != nil) return string;

    return KobaStageClipboardImage(pasteboard);
}

bool KobaReadClipboard(void *userdata, ghostty_clipboard_e location, void *state) {
    KobaSurfaceView *view = (__bridge KobaSurfaceView *)userdata;
    if (view.surface == NULL) return false;
    NSString *contents = KobaClipboardContents();
    // Returning false lets performable paste bindings fall through to the
    // terminal instead of pasting nothing.
    if (contents == nil) return false;
    ghostty_surface_complete_clipboard_request(view.surface, contents.UTF8String, state, false);
    return true;
}

// Paste confirmation (e.g. pasting text with control characters). We skip
// the dialog and confirm directly.
void KobaConfirmReadClipboard(void *userdata,
                                        const char *string,
                                        void *state,
                                        ghostty_clipboard_request_e request) {
    KobaSurfaceView *view = (__bridge KobaSurfaceView *)userdata;
    if (view.surface == NULL || string == NULL) return;
    ghostty_surface_complete_clipboard_request(view.surface, string, state, true);
}

void KobaWriteClipboard(void *userdata,
                                 ghostty_clipboard_e location,
                                 const ghostty_clipboard_content_s *content,
                                 size_t len,
                                 bool confirm) {
    for (size_t i = 0; i < len; i++) {
        if (content[i].mime == NULL || content[i].data == NULL) continue;
        if (strcmp(content[i].mime, "text/plain") != 0) continue;
        NSString *string = [NSString stringWithUTF8String:content[i].data];
        if (string == nil) continue;
        NSPasteboard *pasteboard = NSPasteboard.generalPasteboard;
        [pasteboard clearContents];
        [pasteboard setString:string forType:NSPasteboardTypeString];
        return;
    }
}
