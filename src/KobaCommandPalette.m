#import "KobaCommandPalette.h"
#import "KobaColors.h"

static const CGFloat KobaPaletteWidth = 600;
// Sized so row text carries the same breathing room vertically as the
// shared text inset does horizontally (inset + ~14pt text + inset).
static const CGFloat KobaPaletteRowHeight = 34;
// One inset rules the query band vertically and all text horizontally, so
// padding reads uniform. Rows span the full card width (no outer gutter),
// with a small gap between the divider and the first row, mirrored at the
// bottom.
static const CGFloat KobaPaletteInset = 10;
static const CGFloat KobaPaletteQueryHeight = 16;
static const CGFloat KobaPaletteRowsGap = 6;
static const NSInteger KobaPaletteMaxRows = 12;

@implementation KobaCommandPalette {
    NSArray<NSString *> *_titles;
    NSAttributedString *_note;
    NSString *_placeholder;
    NSMutableString *_query;
    NSArray<NSNumber *> *_filtered;  // indices into _titles
    NSInteger _selectedRow;          // index into _filtered
    BOOL _textInput;
    NSInteger _maxLength;
}

- (instancetype)initWithCommands:(NSArray<NSString *> *)titles {
    return [self initWithCommands:titles note:nil];
}

- (instancetype)initWithCommands:(NSArray<NSString *> *)titles
                            note:(NSAttributedString *)note {
    NSInteger rows = MIN(MAX((NSInteger)titles.count, 1), KobaPaletteMaxRows);
    return [self initWithTitles:titles
                           note:note
                    placeholder:@"Type to filter…"
                      textInput:NO
                      maxLength:0
                           rows:rows];
}

- (instancetype)initForTextInputWithPlaceholder:(NSString *)placeholder
                                           note:(NSAttributedString *)note
                                      maxLength:(NSInteger)maxLength {
    return [self initWithTitles:@[]
                           note:note
                    placeholder:placeholder
                      textInput:YES
                      maxLength:maxLength
                           rows:0];
}

- (instancetype)initWithTitles:(NSArray<NSString *> *)titles
                          note:(NSAttributedString *)note
                   placeholder:(NSString *)placeholder
                     textInput:(BOOL)textInput
                     maxLength:(NSInteger)maxLength
                          rows:(NSInteger)rows {
    CGFloat noteHeight = note != nil ? 22 : 0;
    // Query band (inset evenly around the text), divider, then rows flush
    // against the divider and the card bottom. Any note gets its own gap.
    CGFloat height = KobaPaletteInset + KobaPaletteQueryHeight + KobaPaletteInset + 1;
    if (!textInput) height += rows * KobaPaletteRowHeight;
    if (noteHeight > 0) height += 2 * KobaPaletteRowsGap + noteHeight;
    self = [super initWithFrame:NSMakeRect(0, 0, KobaPaletteWidth, height)];
    if (!self) return nil;

    _titles = [titles copy];
    _note = [note copy];
    _placeholder = [placeholder copy];
    _textInput = textInput;
    _maxLength = maxLength;
    _query = [NSMutableString string];

    self.wantsLayer = YES;
    self.layer.backgroundColor = KobaColorCardBackground().CGColor;
    self.layer.borderWidth = 1;
    self.layer.borderColor = KobaColorBorder().CGColor;

    [self applyFilter];
    return self;
}

- (NSString *)query {
    return [_query copy];
}

- (NSInteger)selectedIndex {
    if (_selectedRow < 0 || _selectedRow >= (NSInteger)_filtered.count) return -1;
    return _filtered[(NSUInteger)_selectedRow].integerValue;
}

- (void)moveSelection:(NSInteger)delta {
    NSInteger count = (NSInteger)_filtered.count;
    if (count == 0) return;
    if (_selectedRow < 0) {
        // Nothing selected yet: down selects the first row, up the last.
        _selectedRow = delta > 0 ? 0 : count - 1;
    } else {
        _selectedRow = (_selectedRow + delta + count) % count;
    }
    [self rebuildRows];
}

- (void)appendQuery:(NSString *)text {
    [_query appendString:text];
    if (_maxLength > 0 && (NSInteger)_query.length > _maxLength) {
        [_query deleteCharactersInRange:
            NSMakeRange((NSUInteger)_maxLength, _query.length - (NSUInteger)_maxLength)];
    }
    [self applyFilter];
}

- (void)deleteQueryCharacter {
    if (_query.length == 0) return;
    [_query deleteCharactersInRange:NSMakeRange(_query.length - 1, 1)];
    [self applyFilter];
}

- (void)applyFilter {
    NSMutableArray<NSNumber *> *filtered = [NSMutableArray array];
    for (NSUInteger i = 0; i < _titles.count; i++) {
        if (_query.length == 0 ||
            [_titles[i] rangeOfString:_query options:NSCaseInsensitiveSearch].location !=
                NSNotFound) {
            [filtered addObject:@(i)];
        }
    }
    _filtered = filtered;
    // Nothing is selected until the user acts: arrow keys select, and a
    // typed filter auto-selects its first match so enter works immediately.
    _selectedRow = (_query.length > 0 && filtered.count > 0) ? 0 : -1;
    [self rebuildRows];
}

- (NSTextField *)labelWithString:(NSString *)text
                            font:(NSFont *)font
                           color:(NSColor *)color {
    NSTextField *label = [NSTextField labelWithString:text];
    label.font = font;
    label.textColor = color;
    label.lineBreakMode = NSLineBreakByTruncatingTail;
    [label sizeToFit];
    return label;
}

- (void)rebuildRows {
    [self.subviews.copy makeObjectsPerformSelector:@selector(removeFromSuperview)];

    // Query line at the top.
    BOOL hasQuery = _query.length > 0;
    NSTextField *query =
        [self labelWithString:hasQuery ? _query : _placeholder
                         font:[NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular]
                        color:hasQuery ? KobaColorTextPrimary() : KobaColorTextMuted()];
    CGFloat queryY = NSHeight(self.bounds) - KobaPaletteInset - KobaPaletteQueryHeight;
    query.frame = NSMakeRect(KobaPaletteInset,
                             queryY + (KobaPaletteQueryHeight - NSHeight(query.frame)) / 2,
                             KobaPaletteWidth - 2 * KobaPaletteInset,
                             NSHeight(query.frame));
    [self addSubview:query];

    CGFloat dividerY = queryY - KobaPaletteInset - 1;
    NSView *divider = [[NSView alloc] initWithFrame:
        NSMakeRect(0, dividerY, KobaPaletteWidth, 1)];
    divider.wantsLayer = YES;
    divider.layer.backgroundColor = KobaColorBorder().CGColor;
    [self addSubview:divider];

    if (_note != nil) {
        NSTextField *note = [NSTextField labelWithString:@""];
        note.attributedStringValue = _note;
        note.lineBreakMode = NSLineBreakByTruncatingMiddle;
        [note sizeToFit];
        note.frame = NSMakeRect(KobaPaletteInset,
                                KobaPaletteRowsGap +
                                (22 - NSHeight(note.frame)) / 2,
                                KobaPaletteWidth - 2 * KobaPaletteInset,
                                NSHeight(note.frame));
        [self addSubview:note];
    }

    // Text-input mode is just the query line and the note.
    if (_textInput) return;

    // Rows sit flush against the divider.
    CGFloat rowsTop = dividerY;

    if (_filtered.count == 0) {
        NSTextField *empty =
            [self labelWithString:_titles.count == 0 ? @"No commands available" : @"No matches"
                             font:[NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular]
                            color:KobaColorTextMuted()];
        empty.frame = NSMakeRect(KobaPaletteInset,
                                 rowsTop - KobaPaletteRowHeight +
                                 (KobaPaletteRowHeight - NSHeight(empty.frame)) / 2,
                                 KobaPaletteWidth - 2 * KobaPaletteInset,
                                 NSHeight(empty.frame));
        [self addSubview:empty];
        return;
    }

    // A window of rows that keeps the selection visible.
    NSInteger first = 0;
    if (_selectedRow >= KobaPaletteMaxRows) first = _selectedRow - KobaPaletteMaxRows + 1;
    NSInteger visible = MIN((NSInteger)_filtered.count - first, KobaPaletteMaxRows);

    for (NSInteger row = 0; row < visible; row++) {
        NSInteger filteredIndex = first + row;
        BOOL selected = (filteredIndex == _selectedRow);
        NSString *title = _titles[_filtered[(NSUInteger)filteredIndex].unsignedIntegerValue];

        // Rows span the full card width; only the text is inset.
        NSView *rowView = [[NSView alloc] initWithFrame:
            NSMakeRect(0,
                       rowsTop - (row + 1) * KobaPaletteRowHeight,
                       KobaPaletteWidth, KobaPaletteRowHeight)];
        rowView.wantsLayer = YES;
        rowView.layer.backgroundColor = selected
            ? KobaColorSelectedFill().CGColor
            : NSColor.clearColor.CGColor;

        NSTextField *label =
            [self labelWithString:title
                             font:[NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular]
                            color:selected ? KobaColorTextPrimary() : KobaColorTextSecondary()];
        label.frame = NSMakeRect(KobaPaletteInset,
                                 (KobaPaletteRowHeight - NSHeight(label.frame)) / 2,
                                 NSWidth(rowView.bounds) - 2 * KobaPaletteInset,
                                 NSHeight(label.frame));
        [rowView addSubview:label];
        [self addSubview:rowView];
    }
}

@end
