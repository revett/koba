#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

// The command palette card: a keyboard-driven, filterable list of command
// titles. Selection, filtering, and execution are driven externally by the
// key event monitor.
@interface KobaCommandPalette : NSView

// Index into the original commands array for the currently selected row,
// or -1 when the filter matches nothing.
@property (nonatomic, readonly) NSInteger selectedIndex;

- (instancetype)initWithCommands:(NSArray<NSString *> *)titles;

// An optional warning line rendered under the commands. The caller styles
// it (font, colors) via attributes.
- (instancetype)initWithCommands:(NSArray<NSString *> *)titles
                            note:(nullable NSAttributedString *)note;

// A text-input palette: no command rows, just the query line (which becomes
// the entered text) and an optional note. maxLength of 0 means unlimited.
- (instancetype)initForTextInputWithPlaceholder:(NSString *)placeholder
                                           note:(nullable NSAttributedString *)note
                                      maxLength:(NSInteger)maxLength;

// The current query / entered text.
@property (nonatomic, readonly) NSString *query;

- (void)moveSelection:(NSInteger)delta;

// Type-to-filter: case-insensitive substring match against the titles.
- (void)appendQuery:(NSString *)text;
- (void)deleteQueryCharacter;

@end

NS_ASSUME_NONNULL_END
