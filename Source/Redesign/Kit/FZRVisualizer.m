// See FZRVisualizer.h.
#import <Metal/Metal.h>
#import <QuartzCore/QuartzCore.h>
#import <simd/simd.h>
#import "Redesign/Kit/FZRVisualizer.h"
#import "Redesign/Kit/FZRPalette.h"
#import "Redesign/Player/FZRAudioLevels.h"
#import "Core/FZLog.h"

NSString *const FZRKeyVisualizerStyle = @"fz.redesign.visualizer.style";
static const NSTimeInterval kShuffleEvery = 20, kShuffleFade = 1.2;
static const NSUInteger kCoverSide = 512;

NSArray<NSString *> *FZRVisualizerStyleNames(void) {
    return @[@"Bars", @"Nebula", @"Halo", @"Poster", @"Cut", @"Shuffle Shaders"];
}

typedef struct {
    simd_float4 c0, c1, c2;
    simd_float4 bands[FZR_BANDS / 4];
    simd_float2 size; float time, bass;
    float mid, treble, level, beat;
    float blend, intensity, hasCover, pad;
    int mode, mode2, pad2, pad3;
} VisUniforms;

static NSString *const kShaders = @
"#include <metal_stdlib>\n"
"using namespace metal;\n"
"struct VOut { float4 position [[position]]; float2 uv; };\n"
"struct U { float4 c0, c1, c2; float4 bands[8]; float2 size; float time, bass; float mid, treble, level, beat;\n"
"           float blend, intensity, hasCover, pad; int mode, mode2, pad2, pad3; };\n"
"vertex VOut vis_vertex(uint vid [[vertex_id]]) {\n"
"  float2 pos[3] = { float2(-1.0, -1.0), float2(3.0, -1.0), float2(-1.0, 3.0) };\n"
"  VOut o; o.position = float4(pos[vid], 0.0, 1.0);\n"
"  o.uv = float2((pos[vid].x + 1.0) * 0.5, 1.0 - (pos[vid].y + 1.0) * 0.5);\n"
"  return o;\n"
"}\n"
"constexpr sampler lin(filter::linear, address::clamp_to_edge);\n"
"float hash(float2 p) { return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453); }\n"
"float noise(float2 p) { float2 i = floor(p), f = fract(p); float2 u = f * f * (3.0 - 2.0 * f);\n"
"  return mix(mix(hash(i), hash(i + float2(1, 0)), u.x), mix(hash(i + float2(0, 1)), hash(i + float2(1, 1)), u.x), u.y); }\n"
"float fbm(float2 p) { float v = 0.0, a = 0.5; for (int i = 0; i < 5; i++) { v += a * noise(p); p = p * 2.02 + float2(1.7, 9.2); a *= 0.5; } return v; }\n"
"float band(constant U &u, float x) {\n"
"  float f = clamp(x, 0.0, 1.0) * 31.0; int i = int(f); int j = min(i + 1, 31);\n"
"  float a = u.bands[i / 4][i % 4], b = u.bands[j / 4][j % 4];\n"
"  return mix(a, b, fract(f)) * u.intensity;\n"
"}\n"
"float3 bars(constant U &u, float2 uv) {\n"
"  float n = 28.0; float id = floor(uv.x * n); float fx = fract(uv.x * n);\n"
"  float v = band(u, id / (n - 1.0)); float h = 0.03 + 0.42 * v; float dy = abs(uv.y - 0.5);\n"
"  float body = smoothstep(h + 0.006, h - 0.006, dy) * smoothstep(0.1, 0.2, fx) * smoothstep(0.9, 0.8, fx);\n"
"  float3 col = mix(u.c0.rgb, u.c1.rgb, clamp(dy / 0.45, 0.0, 1.0));\n"
"  float glow = exp(-max(dy - h, 0.0) * 14.0) * 0.35 * v * smoothstep(0.0, 0.3, fx) * smoothstep(1.0, 0.7, fx);\n"
"  float3 bg = u.c2.rgb * 0.22 + u.c0.rgb * 0.10 * u.beat;\n"
"  return bg + col * body + col * glow * (1.0 - body);\n"
"}\n"
"float3 nebula(constant U &u, float2 uv) {\n"
"  float2 p = (uv - 0.5) * float2(u.size.x / u.size.y, 1.0) * 2.2; float t = u.time * 0.12;\n"
"  float2 q = float2(fbm(p + t), fbm(p + float2(5.2, 1.3) - t));\n"
"  float2 r = float2(fbm(p + 3.0 * q + float2(1.7, 9.2) + 0.3 * t + u.bass * 0.8 * u.intensity), fbm(p + 3.0 * q + float2(8.3, 2.8) - 0.2 * t));\n"
"  float f = fbm(p + 3.0 * r);\n"
"  float3 col = mix(u.c2.rgb * 0.35, u.c0.rgb, clamp(f * f * 2.2, 0.0, 1.0));\n"
"  col = mix(col, u.c1.rgb, clamp(length(q) * 0.6, 0.0, 1.0) * 0.7);\n"
"  return col * (0.6 + 0.8 * (u.level * 0.7 + u.beat * 0.5) * u.intensity);\n"
"}\n"
"float3 halo(constant U &u, float2 uv, texture2d<float> cover) {\n"
"  float2 p = (uv - 0.5) * float2(u.size.x / u.size.y, 1.0); float r = length(p);\n"
"  float x = abs(atan2(p.x, -p.y)) / M_PI_F; float v = band(u, x);\n"
"  float R = 0.26 + (0.04 * u.bass + 0.03 * u.beat) * u.intensity; float ring = R + 0.08 * v;\n"
"  float d = abs(r - ring); float line = smoothstep(0.012, 0.0, d); float glow = exp(-d * 28.0) * (0.35 + v);\n"
"  float3 col = mix(u.c0.rgb, u.c1.rgb, x);\n"
"  float3 res = u.c2.rgb * 0.18 + col * (line + glow * 0.6);\n"
"  float inner = R - 0.025;\n"
"  if (u.hasCover > 0.5 && r < inner) {\n"
"    float3 c = cover.sample(lin, p / (2.0 * inner) + 0.5).rgb;\n"
"    res = mix(res, c, smoothstep(inner, inner - 0.006, r));\n"
"  }\n"
"  return res;\n"
"}\n"
"float3 poster(constant U &u, float2 uv, texture2d<float> cover) {\n"
"  if (u.hasCover < 0.5) return nebula(u, uv);\n"
"  float z = 1.0 - (0.05 * u.beat + 0.03 * u.bass) * u.intensity; float2 cuv = (uv - 0.5) * z + 0.5;\n"
"  float sh = (0.003 + 0.014 * u.treble) * u.intensity;\n"
"  float3 c = float3(cover.sample(lin, cuv + float2(sh, 0.0)).r, cover.sample(lin, cuv).g, cover.sample(lin, cuv - float2(sh, 0.0)).b);\n"
"  float l = dot(c, float3(0.299, 0.587, 0.114)); float q = floor(l * 4.0) / 3.0;\n"
"  float3 duo = q < 0.34 ? u.c2.rgb * 0.5 : (q < 0.67 ? u.c0.rgb : (q < 0.99 ? u.c1.rgb : float3(0.95)));\n"
"  return mix(duo, c, 0.2) * (0.85 + 0.3 * u.beat * u.intensity);\n"
"}\n"
"float3 cut(constant U &u, float2 uv, texture2d<float> cover) {\n"
"  if (u.hasCover < 0.5) return bars(u, uv);\n"
"  float n = 14.0; float id = floor(uv.y * n); float v = band(u, id / (n - 1.0));\n"
"  float off = (v - 0.25) * 0.14 * sin(u.time * 1.3 + id * 1.7);\n"
"  float2 cuv = float2(uv.x + off, uv.y);\n"
"  float gap = smoothstep(0.0, 0.05, fract(uv.y * n)) * smoothstep(1.0, 0.95, fract(uv.y * n));\n"
"  float3 c = (cuv.x < 0.0 || cuv.x > 1.0) ? u.c2.rgb * 0.2 : cover.sample(lin, cuv).rgb;\n"
"  return mix(u.c2.rgb * 0.12, c * (0.9 + 0.25 * v), gap);\n"
"}\n"
"float3 shade(constant U &u, int mode, float2 uv, texture2d<float> cover) {\n"
"  if (mode == 1) return nebula(u, uv);\n"
"  if (mode == 2) return halo(u, uv, cover);\n"
"  if (mode == 3) return poster(u, uv, cover);\n"
"  if (mode == 4) return cut(u, uv, cover);\n"
"  return bars(u, uv);\n"
"}\n"
"fragment float4 vis_fragment(VOut in [[stage_in]], constant U &u [[buffer(0)]], texture2d<float> cover [[texture(0)]]) {\n"
"  float3 a = shade(u, u.mode, in.uv, cover);\n"
"  if (u.blend > 0.001) a = mix(a, shade(u, u.mode2, in.uv, cover), u.blend);\n"
"  return float4(a, 1.0);\n"
"}\n";

@implementation FZRVisualizerView {
    id<MTLDevice> _device;
    id<MTLCommandQueue> _queue;
    id<MTLRenderPipelineState> _pipe;
    id<MTLTexture> _cover, _blank;
    CADisplayLink *_link;
    simd_float4 _colors[3];
    double _time, _lastFrame, _styleStart;
    NSInteger _shown, _previous;
    BOOL _hasCover;
}

+ (Class)layerClass { return CAMetalLayer.class; }

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    _intensity = 1;
    _style = FZRVisualizerShuffle;
    _shown = FZRVisualizerBars;
    _previous = -1;
    _colors[0] = simd_make_float4(0.95, 0.35, 0.45, 1);
    _colors[1] = simd_make_float4(0.35, 0.55, 0.95, 1);
    _colors[2] = simd_make_float4(0.15, 0.10, 0.20, 1);
    self.userInteractionEnabled = NO;
    self.backgroundColor = UIColor.blackColor;
    _available = [self setUpMetal];
    return self;
}

- (BOOL)setUpMetal {
    _device = MTLCreateSystemDefaultDevice();
    if (!_device) return NO;
    NSError *error = nil;
    id<MTLLibrary> library = [_device newLibraryWithSource:kShaders options:nil error:&error];
    if (!library) { FZLogError("visualizer: shaders didn't compile: %@", error.localizedDescription); return NO; }
    MTLRenderPipelineDescriptor *descriptor = [MTLRenderPipelineDescriptor new];
    descriptor.vertexFunction = [library newFunctionWithName:@"vis_vertex"];
    descriptor.fragmentFunction = [library newFunctionWithName:@"vis_fragment"];
    descriptor.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
    _pipe = [_device newRenderPipelineStateWithDescriptor:descriptor error:&error];
    if (!_pipe) { FZLogError("visualizer: pipeline failed: %@", error.localizedDescription); return NO; }
    _queue = [_device newCommandQueue];
    MTLTextureDescriptor *one = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:1 height:1 mipmapped:NO];
    _blank = [_device newTextureWithDescriptor:one];
    uint32_t black = 0xff000000;
    [_blank replaceRegion:MTLRegionMake2D(0, 0, 1, 1) mipmapLevel:0 withBytes:&black bytesPerRow:4];
    CAMetalLayer *layer = (CAMetalLayer *)self.layer;
    layer.device = _device;
    layer.pixelFormat = MTLPixelFormatBGRA8Unorm;
    layer.framebufferOnly = YES;
    layer.opaque = YES;
    return YES;
}

static simd_float4 rgba(UIColor *color) {
    CGFloat r = 0, g = 0, b = 0, a = 1;
    if (![color getRed:&r green:&g blue:&b alpha:&a]) { CGFloat w = 0; [color getWhite:&w alpha:&a]; r = g = b = w; }
    return simd_make_float4((float)r, (float)g, (float)b, 1);
}

// Brighter and more colourful than the field's colours: the visuals light up rather than sit in the dark.
static simd_float4 lifted(UIColor *color, CGFloat minBrightness) {
    CGFloat h = 0, s = 0, v = 0, a = 1;
    if ([color getHue:&h saturation:&s brightness:&v alpha:&a]) {
        color = [UIColor colorWithHue:h saturation:MIN(1, s * 1.2 + 0.1) brightness:MAX(minBrightness, v) alpha:1];
    }
    return rgba(color);
}

- (void)setImage:(UIImage *)image {
    CGImageRef cg = image.CGImage;
    if (!cg || !_available) return;
    NSMutableData *pixels = [NSMutableData dataWithLength:kCoverSide * kCoverSide * 4];
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(pixels.mutableBytes, kCoverSide, kCoverSide, 8, kCoverSide * 4, space,
                                                 kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(space);
    if (!context) return;
    CGContextSetInterpolationQuality(context, kCGInterpolationHigh);
    CGFloat w = CGImageGetWidth(cg), h = CGImageGetHeight(cg), scale = MAX(kCoverSide / w, kCoverSide / h);
    CGContextDrawImage(context, CGRectMake((kCoverSide - w * scale) / 2, (kCoverSide - h * scale) / 2, w * scale, h * scale), cg);
    CGContextRelease(context);
    MTLTextureDescriptor *descriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:kCoverSide height:kCoverSide mipmapped:NO];
    _cover = [_device newTextureWithDescriptor:descriptor];
    [_cover replaceRegion:MTLRegionMake2D(0, 0, kCoverSide, kCoverSide) mipmapLevel:0 withBytes:pixels.bytes bytesPerRow:kCoverSide * 4];
    _hasCover = YES;
    FZRPaletteRequest request = {0};
    request.flow = YES;
    __weak typeof(self) weakSelf = self;
    [FZRPalette paletteForImage:image request:request completion:^(FZRPalette *palette) {
        typeof(self) view = weakSelf;
        NSArray<UIColor *> *flows = palette.flowColors;
        if (!view || !flows.count) return;
        view->_colors[0] = lifted(flows[0], 0.85);
        view->_colors[1] = lifted(flows[MIN(2, flows.count - 1)], 0.75);
        view->_colors[2] = rgba(palette.fieldColor ?: flows.lastObject);
    }];
    [self updateLink];
}

- (void)setStyle:(FZRVisualizerStyle)style {
    if (_style == style) return;
    _style = style;
    _previous = -1;
    _shown = style == FZRVisualizerShuffle ? _shown : style;
    _styleStart = _time;
}

- (void)setPaused:(BOOL)paused { _paused = paused; [self updateLink]; }
- (void)didMoveToWindow { [super didMoveToWindow]; [self updateLink]; }
- (void)setHidden:(BOOL)hidden { [super setHidden:hidden]; [self updateLink]; }

- (void)layoutSubviews {
    [super layoutSubviews];
    CAMetalLayer *layer = (CAMetalLayer *)self.layer;
    CGFloat scale = MIN(2, self.window.screen.scale ?: UIScreen.mainScreen.scale);
    layer.contentsScale = scale;
    layer.drawableSize = CGSizeMake(MAX(1, self.bounds.size.width * scale), MAX(1, self.bounds.size.height * scale));
}

- (void)updateLink {
    BOOL run = _available && self.window && !self.hidden && !_paused;
    if (run && !_link) {
        _link = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)];
        _link.preferredFramesPerSecond = 60;
        [_link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
        _lastFrame = 0;
    } else if (!run && _link) {
        [_link invalidate];
        _link = nil;
    }
}

- (void)tick:(CADisplayLink *)link {
    double dt = _lastFrame > 0 ? MIN(0.1, link.timestamp - _lastFrame) : 0;
    _lastFrame = link.timestamp;
    _time += dt;
    if (_style == FZRVisualizerShuffle && _time - _styleStart > kShuffleEvery) {
        _previous = _shown;
        _shown = (_shown + 1 + arc4random_uniform(4)) % 5;
        _styleStart = _time;
    }
    [self render];
}

- (void)render {
    CAMetalLayer *layer = (CAMetalLayer *)self.layer;
    if (layer.drawableSize.width < 2) return;
    id<CAMetalDrawable> drawable = [layer nextDrawable];
    if (!drawable) return;
    FZRAudioFrame frame = FZRAudioLevelsNow();
    VisUniforms u = {0};
    u.c0 = _colors[0]; u.c1 = _colors[1]; u.c2 = _colors[2];
    for (int i = 0; i < FZR_BANDS / 4; i++) {
        u.bands[i] = simd_make_float4(frame.bands[i * 4], frame.bands[i * 4 + 1], frame.bands[i * 4 + 2], frame.bands[i * 4 + 3]);
    }
    u.size = simd_make_float2((float)layer.drawableSize.width, (float)layer.drawableSize.height);
    u.time = (float)_time;
    u.bass = frame.bass; u.mid = frame.mid; u.treble = frame.treble; u.level = frame.level; u.beat = frame.beat;
    u.intensity = (float)_intensity;
    u.hasCover = _hasCover ? 1 : 0;
    // A shuffle's change crossfades from the shader before.
    double since = _time - _styleStart;
    if (_previous >= 0 && since < kShuffleFade) {
        u.mode = (int)_previous; u.mode2 = (int)_shown; u.blend = (float)(since / kShuffleFade);
    } else {
        u.mode = (int)_shown; u.mode2 = (int)_shown; u.blend = 0;
    }
    MTLRenderPassDescriptor *pass = [MTLRenderPassDescriptor renderPassDescriptor];
    pass.colorAttachments[0].texture = drawable.texture;
    pass.colorAttachments[0].loadAction = MTLLoadActionDontCare;
    pass.colorAttachments[0].storeAction = MTLStoreActionStore;
    id<MTLCommandBuffer> buffer = [_queue commandBuffer];
    id<MTLRenderCommandEncoder> encoder = [buffer renderCommandEncoderWithDescriptor:pass];
    [encoder setRenderPipelineState:_pipe];
    [encoder setFragmentBytes:&u length:sizeof u atIndex:0];
    [encoder setFragmentTexture:_cover ?: _blank atIndex:0];
    [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
    [encoder endEncoding];
    [buffer presentDrawable:drawable];
    [buffer commit];
}

- (void)dealloc { [_link invalidate]; }
@end
