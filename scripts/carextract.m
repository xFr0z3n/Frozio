// carextract: writes one named image from a compiled asset catalog (Assets.car) to a PNG.
// Built and run on the macOS CI runner only (never shipped). Uses Apple's private CoreUI
// (CUICatalog), the same framework actool/assetutil use; checked at runtime, fails loudly.
//
//   carextract <Assets.car> <image name> <out.png>
//
// Picks the rendition with the largest pixel size. Exit codes: 0 ok, 2 usage, 3 CoreUI missing,
// 4 catalog didn't open, 5 image not found, 6 write failed.
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <ImageIO/ImageIO.h>
#import <dlfcn.h>
#import <objc/message.h>

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc != 4) { fprintf(stderr, "usage: carextract <Assets.car> <name> <out.png>\n"); return 2; }
        if (!dlopen("/System/Library/PrivateFrameworks/CoreUI.framework/CoreUI", RTLD_NOW)) {
            fprintf(stderr, "CoreUI not loadable: %s\n", dlerror()); return 3;
        }
        Class CUICatalog = NSClassFromString(@"CUICatalog");
        SEL initSel = NSSelectorFromString(@"initWithURL:error:");
        SEL imagesSel = NSSelectorFromString(@"imagesWithName:");
        if (!CUICatalog || ![CUICatalog instancesRespondToSelector:initSel] || ![CUICatalog instancesRespondToSelector:imagesSel]) {
            fprintf(stderr, "CUICatalog API missing\n"); return 3;
        }
        NSURL *url = [NSURL fileURLWithPath:@(argv[1])];
        NSError *err = nil;
        id catalog = ((id (*)(id, SEL, NSURL *, NSError **))objc_msgSend)([CUICatalog alloc], initSel, url, &err);
        if (!catalog) { fprintf(stderr, "catalog open failed: %s\n", err.description.UTF8String); return 4; }

        NSArray *images = ((NSArray *(*)(id, SEL, NSString *))objc_msgSend)(catalog, imagesSel, @(argv[2]));
        CGImageRef best = NULL; size_t bestPixels = 0;
        SEL imageSel = NSSelectorFromString(@"image");
        for (id named in images) {
            if (![named respondsToSelector:imageSel]) continue;
            CGImageRef img = ((CGImageRef (*)(id, SEL))objc_msgSend)(named, imageSel);
            if (!img) continue;
            size_t px = CGImageGetWidth(img) * CGImageGetHeight(img);
            if (px > bestPixels) { best = img; bestPixels = px; }
        }
        if (!best) { fprintf(stderr, "no image named %s (%lu renditions)\n", argv[2], (unsigned long)images.count); return 5; }

        NSURL *out = [NSURL fileURLWithPath:@(argv[3])];
        CGImageDestinationRef dest = CGImageDestinationCreateWithURL((__bridge CFURLRef)out, CFSTR("public.png"), 1, NULL);
        if (!dest) return 6;
        CGImageDestinationAddImage(dest, best, NULL);
        BOOL ok = CGImageDestinationFinalize(dest);
        CFRelease(dest);
        if (!ok) return 6;
        printf("%s: %zux%zu -> %s\n", argv[2], CGImageGetWidth(best), CGImageGetHeight(best), argv[3]);
        return 0;
    }
}
