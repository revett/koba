#import "KobaSplitView.h"

@implementation KobaSplitView {
    NSView *_left;
    NSView *_right;
}

- (instancetype)initWithLeft:(NSView *)left right:(NSView *)right {
    self = [super initWithFrame:NSMakeRect(0, 0, 1200, 700)];
    if (!self) return nil;
    _left = left;
    _right = right;
    [self addSubview:left];
    [self addSubview:right];
    [self tile];
    return self;
}

- (void)replaceRightView:(NSView *)view {
    [_right removeFromSuperview];
    _right = view;
    [self addSubview:view];
    [self tile];
}

- (void)resizeSubviewsWithOldSize:(NSSize)oldSize {
    [self tile];
}

- (void)tile {
    NSRect bounds = self.bounds;
    CGFloat leftWidth = floor((NSWidth(bounds) - 1) / 2);
    _left.frame = NSMakeRect(0, 0, leftWidth, NSHeight(bounds));
    _right.frame = NSMakeRect(leftWidth + 1, 0,
                              NSWidth(bounds) - leftWidth - 1, NSHeight(bounds));
}

@end
