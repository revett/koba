#import "KobaWorkspaceStrip.h"
#import "KobaColors.h"

static const CGFloat KobaCardWidth = 120;
// 8pt inset top and bottom, a 14pt "#N" line, then three 13pt lines with
// 3pt gaps: 8 + 14 + 3*(3 + 13) + 8 = 78.
static const CGFloat KobaCardHeight = 78;
static const CGFloat KobaCardSpacing = 8;
static const CGFloat KobaStripPadding = 10;
static const CGFloat KobaCardTextInset = 8;

@implementation KobaWorkspaceStrip {
    NSArray<NSString *> *_topLines;
    NSArray<NSArray<NSString *> *> *_lines;
    NSArray<NSNumber *> *_statuses;
    NSInteger _selectedIndex;
}

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    _topLines = @[];
    _lines = @[];
    _statuses = @[];
    _selectedIndex = -1;
    return self;
}

- (void)updateWithTopLines:(NSArray<NSString *> *)topLines
                     lines:(NSArray<NSArray<NSString *> *> *)lines
                  statuses:(NSArray<NSNumber *> *)statuses
             selectedIndex:(NSInteger)selectedIndex {
    _topLines = [topLines copy];
    _lines = [lines copy];
    _statuses = [statuses copy];
    _selectedIndex = selectedIndex;
    [self rebuildCards];
}

// Idle keeps the neutral chrome; anything else colors the border.
static NSColor *KobaStatusBorderColor(KobaClaudeStatus status, BOOL selected) {
    switch (status) {
        case KobaClaudeStatusWorking: return KobaColorStatusWorking();
        case KobaClaudeStatusDone: return KobaColorStatusDone();
        case KobaClaudeStatusError: return KobaColorStatusError();
        case KobaClaudeStatusIdle:
            return selected ? KobaColorSelectedBorder() : KobaColorBorder();
    }
}

- (void)resizeSubviewsWithOldSize:(NSSize)oldSize {
    [self rebuildCards];
}

// Cards overflowing the strip are shifted left just enough to keep the
// selected card fully visible; navigation is keyboard driven, so there is
// no scrollbar.
- (CGFloat)shiftForSelectedCard {
    if (_selectedIndex < 0) return 0;
    CGFloat cardX = KobaStripPadding + _selectedIndex * (KobaCardWidth + KobaCardSpacing);
    CGFloat overflow = cardX + KobaCardWidth + KobaStripPadding - NSWidth(self.bounds);
    return MAX(0, MIN(overflow, cardX - KobaStripPadding));
}

- (NSTextField *)cardLabel:(NSString *)text
                      font:(NSFont *)font
                     color:(NSColor *)color
                      topY:(CGFloat)topY {
    NSTextField *label = [NSTextField labelWithString:text];
    label.font = font;
    label.textColor = color;
    label.alignment = NSTextAlignmentLeft;
    label.lineBreakMode = NSLineBreakByTruncatingMiddle;
    [label sizeToFit];
    label.frame = NSMakeRect(KobaCardTextInset, topY - NSHeight(label.frame),
                             KobaCardWidth - 2 * KobaCardTextInset,
                             NSHeight(label.frame));
    return label;
}

- (void)rebuildCards {
    [self.subviews.copy makeObjectsPerformSelector:@selector(removeFromSuperview)];

    CGFloat shift = [self shiftForSelectedCard];
    CGFloat y = (NSHeight(self.bounds) - KobaCardHeight) / 2;
    for (NSInteger i = 0; i < (NSInteger)_lines.count; i++) {
        BOOL selected = (i == _selectedIndex);

        NSView *card = [[NSView alloc] initWithFrame:
            NSMakeRect(KobaStripPadding + i * (KobaCardWidth + KobaCardSpacing) - shift, y,
                       KobaCardWidth, KobaCardHeight)];
        KobaClaudeStatus status = (KobaClaudeStatus)_statuses[(NSUInteger)i].integerValue;
        card.wantsLayer = YES;
        card.layer.borderWidth = selected ? 2 : 1;
        card.layer.borderColor = KobaStatusBorderColor(status, selected).CGColor;
        card.layer.backgroundColor = selected
            ? KobaColorSelectedFill().CGColor
            : NSColor.clearColor.CGColor;

        NSTextField *number =
            [self cardLabel:_topLines[(NSUInteger)i]
                       font:[NSFont monospacedSystemFontOfSize:10 weight:NSFontWeightSemibold]
                      color:selected ? KobaColorTextPrimary() : KobaColorTextSecondary()
                       topY:KobaCardHeight - KobaCardTextInset];
        [card addSubview:number];

        CGFloat topY = NSMinY(number.frame) - 3;
        for (NSString *line in _lines[(NSUInteger)i]) {
            NSTextField *label =
                [self cardLabel:line
                           font:[NSFont monospacedSystemFontOfSize:10 weight:NSFontWeightRegular]
                          color:selected ? KobaColorTextSecondary() : KobaColorTextMuted()
                           topY:topY];
            [card addSubview:label];
            topY = NSMinY(label.frame) - 3;
        }

        [self addSubview:card];
    }

    self.needsDisplay = YES;
}

@end
