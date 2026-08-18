#import "KobaSurfaceView.h"
#import <QuartzCore/QuartzCore.h>
#import <IOKit/hidsystem/IOLLEvent.h>

// Translate AppKit modifier flags to ghostty mods, including sided keys.
// Mirrors Ghostty.Input.ghosttyMods in the reference macOS app.
static ghostty_input_mods_e KobaMods(NSEventModifierFlags flags) {
    uint32_t mods = GHOSTTY_MODS_NONE;
    if (flags & NSEventModifierFlagShift) mods |= GHOSTTY_MODS_SHIFT;
    if (flags & NSEventModifierFlagControl) mods |= GHOSTTY_MODS_CTRL;
    if (flags & NSEventModifierFlagOption) mods |= GHOSTTY_MODS_ALT;
    if (flags & NSEventModifierFlagCommand) mods |= GHOSTTY_MODS_SUPER;
    if (flags & NSEventModifierFlagCapsLock) mods |= GHOSTTY_MODS_CAPS;
    if (flags & NX_DEVICERSHIFTKEYMASK) mods |= GHOSTTY_MODS_SHIFT_RIGHT;
    if (flags & NX_DEVICERCTLKEYMASK) mods |= GHOSTTY_MODS_CTRL_RIGHT;
    if (flags & NX_DEVICERALTKEYMASK) mods |= GHOSTTY_MODS_ALT_RIGHT;
    if (flags & NX_DEVICERCMDKEYMASK) mods |= GHOSTTY_MODS_SUPER_RIGHT;
    return (ghostty_input_mods_e)mods;
}

static int KobaMomentum(NSEventPhase phase) {
    switch (phase) {
        case NSEventPhaseBegan: return 1;
        case NSEventPhaseStationary: return 2;
        case NSEventPhaseChanged: return 3;
        case NSEventPhaseEnded: return 4;
        case NSEventPhaseCancelled: return 5;
        case NSEventPhaseMayBegin: return 6;
        default: return 0;
    }
}

@implementation KobaSurfaceView {
    BOOL _focused;
}

- (instancetype)initWithGhosttyApp:(ghostty_app_t)app {
    return [self initWithGhosttyApp:app workingDirectory:nil];
}

- (instancetype)initWithGhosttyApp:(ghostty_app_t)app
                  workingDirectory:(NSString *)workingDirectory {
    // Non-zero initial frame so the renderer's layer has non-zero bounds.
    self = [super initWithFrame:NSMakeRect(0, 0, 800, 600)];
    if (!self) return nil;

    ghostty_surface_config_s cfg = ghostty_surface_config_new();
    cfg.platform_tag = GHOSTTY_PLATFORM_MACOS;
    cfg.platform.macos.nsview = (__bridge void *)self;
    cfg.userdata = (__bridge void *)self;
    cfg.scale_factor = NSScreen.mainScreen.backingScaleFactor;
    cfg.context = GHOSTTY_SURFACE_CONTEXT_WINDOW;
    if (workingDirectory.length > 0) {
        cfg.working_directory = workingDirectory.UTF8String;
    }

    _surface = ghostty_surface_new(app, &cfg);
    if (_surface == NULL) return nil;

    // Surfaces start focused inside ghostty; unfocus so only the pane that
    // actually becomes first responder shows a blinking cursor.
    ghostty_surface_set_focus(_surface, false);

    return self;
}

- (void)closeSurface {
    if (_surface == NULL) return;
    ghostty_surface_free(_surface);
    _surface = NULL;
}

- (void)dealloc {
    [self closeSurface];
}

#pragma mark - Window lifecycle

- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    NSWindow *window = self.window;
    if (window == nil) return;

    window.acceptsMouseMovedEvents = YES;

    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    [center removeObserver:self];
    [center addObserver:self
               selector:@selector(windowKeyDidChange:)
                   name:NSWindowDidBecomeKeyNotification
                 object:window];
    [center addObserver:self
               selector:@selector(windowKeyDidChange:)
                   name:NSWindowDidResignKeyNotification
                 object:window];

    [self viewDidChangeBackingProperties];
}

- (void)windowKeyDidChange:(NSNotification *)note {
    [self updateFocus];
}

- (void)updateFocus {
    if (_surface == NULL) return;
    BOOL focused = self.window.isKeyWindow && self.window.firstResponder == self;
    if (focused == _focused) return;
    _focused = focused;
    ghostty_surface_set_focus(_surface, focused);
}

#pragma mark - Geometry

- (void)setFrameSize:(NSSize)newSize {
    [super setFrameSize:newSize];
    [self syncSurfaceSize];
}

- (void)layout {
    [super layout];
    [self syncSurfaceSize];
}

- (void)syncSurfaceSize {
    if (_surface == NULL || self.window == nil) return;
    NSSize backing = [self convertSizeToBacking:self.frame.size];
    ghostty_surface_set_size(_surface, (uint32_t)backing.width, (uint32_t)backing.height);
}

- (void)viewDidChangeBackingProperties {
    [super viewDidChangeBackingProperties];
    if (_surface == NULL || self.window == nil) return;
    CGFloat scale = self.window.backingScaleFactor;

    // The renderer owns the layer, but we keep contentsScale in sync with
    // the screen so rendering stays sharp when moving between displays.
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.layer.contentsScale = scale;
    [CATransaction commit];

    ghostty_surface_set_content_scale(_surface, scale, scale);
    NSSize backing = [self convertSizeToBacking:self.frame.size];
    ghostty_surface_set_size(_surface, (uint32_t)backing.width, (uint32_t)backing.height);
}

#pragma mark - Focus / responder

- (BOOL)acceptsFirstResponder {
    // Pane focus is keyboard-only. AppKit focuses a clicked view on its own,
    // so refuse here; this runs before the current pane is asked to resign,
    // which keeps existing focus intact. Clicks still reach the surface for
    // text selection.
    NSEvent *event = NSApp.currentEvent;
    switch (event.type) {
        case NSEventTypeLeftMouseDown:
        case NSEventTypeRightMouseDown:
        case NSEventTypeOtherMouseDown:
            if (event.window == self.window) return NO;
            break;
        default:
            break;
    }
    return YES;
}

- (BOOL)acceptsFirstMouse:(NSEvent *)event {
    return YES;
}

- (BOOL)becomeFirstResponder {
    BOOL result = [super becomeFirstResponder];
    // firstResponder isn't updated until after this returns.
    dispatch_async(dispatch_get_main_queue(), ^{ [self updateFocus]; });
    return result;
}

- (BOOL)resignFirstResponder {
    BOOL result = [super resignFirstResponder];
    dispatch_async(dispatch_get_main_queue(), ^{ [self updateFocus]; });
    return result;
}

#pragma mark - Keyboard

// Builds the ghostty key event for an NSEvent. Does not set text; callers
// own that because of C string lifetimes. Mirrors NSEvent+Extension.swift.
- (ghostty_input_key_s)keyEventFor:(NSEvent *)event action:(ghostty_input_action_e)action {
    ghostty_input_key_s key = {0};
    key.action = action;
    key.keycode = event.keyCode;
    key.mods = KobaMods(event.modifierFlags);

    // Heuristic from the reference app: control and command never contribute
    // to text translation, assume everything else did.
    key.consumed_mods = KobaMods(event.modifierFlags &
                                 ~(NSEventModifierFlagControl | NSEventModifierFlagCommand));

    if (event.type == NSEventTypeKeyDown || event.type == NSEventTypeKeyUp) {
        NSString *unshifted = [event charactersByApplyingModifiers:0];
        if (unshifted.length > 0) {
            key.unshifted_codepoint = [unshifted characterAtIndex:0];
        }
    }
    return key;
}

// The text ghostty should receive for a key event. Control characters and
// function-key PUA codepoints are excluded; ghostty encodes those itself.
- (NSString *)textFor:(NSEvent *)event {
    NSString *characters = event.characters;
    if (characters.length == 0) return nil;
    unichar first = [characters characterAtIndex:0];
    if (characters.length == 1) {
        if (first < 0x20) {
            return [event charactersByApplyingModifiers:
                    event.modifierFlags & ~NSEventModifierFlagControl];
        }
        if (first >= 0xF700 && first <= 0xF8FF) return nil;
    }
    return characters;
}

- (BOOL)sendKey:(NSEvent *)event action:(ghostty_input_action_e)action text:(NSString *)text {
    if (_surface == NULL) return NO;
    ghostty_input_key_s key = [self keyEventFor:event action:action];
    const char *utf8 = text.UTF8String;
    if (utf8 != NULL && (unsigned char)utf8[0] >= 0x20) {
        key.text = utf8;
    }
    return ghostty_surface_key(_surface, key);
}

- (void)keyDown:(NSEvent *)event {
    ghostty_input_action_e action =
        event.isARepeat ? GHOSTTY_ACTION_REPEAT : GHOSTTY_ACTION_PRESS;
    [self sendKey:event action:action text:[self textFor:event]];
}

- (void)keyUp:(NSEvent *)event {
    [self sendKey:event action:GHOSTTY_ACTION_RELEASE text:nil];
}

// Command-modified keys arrive here, not keyDown. Forward them so ghostty
// keybindings (cmd+C, cmd+V, ...) work; unconsumed keys fall through to the
// menu bar.
- (BOOL)performKeyEquivalent:(NSEvent *)event {
    if (_surface == NULL) return NO;
    if (self.window.firstResponder != self) return NO;
    if (!(event.modifierFlags & NSEventModifierFlagCommand)) return NO;

    return [self sendKey:event action:GHOSTTY_ACTION_PRESS text:[self textFor:event]];
}

- (void)flagsChanged:(NSEvent *)event {
    uint32_t mod;
    switch (event.keyCode) {
        case 0x39: mod = GHOSTTY_MODS_CAPS; break;
        case 0x38: case 0x3C: mod = GHOSTTY_MODS_SHIFT; break;
        case 0x3B: case 0x3E: mod = GHOSTTY_MODS_CTRL; break;
        case 0x3A: case 0x3D: mod = GHOSTTY_MODS_ALT; break;
        case 0x37: case 0x36: mod = GHOSTTY_MODS_SUPER; break;
        default: return;
    }

    ghostty_input_mods_e mods = KobaMods(event.modifierFlags);

    // Press if the flag is active and (for right-side keys) the correct side
    // is held; otherwise this is a release.
    ghostty_input_action_e action = GHOSTTY_ACTION_RELEASE;
    if (mods & mod) {
        BOOL sidePressed = YES;
        switch (event.keyCode) {
            case 0x3C: sidePressed = (event.modifierFlags & NX_DEVICERSHIFTKEYMASK) != 0; break;
            case 0x3E: sidePressed = (event.modifierFlags & NX_DEVICERCTLKEYMASK) != 0; break;
            case 0x3D: sidePressed = (event.modifierFlags & NX_DEVICERALTKEYMASK) != 0; break;
            case 0x36: sidePressed = (event.modifierFlags & NX_DEVICERCMDKEYMASK) != 0; break;
        }
        if (sidePressed) action = GHOSTTY_ACTION_PRESS;
    }

    [self sendKey:event action:action text:nil];
}

#pragma mark - Mouse

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    for (NSTrackingArea *area in self.trackingAreas) {
        [self removeTrackingArea:area];
    }
    NSTrackingAreaOptions options = NSTrackingMouseEnteredAndExited |
                                    NSTrackingMouseMoved |
                                    NSTrackingInVisibleRect |
                                    NSTrackingActiveAlways;
    [self addTrackingArea:[[NSTrackingArea alloc] initWithRect:NSZeroRect
                                                       options:options
                                                         owner:self
                                                      userInfo:nil]];
}

- (void)sendMouseButton:(ghostty_input_mouse_state_e)state
                 button:(ghostty_input_mouse_button_e)button
                  event:(NSEvent *)event {
    if (_surface == NULL) return;
    ghostty_surface_mouse_button(_surface, state, button, KobaMods(event.modifierFlags));
}

- (void)mouseDown:(NSEvent *)event {
    // Deliberately no makeFirstResponder: pane focus is keyboard-only
    // (cmd+shift+[ and cmd+shift+]). Clicks still reach the surface for
    // text selection.
    [self sendMouseButton:GHOSTTY_MOUSE_PRESS button:GHOSTTY_MOUSE_LEFT event:event];
}

- (void)mouseUp:(NSEvent *)event {
    [self sendMouseButton:GHOSTTY_MOUSE_RELEASE button:GHOSTTY_MOUSE_LEFT event:event];
}

- (void)rightMouseDown:(NSEvent *)event {
    [self sendMouseButton:GHOSTTY_MOUSE_PRESS button:GHOSTTY_MOUSE_RIGHT event:event];
}

- (void)rightMouseUp:(NSEvent *)event {
    [self sendMouseButton:GHOSTTY_MOUSE_RELEASE button:GHOSTTY_MOUSE_RIGHT event:event];
}

- (void)otherMouseDown:(NSEvent *)event {
    if (event.buttonNumber != 2) return;
    [self sendMouseButton:GHOSTTY_MOUSE_PRESS button:GHOSTTY_MOUSE_MIDDLE event:event];
}

- (void)otherMouseUp:(NSEvent *)event {
    if (event.buttonNumber != 2) return;
    [self sendMouseButton:GHOSTTY_MOUSE_RELEASE button:GHOSTTY_MOUSE_MIDDLE event:event];
}

- (void)sendMousePos:(NSEvent *)event {
    if (_surface == NULL) return;
    NSPoint pos = [self convertPoint:event.locationInWindow fromView:nil];
    // ghostty expects a top-left origin.
    ghostty_surface_mouse_pos(_surface, pos.x, self.frame.size.height - pos.y,
                              KobaMods(event.modifierFlags));
}

- (void)mouseMoved:(NSEvent *)event {
    [self sendMousePos:event];
}

- (void)mouseDragged:(NSEvent *)event {
    [self sendMousePos:event];
}

- (void)rightMouseDragged:(NSEvent *)event {
    [self sendMousePos:event];
}

- (void)otherMouseDragged:(NSEvent *)event {
    [self sendMousePos:event];
}

- (void)mouseEntered:(NSEvent *)event {
    [self sendMousePos:event];
}

- (void)mouseExited:(NSEvent *)event {
    if (_surface == NULL) return;
    // Negative position tells ghostty the mouse left the surface.
    ghostty_surface_mouse_pos(_surface, -1, -1, KobaMods(event.modifierFlags));
}

- (void)scrollWheel:(NSEvent *)event {
    if (_surface == NULL) return;
    double x = event.scrollingDeltaX;
    double y = event.scrollingDeltaY;
    BOOL precision = event.hasPreciseScrollingDeltas;
    if (precision) {
        // Matches the reference app's subjective 2x multiplier.
        x *= 2;
        y *= 2;
    }
    ghostty_input_scroll_mods_t scrollMods =
        (precision ? 1 : 0) | (KobaMomentum(event.momentumPhase) << 1);
    ghostty_surface_mouse_scroll(_surface, x, y, scrollMods);
}

@end
