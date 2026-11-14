// FZHook: Frozio's only hooking primitive for ObjC methods (decision 2026-11-14: ObjC runtime only;
// fishhook / Swift table patching are added per feature when needed).
//
// Every hook is fail-safe: the class and selector must exist, and the method's type encoding must
// match exactly (frame-size digits ignored). Otherwise nothing is changed, the failure is logged,
// and NO is returned, so the app keeps its original behaviour.
#pragma once
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

/// Replaces the implementation of an instance method that `cls` itself declares or inherits.
/// If the method is only inherited, a per-class override is added (so the superclass stays untouched)
/// and `*original` then points at the superclass implementation.
/// `types` is the expected encoding without digits, e.g. "v@:B" for -(void)viewDidAppear:(BOOL).
BOOL FZHookInstanceMethod(Class cls, SEL sel, const char *types, IMP replacement, IMP *original, const char *tag);

/// Looks up a class by name and hooks it; logs and returns NO if the class isn't loaded.
BOOL FZHookInstanceMethodNamed(NSString *className, NSString *selector, const char *types,
                               IMP replacement, IMP *original, const char *tag);
