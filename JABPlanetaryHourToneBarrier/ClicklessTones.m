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
static const float min_duration   = 0.25;
static const float max_duration   = 2.00;

@interface ClicklessTones ()
{
    NSInteger blend_frequency[2];
    double frequency[2];
    NSInteger alternate_channel_flag;
    double duration_bifurcate;
}

@property (nonatomic, readonly) GKMersenneTwisterRandomSource * _Nullable randomizer;
@property (nonatomic, readonly) GKGaussianDistribution * _Nullable distributor;

// Randomizes duration
@property (nonatomic, readonly) GKGaussianDistribution * _Nullable distributor_duration;

@end


@implementation ClicklessTones

- (instancetype)init
{
    self = [super init];
    
    if (self)
    {
        _randomizer  = [[GKMersenneTwisterRandomSource alloc] initWithSeed:time(NULL)];
        _distributor = [[GKGaussianDistribution alloc] initWithRandomSource:_randomizer mean:(high_frequency / .75) deviation:low_frequency];
        _distributor_duration = [[GKGaussianDistribution alloc] initWithRandomSource:_randomizer mean:max_duration deviation:min_duration];
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

- (float)generateRandomNumberBetweenMin:(int)min Max:(int)max
{
    return ( (arc4random() % (max-min+1)) + min );
}

- (void)createAudioBufferWithFormat:(AVAudioFormat *)audioFormat completionBlock:(CreateAudioBufferCompletionBlock)createAudioBufferCompletionBlock
{
    
//    self->frequency[0] = (((double)arc4random() / 0x100000000) * (high_frequency - low_frequency) + low_frequency);
//    self->frequency[1] = (((double)arc4random() / 0x100000000) * (high_frequency - low_frequency) + low_frequency);
    static AVAudioPCMBuffer * (^createAudioBuffer)(Fade, double, double);
    createAudioBuffer = ^AVAudioPCMBuffer *(Fade leading_fade, double frequencyLeft, double frequencyRight)
    {
//        AVAudioFormat *audioFormat = [self->_mixerNode outputFormatForBus:0];
        AVAudioFrameCount frameCount = audioFormat.sampleRate * (2.0 / [self generateRandomNumberBetweenMin:2 Max:4]);
        AVAudioPCMBuffer *pcmBuffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:audioFormat frameCapacity:frameCount];
        pcmBuffer.frameLength = frameCount;
        float *left_channel  = pcmBuffer.floatChannelData[0];
        float *right_channel = (audioFormat.channelCount == 2) ? pcmBuffer.floatChannelData[1] : nil;
        
        int amplitude_frequency = arc4random_uniform(4) + 2;
        for (int index = 0; index < frameCount; index++)
        {
            double normalized_index = LinearInterpolation(index, frameCount);
            
            if (left_channel)  left_channel[index]  = fade(FadeOut, normalized_index, (NormalizedSineEaseInOut(normalized_index, frequencyLeft)  * NormalizedSineEaseInOut(normalized_index, amplitude_frequency)));
            if (right_channel) right_channel[index] = fade(FadeIn,  normalized_index, (NormalizedSineEaseInOut(normalized_index, frequencyRight) * NormalizedSineEaseInOut(normalized_index, amplitude_frequency))); // fade((leading_fade == FadeOut) ? FadeIn : leading_fade, normalized_index, (SineEaseInOutFrequency(normalized_index, frequencyRight) * NormalizedSineEaseInOutAmplitude((1.0 - normalized_index), 1)));
        }
        
//        self->frequency[0] = (((double)arc4random() / 0x100000000) * (high_frequency - low_frequency) + low_frequency); //self->frequency[1];
//        self->frequency[1] = (((double)arc4random() / 0x100000000) * (high_frequency - low_frequency) + low_frequency);
        
        return pcmBuffer;
    };
    
    static void (^block)(void);
    block = ^void(void)
    {
        AudioBuffers * audio_buffers = malloc(sizeof(AudioBuffers));
        audio_buffers->buffer1 = createAudioBuffer((Fade)self->alternate_channel_flag, (((double)arc4random() / 0x100000000) * (high_frequency - low_frequency) + low_frequency), (((double)arc4random() / 0x100000000) * (high_frequency - low_frequency) + low_frequency));
        audio_buffers->buffer2 = createAudioBuffer((Fade)self->alternate_channel_flag, (((double)arc4random() / 0x100000000) * (high_frequency - low_frequency) + low_frequency), (((double)arc4random() / 0x100000000) * (high_frequency - low_frequency) + low_frequency));
        createAudioBufferCompletionBlock(audio_buffers, ^{
//        createAudioBufferCompletionBlock(createAudioBuffer((Fade)self->alternate_channel_flag, [self->_distributor nextInt]/*(((double)arc4random() / 0x100000000) * (high_frequency - low_frequency) + low_frequency)*/, [_distributor nextInt] /*(((double)arc4random() / 0x100000000) * (high_frequency - low_frequency) + low_frequency)*/), createAudioBuffer((Fade)self->alternate_channel_flag, [_distributor nextInt] /*(((double)arc4random() / 0x100000000) * (high_frequency - low_frequency) + low_frequency)*/, [_distributor nextInt] /*(((double)arc4random() / 0x100000000) * (high_frequency - low_frequency) + low_frequency)*/), ^{
//            NSLog(@"alternate_channel_flag == %ld", (long)self->alternate_channel_flag);
            self->alternate_channel_flag = (self->alternate_channel_flag == 1) ? 0 : 1;
            self->duration_bifurcate = /*[self->_distributor_duration nextInt];*/ (((double)arc4random() / 0x100000000) * (max_duration - min_duration) + min_duration);
            // THIS IS WRONG (BELOW)
//            self->frequency[0] = (((double)arc4random() / 0x100000000) * (high_frequency - low_frequency) + low_frequency); //self->frequency[1];
//            self->frequency[1] = (((double)arc4random() / 0x100000000) * (high_frequency - low_frequency) + low_frequency);
            
            block();
            
            
            
        });
    };
    block();
}

@end
