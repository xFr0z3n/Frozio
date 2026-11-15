// See FZRVisualizer.h.
#import <Metal/Metal.h>
#import <QuartzCore/QuartzCore.h>
#import <simd/simd.h>
#import <CoreMotion/CoreMotion.h>
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
    float blend, intensity, hasCover, dim;
    int mode, mode2, pad2, pad3;
    simd_float4 coverRect;   // the cover's centre and half size, in 0…1 of the view
    simd_float2 tilt; float phase, pad4;
} VisUniforms;

static NSString *const kShaders = @
"#include <metal_stdlib>\n"
"using namespace metal;\n"
"struct VOut { float4 position [[position]]; float2 uv; };\n"
"struct U { float4 c0, c1, c2; float4 bands[8]; float2 size; float time, bass; float mid, treble, level, beat;\n"
"           float blend, intensity, hasCover, dim; int mode, mode2, pad2, pad3; float4 coverRect; float2 tilt; float phase, pad4; };\n"
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
"float aspect(constant U &u) { return u.size.x / max(u.size.y, 1.0); }\n"
"float2 fillUV(constant U &u, float2 uv) { float a = aspect(u); return a < 1.0 ? float2((uv.x - 0.5) * a + 0.5, uv.y) : float2(uv.x, (uv.y - 0.5) / a + 0.5); }\n"
"float sdBox(float2 p, float2 b, float r) { float2 q = abs(p) - b + r; return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r; }\n"
// Bars: an LED wall, its columns lit from the middle by their part of the spectrum.
"float3 bars(constant U &u, float2 uv) {\n"
"  float a = aspect(u); float cols = 22.0; float cell = 1.0 / cols;\n"
"  float2 p = float2(uv.x, uv.y / a) + u.tilt * 0.01; float2 id = floor(p / cell); float2 f = fract(p / cell) - 0.5;\n"
"  float rows = floor(1.0 / a / cell); float mid = rows * 0.5;\n"
"  float v = band(u, abs(id.x / (cols - 1.0) * 2.0 - 1.0));\n"
"  float reach = abs(id.y + 0.5 - mid) / mid;\n"
"  float lit = step(reach, 0.12 + v * 0.95);\n"
"  float led = smoothstep(0.36, 0.30, length(f));\n"
"  float3 on = mix(u.c0.rgb, u.c1.rgb, reach) * (0.75 + 0.5 * u.beat);\n"
"  float3 off = u.c2.rgb * 0.35 + 0.05;\n"
"  return u.c2.rgb * 0.12 + led * mix(off, on, lit);\n"
"}\n"
// Nebula: smoke that thickens with the bass.
"float3 nebula(constant U &u, float2 uv) {\n"
"  float2 p = (uv - 0.5) * float2(aspect(u), 1.0) * 2.2 + u.tilt * 0.15; float t = u.time * 0.12;\n"
"  float2 q = float2(fbm(p + t), fbm(p + float2(5.2, 1.3) - t));\n"
"  float2 r = float2(fbm(p + 3.0 * q + float2(1.7, 9.2) + 0.3 * t + u.bass * 0.8 * u.intensity), fbm(p + 3.0 * q + float2(8.3, 2.8) - 0.2 * t));\n"
"  float f = fbm(p + 3.0 * r);\n"
"  float3 col = mix(u.c2.rgb * 0.35, u.c0.rgb, clamp(f * f * (1.6 + 1.4 * u.bass * u.intensity), 0.0, 1.0));\n"
"  col = mix(col, u.c1.rgb, clamp(length(q) * 0.6, 0.0, 1.0) * 0.7);\n"
"  return col * (0.6 + 0.8 * (u.level * 0.7 + u.beat * 0.5) * u.intensity);\n"
"}\n"
// Halo: rings stepping out from the cover, quicker with the music.
"float3 halo(constant U &u, float2 uv, texture2d<float> cover) {\n"
"  float a = aspect(u); float2 p = (uv - u.coverRect.xy) * float2(a, 1.0) + u.tilt * 0.01; float2 hs = u.coverRect.zw * float2(a, 1.0);\n"
"  float d = sdBox(p, hs, 0.03);\n"
"  float3 res = u.c2.rgb * 0.22;\n"
"  for (int k = 0; k < 4; k++) {\n"
"    float rr = fract(u.phase + float(k) * 0.25); float radius = 0.01 + rr * 0.55;\n"
"    float line = exp(-abs(d - radius) * 70.0) * (1.0 - rr) * (0.55 + u.beat * u.intensity);\n"
"    res += mix(u.c0.rgb, u.c1.rgb, rr) * line;\n"
"  }\n"
"  return res + u.c0.rgb * exp(-max(d, 0.0) * 9.0) * (0.15 + 0.4 * u.level * u.intensity);\n"
"}\n"
// Poster: the cover across the screen in a few of its own colours.
"float3 poster(constant U &u, float2 uv, texture2d<float> cover) {\n"
"  if (u.hasCover < 0.5) return nebula(u, uv);\n"
"  float z = 1.0 - (0.05 * u.beat + 0.03 * u.bass) * u.intensity; float2 cuv = (fillUV(u, uv) - 0.5) * z + 0.5 + u.tilt * 0.01;\n"
"  float sh = (0.003 + 0.014 * u.treble) * u.intensity;\n"
"  float3 c = float3(cover.sample(lin, cuv + float2(sh, 0.0)).r, cover.sample(lin, cuv).g, cover.sample(lin, cuv - float2(sh, 0.0)).b);\n"
"  float l = dot(c, float3(0.299, 0.587, 0.114)); float q = floor(l * 4.0) / 3.0;\n"
"  float3 duo = q < 0.34 ? u.c2.rgb * 0.5 : (q < 0.67 ? u.c0.rgb : (q < 0.99 ? u.c1.rgb : float3(0.95)));\n"
"  return mix(duo, c, 0.2) * (0.85 + 0.3 * u.beat * u.intensity);\n"
"}\n"
// Cut: the cover across the screen in strips sliding with the spectrum.
"float3 cut(constant U &u, float2 uv, texture2d<float> cover) {\n"
"  if (u.hasCover < 0.5) return bars(u, uv);\n"
"  float n = 22.0; float id = floor(uv.y * n); float v = band(u, id / (n - 1.0));\n"
"  float off = (v - 0.25) * 0.14 * sin(u.time * 1.3 + id * 1.7);\n"
"  float2 cuv = fillUV(u, float2(uv.x + off, uv.y));\n"
"  float gap = smoothstep(0.0, 0.05, fract(uv.y * n)) * smoothstep(1.0, 0.95, fract(uv.y * n));\n"
"  float3 c = (cuv.x < 0.0 || cuv.x > 1.0) ? u.c2.rgb * 0.2 : cover.sample(lin, cuv).rgb;\n"
"  return mix(u.c2.rgb * 0.12, c * (0.9 + 0.25 * v), gap);\n"
"}\n"
// The lyrics styles' backgrounds.
"float3 night(constant U &u, float2 uv) {\n"
"  float3 base = mix(float3(0.02, 0.05, 0.13), float3(0.01, 0.02, 0.06), uv.y);\n"
"  float2 p = uv * float2(aspect(u), 1.0) * 1.6; float t = u.time * 0.05;\n"
"  float glowA = fbm(p + float2(t, -t)), glowB = fbm(p * 1.3 + float2(-t, t) + 4.0);\n"
"  base += float3(0.0, 0.55, 0.65) * pow(glowA, 3.0) * (0.35 + 0.5 * u.level) + float3(0.7, 0.1, 0.6) * pow(glowB, 3.0) * (0.25 + 0.5 * u.beat);\n"
"  return base;\n"
"}\n"
"float3 inferno(constant U &u, float2 uv) {\n"
"  float2 p = uv * float2(aspect(u), 1.0);\n"
"  float n = fbm(float2(p.x * 3.0, p.y * 2.2 + u.time * 1.4)) + 0.5 * fbm(float2(p.x * 7.0, p.y * 5.0 + u.time * 2.6));\n"
"  float heat = clamp((uv.y - 0.45) * 1.9 + n * 0.75 - 0.55 + u.bass * 0.35 * u.intensity, 0.0, 1.0);\n"
"  float3 col = mix(float3(0.05, 0.01, 0.0), float3(0.75, 0.12, 0.02), smoothstep(0.0, 0.5, heat));\n"
"  col = mix(col, float3(1.0, 0.55, 0.08), smoothstep(0.45, 0.85, heat));\n"
"  col = mix(col, float3(1.0, 0.8, 0.4), smoothstep(0.9, 1.0, heat) * 0.6);\n"
"  // Darker again under the controls, so they stay readable.\n"
"  return col * (0.8 - 0.45 * smoothstep(0.72, 1.0, uv.y));\n"
"}\n"
"float3 hologram(constant U &u, float2 uv) {\n"
"  float3 col = mix(float3(0.05, 0.18, 0.28), float3(0.02, 0.07, 0.12), uv.y);\n"
"  float2 base = float2(0.5, 0.97); float h = base.y - uv.y; float w = abs(uv.x - base.x);\n"
"  float cone = h > 0.0 ? smoothstep(h * 0.42, h * 0.42 - 0.08, w) * smoothstep(0.0, 0.5, 1.0 - h) : 0.0;\n"
"  col += float3(0.2, 0.75, 0.95) * cone * (0.35 + 0.35 * u.level * u.intensity);\n"
"  float2 e = (uv - base) * float2(aspect(u), 1.0) * float2(1.0, 3.2); float ring = exp(-abs(length(e) - 0.12 - 0.02 * u.beat) * 60.0);\n"
"  col += float3(0.3, 0.9, 1.0) * ring;\n"
"  col *= 0.9 + 0.1 * sin(uv.y * u.size.y * 0.5 + u.time * 6.0);\n"
"  return col;\n"
"}\n"
"float3 chrome(constant U &u, float2 uv) {\n"
"  float horizon = 0.76;\n"
"  float3 col = mix(float3(0.08, 0.02, 0.18), float3(0.55, 0.08, 0.45), smoothstep(0.1, horizon, uv.y));\n"
"  float2 sp = (uv - float2(0.5, horizon - 0.04)) * float2(aspect(u), 1.0); float sun = length(sp);\n"
"  float stripes = uv.y > horizon - 0.12 ? step(0.35, fract((uv.y - horizon) * 60.0)) : 1.0;\n"
"  float disc = smoothstep(0.2, 0.195, sun) * stripes * step(uv.y, horizon);\n"
"  col = mix(col, mix(float3(1.0, 0.85, 0.3), float3(1.0, 0.3, 0.45), smoothstep(-0.2, 0.05, sp.y)), disc);\n"
"  col += float3(1.0, 0.4, 0.5) * exp(-max(sun - 0.2, 0.0) * 12.0) * 0.25 * (1.0 + u.beat);\n"
"  if (uv.y > horizon) {\n"
"    float depth = (uv.y - horizon) / (1.0 - horizon); float z = 1.0 / max(depth, 0.02);\n"
"    float gx = abs(fract((uv.x - 0.5) * z * 2.0) - 0.5); float gz = abs(fract(z * 0.6 - u.time * 1.2) - 0.5);\n"
"    float line = max(smoothstep(0.03 * z, 0.0, gx), smoothstep(0.06, 0.0, gz)) * depth;\n"
"    col = mix(float3(0.06, 0.0, 0.1), float3(1.0, 0.2, 0.8), line);\n"
"  }\n"
"  return col;\n"
"}\n"
"float3 blueprint(constant U &u, float2 uv) {\n"
"  float2 px = uv * u.size; float3 col = float3(0.07, 0.26, 0.62);\n"
"  float minor = max(step(fract(px.x / 24.0), 0.04), step(fract(px.y / 24.0), 0.04));\n"
"  float major = max(step(fract(px.x / 120.0), 0.012), step(fract(px.y / 120.0), 0.012));\n"
"  col += float3(0.12, 0.2, 0.3) * minor * 0.6 + float3(0.25, 0.35, 0.45) * major;\n"
"  col *= 1.0 - 0.35 * length(uv - 0.5);\n"
"  return col * (0.95 + 0.1 * u.beat);\n"
"}\n"
"float3 shade(constant U &u, int mode, float2 uv, texture2d<float> cover) {\n"
"  if (mode == 1) return nebula(u, uv);\n"
"  if (mode == 2) return halo(u, uv, cover);\n"
"  if (mode == 3) return poster(u, uv, cover);\n"
"  if (mode == 4) return cut(u, uv, cover);\n"
"  if (mode == 10) return night(u, uv);\n"
"  if (mode == 11) return inferno(u, uv);\n"
"  if (mode == 12) return hologram(u, uv);\n"
"  if (mode == 13) return chrome(u, uv);\n"
"  if (mode == 14) return blueprint(u, uv);\n"
"  return bars(u, uv);\n"
"}\n"
"fragment float4 vis_fragment(VOut in [[stage_in]], constant U &u [[buffer(0)]], texture2d<float> cover [[texture(0)]]) {\n"
"  float3 a = shade(u, u.mode, in.uv, cover);\n"
"  if (u.blend > 0.001) a = mix(a, shade(u, u.mode2, in.uv, cover), u.blend);\n"
"  return float4(a * u.dim, 1.0);\n"
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
    double _phase;
}

// The phone's tilt for every visualizer on screen, from one motion manager while any is drawing.
static CMMotionManager *sMotion;
static NSInteger sMotionUsers;
static void useMotion(BOOL use) {
    if (!sMotion) sMotion = [CMMotionManager new];
    sMotionUsers = MAX(0, sMotionUsers + (use ? 1 : -1));
    if (!sMotion.deviceMotionAvailable) return;
    if (sMotionUsers > 0 && !sMotion.deviceMotionActive) {
        sMotion.deviceMotionUpdateInterval = 1.0 / 30;
        [sMotion startDeviceMotionUpdates];
    } else if (sMotionUsers == 0 && sMotion.deviceMotionActive) {
        [sMotion stopDeviceMotionUpdates];
    }
}

+ (Class)layerClass { return CAMetalLayer.class; }

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    _intensity = 1;
    _dim = 1;
    _coverRect = CGRectMake(0.25, 0.25, 0.5, 0.5);
    _tilts = YES;
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
        if (_tilts) useMotion(YES);
        _link = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)];
        _link.preferredFramesPerSecond = 60;
        [_link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
        _lastFrame = 0;
    } else if (!run && _link) {
        if (_tilts) useMotion(NO);
        [_link invalidate];
        _link = nil;
    }
}

- (void)tick:(CADisplayLink *)link {
    double dt = _lastFrame > 0 ? MIN(0.1, link.timestamp - _lastFrame) : 0;
    _lastFrame = link.timestamp;
    _time += dt;
    FZRAudioFrame levels = FZRAudioLevelsNow();
    _phase += dt * (0.18 + 0.45 * levels.level + 0.9 * levels.beat) * _intensity;
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
    u.dim = (float)_dim;
    u.phase = (float)_phase;
    u.coverRect = simd_make_float4((float)CGRectGetMidX(_coverRect), (float)CGRectGetMidY(_coverRect),
                                   (float)(_coverRect.size.width / 2), (float)(_coverRect.size.height / 2));
    CMDeviceMotion *motion = _tilts && sMotion.deviceMotionActive ? sMotion.deviceMotion : nil;
    u.tilt = motion ? simd_make_float2((float)motion.gravity.x * 3, (float)motion.gravity.y * 3) : simd_make_float2(0, 0);
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
