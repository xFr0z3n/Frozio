// A Metal port of Kawarp (github.com/better-lyrics/kawarp @ f4a4b29, packages/core/src/index.ts and defaults.ts,
// MIT, Copyright (c) 2026 Better Lyrics). See FZRKawarp.h. The shaders below are Kawarp's GLSL rewritten in Metal
// Shading Language, same constants; the passes and their order are Kawarp's render() and blurSourceInto().
#import <Metal/Metal.h>
#import <simd/simd.h>
#import <QuartzCore/QuartzCore.h>
#import "Redesign/Kit/FZRKawarp.h"
#import "Redesign/Kit/FZRTokens.h"
#import "Settings/Kit/FZModPage.h"
#import "Settings/Kit/FZKitCore.h"
#import "Core/FZLog.h"

static const NSUInteger kBlurSize = 128;                         // Kawarp's BLUR_SIZE
static const float kTint[3] = {0.157f, 0.157f, 0.235f};          // DEFAULTS.tintColor
static const float kTintIntensity = 0.15f;                       // DEFAULTS.tintIntensity
static const NSTimeInterval kTransition = 1.0;                   // transitionDuration 1000 ms

static NSString *const kShaders = @
"#include <metal_stdlib>\n"
"using namespace metal;\n"
"struct VOut { float4 position [[position]]; float2 uv; };\n"
"vertex VOut fz_vertex(uint vid [[vertex_id]]) {\n"
"  float2 pos[3] = { float2(-1.0, -1.0), float2(3.0, -1.0), float2(-1.0, 3.0) };\n"
"  VOut o; o.position = float4(pos[vid], 0.0, 1.0);\n"
"  o.uv = float2((pos[vid].x + 1.0) * 0.5, 1.0 - (pos[vid].y + 1.0) * 0.5);\n"
"  return o;\n"
"}\n"
"constexpr sampler lin(filter::linear, address::clamp_to_edge);\n"
// TINT_SHADER
"fragment float4 fz_tint(VOut in [[stage_in]], texture2d<float> tex [[texture(0)]], constant float4 &p [[buffer(0)]]) {\n"
"  float4 color = tex.sample(lin, in.uv);\n"
"  float luma = dot(color.rgb, float3(0.299, 0.587, 0.114));\n"
"  float darkMask = 1.0 - smoothstep(0.0, 0.5, luma);\n"
"  color.rgb = mix(color.rgb, p.xyz, darkMask * p.w);\n"
"  return color;\n"
"}\n"
// KAWASE_BLUR_SHADER (p.x offset, p.y resolution)
"fragment float4 fz_blur(VOut in [[stage_in]], texture2d<float> tex [[texture(0)]], constant float2 &p [[buffer(0)]]) {\n"
"  float2 texel = 1.0 / float2(p.y);\n"
"  float o = p.x;\n"
"  float4 color = tex.sample(lin, in.uv + float2(-o, -o) * texel);\n"
"  color += tex.sample(lin, in.uv + float2(o, -o) * texel);\n"
"  color += tex.sample(lin, in.uv + float2(-o, o) * texel);\n"
"  color += tex.sample(lin, in.uv + float2(o, o) * texel);\n"
"  return color * 0.25;\n"
"}\n"
// BLEND_SHADER
"fragment float4 fz_blend(VOut in [[stage_in]], texture2d<float> a [[texture(0)]], texture2d<float> b [[texture(1)]], constant float &t [[buffer(0)]]) {\n"
"  return mix(a.sample(lin, in.uv), b.sample(lin, in.uv), t);\n"
"}\n"
// DOMAIN_WARP_SHADER (p.x time, p.y intensity)
"float3 mod289(float3 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }\n"
"float2 mod289(float2 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }\n"
"float3 permute(float3 x) { return mod289(((x * 34.0) + 1.0) * x); }\n"
"float snoise(float2 v) {\n"
"  const float4 C = float4(0.211324865405187, 0.366025403784439, -0.577350269189626, 0.024390243902439);\n"
"  float2 i = floor(v + dot(v, C.yy));\n"
"  float2 x0 = v - i + dot(i, C.xx);\n"
"  float2 i1 = (x0.x > x0.y) ? float2(1.0, 0.0) : float2(0.0, 1.0);\n"
"  float4 x12 = x0.xyxy + C.xxzz;\n"
"  x12.xy -= i1;\n"
"  i = mod289(i);\n"
"  float3 p = permute(permute(i.y + float3(0.0, i1.y, 1.0)) + i.x + float3(0.0, i1.x, 1.0));\n"
"  float3 m = max(0.5 - float3(dot(x0, x0), dot(x12.xy, x12.xy), dot(x12.zw, x12.zw)), 0.0);\n"
"  m = m * m; m = m * m;\n"
"  float3 x = 2.0 * fract(p * C.www) - 1.0;\n"
"  float3 h = abs(x) - 0.5;\n"
"  float3 ox = floor(x + 0.5);\n"
"  float3 a0 = x - ox;\n"
"  m *= 1.79284291400159 - 0.85373472095314 * (a0 * a0 + h * h);\n"
"  float3 g;\n"
"  g.x = a0.x * x0.x + h.x * x0.y;\n"
"  g.yz = a0.yz * x12.xz + h.yz * x12.yw;\n"
"  return 130.0 * dot(m, g);\n"
"}\n"
"fragment float4 fz_warp(VOut in [[stage_in]], texture2d<float> tex [[texture(0)]], constant float2 &p [[buffer(0)]]) {\n"
"  float2 uv = in.uv;\n"
"  float t = p.x * 0.05;\n"
"  float2 center = uv - 0.5;\n"
"  float centerWeight = 1.0 - smoothstep(0.0, 0.7, length(center));\n"
"  float n1 = snoise(uv * 0.35 + float2(t, t * 0.7));\n"
"  float n2 = snoise(uv * 0.35 + float2(-t * 0.8, t * 0.5) + float2(50.0, 50.0));\n"
"  float n3 = snoise(uv * 0.9 + float2(t * 1.2, -t) + float2(100.0, 0.0));\n"
"  float n4 = snoise(uv * 0.9 + float2(-t, t * 1.1) + float2(0.0, 100.0));\n"
"  float2 warp = float2(n1 * 0.65 + n3 * 0.35, n2 * 0.65 + n4 * 0.35) * centerWeight;\n"
"  float2 warpedUV = clamp(uv + warp * p.y, 0.0, 1.0);\n"
"  return tex.sample(lin, warpedUV);\n"
"}\n"
// OUTPUT_SHADER (p: saturation, dithering, time, brightness; r: resolution), scale 1
"float hash3(float3 p) {\n"
"  p = fract(p * 0.1031);\n"
"  p += dot(p, p.zyx + 31.32);\n"
"  return fract((p.x + p.y) * p.z);\n"
"}\n"
"fragment float4 fz_output(VOut in [[stage_in]], texture2d<float> tex [[texture(0)]], constant float4 &p [[buffer(0)]], constant float2 &r [[buffer(1)]]) {\n"
"  float2 uv = clamp(in.uv, 0.0, 1.0);\n"
"  float4 color = tex.sample(lin, uv);\n"
"  float2 center = in.uv - 0.5;\n"
"  float vignette = 1.0 - dot(center, center) * 0.3;\n"
"  color.rgb *= vignette;\n"
"  float gray = dot(color.rgb, float3(0.299, 0.587, 0.114));\n"
"  color.rgb = mix(float3(gray), color.rgb, p.x);\n"
"  float2 pixelPos = floor(in.uv * r);\n"
"  float noise = hash3(float3(pixelPos, floor(p.z * 60.0)));\n"
"  color.rgb += (noise - 0.5) * p.y;\n"
"  color.rgb *= p.w;\n"
"  color.a = 1.0;\n"
"  return color;\n"
"}\n";

@implementation FZRKawarpView {
    id<MTLDevice> _device;
    id<MTLCommandQueue> _queue;
    id<MTLRenderPipelineState> _tintPipe, _blurPipe, _blendPipe, _warpPipe, _outPipe;
    id<MTLTexture> _source, _blur1, _blur2, _current, _next, _warpTex;
    CADisplayLink *_link;
    CFTimeInterval _lastFrame, _transitionStart;
    double _time;
    CGFloat _currentSpeed;
    BOOL _hasImage, _transitioning;
}

+ (Class)layerClass { return CAMetalLayer.class; }

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    _speed = _currentSpeed = 1.0;
    _warp = 1.0;
    _blurPasses = 8;
    _saturation = 1.5;
    _grain = 0.008;
    _brightness = 1.0;
    self.userInteractionEnabled = NO;
    self.backgroundColor = UIColor.blackColor;
    _available = [self setUpMetal];
    return self;
}

- (id<MTLRenderPipelineState>)pipeline:(id<MTLLibrary>)library fragment:(NSString *)name format:(MTLPixelFormat)format {
    MTLRenderPipelineDescriptor *descriptor = [MTLRenderPipelineDescriptor new];
    descriptor.vertexFunction = [library newFunctionWithName:@"fz_vertex"];
    descriptor.fragmentFunction = [library newFunctionWithName:name];
    descriptor.colorAttachments[0].pixelFormat = format;
    NSError *error = nil;
    id<MTLRenderPipelineState> state = [_device newRenderPipelineStateWithDescriptor:descriptor error:&error];
    if (!state) FZLogError("kawarp: pipeline %@ failed: %@", name, error.localizedDescription);
    return state;
}

- (id<MTLTexture>)textureSide:(NSUInteger)width height:(NSUInteger)height format:(MTLPixelFormat)format {
    MTLTextureDescriptor *descriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:format width:MAX(1, width) height:MAX(1, height) mipmapped:NO];
    descriptor.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
    descriptor.storageMode = MTLStorageModePrivate;
    return [_device newTextureWithDescriptor:descriptor];
}

- (BOOL)setUpMetal {
    _device = MTLCreateSystemDefaultDevice();
    if (!_device) { FZLogError("kawarp: no Metal device"); return NO; }
    NSError *error = nil;
    id<MTLLibrary> library = [_device newLibraryWithSource:kShaders options:nil error:&error];
    if (!library) { FZLogError("kawarp: shaders didn't compile: %@", error.localizedDescription); return NO; }
    _queue = [_device newCommandQueue];
    MTLPixelFormat half = MTLPixelFormatRGBA16Float;   // high precision against banding, as Kawarp's FBOs
    _tintPipe = [self pipeline:library fragment:@"fz_tint" format:half];
    _blurPipe = [self pipeline:library fragment:@"fz_blur" format:half];
    _blendPipe = [self pipeline:library fragment:@"fz_blend" format:half];
    _warpPipe = [self pipeline:library fragment:@"fz_warp" format:half];
    _outPipe = [self pipeline:library fragment:@"fz_output" format:MTLPixelFormatBGRA8Unorm];
    if (!_tintPipe || !_blurPipe || !_blendPipe || !_warpPipe || !_outPipe) return NO;
    _blur1 = [self textureSide:kBlurSize height:kBlurSize format:half];
    _blur2 = [self textureSide:kBlurSize height:kBlurSize format:half];
    _current = [self textureSide:kBlurSize height:kBlurSize format:half];
    _next = [self textureSide:kBlurSize height:kBlurSize format:half];
    CAMetalLayer *layer = (CAMetalLayer *)self.layer;
    layer.device = _device;
    layer.pixelFormat = MTLPixelFormatBGRA8Unorm;
    layer.framebufferOnly = YES;
    layer.opaque = YES;
    // A blurred, moving field needs no more than one pixel per point.
    layer.contentsScale = 1;
    return YES;
}

#pragma mark - passes

- (void)pass:(id<MTLCommandBuffer>)buffer into:(id<MTLTexture>)target pipe:(id<MTLRenderPipelineState>)pipe
       setup:(void (^)(id<MTLRenderCommandEncoder> encoder))setup {
    MTLRenderPassDescriptor *pass = [MTLRenderPassDescriptor renderPassDescriptor];
    pass.colorAttachments[0].texture = target;
    pass.colorAttachments[0].loadAction = MTLLoadActionDontCare;
    pass.colorAttachments[0].storeAction = MTLStoreActionStore;
    id<MTLRenderCommandEncoder> encoder = [buffer renderCommandEncoderWithDescriptor:pass];
    [encoder setRenderPipelineState:pipe];
    setup(encoder);
    [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
    [encoder endEncoding];
}

// blurSourceInto: tint the source into blur1, ping-pong the Kawase passes, copy the result into `target`.
- (void)blurSourceInto:(id<MTLTexture>)target buffer:(id<MTLCommandBuffer>)buffer {
    simd_float4 tint = simd_make_float4(kTint[0], kTint[1], kTint[2], kTintIntensity);
    id<MTLTexture> source = _source;
    [self pass:buffer into:_blur1 pipe:_tintPipe setup:^(id<MTLRenderCommandEncoder> e) {
        [e setFragmentTexture:source atIndex:0];
        [e setFragmentBytes:&tint length:sizeof tint atIndex:0];
    }];
    id<MTLTexture> read = _blur1, write = _blur2;
    for (NSInteger i = 0; i < _blurPasses; i++) {
        simd_float2 params = simd_make_float2((float)i + 0.5f, (float)kBlurSize);
        id<MTLTexture> from = read;
        [self pass:buffer into:write pipe:_blurPipe setup:^(id<MTLRenderCommandEncoder> e) {
            [e setFragmentTexture:from atIndex:0];
            [e setFragmentBytes:&params length:sizeof params atIndex:0];
        }];
        id<MTLTexture> swap = read; read = write; write = swap;
    }
    simd_float2 copy = simd_make_float2(0, (float)kBlurSize);
    id<MTLTexture> result = read;
    [self pass:buffer into:target pipe:_blurPipe setup:^(id<MTLRenderCommandEncoder> e) {
        [e setFragmentTexture:result atIndex:0];
        [e setFragmentBytes:&copy length:sizeof copy atIndex:0];
    }];
}

#pragma mark - image

// The cover drawn at 128 × 128, filling the square (Kawarp samples its source at that size).
- (id<MTLTexture>)textureForImage:(UIImage *)image {
    CGImageRef cg = image.CGImage;
    if (!cg) return nil;
    NSUInteger side = kBlurSize;
    NSMutableData *pixels = [NSMutableData dataWithLength:side * side * 4];
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(pixels.mutableBytes, side, side, 8, side * 4, space,
                                                 kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(space);
    if (!context) return nil;
    CGContextSetInterpolationQuality(context, kCGInterpolationHigh);
    CGFloat w = CGImageGetWidth(cg), h = CGImageGetHeight(cg), scale = MAX(side / w, side / h);
    CGRect rect = CGRectMake((side - w * scale) / 2, (side - h * scale) / 2, w * scale, h * scale);
    CGContextDrawImage(context, rect, cg);
    CGContextRelease(context);
    MTLTextureDescriptor *descriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:side height:side mipmapped:NO];
    descriptor.usage = MTLTextureUsageShaderRead;
    id<MTLTexture> texture = [_device newTextureWithDescriptor:descriptor];
    [texture replaceRegion:MTLRegionMake2D(0, 0, side, side) mipmapLevel:0 withBytes:pixels.bytes bytesPerRow:side * 4];
    return texture;
}

- (void)setImage:(UIImage *)image animated:(BOOL)animated {
    if (!_available || !image) return;
    id<MTLTexture> texture = [self textureForImage:image];
    if (!texture) return;
    _source = texture;
    id<MTLCommandBuffer> buffer = [_queue commandBuffer];
    BOOL fade = _hasImage && animated && kTransition > 0;
    if (fade) {
        // The picture on screen now becomes the one faded from (Kawarp swaps its album FBOs).
        id<MTLTexture> from = _transitioning ? [self snapshotBlend:buffer] : _next;
        if (from != _current) {
            id<MTLBlitCommandEncoder> blit = [buffer blitCommandEncoder];
            [blit copyFromTexture:from toTexture:_current];
            [blit endEncoding];
        }
    }
    [self blurSourceInto:_next buffer:buffer];
    [buffer commit];
    _transitioning = fade;
    _transitionStart = CACurrentMediaTime();
    _hasImage = YES;
    [self updateLink];
    if (!_link) [self renderFrame];
}

// Mid-crossfade, what shows is the blend; it's drawn into blur1 and faded from.
- (id<MTLTexture>)snapshotBlend:(id<MTLCommandBuffer>)buffer {
    float t = [self easedBlend];
    id<MTLTexture> a = _current, b = _next;
    [self pass:buffer into:_blur1 pipe:_blendPipe setup:^(id<MTLRenderCommandEncoder> e) {
        [e setFragmentTexture:a atIndex:0];
        [e setFragmentTexture:b atIndex:1];
        [e setFragmentBytes:&t length:sizeof t atIndex:0];
    }];
    return _blur1;
}

- (float)easedBlend {
    double factor = MIN(1.0, MAX(0, CACurrentMediaTime() - _transitionStart) / kTransition);
    return (float)(0.5 - 0.5 * cos(factor * M_PI));
}

- (void)setBlurPasses:(NSInteger)blurPasses {
    blurPasses = MIN(40, MAX(0, blurPasses));
    if (blurPasses == _blurPasses) return;
    _blurPasses = blurPasses;
    if (!_hasImage || !_source) return;
    id<MTLCommandBuffer> buffer = [_queue commandBuffer];
    [self blurSourceInto:_next buffer:buffer];   // reblurCurrentImage
    [buffer commit];
    if (!_link) [self renderFrame];
}

- (void)setSpeed:(CGFloat)speed { _speed = MIN(16, MAX(0, speed)); }
- (void)setWarp:(CGFloat)warp { _warp = MIN(1, MAX(0, warp)); if (!_link) [self renderFrame]; }
- (void)setSaturation:(CGFloat)saturation { _saturation = MIN(3, MAX(0, saturation)); if (!_link) [self renderFrame]; }
- (void)setGrain:(CGFloat)grain { _grain = MIN(0.1, MAX(0, grain)); if (!_link) [self renderFrame]; }
- (void)setBrightness:(CGFloat)brightness { _brightness = MIN(2, MAX(0, brightness)); if (!_link) [self renderFrame]; }
- (void)setPaused:(BOOL)paused { _paused = paused; [self updateLink]; }

#pragma mark - frames

- (void)layoutSubviews {
    [super layoutSubviews];
    CAMetalLayer *layer = (CAMetalLayer *)self.layer;
    CGSize size = CGSizeMake(MAX(1, round(self.bounds.size.width * layer.contentsScale)), MAX(1, round(self.bounds.size.height * layer.contentsScale)));
    if (!CGSizeEqualToSize(layer.drawableSize, size)) {
        layer.drawableSize = size;
        _warpTex = nil;
    }
    if (!_link) [self renderFrame];
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    [self updateLink];
}

- (void)setHidden:(BOOL)hidden {
    [super setHidden:hidden];
    [self updateLink];
}

- (void)updateLink {
    BOOL run = _available && _hasImage && self.window && !self.hidden && (!_paused || _transitioning);
    if (run && !_link) {
        _link = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)];
        _link.preferredFramesPerSecond = 30;
        [_link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
        _lastFrame = 0;
    } else if (!run && _link) {
        [_link invalidate];
        _link = nil;
    }
}

- (void)tick:(CADisplayLink *)link {
    CFTimeInterval now = link.timestamp;
    double dt = _lastFrame > 0 ? MIN(0.1, now - _lastFrame) : 0;
    _lastFrame = now;
    // Kawarp eases its speed 5 % a frame at 60 fps; the same ease per second at 30 fps.
    _currentSpeed += (_speed - _currentSpeed) * 0.0975;
    if (!_paused) _time += dt * _currentSpeed;
    [self renderFrame];
    if (_paused && !_transitioning) [self updateLink];
}

- (void)renderFrame {
    if (!_available || !_hasImage || !self.window) return;
    CAMetalLayer *layer = (CAMetalLayer *)self.layer;
    CGSize size = layer.drawableSize;
    if (size.width < 2 || size.height < 2) return;
    if (!_warpTex || _warpTex.width != (NSUInteger)size.width || _warpTex.height != (NSUInteger)size.height) {
        _warpTex = [self textureSide:(NSUInteger)size.width height:(NSUInteger)size.height format:MTLPixelFormatRGBA16Float];
    }
    id<CAMetalDrawable> drawable = [layer nextDrawable];
    if (!drawable) return;
    id<MTLCommandBuffer> buffer = [_queue commandBuffer];

    id<MTLTexture> albumTexture = _next;
    if (_transitioning) {
        if (CACurrentMediaTime() - _transitionStart >= kTransition) _transitioning = NO;
        else albumTexture = [self snapshotBlend:buffer];
    }
    simd_float2 warp = simd_make_float2((float)_time, (float)_warp);
    [self pass:buffer into:_warpTex pipe:_warpPipe setup:^(id<MTLRenderCommandEncoder> e) {
        [e setFragmentTexture:albumTexture atIndex:0];
        [e setFragmentBytes:&warp length:sizeof warp atIndex:0];
    }];
    simd_float4 output = simd_make_float4((float)_saturation, (float)_grain, (float)_time, (float)_brightness);
    simd_float2 resolution = simd_make_float2((float)size.width, (float)size.height);
    id<MTLTexture> warped = _warpTex;
    [self pass:buffer into:drawable.texture pipe:_outPipe setup:^(id<MTLRenderCommandEncoder> e) {
        [e setFragmentTexture:warped atIndex:0];
        [e setFragmentBytes:&output length:sizeof output atIndex:0];
        [e setFragmentBytes:&resolution length:sizeof resolution atIndex:1];
    }];
    [buffer presentDrawable:drawable];
    [buffer commit];
}

- (void)dealloc {
    [_link invalidate];
}
@end

#pragma mark - chroma.pw's Fluid artwork settings

NSString *const FZRKeyFluidSpeed = @"fz.redesign.player.fluid.speed";
NSString *const FZRKeyFluidWarp = @"fz.redesign.player.fluid.warp";
NSString *const FZRKeyFluidGrain = @"fz.redesign.player.fluid.grain";
NSString *const FZRKeyFluidBlur = @"fz.redesign.player.fluid.blur";
NSString *const FZRKeyFluidSaturation = @"fz.redesign.player.fluid.saturation";
NSString *const FZRKeyFluidBrightness = @"fz.redesign.player.fluid.brightness";
NSNotificationName const FZRFluidLookDidChangeNotification = @"fz.redesign.player.fluidLookDidChange";

// Stored in percent of Kawarp's defaults so 100 is Kawarp as it ships.
static double percent(NSString *key) { return (double)FZInt(key, 100); }
static void setPercent(NSString *key, double value) {
    FZSetInt(key, (NSInteger)llround(value));
    [NSNotificationCenter.defaultCenter postNotificationName:FZRFluidLookDidChangeNotification object:nil];
}

void FZRApplyFluidLook(FZRKawarpView *view) {
    view.speed = percent(FZRKeyFluidSpeed) / 100.0;
    view.warp = MIN(1, percent(FZRKeyFluidWarp) / 100.0);
    view.grain = 0.008 * percent(FZRKeyFluidGrain) / 100.0;
    view.blurPasses = (NSInteger)llround(8 * percent(FZRKeyFluidBlur) / 100.0);
    view.saturation = 1.5 * percent(FZRKeyFluidSaturation) / 100.0;
    view.brightness = percent(FZRKeyFluidBrightness) / 100.0;
    view.paused = FZRReduceMotion();
}

// The presets chroma.pw names (default, soft, calm, slow, vivid, bright, fast), as percents of speed, warp, grain,
// blur, saturation and brightness. chroma.pw's own numbers aren't in its strings; these are Frozio's readings of
// the names around Kawarp's defaults.
static NSArray<NSArray *> *presets(void) {
    return @[
        @[@"Default", @[@100, @100, @100, @100, @100, @100]],
        @[@"Soft",    @[@100, @60, @50, @150, @85, @100]],
        @[@"Calm",    @[@50, @70, @100, @125, @90, @95]],
        @[@"Slow",    @[@35, @100, @100, @100, @100, @100]],
        @[@"Vivid",   @[@100, @100, @100, @100, @135, @105]],
        @[@"Bright",  @[@100, @100, @100, @100, @110, @125]],
        @[@"Fast",    @[@200, @100, @100, @100, @100, @100]],
    ];
}

UIViewController *FZRFluidOptionsPage(void) {
    NSArray *keys = @[FZRKeyFluidSpeed, FZRKeyFluidWarp, FZRKeyFluidGrain, FZRKeyFluidBlur, FZRKeyFluidSaturation, FZRKeyFluidBrightness];
    NSMutableArray *names = [NSMutableArray array];
    for (NSArray *preset in presets()) [names addObject:preset[0]];
    __block FZModPage *page = nil;
    FZModRow *preset = FZMenuRow(@"Preset", names, ^NSString *{
        for (NSArray *p in presets()) {
            BOOL match = YES;
            for (NSUInteger i = 0; i < keys.count; i++) match = match && percent(keys[i]) == [p[1][i] doubleValue];
            if (match) return p[0];
        }
        return @"Custom";
    }, ^(NSInteger index) {
        NSArray *values = presets()[(NSUInteger)index][1];
        for (NSUInteger i = 0; i < keys.count; i++) FZSetInt(keys[i], [values[i] integerValue]);
        [NSNotificationCenter.defaultCenter postNotificationName:FZRFluidLookDidChangeNotification object:nil];
        [page refreshVisibility];
    });
    NSString *(^format)(double) = ^NSString *(double value) { return [NSString stringWithFormat:@"%.0f%%", value]; };
    NSArray *titles = @[@"Speed", @"Warp", @"Grain", @"Blur", @"Saturation", @"Brightness"];
    NSArray *ranges = @[@[@0, @400], @[@0, @100], @[@0, @400], @[@0, @300], @[@0, @200], @[@50, @150]];
    NSMutableArray *rows = [NSMutableArray array];
    for (NSUInteger i = 0; i < keys.count; i++) {
        NSString *key = keys[i];
        [rows addObject:FZSliderRow(titles[i], nil, [ranges[i][0] doubleValue], [ranges[i][1] doubleValue], 5,
                                    ^double { return percent(key); }, ^(double value) { setPercent(key, value); }, format)];
    }
    page = [[FZModPage alloc] initWithTitle:@"Fluid artwork" intro:nil sections:@[
        FZSection(@"Look", @[preset]),
        FZNotedSection(@"Adjust", rows, @"Brightness past 100% can make white text harder to read on a light cover. Kawarp by Better Lyrics (MIT)."),
    ] footer:nil];
    return page;
}
