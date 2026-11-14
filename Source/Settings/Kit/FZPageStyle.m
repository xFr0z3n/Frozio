// Adapted from taurus/tweak/Sources/Settings/SGPageStyle.m (GPL-3.0, github.com/xFr0z3n/taurus).
#import "FZPageStyle.h"
#import "Settings/Kit/FZKitCore.h"

static UIFont *fz_titleFont, *fz_subtitleFont;

UIColor *FZGrey(void) { return [UIColor colorWithWhite:0xB3 / 255.0 alpha:1]; }
UIFont *FZTitleFont(void) { return fz_titleFont ?: [UIFont systemFontOfSize:13 weight:UIFontWeightBold]; }
UIFont *FZSubtitleFont(void) { return fz_subtitleFont ?: [UIFont systemFontOfSize:11]; }

UIImageView *FZSymbolView(NSString *name, CGFloat size, UIImageSymbolWeight weight, CGFloat box) {
    UIImage *image = [UIImage systemImageNamed:name withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:size weight:weight]];
    UIImageView *view = [[UIImageView alloc] initWithImage:image];
    view.tintColor = UIColor.whiteColor;
    view.contentMode = UIViewContentModeCenter;
    view.frame = CGRectMake(0, 0, box, box);
    return view;
}

// A grey note in a wrapper view, for the table header and footer.
UIView *FZNote(NSString *text) {
    UILabel *label = [UILabel new];
    label.text = text;
    label.font = FZSubtitleFont();
    label.textColor = FZGrey();
    label.numberOfLines = 0;
    UIView *wrapper = [UIView new];
    [wrapper addSubview:label];
    return wrapper;
}

void FZFitNote(UITableView *table, UIView *wrapper, CGFloat top, CGFloat bottom) {
    UILabel *label = wrapper.subviews.firstObject;
    CGFloat inset = table.layoutMargins.left;
    CGFloat width = table.bounds.size.width - 2 * inset;
    CGFloat height = ceil([label sizeThatFits:CGSizeMake(width, CGFLOAT_MAX)].height);
    label.frame = CGRectMake(inset, top, width, height);
    CGSize size = CGSizeMake(table.bounds.size.width, top + height + bottom);
    if (CGSizeEqualToSize(wrapper.bounds.size, size)) return;
    wrapper.frame = (CGRect){wrapper.frame.origin, size};
    if (wrapper == table.tableHeaderView) table.tableHeaderView = wrapper;
    else table.tableFooterView = wrapper;
}

static CGFloat barsHeight(UIView *view) {
    UIWindow *window = view.window;
    __block CGFloat top = window.bounds.size.height;
    FZForEachView(window, ^(UIView *v) {
        NSString *name = NSStringFromClass(v.class);
        BOOL bar = [name containsString:@"NowPlaying_BarPageImpl"] || [name isEqualToString:@"_TtC23NavigationUI_TabBarImpl10TabBarView"];
        if (!bar || v.hidden || v.alpha == 0 || v.bounds.size.height == 0) return;
        top = MIN(top, FZFrameIn(v, window).origin.y);
    });
    return window.bounds.size.height - top;
}

void FZInsetForBars(UITableView *table) {
    CGFloat bottom = MAX(0, barsHeight(table) - table.safeAreaInsets.bottom);
    if (table.contentInset.bottom == bottom) return;
    UIEdgeInsets inset = table.contentInset;
    inset.bottom = bottom;
    table.contentInset = inset;
    table.verticalScrollIndicatorInsets = inset;
}

// Frozio: redesign look only (docs/DECISIONS.md). The accent key is Frozio's; its default is the
// redesign's own green #37F200 (docs/DESIGN_TOKENS.md, color.accent).
NSString *const FZAccentKey = @"fz.redesign.accent";
static const NSInteger kDefaultAccent = 0x37F200;

static UIColor *lookAccent(void) {
    NSInteger rgb = FZInt(FZAccentKey, kDefaultAccent);
    if (rgb < 0 || rgb > 0xFFFFFF) return nil;
    return [UIColor colorWithRed:((rgb >> 16) & 0xFF) / 255.0 green:((rgb >> 8) & 0xFF) / 255.0 blue:(rgb & 0xFF) / 255.0 alpha:1];
}

static BOOL lookBlack(void) {
    return YES; // the redesign draws its pages on black
}

UIColor *FZGreen(void) { return lookAccent() ?: [UIColor colorWithRed:0x1E / 255.0 green:0xD7 / 255.0 blue:0x60 / 255.0 alpha:1]; }
UIColor *FZAccentMark(void) { return FZGreen(); }
UIColor *FZOnAccent(void) {
    CGFloat r, g, b, a;
    if (![FZGreen() getRed:&r green:&g blue:&b alpha:&a]) return UIColor.whiteColor;
    CGFloat luma = 0.2126 * r + 0.7152 * g + 0.0722 * b;
    return luma > 0.6 ? UIColor.blackColor : UIColor.whiteColor;
}
UIColor *FZRed(void) { return [UIColor colorWithRed:0xF1 / 255.0 green:0x5E / 255.0 blue:0x6B / 255.0 alpha:1]; }
UIColor *FZPageBackground(void) { return lookBlack() ? UIColor.blackColor : [UIColor colorWithWhite:0x12 / 255.0 alpha:1]; }
// The redesign's card grey on its black page.
UIColor *FZCardBackground(void) { return [UIColor colorWithWhite:(lookBlack() ? 0x1C : 0x2A) / 255.0 alpha:1]; }

UIImage *FZTileImage(NSString *symbol) {
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:14 weight:UIImageSymbolWeightMedium];
    UIImage *glyph = [[UIImage systemImageNamed:symbol withConfiguration:config] imageWithTintColor:UIColor.whiteColor renderingMode:UIImageRenderingModeAlwaysOriginal];
    CGRect box = CGRectMake(0, 0, 28, 28);
    UIImage *tile = [[[UIGraphicsImageRenderer alloc] initWithSize:box.size] imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        [[UIColor colorWithWhite:1 alpha:0.12] setFill];
        [[UIBezierPath bezierPathWithRoundedRect:box cornerRadius:7] fill];
        CGSize size = glyph.size;
        [glyph drawInRect:CGRectMake((box.size.width - size.width) / 2, (box.size.height - size.height) / 2, size.width, size.height)];
    }];
    return [tile imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
}

const CGFloat FZSectionHeaderHeight = 38;
const CGFloat FZSectionGap = 20;

void FZFillCell(UITableViewCell *cell, NSString *title, NSString *subtitle, UIColor *color, NSString *symbolName) {
    UIListContentConfiguration *content = [UIListContentConfiguration subtitleCellConfiguration];
    content.text = title;
    content.secondaryText = subtitle;
    content.textProperties.font = FZTitleFont();
    content.textProperties.color = color ?: UIColor.whiteColor;
    content.secondaryTextProperties.font = FZSubtitleFont();
    content.secondaryTextProperties.color = FZGrey();
    content.textToSecondaryTextVerticalPadding = 0;
    content.directionalLayoutMargins = NSDirectionalEdgeInsetsMake(10, 16, 10, 16);
    if (symbolName) {
        content.image = [UIImage systemImageNamed:symbolName withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:15 weight:UIImageSymbolWeightRegular]];
        content.imageProperties.tintColor = color ?: UIColor.whiteColor;
        content.imageToTextPadding = 14;
    }
    cell.contentConfiguration = content;
    cell.backgroundColor = FZCardBackground();
    cell.accessoryView = nil;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
}

UIView *FZSectionHeader(UITableView *table, NSString *title) {
    UILabel *label = [UILabel new];
    label.text = title.uppercaseString;
    label.font = FZSubtitleFont();
    label.textColor = FZGrey();
    label.frame = CGRectMake(16, 20, table.bounds.size.width - 32, 14);
    label.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, table.bounds.size.width, FZSectionHeaderHeight)];
    [header addSubview:label];
    return header;
}

static const CGFloat kFooterTop = 8, kFooterBottom = 4;

static CGFloat footerTextHeight(UITableView *table, NSString *text) {
    // An inset grouped table narrows its footers by its side margins, and the label wraps at that width.
    CGFloat inset = table.style == UITableViewStyleInsetGrouped ? table.layoutMargins.left + table.layoutMargins.right : 0;
    CGFloat width = MAX(table.bounds.size.width - inset - 32, 100);
    return ceil([text boundingRectWithSize:CGSizeMake(width, CGFLOAT_MAX)
                                   options:NSStringDrawingUsesLineFragmentOrigin
                                attributes:@{NSFontAttributeName: FZSubtitleFont()}
                                   context:nil].size.height);
}

UIView *FZSectionFooter(UITableView *table, NSString *text) {
    UILabel *label = [UILabel new];
    label.text = text;
    label.font = FZSubtitleFont();
    label.textColor = FZGrey();
    label.numberOfLines = 0;
    label.frame = CGRectMake(16, kFooterTop, table.bounds.size.width - 32, footerTextHeight(table, text));
    label.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    UIView *footer = [[UIView alloc] initWithFrame:CGRectMake(0, 0, table.bounds.size.width, FZSectionFooterHeight(table, text))];
    [footer addSubview:label];
    return footer;
}

CGFloat FZSectionFooterHeight(UITableView *table, NSString *text) {
    return kFooterTop + footerTextHeight(table, text) + kFooterBottom;
}

UITableViewCell *FZDequeueCell(UITableView *table, NSString *identifier) {
    return [table dequeueReusableCellWithIdentifier:identifier]
        ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:identifier];
}

static CGFloat brightness(UIColor *color) {
    CGFloat white = 0;
    [color getWhite:&white alpha:NULL];
    return white;
}

// Spotify's list labels carry its typeface: 13pt titles and 11pt grey subtitles.
void FZAdoptFonts(UIView *list, UIView *row) {
    if (fz_titleFont && fz_subtitleFont) return;
    FZForEachView(list, ^(UIView *v) {
        if (![v isKindOfClass:UILabel.class] || FZIsInside(v, row)) return;
        UILabel *label = (UILabel *)v;
        if (label.text.length < 2) return;
        CGFloat size = label.font.pointSize, white = brightness(label.textColor);
        if (size == 13 && !fz_titleFont) fz_titleFont = label.font;
        if (size == 11 && !fz_subtitleFont && white > 0.3 && white < 0.95) fz_subtitleFont = label.font;
    });
}

UIViewController *FZTopController(void) {
    UIViewController *top = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (window.hidden) continue;
            if (!top || window.isKeyWindow) top = window.rootViewController;
        }
    }
    while (top.presentedViewController) top = top.presentedViewController;
    return top;
}

NSString *const FZRepoURL = @"https://github.com/xFr0z3n/Frozio";

void FZOpenURL(NSString *url) {
    NSURL *target = url ? [NSURL URLWithString:url] : nil;
    if (!target) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        [UIApplication.sharedApplication openURL:target options:@{} completionHandler:nil];
    });
}

void FZPresentDark(UIViewController *vc) {
    if (vc) vc.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
}
