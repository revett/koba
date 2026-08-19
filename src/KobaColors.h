#import <Cocoa/Cocoa.h>

// Koba's chrome palette, derived at startup from the user's ghostty theme:
// every colour is a mix between the terminal background and foreground, so
// the chrome always matches the terminal. Falls back to Tailwind Stone
// (https://tailwindcss.com/docs/colors) when the theme can't be read.

// Call once at startup with the terminal's background and foreground.
void KobaColorsInitialize(NSColor *background, NSColor *foreground);

// Surfaces
NSColor *KobaColorAppBackground(void);
NSColor *KobaColorCardBackground(void);
NSColor *KobaColorScrim(void);

// Selection
NSColor *KobaColorSelectedBorder(void);
NSColor *KobaColorSelectedFill(void);

// Borders
NSColor *KobaColorBorder(void);

// Text
NSColor *KobaColorTextPrimary(void);
NSColor *KobaColorTextSecondary(void);
NSColor *KobaColorTextMuted(void);
NSColor *KobaColorWarning(void);
