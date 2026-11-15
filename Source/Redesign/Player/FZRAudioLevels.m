// See FZRAudioLevels.h.
#import <AVFoundation/AVFoundation.h>
#import <MediaToolbox/MediaToolbox.h>
#import <Accelerate/Accelerate.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <os/lock.h>
#import "Redesign/Player/FZRAudioLevels.h"
#import "Settings/Kit/FZKitCore.h"
#import "Core/FZRemote.h"
#import "Core/FZHook.h"
#import "Core/FZLog.h"

NSString *const FZRKeyAudioTap = @"fz.redesign.audioTap";

#define kFFTLog2 10
#define kFFTSize (1 << kFFTLog2)   // 1024 samples

// Written on the audio thread, read on the main thread.
static os_unfair_lock sLock = OS_UNFAIR_LOCK_INIT;
static float sRaw[FZR_BANDS];
static double sRawTime;   // CACurrentMediaTime of the last analysis

#pragma mark - the tap

typedef struct {
    AudioStreamBasicDescription format;
    FFTSetup fft;
    float window[kFFTSize];
    float samples[kFFTSize];
    int filled;
    float real[kFFTSize / 2], imag[kFFTSize / 2], magnitudes[kFFTSize / 2];
} TapState;

static void tapInit(MTAudioProcessingTapRef tap, void *clientInfo, void **tapStorageOut) {
    TapState *state = calloc(1, sizeof(TapState));
    state->fft = vDSP_create_fftsetup(kFFTLog2, kFFTRadix2);
    vDSP_hann_window(state->window, kFFTSize, vDSP_HANN_NORM);
    *tapStorageOut = state;
}

static void tapFinalize(MTAudioProcessingTapRef tap) {
    TapState *state = MTAudioProcessingTapGetStorage(tap);
    if (!state) return;
    if (state->fft) vDSP_destroy_fftsetup(state->fft);
    free(state);
}

static void tapPrepare(MTAudioProcessingTapRef tap, CMItemCount maxFrames, const AudioStreamBasicDescription *format) {
    TapState *state = MTAudioProcessingTapGetStorage(tap);
    if (state && format) state->format = *format;
}

static void tapUnprepare(MTAudioProcessingTapRef tap) {}

// 32 bands spaced by octave fractions from 40 Hz to 16 kHz, each the loudest bin in it, on a log scale.
static void analyse(TapState *state) {
    float windowed[kFFTSize];
    vDSP_vmul(state->samples, 1, state->window, 1, windowed, 1, kFFTSize);
    DSPSplitComplex split = {state->real, state->imag};
    vDSP_ctoz((const DSPComplex *)windowed, 2, &split, 1, kFFTSize / 2);
    vDSP_fft_zrip(state->fft, &split, 1, kFFTLog2, kFFTRadix2);
    vDSP_zvabs(&split, 1, state->magnitudes, 1, kFFTSize / 2);
    float scale = 2.0f / kFFTSize;
    vDSP_vsmul(state->magnitudes, 1, &scale, state->magnitudes, 1, kFFTSize / 2);

    double rate = state->format.mSampleRate > 0 ? state->format.mSampleRate : 44100;
    double binHz = rate / kFFTSize, low = 40, high = MIN(16000, rate / 2 - binHz);
    float bands[FZR_BANDS];
    for (int b = 0; b < FZR_BANDS; b++) {
        double from = low * pow(high / low, (double)b / FZR_BANDS), to = low * pow(high / low, (double)(b + 1) / FZR_BANDS);
        int first = MAX(1, (int)floor(from / binHz)), last = MAX(first, MIN(kFFTSize / 2 - 1, (int)ceil(to / binHz)));
        float peak = 0;
        for (int i = first; i <= last; i++) peak = MAX(peak, state->magnitudes[i]);
        // -60…0 dB as 0…1, a little lift for the highs, which are quieter in music.
        float db = 20 * log10f(MAX(peak, 1e-6f)) + 6 * (float)b / FZR_BANDS;
        bands[b] = MIN(1, MAX(0, (db + 60) / 60));
    }
    os_unfair_lock_lock(&sLock);
    memcpy(sRaw, bands, sizeof bands);
    sRawTime = CACurrentMediaTime();
    os_unfair_lock_unlock(&sLock);
}

static float sampleAt(const AudioBufferList *list, const AudioStreamBasicDescription *format, UInt32 frame) {
    if (!list->mNumberBuffers) return 0;
    BOOL isFloat = (format->mFormatFlags & kAudioFormatFlagIsFloat) != 0;
    BOOL interleaved = (format->mFormatFlags & kAudioFormatFlagIsNonInterleaved) == 0;
    UInt32 channels = MAX(1, format->mChannelsPerFrame);
    const AudioBuffer *buffer = &list->mBuffers[0];
    UInt32 index = interleaved ? frame * channels : frame;
    if (isFloat && format->mBitsPerChannel == 32) {
        if ((index + 1) * sizeof(float) > buffer->mDataByteSize) return 0;
        float value = ((const float *)buffer->mData)[index];
        // Both channels, when the second is its own buffer.
        if (!interleaved && list->mNumberBuffers > 1 && (frame + 1) * sizeof(float) <= list->mBuffers[1].mDataByteSize) {
            value = 0.5f * (value + ((const float *)list->mBuffers[1].mData)[frame]);
        }
        return value;
    }
    if (!isFloat && format->mBitsPerChannel == 16) {
        if ((index + 1) * sizeof(SInt16) > buffer->mDataByteSize) return 0;
        return ((const SInt16 *)buffer->mData)[index] / 32768.0f;
    }
    return 0;
}

static void tapProcess(MTAudioProcessingTapRef tap, CMItemCount numberFrames, MTAudioProcessingTapFlags flags,
                       AudioBufferList *bufferList, CMItemCount *framesOut, MTAudioProcessingTapFlags *flagsOut) {
    // The sound goes on as it came: Frozio only reads it.
    OSStatus status = MTAudioProcessingTapGetSourceAudio(tap, numberFrames, bufferList, flagsOut, NULL, framesOut);
    if (status != noErr) return;
    TapState *state = MTAudioProcessingTapGetStorage(tap);
    if (!state || !state->fft) return;
    for (CMItemCount i = 0; i < *framesOut; i++) {
        state->samples[state->filled++] = sampleAt(bufferList, &state->format, (UInt32)i);
        if (state->filled == kFFTSize) {
            analyse(state);
            // Half overlap: the next analysis starts from the second half.
            memmove(state->samples, state->samples + kFFTSize / 2, sizeof(float) * kFFTSize / 2);
            state->filled = kFFTSize / 2;
        }
    }
}

static id newTap(void) {
    // Filled in one by one: the struct is packed, and a constant initialiser leaves unaligned pointers for the linker.
    MTAudioProcessingTapCallbacks callbacks;
    memset(&callbacks, 0, sizeof callbacks);
    callbacks.version = kMTAudioProcessingTapCallbacksVersion_0;
    callbacks.init = tapInit;
    callbacks.finalize = tapFinalize;
    callbacks.prepare = tapPrepare;
    callbacks.unprepare = tapUnprepare;
    callbacks.process = tapProcess;
    MTAudioProcessingTapRef tap = NULL;
    OSStatus status = MTAudioProcessingTapCreate(kCFAllocatorDefault, &callbacks, kMTAudioProcessingTapCreationFlag_PostEffects, &tap);
    if (status != noErr || !tap) { FZLogError("audio levels: no tap (%d)", (int)status); return nil; }
    return (__bridge_transfer id)tap;
}

#pragma mark - attaching it to NaviMus's items

static char kTappedKey;
static IMP fz_origSetAudioMix, fz_origInsert, fz_origReplace, fz_origInitItems;

// NaviMus's mix (or none) with Frozio's tap on every audio input that hasn't one.
static AVAudioMix *withTaps(AVAudioMix *mix, AVAssetTrack *track) {
    NSMutableArray<AVAudioMixInputParameters *> *inputs = [NSMutableArray array];
    BOOL changed = NO;
    for (AVAudioMixInputParameters *given in mix.inputParameters) {
        AVMutableAudioMixInputParameters *copy = [given mutableCopy];
        if (!copy.audioTapProcessor) {
            id tap = newTap();
            if (tap) { copy.audioTapProcessor = (__bridge MTAudioProcessingTapRef)tap; changed = YES; }
        }
        [inputs addObject:copy];
    }
    if (!inputs.count && track) {
        AVMutableAudioMixInputParameters *own = [AVMutableAudioMixInputParameters audioMixInputParametersWithTrack:track];
        id tap = newTap();
        if (tap) { own.audioTapProcessor = (__bridge MTAudioProcessingTapRef)tap; [inputs addObject:own]; changed = YES; }
    }
    if (!changed) return mix;
    AVMutableAudioMix *result = [AVMutableAudioMix audioMix];
    result.inputParameters = inputs;
    return result;
}

static void fz_setAudioMix(AVPlayerItem *self, SEL _cmd, AVAudioMix *mix) {
    AVAudioMix *use = mix;
    if (mix && FZEnabled(FZRKeyAudioTap)) {
        @try { use = withTaps(mix, nil); } @catch (NSException *e) { use = mix; }
        if (use != mix) objc_setAssociatedObject(self, &kTappedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    ((void (*)(id, SEL, id))fz_origSetAudioMix)(self, _cmd, use);
}

// An item NaviMus gave no mix: a mix of Frozio's own, with the tap, once its audio track is known.
static void tapItem(AVPlayerItem *item) {
    if (!item || !FZEnabled(FZRKeyAudioTap) || objc_getAssociatedObject(item, &kTappedKey)) return;
    // Frozio's own animated covers (silent videos from the caches) are left alone.
    NSURL *url = [item.asset isKindOfClass:AVURLAsset.class] ? ((AVURLAsset *)item.asset).URL : nil;
    if (url.isFileURL && [url.path containsString:@"/Frozio/AnimatedCovers/"]) return;
    objc_setAssociatedObject(item, &kTappedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    AVAsset *asset = item.asset;
    __weak AVPlayerItem *weakItem = item;
    [asset loadValuesAsynchronouslyForKeys:@[@"tracks"] completionHandler:^{
        if ([asset statusOfValueForKey:@"tracks" error:nil] != AVKeyValueStatusLoaded) return;
        AVAssetTrack *track = [asset tracksWithMediaType:AVMediaTypeAudio].firstObject;
        if (!track) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            AVPlayerItem *strongItem = weakItem;
            if (!strongItem) return;
            AVAudioMix *mix = withTaps(strongItem.audioMix, track);
            if (mix != strongItem.audioMix) ((void (*)(id, SEL, id))fz_origSetAudioMix)(strongItem, @selector(setAudioMix:), mix);
            static dispatch_once_t once;
            dispatch_once(&once, ^{ FZLog("audio levels: tap on %@ (%@)", NSStringFromClass(strongItem.class), mix ? @"mix" : @"none"); });
        });
    }];
}

static void fz_insertItem(AVQueuePlayer *self, SEL _cmd, AVPlayerItem *item, AVPlayerItem *after) {
    tapItem(item);
    ((void (*)(id, SEL, id, id))fz_origInsert)(self, _cmd, item, after);
}

static void fz_replaceCurrentItem(AVPlayer *self, SEL _cmd, AVPlayerItem *item) {
    tapItem(item);
    ((void (*)(id, SEL, id))fz_origReplace)(self, _cmd, item);
}

static id fz_initWithItems(AVQueuePlayer *self, SEL _cmd, NSArray<AVPlayerItem *> *items) {
    for (AVPlayerItem *item in items) tapItem(item);
    return ((id (*)(id, SEL, id))fz_origInitItems)(self, _cmd, items);
}

void FZInstallAudioLevels(void) {
    BOOL mix = FZHookInstanceMethod(AVPlayerItem.class, @selector(setAudioMix:), "v@:@", (IMP)fz_setAudioMix, &fz_origSetAudioMix, "audio.mix");
    BOOL insert = FZHookInstanceMethod(AVQueuePlayer.class, @selector(insertItem:afterItem:), "v@:@@", (IMP)fz_insertItem, &fz_origInsert, "audio.insert");
    BOOL items = FZHookInstanceMethod(AVQueuePlayer.class, @selector(initWithItems:), "@@:@", (IMP)fz_initWithItems, &fz_origInitItems, "audio.initItems");
    // Not on every iOS (the harness's iOS 26 has it elsewhere); NaviMus's queue player goes through the two above.
    BOOL replace = FZHookInstanceMethod(AVPlayer.class, @selector(replaceCurrentItemWithItem:), "v@:@", (IMP)fz_replaceCurrentItem, &fz_origReplace, "audio.replace");
    FZLog("audio levels: hooks %d/%d/%d/%d (tap %@)", mix, insert, items, replace, FZEnabled(FZRKeyAudioTap) ? @"on" : @"off");
}

#pragma mark - reading

static FZRAudioFrame sSmooth;
static double sLastRead;
static float sBassAverage;

BOOL FZRAudioLevelsLive(void) {
    os_unfair_lock_lock(&sLock);
    double at = sRawTime;
    os_unfair_lock_unlock(&sLock);
    return CACurrentMediaTime() - at < 0.5;
}

// Without the music's own levels: a pulse at 120 bpm with a slow sway across the bands, while something plays.
static void madeUp(float *bands, double now) {
    BOOL playing = FZNowPlayingIsPlaying();
    double beat = fmod(now * 2.0, 1.0);
    float kick = playing ? (float)pow(1 - beat, 4) : 0;
    for (int b = 0; b < FZR_BANDS; b++) {
        float sway = 0.5f + 0.5f * (float)sin(now * (0.7 + b * 0.09) + b * 0.8);
        float base = playing ? 0.25f + 0.35f * sway * (1 - (float)b / FZR_BANDS * 0.5f) : 0.02f;
        bands[b] = MIN(1, base + (b < 6 ? kick * 0.5f : kick * 0.12f));
    }
}

FZRAudioFrame FZRAudioLevelsNow(void) {
    double now = CACurrentMediaTime();
    double dt = sLastRead > 0 ? MIN(0.1, now - sLastRead) : 1.0 / 60;
    sLastRead = now;
    float raw[FZR_BANDS];
    os_unfair_lock_lock(&sLock);
    memcpy(raw, sRaw, sizeof raw);
    double at = sRawTime;
    os_unfair_lock_unlock(&sLock);
    if (now - at > 0.5) madeUp(raw, now);
    // Quick up, slow down, as a meter.
    float up = 1 - expf(-(float)dt / 0.04f), down = 1 - expf(-(float)dt / 0.25f);
    float bass = 0, mid = 0, treble = 0, level = 0;
    for (int b = 0; b < FZR_BANDS; b++) {
        float target = raw[b], current = sSmooth.bands[b];
        sSmooth.bands[b] = current + (target - current) * (target > current ? up : down);
        float v = sSmooth.bands[b];
        if (b < 6) bass += v / 6; else if (b < 20) mid += v / 14; else treble += v / 12;
        level += v / FZR_BANDS;
    }
    sSmooth.bass = bass;
    sSmooth.mid = mid;
    sSmooth.treble = treble;
    sSmooth.level = level;
    // A beat: the bass rising clearly above its own recent average.
    sBassAverage += (bass - sBassAverage) * (1 - expf(-(float)dt / 0.6f));
    float hit = MAX(0, (bass - sBassAverage) * 4);
    sSmooth.beat = MAX(hit > 0.25f ? MIN(1, hit) : 0, sSmooth.beat - (float)dt * 3);
    return sSmooth;
}
