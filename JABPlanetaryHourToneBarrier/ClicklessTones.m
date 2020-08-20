//
//  ClicklessTones.m
//  JABPlanetaryHourToneBarrier
//
//  Created by Xcode Developer on 12/17/19.
//  Copyright © 2019 The Life of a Demoniac. All rights reserved.
//
// TO-DO: Blend release of each frequency with the attack of the next using one of three approaches:
//        1) Send the last frequency with the next when creating the audio buffer and cross-fade (overlap amplitude envelopes)
//        2) Alternate consecutive frequencies between two separate player nodes, offsetting the schedules by the duration of the release and attack (and increasing the sustain by that same duration)

#import "ClicklessTones.h"
#include "easing.h"


static const float high_frequency = 1750.0;
static const float low_frequency  = 500.0;
static const float min_duration   = 1.0;
static const float max_duration   = 8.00;

@interface ClicklessTones ()
{
    NSInteger blend_frequency[2];
    double frequency[2];
    NSInteger alternate_channel_flag;
    double duration_bifurcate;
    GKMersenneTwisterRandomSource * _Nullable _randomizer;
    GKGaussianDistribution * _Nullable _distributor;
    GKMersenneTwisterRandomSource * _Nullable _randomizer_aux;
    GKGaussianDistribution * _Nullable _distributor_aux;
    
    GKMersenneTwisterRandomSource * _Nullable _duration_randomizer;
    GKRandomDistribution * _Nullable _duration_distributor;
    GKMersenneTwisterRandomSource * _Nullable _trill_randomizer;
    GKRandomDistribution * _Nullable _trill_distributor;
}

@end


@implementation ClicklessTones

- (instancetype)init
{
    self = [super init];
    
    if (self)
    {
        _randomizer  = [[GKMersenneTwisterRandomSource alloc] initWithSeed:time(NULL)];
        _distributor = [[GKGaussianDistribution alloc] initWithRandomSource:_randomizer mean:(high_frequency / 1.5) deviation:low_frequency];
        _randomizer_aux  = [[GKMersenneTwisterRandomSource alloc] initWithSeed:time(NULL)];
        _distributor_aux = [[GKGaussianDistribution alloc] initWithRandomSource:_randomizer_aux mean:(high_frequency / 2.25) deviation:low_frequency];
        
        _duration_randomizer  = [[GKMersenneTwisterRandomSource alloc] initWithSeed:time(NULL)];
        _duration_distributor = [[GKRandomDistribution alloc] initWithRandomSource:_duration_randomizer lowestValue:1 highestValue:8];
        _trill_randomizer  = [[GKMersenneTwisterRandomSource alloc] initWithSeed:time(NULL)];
        _trill_distributor = [[GKRandomDistribution alloc] initWithRandomSource:_trill_randomizer lowestValue:4 highestValue:6];
    }
    
    return self;
}

typedef NS_ENUM(NSUInteger, Fade) {
    FadeOut,
    FadeIn
};

float normalize(float unscaledNum, float minAllowed, float maxAllowed, float min, float max) {
    return (maxAllowed - minAllowed) * (unscaledNum - min) / (max - min) + minAllowed;
}

double (^fade)(Fade, double, double) = ^double(Fade fadeType, double x, double freq_amp)
{
    double fade_effect = freq_amp * ((fadeType == FadeIn) ? x : (1.0 - x));
    
    return fade_effect;
};

double(^trill)(double, double, double) = ^double(double time, double trill, double freq_amp)
{
    return freq_amp * pow(2.0 * pow(sinf(M_PI * time * trill), 2.0) * 0.5, 4.0);
};

double(^amplitude)(double, double) = ^double(double time, double trill)
{
    double mid   = 0.5;
//    double trill = 4.0;
    double slope = 2.0;
    BOOL invert  = FALSE;
    
    time = (mid > 1.0) ? pow(time, mid) : time;
    time = (invert) ? 1.0 - time : time;
    time = (trill != 1.0) ? time * (trill * time) : time;
    double w = (M_PI * time);
    w = pow(sinf(w), slope);

    return sinf(w); //signbit(sinf(time * M_PI * 2));
};

float * (^calculateChannelData)(AVAudioFrameCount, float, int, float *, float *) = ^float * (AVAudioFrameCount samples, float frequency, int trill_value, float * floatChannelDataPtrsArray, float * floatChannelDataPtrs)
{
    int amplitude_frequency = arc4random_uniform(4) + 2;
    
    floatChannelDataPtrsArray = floatChannelDataPtrs;
    for (int time = 0; time < samples; time++)
    {
        double normalized_time = LinearInterpolation(time, samples);
        if (floatChannelDataPtrsArray) floatChannelDataPtrsArray[time] = (NormalizedSineEaseInOut(normalized_time, frequency) * NormalizedSineEaseInOut(normalized_time, amplitude_frequency)) + (NormalizedSineEaseInOut(normalized_time, frequency * (5.0/4.0)) * NormalizedSineEaseInOut(normalized_time, amplitude_frequency));
            //trill(normalized_time, trill_value, (NormalizedSineEaseInOut(normalized_time, frequency) * NormalizedSineEaseInOut(normalized_time, amplitude_frequency)) + (NormalizedSineEaseInOut(normalized_time, frequency * (5.0/4.0)) * NormalizedSineEaseInOut(normalized_time, amplitude_frequency)));
    }
    
    return floatChannelDataPtrsArray;
};

static void(^createAudioBuffer)(AVAudioFormat *, CreateAudioBufferCompletionBlock) = ^(AVAudioFormat * audioFormat, CreateAudioBufferCompletionBlock createAudioBufferCompletionBlock)
{
    static AVAudioPCMBuffer * (^calculateBufferData)(AVAudioFormat *);
    calculateBufferData = ^AVAudioPCMBuffer *(AVAudioFormat * audio_format)
    {
        double duration              = 2.0;
        NSLog(@"duration: %f", duration);
        double sampleRate            = [audio_format sampleRate];
        AVAudioFrameCount frameCount = (sampleRate * 2.0) * duration; // duration = (1 / mSampleRate) * mFramesPerPacket
        AVAudioPCMBuffer *pcmBuffer  = [[AVAudioPCMBuffer alloc] initWithPCMFormat:audio_format frameCapacity:frameCount];
        pcmBuffer.frameLength        = sampleRate * duration; // The number of bytes in the buffer
        float * channelL, * channelR;
        
        channelL = calculateChannelData(pcmBuffer.frameLength,
                                        1000.0,
                                        1.0,
                                        channelL,
                                        pcmBuffer.floatChannelData[0]);
        channelR = calculateChannelData(pcmBuffer.frameLength,
                                        1000.0,
                                        1.0,
                                        channelR,
                                        ([audio_format channelCount] == 2) ? pcmBuffer.floatChannelData[1] : nil);
        
        return pcmBuffer;
    };
    
    static void (^block)(void);
    block = ^void(void)
    {
        createAudioBufferCompletionBlock(calculateBufferData(audioFormat), ^{            
            block();
        });
    };
    block();
};

- (void)createAudioBufferWithFormat:(AVAudioFormat *)audioFormat completionBlock:(CreateAudioBufferCompletionBlock)createAudioBufferCompletionBlock
{
    static AVAudioPCMBuffer * (^calculateBufferData)(AVAudioFormat *, GKGaussianDistribution *, GKGaussianDistribution *, GKGaussianDistribution *);
    calculateBufferData = ^AVAudioPCMBuffer *(AVAudioFormat * audio_format, GKGaussianDistribution * frequency_distributor, GKGaussianDistribution * duration_distributor, GKGaussianDistribution * trill_distributor)
    {
        double duration              = [duration_distributor nextInt];
        NSLog(@"duration: %f", duration);
        double sampleRate            = [audio_format sampleRate];
        AVAudioFrameCount frameCount = (sampleRate * 2.0) * duration; // duration = (1 / mSampleRate) * mFramesPerPacket
        AVAudioPCMBuffer *pcmBuffer  = [[AVAudioPCMBuffer alloc] initWithPCMFormat:audio_format frameCapacity:frameCount];
        pcmBuffer.frameLength        = sampleRate * duration; // The number of bytes in the buffer
        float * channelL, * channelR;
        
        int trill_value = (int)[trill_distributor nextInt];
        channelL = calculateChannelData(pcmBuffer.frameLength,
                                        [frequency_distributor nextInt],
                                        trill_value,
                                        channelL,
                                        pcmBuffer.floatChannelData[0]);
        channelR = calculateChannelData(pcmBuffer.frameLength,
                                        [frequency_distributor nextInt],
                                        trill_value,
                                        channelR,
                                        ([audio_format channelCount] == 2) ? pcmBuffer.floatChannelData[1] : nil);
        
        return pcmBuffer;
    };
    
    static void (^block)(void);
    block = ^void(void)
    {
        createAudioBufferCompletionBlock(calculateBufferData(audioFormat, (self->alternate_channel_flag == 0) ? _distributor : _distributor_aux, _duration_distributor, _trill_distributor), ^{
            self->alternate_channel_flag = (self->alternate_channel_flag == 1) ? 0 : 1;
            self->duration_bifurcate = (((double)arc4random() / 0x100000000) * (max_duration - min_duration) + min_duration);
            
            block();
        });
    };
    block();
}

@end
//