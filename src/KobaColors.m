#import "KobaColors.h"

static NSColor *background;
static NSColor *foreground;

static NSColor *KobaColorHex(uint32_t rgb) {
    return [NSColor colorWithSRGBRed:((rgb >> 16) & 0xFF) / 255.0
                               green:((rgb >> 8) & 0xFF) / 255.0
                                blue:(rgb & 0xFF) / 255.0
                               alpha:1];
}

// Linear mix from the terminal background towards the foreground. The
// ratios below are calibrated so a near-black warm theme reproduces the
// original Tailwind Stone chrome (950/900/800/400/100).
static NSColor *KobaColorMix(CGFloat towardsForeground) {
    NSColor *bg = [background colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
    NSColor *fg = [foreground colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
    CGFloat t = towardsForeground;
    return [NSColor colorWithSRGBRed:bg.redComponent + (fg.redComponent - bg.redComponent) * t
                               green:bg.greenComponent + (fg.greenComponent - bg.greenComponent) * t
                                blue:bg.blueComponent + (fg.blueComponent - bg.blueComponent) * t
                               alpha:1];
}

void KobaColorsInitialize(NSColor *bg, NSColor *fg) {
    background = bg;
    foreground = fg;
}

static void KobaColorsEnsureDefaults(void) {
    if (background == nil) background = KobaColorHex(0x0c0a09);  // stone-950
    if (foreground == nil) foreground = KobaColorHex(0xf5f5f4);  // stone-100
}

// Surfaces
NSColor *KobaColorAppBackground(void) {
    KobaColorsEnsureDefaults();
    // Slightly darker than the terminal so panes read as content.
    NSColor *bg = [background colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
    return [NSColor colorWithSRGBRed:bg.redComponent * 0.6
                               green:bg.greenComponent * 0.6
                                blue:bg.blueComponent * 0.6
                               alpha:1];
}

NSColor *KobaColorCardBackground(void) {
    KobaColorsEnsureDefaults();
    return KobaColorMix(0.08);
}

NSColor *KobaColorScrim(void) {
    return [KobaColorAppBackground() colorWithAlphaComponent:0.6];
}

// Selection
NSColor *KobaColorSelectedBorder(void) {
    KobaColorsEnsureDefaults();
    return KobaColorMix(0.62);
}

NSColor *KobaColorSelectedFill(void) {
    KobaColorsEnsureDefaults();
    return KobaColorMix(0.15);
}

// Borders
NSColor *KobaColorBorder(void) {
    KobaColorsEnsureDefaults();
    return KobaColorMix(0.15);
}

// Text
NSColor *KobaColorTextPrimary(void) {
    KobaColorsEnsureDefaults();
    return foreground;
}

NSColor *KobaColorTextSecondary(void) {
    KobaColorsEnsureDefaults();
    return KobaColorMix(0.62);
}

NSColor *KobaColorTextMuted(void) {
    KobaColorsEnsureDefaults();
    return KobaColorMix(0.34);
}

NSColor *KobaColorWarning(void) {
    return KobaColorHex(0xf59e0b);  // amber-500
}
