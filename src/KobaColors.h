#import <Cocoa/Cocoa.h>

// Koba's colour palette: Tailwind "Stone" (https://tailwindcss.com/docs/colors),
// plus amber for warnings. The chrome is deliberately dark-only.

static inline NSColor *KobaColorHex(uint32_t rgb, CGFloat alpha) {
    return [NSColor colorWithSRGBRed:((rgb >> 16) & 0xFF) / 255.0
                               green:((rgb >> 8) & 0xFF) / 255.0
                                blue:(rgb & 0xFF) / 255.0
                               alpha:alpha];
}

// Surfaces
static inline NSColor *KobaColorAppBackground(void)  { return KobaColorHex(0x0c0a09, 1); }    // stone-950
static inline NSColor *KobaColorCardBackground(void) { return KobaColorHex(0x1c1917, 1); }    // stone-900
static inline NSColor *KobaColorScrim(void)          { return KobaColorHex(0x0c0a09, 0.6); }  // stone-950

// Selection
static inline NSColor *KobaColorSelectedBorder(void) { return KobaColorHex(0xa8a29e, 1); }    // stone-400
static inline NSColor *KobaColorSelectedFill(void)   { return KobaColorHex(0x292524, 1); }    // stone-800

// Borders
static inline NSColor *KobaColorBorder(void)         { return KobaColorHex(0x292524, 1); }    // stone-800

// Text
static inline NSColor *KobaColorTextPrimary(void)    { return KobaColorHex(0xf5f5f4, 1); }    // stone-100
static inline NSColor *KobaColorTextSecondary(void)  { return KobaColorHex(0xa8a29e, 1); }    // stone-400
static inline NSColor *KobaColorTextMuted(void)      { return KobaColorHex(0x57534e, 1); }    // stone-600
static inline NSColor *KobaColorWarning(void)        { return KobaColorHex(0xf59e0b, 1); }    // amber-500
