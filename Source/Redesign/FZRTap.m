#import <dlfcn.h>
#import <mach/mach_time.h>
#import <objc/message.h>
#import "Redesign/FZRTap.h"
#import "Core/FZLog.h"

typedef struct __IOHIDEvent *IOHIDEventRef;
typedef IOHIDEventRef (*DigitizerFn)(CFAllocatorRef, uint64_t, uint32_t, uint32_t, uint32_t, uint32_t, uint32_t,
                                     double, double, double, double, double, Boolean, Boolean, uint32_t);
typedef IOHIDEventRef (*FingerFn)(CFAllocatorRef, uint64_t, uint32_t, uint32_t, uint32_t, double, double, double,
                                  double, double, Boolean, Boolean, uint32_t);
typedef void (*AppendFn)(IOHIDEventRef, IOHIDEventRef, uint32_t);
typedef void (*SetIntegerFn)(IOHIDEventRef, uint32_t, int64_t);

static const uint32_t kTransducerHand = 3;                 // kIOHIDDigitizerTransducerTypeHand
static const uint32_t kEventRange = 1, kEventTouch = 2;    // kIOHIDDigitizerEventRange / Touch
static const uint32_t kFieldDisplayIntegrated = 0xB0019;   // kIOHIDEventFieldDigitizerIsDisplayIntegrated

static DigitizerFn sDigitizer;
static FingerFn sFinger;
static AppendFn sAppend;
static SetIntegerFn sSetInteger;

static BOOL loadIOKit(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void *iokit = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW);
        sDigitizer = (DigitizerFn)dlsym(iokit ?: RTLD_DEFAULT, "IOHIDEventCreateDigitizerEvent");
        sFinger = (FingerFn)dlsym(iokit ?: RTLD_DEFAULT, "IOHIDEventCreateDigitizerFingerEvent");
        sAppend = (AppendFn)dlsym(iokit ?: RTLD_DEFAULT, "IOHIDEventAppendEvent");
        sSetInteger = (SetIntegerFn)dlsym(iokit ?: RTLD_DEFAULT, "IOHIDEventSetIntegerValue");
    });
    return sDigitizer && sFinger && sAppend && sSetInteger;
}

static IOHIDEventRef hidEvent(CGPoint screenPoint, BOOL touching) {
    uint64_t now = mach_absolute_time();
    IOHIDEventRef hand = sDigitizer(kCFAllocatorDefault, now, kTransducerHand, 0, 0, kEventTouch, 0, 0, 0, 0, 0, 0,
                                    touching, touching, 0);
    sSetInteger(hand, kFieldDisplayIntegrated, 1);
    IOHIDEventRef finger = sFinger(kCFAllocatorDefault, now, 1, 2, kEventRange | kEventTouch, screenPoint.x, screenPoint.y,
                                   0, touching ? 1 : 0, 0, touching, touching, 0);
    sAppend(hand, finger, 0);
    CFRelease(finger);
    return hand;
}

static BOOL responds(id object, NSString *selector) {
    if ([object respondsToSelector:NSSelectorFromString(selector)]) return YES;
    FZLogError("tap: %@ doesn't answer %@; no tap sent", NSStringFromClass([object class]), selector);
    return NO;
}

static void send(id object, NSString *selector, id argument) {
    ((void (*)(id, SEL, id))objc_msgSend)(object, NSSelectorFromString(selector), argument);
}

static BOOL tapView(UIWindow *window, CGPoint point, UIView *target);

BOOL FZRTap(UIWindow *window, CGPoint point) {
    return tapView(window, point, nil);
}

BOOL FZRTapIn(UIView *root, CGPoint point) {
    UIWindow *window = root.window;
    UIView *target = window ? [root hitTest:[root convertPoint:point fromView:window] withEvent:nil] : nil;
    if (!target) { FZLogError("tap: nothing under %@ in %@", NSStringFromCGPoint(point), NSStringFromClass(root.class)); return NO; }
    return tapView(window, point, target);
}

// One phase of a touch, sent through UIApplication as a real one is.
static void sendPhase(UIApplication *app, UIEvent *event, UITouch *touch, CGPoint screenPoint, NSInteger phase) {
    BOOL touching = phase == UITouchPhaseBegan || phase == UITouchPhaseMoved || phase == UITouchPhaseStationary;
    IOHIDEventRef hid = hidEvent(screenPoint, touching);
    ((void (*)(id, SEL, NSInteger))objc_msgSend)(touch, NSSelectorFromString(@"setPhase:"), phase);
    ((void (*)(id, SEL, NSTimeInterval))objc_msgSend)(touch, NSSelectorFromString(@"setTimestamp:"), NSProcessInfo.processInfo.systemUptime);
    ((void (*)(id, SEL, IOHIDEventRef))objc_msgSend)(touch, NSSelectorFromString(@"_setHidEvent:"), hid);
    ((void (*)(id, SEL))objc_msgSend)(event, NSSelectorFromString(@"_clearTouches"));
    ((void (*)(id, SEL, IOHIDEventRef))objc_msgSend)(event, NSSelectorFromString(@"_setHIDEvent:"), hid);
    ((void (*)(id, SEL, id, BOOL))objc_msgSend)(event, NSSelectorFromString(@"_addTouch:forDelayedDelivery:"), touch, NO);
    [app sendEvent:event];
    CFRelease(hid);
}

// `hold` > 0 lifts the finger that long after it went down, on a later turn of the run loop, as a person's tap
// does: SwiftUI's tap gestures let an instant one go by now and then (rows not starting, device build 51).
static BOOL tapViewHeld(UIWindow *window, CGPoint point, UIView *target, NSTimeInterval hold) {
    if (!window || !loadIOKit()) {
        FZLogError("tap: %@", window ? @"IOKit's HID event functions aren't there; no tap sent" : @"no window");
        return NO;
    }
    UIApplication *app = UIApplication.sharedApplication;
    UIView *view = target ?: [window hitTest:point withEvent:nil];
    UITouch *touch = [UITouch new];
    NSArray *touchSelectors = @[@"setWindow:", @"setView:", @"setTapCount:", @"setPhase:", @"setTimestamp:",
                                @"_setLocationInWindow:resetPrevious:", @"_setIsFirstTouchForView:", @"_setHidEvent:"];
    for (NSString *selector in touchSelectors) if (!responds(touch, selector)) return NO;
    if (!responds(app, @"_touchesEvent")) return NO;
    UIEvent *event = ((UIEvent *(*)(id, SEL))objc_msgSend)(app, NSSelectorFromString(@"_touchesEvent"));
    for (NSString *selector in @[@"_clearTouches", @"_setHIDEvent:", @"_addTouch:forDelayedDelivery:"]) {
        if (!responds(event, selector)) return NO;
    }
    CGPoint screenPoint = [window convertPoint:point toCoordinateSpace:window.screen.coordinateSpace];

    send(touch, @"setWindow:", window);
    send(touch, @"setView:", view);
    ((void (*)(id, SEL, NSUInteger))objc_msgSend)(touch, NSSelectorFromString(@"setTapCount:"), 1);
    ((void (*)(id, SEL, CGPoint, BOOL))objc_msgSend)(touch, NSSelectorFromString(@"_setLocationInWindow:resetPrevious:"), point, YES);
    ((void (*)(id, SEL, BOOL))objc_msgSend)(touch, NSSelectorFromString(@"_setIsFirstTouchForView:"), YES);

    sendPhase(app, event, touch, screenPoint, UITouchPhaseBegan);
    if (hold <= 0) {
        sendPhase(app, event, touch, screenPoint, UITouchPhaseEnded);
    } else {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(hold * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            UIEvent *later = ((UIEvent *(*)(id, SEL))objc_msgSend)(app, NSSelectorFromString(@"_touchesEvent"));
            sendPhase(app, later, touch, screenPoint, UITouchPhaseEnded);
        });
    }
    FZLog("tap: sent at %@ to %@%@", NSStringFromCGPoint(point), NSStringFromClass(view.class), hold > 0 ? @" (held)" : @"");
    return YES;
}

static BOOL tapView(UIWindow *window, CGPoint point, UIView *target) {
    return tapViewHeld(window, point, target, 0);
}

BOOL FZRTapHeld(UIWindow *window, CGPoint point, NSTimeInterval hold) {
    return tapViewHeld(window, point, nil, hold);
}

// A finger drag from `from` to `to` (window coordinates) over `duration`, ~60 moves a second, then lifted.
BOOL FZRDrag(UIWindow *window, CGPoint from, CGPoint to, NSTimeInterval duration) {
    if (!window || !loadIOKit()) return NO;
    UIApplication *app = UIApplication.sharedApplication;
    UIView *view = [window hitTest:from withEvent:nil];
    UITouch *touch = [UITouch new];
    for (NSString *selector in @[@"setWindow:", @"setView:", @"setTapCount:", @"setPhase:", @"setTimestamp:",
                                 @"_setLocationInWindow:resetPrevious:", @"_setIsFirstTouchForView:", @"_setHidEvent:"]) {
        if (!responds(touch, selector)) return NO;
    }
    if (!responds(app, @"_touchesEvent")) return NO;
    send(touch, @"setWindow:", window);
    send(touch, @"setView:", view);
    ((void (*)(id, SEL, NSUInteger))objc_msgSend)(touch, NSSelectorFromString(@"setTapCount:"), 1);
    ((void (*)(id, SEL, CGPoint, BOOL))objc_msgSend)(touch, NSSelectorFromString(@"_setLocationInWindow:resetPrevious:"), from, YES);
    ((void (*)(id, SEL, BOOL))objc_msgSend)(touch, NSSelectorFromString(@"_setIsFirstTouchForView:"), YES);
    id<UICoordinateSpace> space = window.screen.coordinateSpace;
    UIEvent *event = ((UIEvent *(*)(id, SEL))objc_msgSend)(app, NSSelectorFromString(@"_touchesEvent"));
    sendPhase(app, event, touch, [window convertPoint:from toCoordinateSpace:space], UITouchPhaseBegan);

    NSInteger steps = MAX(2, (NSInteger)(duration * 60));
    for (NSInteger i = 1; i <= steps; i++) {
        CGFloat t = (CGFloat)i / steps;
        CGPoint p = CGPointMake(from.x + (to.x - from.x) * t, from.y + (to.y - from.y) * t);
        BOOL last = i == steps;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(duration * t * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            ((void (*)(id, SEL, CGPoint, BOOL))objc_msgSend)(touch, NSSelectorFromString(@"_setLocationInWindow:resetPrevious:"), p, NO);
            UIEvent *e = ((UIEvent *(*)(id, SEL))objc_msgSend)(app, NSSelectorFromString(@"_touchesEvent"));
            CGPoint sp = [window convertPoint:p toCoordinateSpace:space];
            sendPhase(app, e, touch, sp, UITouchPhaseMoved);
            if (last) {
                UIEvent *e2 = ((UIEvent *(*)(id, SEL))objc_msgSend)(app, NSSelectorFromString(@"_touchesEvent"));
                sendPhase(app, e2, touch, sp, UITouchPhaseEnded);
            }
        });
    }
    return YES;
}
