//
//  ToneGenerator.m
//  JABPlanetaryHourToneBarrier
//
//  Created by Xcode Developer on 7/8/19.
//  Copyright © 2019 The Life of a Demoniac. All rights reserved.
//

#import <AVFoundation/AVFoundation.h>
#import <MediaPlayer/MediaPlayer.h>
#import <GameKit/GameKit.h>

#import "ToneGenerator.h"
#import "ToneBarrierPlayer.h"
//#import "ClicklessTones.h"
//#import "FrequenciesPairs.h"
//#import "Frequencies.h"

#include "easing.h"


@interface ToneGenerator ()

@property (nonatomic, strong) AVAudioMixerNode * _Nullable  mainNode;
@property (nonatomic, strong) AVAudioMixerNode * _Nullable  mixerNode;
@property (nonatomic, strong) AVAudioFormat * _Nullable     audioFormat;
@property (nonatomic, strong) AVAudioUnitReverb * _Nullable reverb;


@end

@implementation ToneGenerator

static ToneGenerator *sharedGenerator = NULL;
+ (nonnull ToneGenerator *)sharedGenerator
{
    static dispatch_once_t onceSecurePredicate;
    dispatch_once(&onceSecurePredicate,^
                  {
        if (!sharedGenerator)
        {
            sharedGenerator = [[self alloc] init];
        }
    });
    
    return sharedGenerator;
}

double Normalize(double a, double b)
{
    return (double)(a / b);
}

#define max_frequency      1500.0
#define min_frequency       100.0
#define max_trill_interval    4.0
#define min_trill_interval    2.0
#define duration_interval     5.0
#define duration_maximum      2.0


// Elements of an effective tone:
// High-pitched
// Modulating amplitude
// Alternating channel output
// Loud
// Non-natural (no spatialization)
//
// Elements of an effective score:
// Random frequencies
// Random duration
// Random tonality

// To-Do: Multiply the frequency by a random number between 1.01 and 1.1)

typedef NS_ENUM(NSUInteger, TonalHarmony) {
    TonalHarmonyConsonance,
    TonalHarmonyDissonance,
    TonalHarmonyRandom
};

typedef NS_ENUM(NSUInteger, TonalInterval) {
    TonalIntervalUnison,
    TonalIntervalOctave,
    TonalIntervalMajorSixth,
    TonalIntervalPerfectFifth,
    TonalIntervalPerfectFourth,
    TonalIntervalMajorThird,
    TonalIntervalMinorThird,
    TonalIntervalRandom
};

typedef NS_ENUM(NSUInteger, TonalEnvelope) {
    TonalEnvelopeAverageSustain,
    TonalEnvelopeLongSustain,
    TonalEnvelopeShortSustain
};

double Tonality(double frequency, TonalInterval interval, TonalHarmony harmony)
{
    double new_frequency = frequency;
    switch (harmony) {
        case TonalHarmonyDissonance:
            new_frequency *= (1.1 + drand48());
            break;
            
        case TonalHarmonyConsonance:
            new_frequency = ToneGenerator.Interval(frequency, interval);
            break;
            
        case TonalHarmonyRandom:
            new_frequency = Tonality(frequency, interval, (TonalHarmony)arc4random_uniform(2));
            break;
            
        default:
            break;
    }
    
    return new_frequency;
}

double Envelope(double x, TonalEnvelope envelope)
{
    double x_envelope = 1.0;
    switch (envelope) {
        case TonalEnvelopeAverageSustain:
            x_envelope = sinf(x * M_PI) * (sinf((2 * x * M_PI) / 2));
            break;
            
        case TonalEnvelopeLongSustain:
            x_envelope = sinf(x * M_PI) * -sinf(
                                                ((Envelope(x, TonalEnvelopeAverageSustain) - (2.0 * Envelope(x, TonalEnvelopeAverageSustain)))) / 2.0)
            * (M_PI / 2.0) * 2.0;
            break;
            
        case TonalEnvelopeShortSustain:
            x_envelope = sinf(x * M_PI) * -sinf(
                                                ((Envelope(x, TonalEnvelopeAverageSustain) - (-2.0 * Envelope(x, TonalEnvelopeAverageSustain)))) / 2.0)
            * (M_PI / 2.0) * 2.0;
            break;
            
        default:
            break;
    }
    
    return x_envelope;
}

typedef NS_ENUM(NSUInteger, Trill) {
    TonalTrillUnsigned,
    TonalTrillInverse
};

+ (double(^)(double, double))Frequency
{
    return ^double(double time, double frequency)
    {
        return pow(sinf(M_PI * time * frequency), 2.0);
    };
}

+ (double(^)(double))TrillInterval
{
    return ^double(double frequency)
    {
        return ((frequency / (max_frequency - min_frequency) * (max_trill_interval - min_trill_interval)) + min_trill_interval);
    };
}

+ (double(^)(double, double))Trill
{
    return ^double(double time, double trill)
    {
        return pow(2.0 * pow(sinf(M_PI * time * trill), 2.0) * 0.5, 4.0);
    };
}

+ (double(^)(double, double))TrillInverse
{
    return ^double(double time, double trill)
    {
        return pow(-(2.0 * pow(sinf(M_PI * time * trill), 2.0) * 0.5) + 1.0, 4.0);
    };
}

+ (double(^)(double))Amplitude
{
    return ^double(double time)
    {
        return pow(sinf(time * M_PI), 3.0) * 0.5;
    };
}

+ (double(^)(double, TonalInterval))Interval
{
    return ^double(double frequency, TonalInterval interval)
    {
        double new_frequency = frequency;
        switch (interval)
        {
            case TonalIntervalUnison:
                new_frequency *= 1.0;
                break;
                
            case TonalIntervalOctave:
                new_frequency *= 2.0;
                break;
                
            case TonalIntervalMajorSixth:
                new_frequency *= 5.0/3.0;
                break;
                
            case TonalIntervalPerfectFifth:
                new_frequency *= 4.0/3.0;
                break;
                
            case TonalIntervalMajorThird:
                new_frequency *= 5.0/4.0;
                break;
                
            case TonalIntervalMinorThird:
                new_frequency *= 6.0/5.0;
                break;
                
            case TonalIntervalRandom:
                new_frequency = ToneGenerator.Interval(frequency, (TonalInterval)arc4random_uniform(7));
                
            default:
                break;
        }
        
        return new_frequency;
    };
};

- (instancetype)init
{
    self = [super init];
    
    if (self)
    {
        [self setupEngine];
    }
    
    return self;
}

- (void)setupEngine
{
    self.audioEngine = [[AVAudioEngine alloc] init];
    
    self.mainNode = self.audioEngine.mainMixerNode;
    
    double sampleRate = [self.mainNode outputFormatForBus:0].sampleRate;
    AVAudioChannelCount channelCount = [self.mainNode outputFormatForBus:0].channelCount;
    self.audioFormat = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:sampleRate channels:channelCount];
}

- (BOOL)startEngine
{
    __autoreleasing NSError *error = nil;
    if ([self.audioEngine startAndReturnError:&error])
    {
        NSLog(@"AudioEngine started");
        [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:&error];
        if (error)
        {
            NSLog(@"%@", [error description]);
            return FALSE;
        } else {
            NSLog(@"AudioSession configured");
            [[AVAudioSession sharedInstance] setActive:YES error:&error];
            if (error)
            {
                NSLog(@"%@", [error description]);
                return FALSE;
            } else {
                NSLog(@"AudioSession active");
                return TRUE;
            }
        }
    } else {
        NSLog(@"AudioEngine did not start: %@", [error description]);
        return FALSE;
    }
}

double (^standardize)(double, double, double, double, double) = ^double(double value, double min, double max, double new_min, double new_max)
{
    double standardized_value = (new_max - new_min) * (value - min) / (max - min) + new_min;
    
    return standardized_value;
};

double (^normalize)(double, double, double, double, double) = ^double(double min_new, double max_new, double val_old, double min_old, double max_old)
{
    double val_new = min_new + ((((val_old - min_old) * (max_new - min_new))) / (max_old - min_old));
    
    return val_new;
};

double(^randomize)(double, double, double) = ^double(double min, double max, double weight)
{
    double random = drand48();
    double weighted_random = pow(random, weight);
    double frequency = (weighted_random * (max - min)) + min;
    
    return frequency;
};


double sincf(double x)
{
    double sincf_x = sin(x * M_PI) / (x * M_PI);
    
    return sincf_x;
}

double (^frequency_sin)(double, double) =  ^(double time, double frequency)
{
    double freq_sin = sinf(M_PI * 2.0 * time * frequency);
    
    return freq_sin;
};

double (^envelope_lfo)(double, double) = ^(double time, double slope)
{
    double env_lfo = pow(sin(time * M_PI), slope);
    
    return env_lfo;
};

typedef struct frequencies
{
    int length;
    double * __nullable frequencies_array;             // Frequencies.frequencies = malloc(Frequencies.frequency_count * sizeof(double));
} Frequencies;

Frequencies * (^createFrequenciesArray)(int, double, double) = ^ Frequencies * (int frequency_count, double root_frequency, double duration)
{
    Frequencies * frequencies_struct = (Frequencies *)malloc(sizeof(Frequencies));
    frequencies_struct->length = frequency_count;
    frequencies_struct->frequencies_array = (double *)malloc(sizeof(float) * frequency_count);
    
    double * frequencies = calloc(frequency_count, sizeof(double));
    for (int i = 0; i < frequency_count; i++)
    {
        frequencies[i] = (root_frequency * (i * (5.0/4.0)) * duration);
    }
    
    return frequencies_struct;
};

typedef enum : NSUInteger
{
    StereoChannelOutputLeft,
    StereoChannelOutputRight
} StereoChannelOutput;

// compare to AudioBuffer
typedef struct stereo_channel
{
    StereoChannelOutput stereo_channel_output;
    Frequencies frequencies;                    // compare to AudioFormatListItem.mASBD (AudioStreamBasicDescription)
    AVAudioFramePosition index_start;
    AVAudioFrameCount samples_count;
    float * __nullable samples;                 // pointer to AVAudioPCMBuffer.floatChannelData[0...1]
} StereoChannel;

// compare to AudioBufferList
typedef struct stereo_channel_list
{
    AVAudioFrameCount frame_capacity;
    AVAudioChannelCount channel_count;          // compare to AudioBufferList.mNumberBuffers
    StereoChannel * channels[1];                  // compare to AudioBufferList.mBuffers (AudioBuffer)
} StereoChannelList;

//StereoChannelList * (^createStereoChannelList)(AVAudioFrameCount, AVAudioChannelCount, float * const *) = ^StereoChannelList * (AVAudioFrameCount frame_capacity,
//                                                                                                                                                 AVAudioChannelCount channel_count,
//                                                                                                                                                 float * const * channel_samples)
//{
//    StereoChannelList * stereoChannelList = (StereoChannelList *)malloc(sizeof(StereoChannelList) + (2 * sizeof(StereoChannel)));
//    stereoChannelList->channel_count = channel_count;
//    for (StereoChannelOutput channel = 0; channel < channel_count; channel++)
//    {
//        StereoChannel * stereoChannel = (StereoChannel *)malloc(sizeof(StereoChannel));
//        stereoChannel->stereo_channel_output = (StereoChannelOutput)channel;
//        stereoChannel->samples = channel_samples[channel];
//        
//        Frequencies * frequencies = (Frequencies *)malloc(sizeof(Frequencies) + sizeof(float));
//        int frequency_count = 2;
//        float * frequencies_arr = malloc(frequency_count * sizeof(float));
//        for (int i = 0; i < frequency_count; i++)
//        {
//            frequencies_arr[i] = 440 * (i * (5.0/4.0));
//        }
//        frequencies->frequencies = frequencies_arr;
//        stereoChannel->frequencies = *frequencies;
//        
//        stereoChannelList->channels[channel] = stereoChannel;
//    }
//    
//    return stereoChannelList;
//};

//+ (StereoChannelList *)audioBufferListWithNumberOfFrames:(UInt32)frames
//                                      numberOfChannels:(UInt32)channels
//                                           interleaved:(BOOL)interleaved
//{
//    unsigned nBuffers;
//    unsigned bufferSize;
//    unsigned channelsPerBuffer;
//    if (interleaved)
//    {
//        nBuffers = 1;
//        bufferSize = sizeof(float) * frames * channels;
//        channelsPerBuffer = channels;
//    }
//    else
//    {
//        nBuffers = channels;
//        bufferSize = sizeof(float) * frames;
//        channelsPerBuffer = 1;
//    }
//
//    AudioBufferList *audioBufferList = (AudioBufferList *)malloc(sizeof(AudioBufferList) + sizeof(AudioBuffer) * (channels-1));
//    audioBufferList->mNumberBuffers = nBuffers;
//    for(unsigned i = 0; i < nBuffers; i++)
//    {
//        audioBufferList->mBuffers[i].mNumberChannels = channelsPerBuffer;
//        audioBufferList->mBuffers[i].mDataByteSize = bufferSize;
//        audioBufferList->mBuffers[i].mData = calloc(bufferSize, 1);
//    }
//    return audioBufferList;
//}


// Modify for Frequencies struct initializer
//static OSStatus recordingCallback(void *inRefCon,
//                                  AudioUnitRenderActionFlags *ioActionFlags,
//                                  const AudioTimeStamp *inTimeStamp,
//                                  UInt32 inBusNumber,
//                                  UInt32 inNumberFrames,
//                                  AudioBufferList *ioData) {
//
//    // the data gets rendered here
//    AudioBuffer buffer;
//
//    // a variable where we check the status
//    OSStatus status;
//
//    /**
//     This is the reference to the object who owns the callback.
//     */
//    AudioProcessor *audioProcessor = (AudioProcessor*) inRefCon;
//
//    /**
//     on this point we define the number of channels, which is mono
//     for the iphone. the number of frames is usally 512 or 1024.
//     */
//    buffer.mDataByteSize = inNumberFrames * 2; // sample size
//    buffer.mNumberChannels = 1; // one channel
//    buffer.mData = malloc( inNumberFrames * 2 ); // buffer size
//
//    // we put our buffer into a bufferlist array for rendering
//    AudioBufferList bufferList;
//    bufferList.mNumberBuffers = 1;
//    bufferList.mBuffers[0] = buffer;
//
//    // render input and check for error
//    status = AudioUnitRender([audioProcessor audioUnit], ioActionFlags, inTimeStamp, inBusNumber, inNumberFrames, &bufferList);
//    [audioProcessor hasError:status:__FILE__:__LINE__];
//
//    // process the bufferlist in the audio processor
//    [audioProcessor processBuffer:&bufferList];
//
//    // clean up the buffer
//    free(bufferList.mBuffers[0].mData);
//
//    return noErr;
//}


//static void(^initStereoChannel)(void * inRefCon, float * samples, AVAudioFrameCount samples_count, StereoChannelList * stereoChannelData)
//{
//    NSObject * refCon = (__bridge NSObject *) inRefCon;
//
//    // iterate over incoming stream an copy to output stream
//    for (int i = 0; i < stereoChannelData->channel_count; i++) {
//        StereoChannel channel = stereoChannelData->channels[i];
//        channel.samples_count = samples_count;
//        channel.samples       = samples;
//    }
//    return noErr;
//}

//void (^calculateChannelData)(AVAudioFrameCount, double, double, double, float *) = ^(AVAudioFrameCount sampleCount, double frequency, double duration, double outputVolume, float * samples)
void (^calculateChannelData)(AVAudioFrameCount, Frequencies *, double, double, float *) = ^(AVAudioFrameCount sampleCount, Frequencies * frequencies, double duration, double outputVolume, float * samples)
{
    for (int index = 0; index < sampleCount; index++)
    {
        double normalized_time = normalize(0.0, 1.0, index, 0.0, sampleCount);
        double frequency_sum   = 0.0;
        for (int i = 0; i < frequencies->length; i++)
        {
            frequency_sum += sinf(2.0 * M_PI * normalized_time * frequencies->frequencies_array[i]);
        }
        double sample = frequency_sum * envelope_lfo(normalized_time, outputVolume);
        
        
        if (samples) samples[index] = sample;
    }
};

static void(^createAudioBuffer)(AVAudioSession *, AVAudioFormat *, CreateAudioBufferCompletionBlock) = ^(AVAudioSession * audioSession, AVAudioFormat * audioFormat, CreateAudioBufferCompletionBlock createAudioBufferCompletionBlock)
{
    static AVAudioPCMBuffer * (^calculateBufferData)(void);
    calculateBufferData = ^AVAudioPCMBuffer *(void)
    {
        double duration = 0.25;
        AVAudioFrameCount frameCount = ([audioFormat sampleRate] * duration);
        AVAudioPCMBuffer *pcmBuffer  = [[AVAudioPCMBuffer alloc] initWithPCMFormat:audioFormat frameCapacity:frameCount];
        pcmBuffer.frameLength        = frameCount;
        
        double tone_split = randomize(0.0, 1.0, 1.0);
        double device_volume = pow(audioSession.outputVolume, 3.0);
        
        Frequencies *frequencies = createFrequenciesArray(2, 440, duration);
        calculateChannelData(pcmBuffer.frameLength,
                             frequencies,
                             tone_split,
                             device_volume,
                             pcmBuffer.floatChannelData[0]);
        
        calculateChannelData(pcmBuffer.frameLength,
                             frequencies,
                             tone_split,
                             device_volume,
                             ([audioFormat channelCount] == 2) ? pcmBuffer.floatChannelData[1] : nil);
        
        return pcmBuffer;
    };
    
    static void (^audioBufferCreatedCompletionBlock)(void);
    static void (^tonePlayedCompletionBlock)(void) = ^(void) {
        audioBufferCreatedCompletionBlock();
    };
    audioBufferCreatedCompletionBlock = ^void(void)
    {
        createAudioBufferCompletionBlock(calculateBufferData(), ^{
            tonePlayedCompletionBlock();
        });
    };
    audioBufferCreatedCompletionBlock();
};

- (BOOL)play
{
    if ([self.audioEngine isRunning])
    {
        [self.playerNode pause];
        
        [self.audioEngine pause];
        
        [self.audioEngine detachNode:self.playerNode];
        self.playerNode = nil;
        
        [self.audioEngine detachNode:self.reverb];
        self.reverb = nil;
        
        [self.audioEngine detachNode:self.mixerNode];
        self.mixerNode = nil;
        
        [self.audioEngine stop];
    } else {
        [self setupEngine];
        self.playerNode = [[AVAudioPlayerNode alloc] init];
        [self.playerNode setRenderingAlgorithm:AVAudio3DMixingRenderingAlgorithmAuto];
        [self.playerNode setSourceMode:AVAudio3DMixingSourceModeAmbienceBed];
        [self.playerNode setPosition:AVAudioMake3DPoint(0.0, 0.0, 0.0)];
        
        self.mixerNode = [[AVAudioMixerNode alloc] init];
        
        self.reverb = [[AVAudioUnitReverb alloc] init];
        [self.reverb loadFactoryPreset:AVAudioUnitReverbPresetLargeChamber];
        [self.reverb setWetDryMix:50.0];
        
        [self.audioEngine attachNode:self.reverb];
        [self.audioEngine attachNode:self.playerNode];
        [self.audioEngine attachNode:self.mixerNode];
        
        [self.audioEngine connect:self.playerNode     to:self.mixerNode  format:self.audioFormat];
        [self.audioEngine connect:self.mixerNode      to:self.reverb      format:self.audioFormat];
        [self.audioEngine connect:self.reverb         to:self.mainNode    format:self.audioFormat];
        
        if ([self startEngine])
        {
            if (![self.playerNode isPlaying]) [self.playerNode play];
            
            createAudioBuffer([AVAudioSession sharedInstance], self.audioFormat, ^(AVAudioPCMBuffer * audio_buffer, PlayedToneCompletionBlock playedToneCompletionBlock) {
                [self.playerNode scheduleBuffer:audio_buffer atTime:nil options:AVAudioPlayerNodeBufferInterruptsAtLoop completionCallbackType:AVAudioPlayerNodeCompletionDataPlayedBack completionHandler:^(AVAudioPlayerNodeCompletionCallbackType callbackType) {
                    if (callbackType == AVAudioPlayerNodeCompletionDataPlayedBack)
                    {
                        playedToneCompletionBlock();
                    }
                }];
            });
            
            return TRUE;
        }
    }
    
    return FALSE;
}

@end



