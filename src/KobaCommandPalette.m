#import "KobaCommandPalette.h"
#import "KobaColors.h"

static const CGFloat KobaPaletteWidth = 600;
static const CGFloat KobaPaletteRowHeight = 28;
static const CGFloat KobaPalettePadding = 8;
static const NSInteger KobaPaletteMaxRows = 12;

@implementation KobaCommandPalette {
    NSArray<NSString *> *_titles;
    NSAttributedString *_note;
    NSMutableString *_query;
    NSArray<NSNumber *> *_filtered;  // indices into _titles
    NSInteger _selectedRow;          // index into _filtered
}

- (instancetype)initWithCommands:(NSArray<NSString *> *)titles {
    return [self initWithCommands:titles note:nil];
}

- (instancetype)initWithCommands:(NSArray<NSString *> *)titles
                            note:(NSAttributedString *)note {
    NSInteger rows = MIN(MAX((NSInteger)titles.count, 1), KobaPaletteMaxRows);
    CGFloat noteHeight = note != nil ? 22 : 0;
    self = [super initWithFrame:NSMakeRect(0, 0, KobaPaletteWidth,
                                           (rows + 1) * KobaPaletteRowHeight +
                                           2 * KobaPalettePadding + noteHeight)];
    if (!self) return nil;

    _titles = [titles copy];
    _note = [note copy];
    _query = [NSMutableString string];

    self.wantsLayer = YES;
    self.layer.backgroundColor = KobaColorCardBackground().CGColor;
    self.layer.borderWidth = 1;
    self.layer.borderColor = KobaColorBorder().CGColor;

    [self applyFilter];
    return self;
}

- (NSInteger)selectedIndex {
    if (_selectedRow < 0 || _selectedRow >= (NSInteger)_filtered.count) return -1;
    return _filtered[(NSUInteger)_selectedRow].integerValue;
}

- (void)moveSelection:(NSInteger)delta {
    NSInteger count = (NSInteger)_filtered.count;
    if (count == 0) return;
    _selectedRow = (_selectedRow + delta + count) % count;
    [self rebuildRows];
}

- (void)appendQuery:(NSString *)text {
    [_query appendString:text];
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
    _selectedRow = filtered.count > 0 ? 0 : -1;
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
        [self labelWithString:hasQuery ? _query : @"Type to filter…"
                         font:[NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular]
                        color:hasQuery ? KobaColorTextPrimary() : KobaColorTextMuted()];
    CGFloat queryY = NSHeight(self.bounds) - KobaPalettePadding - KobaPaletteRowHeight;
    query.frame = NSMakeRect(KobaPalettePadding + 8,
                             queryY + (KobaPaletteRowHeight - NSHeight(query.frame)) / 2,
                             KobaPaletteWidth - 2 * (KobaPalettePadding + 8),
                             NSHeight(query.frame));
    [self addSubview:query];

    if (_note != nil) {
        NSTextField *note = [NSTextField labelWithString:@""];
        note.attributedStringValue = _note;
        note.lineBreakMode = NSLineBreakByTruncatingMiddle;
        [note sizeToFit];
        note.frame = NSMakeRect(KobaPalettePadding + 8, KobaPalettePadding,
                                KobaPaletteWidth - 2 * (KobaPalettePadding + 8),
                                NSHeight(note.frame));
        [self addSubview:note];
    }

    if (_filtered.count == 0) {
        NSTextField *empty =
            [self labelWithString:_titles.count == 0 ? @"No commands available" : @"No matches"
                             font:[NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular]
                            color:KobaColorTextMuted()];
        empty.frame = NSMakeRect(KobaPalettePadding + 8,
                                 queryY - KobaPaletteRowHeight +
                                 (KobaPaletteRowHeight - NSHeight(empty.frame)) / 2,
                                 KobaPaletteWidth - 2 * (KobaPalettePadding + 8),
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

        NSView *rowView = [[NSView alloc] initWithFrame:
            NSMakeRect(KobaPalettePadding,
                       queryY - (row + 1) * KobaPaletteRowHeight,
                       KobaPaletteWidth - 2 * KobaPalettePadding, KobaPaletteRowHeight)];
        rowView.wantsLayer = YES;
        rowView.layer.backgroundColor = selected
            ? KobaColorSelectedFill().CGColor
            : NSColor.clearColor.CGColor;

        NSTextField *label =
            [self labelWithString:title
                             font:[NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular]
                            color:selected ? KobaColorTextPrimary() : KobaColorTextSecondary()];
        label.frame = NSMakeRect(8, (KobaPaletteRowHeight - NSHeight(label.frame)) / 2,
                                 NSWidth(rowView.bounds) - 16, NSHeight(label.frame));
        [rowView addSubview:label];
        [self addSubview:rowView];
    }
}

@end
