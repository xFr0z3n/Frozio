// How loud the music is right now, by frequency, for the visualizer and the lyrics shaders.
//
// NaviMus plays through AVQueuePlayer (Arpeggi's AudioManager: player, playerA, playerB) and sets audio mixes of its
// own (AVAudioMixInputParameters in its binary, for its fades). Frozio adds an MTAudioProcessingTap to each item's
// audio: to NaviMus's own mix when it sets one (its parameters copied, the tap added), else to a mix of its own once
// the item's audio track has loaded. The tap passes the sound through untouched and reads it: a 1024-point FFT,
// 32 bands spaced by octave from 40 Hz to 16 kHz. When there is no tap (AirPlay, a stream it can't see), the levels
// are made up from a steady pulse while music plays, so the visuals still move.
#pragma once
#import <Foundation/Foundation.h>

#define FZR_BANDS 32

typedef struct {
    float bands[FZR_BANDS];   // 0…1, low to high
    float bass, mid, treble;  // 0…1
    float level;              // 0…1, overall
    float beat;               // 0…1, jumps on a bass hit and falls off
} FZRAudioFrame;

extern NSString *const FZRKeyAudioTap;   // "fz.redesign.audioTap": read NaviMus's sound for the visuals (on)

void FZInstallAudioLevels(void);
/// The levels now, smoothed (main thread; call once per frame).
FZRAudioFrame FZRAudioLevelsNow(void);
/// YES while the levels come from the music itself rather than the made-up pulse.
BOOL FZRAudioLevelsLive(void);
