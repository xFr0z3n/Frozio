// FZRPlayerTransition: the player grows out of the mini player and shrinks back into it (the user's request, build 73,
// with YouTube Music's player as the example of "lightweight and clean"): the player is revealed through a rounded
// window that grows from the mini bar to the screen as it fades in, while the mini player's cover flies to the player's
// cover. Closing (the ⌄ or a swipe down) runs the same backwards, from wherever the swipe left the player.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "Redesign/Player/FZRPlayer.h"
#import "Redesign/Kit/FZRTokens.h"
#import "Core/FZLog.h"

@interface FZRPlayerAnimator : NSObject <UIViewControllerAnimatedTransitioning>
@property (nonatomic) BOOL presenting;
@end

@interface FZRPlayerTransitionDelegate : NSObject <UIViewControllerTransitioningDelegate>
@end

// What the mini player and the player show, without knowing their classes here.
static UIImageView *imageViewFor(id owner, NSString *selector) {
    SEL sel = NSSelectorFromString(selector);
    if (![owner respondsToSelector:sel]) return nil;
    UIImageView *(*fn)(id, SEL) = (void *)[owner methodForSelector:sel];
    return fn(owner, sel);
}

@implementation FZRPlayerAnimator

- (NSTimeInterval)transitionDuration:(id<UIViewControllerContextTransitioning>)context {
    return self.presenting ? 0.42 : 0.36;
}

- (void)animateTransition:(id<UIViewControllerContextTransitioning>)context {
    UIView *container = context.containerView;
    UIViewController *player = [context viewControllerForKey:self.presenting ? UITransitionContextToViewControllerKey : UITransitionContextFromViewControllerKey];
    UIView *view = player.view;
    if (self.presenting) {
        view.frame = [context finalFrameForViewController:player];
        [container addSubview:view];
        [view layoutIfNeeded];
    }
    UIView *mini = FZRPlayerMiniBar();
    BOOL miniShown = mini.window && !mini.hidden && mini.alpha > 0.01;
    CGFloat width = container.bounds.size.width, height = container.bounds.size.height;
    CGRect miniFrame = miniShown ? [mini convertRect:mini.bounds toView:container] : CGRectMake(8, height - 150, width - 16, 56);
    CGFloat miniRadius = miniShown ? mini.layer.cornerRadius ?: 18 : 18;
    CGFloat screenRadius = 44;

    // The reveal: a rounded window in the player's own coordinates (they include a swipe's offset when closing).
    UIView *window = [UIView new];
    window.backgroundColor = UIColor.blackColor;
    window.layer.cornerCurve = kCACornerCurveContinuous;
    CGRect small = [container convertRect:miniFrame toView:view];
    CGRect large = view.bounds;
    window.frame = self.presenting ? small : large;
    window.layer.cornerRadius = self.presenting ? miniRadius : screenRadius;
    view.maskView = window;

    // The flying cover: the mini player's picture to the player's, or back.
    UIImageView *miniArt = imageViewFor(mini, @"artworkView");
    UIImageView *playerArt = imageViewFor(player, @"coverView");
    UIImageView *flyer = nil;
    BOOL playerArtShown = playerArt.window && !playerArt.hidden && playerArt.alpha > 0.01 && playerArt.superview.alpha > 0.01;
    if (miniShown && miniArt.image && playerArtShown) {
        CGRect from = [miniArt convertRect:miniArt.bounds toView:container];
        CGRect to = [playerArt convertRect:playerArt.bounds toView:container];
        flyer = [[UIImageView alloc] initWithImage:playerArt.image ?: miniArt.image];
        flyer.contentMode = UIViewContentModeScaleAspectFill;
        flyer.clipsToBounds = YES;
        flyer.layer.cornerCurve = kCACornerCurveContinuous;
        flyer.frame = self.presenting ? from : to;
        flyer.layer.cornerRadius = self.presenting ? miniArt.layer.cornerRadius : playerArt.layer.cornerRadius;
        [container addSubview:flyer];
        playerArt.alpha = 0;
        miniArt.alpha = 0;
        CGRect target = self.presenting ? to : from;
        CGFloat targetRadius = self.presenting ? playerArt.layer.cornerRadius : miniArt.layer.cornerRadius;
        objc_setAssociatedObject(flyer, "target", [NSValue valueWithCGRect:target], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(flyer, "radius", @(targetRadius), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    view.alpha = self.presenting ? 0 : 1;
    if (miniShown) mini.alpha = self.presenting ? 1 : 0;
    BOOL presenting = self.presenting;
    NSTimeInterval duration = [self transitionDuration:context];
    UIViewPropertyAnimator *animator = [[UIViewPropertyAnimator alloc] initWithDuration:duration dampingRatio:presenting ? 0.86 : 1 animations:^{
        window.frame = presenting ? large : small;
        window.layer.cornerRadius = presenting ? screenRadius : miniRadius;
        if (flyer) {
            flyer.frame = [objc_getAssociatedObject(flyer, "target") CGRectValue];
            flyer.layer.cornerRadius = [objc_getAssociatedObject(flyer, "radius") doubleValue];
        }
    }];
    // The player fades in over the first part of opening and out over the last part of closing.
    [animator addAnimations:^{
        [UIView animateKeyframesWithDuration:duration delay:0 options:0 animations:^{
            [UIView addKeyframeWithRelativeStartTime:presenting ? 0 : 0.45 relativeDuration:0.55 animations:^{ view.alpha = presenting ? 1 : 0; }];
            if (miniShown) [UIView addKeyframeWithRelativeStartTime:presenting ? 0 : 0.5 relativeDuration:0.5 animations:^{ mini.alpha = presenting ? 0 : 1; }];
        } completion:nil];
    }];
    [animator addCompletion:^(UIViewAnimatingPosition position) {
        BOOL cancelled = context.transitionWasCancelled;
        view.maskView = nil;
        [flyer removeFromSuperview];
        playerArt.alpha = 1;
        miniArt.alpha = 1;
        view.alpha = 1;
        if (miniShown) mini.alpha = presenting && !cancelled ? 0 : 1;
        if (!presenting && !cancelled) [view removeFromSuperview];
        [context completeTransition:!cancelled];
        // Behind the open player the mini player isn't needed; it's back once the player has gone.
        if (presenting && miniShown) mini.alpha = 1;
    }];
    [animator startAnimation];
}
@end

@implementation FZRPlayerTransitionDelegate
- (id<UIViewControllerAnimatedTransitioning>)animationControllerForPresentedController:(UIViewController *)presented
                                                                  presentingController:(UIViewController *)presenting
                                                                      sourceController:(UIViewController *)source {
    FZRPlayerAnimator *animator = [FZRPlayerAnimator new];
    animator.presenting = YES;
    return animator;
}
- (id<UIViewControllerAnimatedTransitioning>)animationControllerForDismissedController:(UIViewController *)dismissed {
    return [FZRPlayerAnimator new];
}
@end

id<UIViewControllerTransitioningDelegate> FZRPlayerTransitioning(void) {
    static FZRPlayerTransitionDelegate *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [FZRPlayerTransitionDelegate new]; });
    return shared;
}
