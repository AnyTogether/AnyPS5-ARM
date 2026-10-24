// Share play's audio device for WebRTC: the game's sound in as the "microphone" of the share
// play factory, the received sound out to whoever pulls it. No real device is ever opened.
//
// The RTCAudioDevice protocols below are WebRTC's (sdk/objc/components/audio/RTCAudioDevice.h,
// Copyright 2022 The WebRTC project authors, BSD-3-Clause). Google's macOS framework carries their
// implementation (ObjCAudioDeviceModule) but leaves the header out, so they are declared here with
// the same selectors.
#import <AudioToolbox/AudioToolbox.h>
#import <Foundation/Foundation.h>
#import <WebRTC/WebRTC.h>

NS_ASSUME_NONNULL_BEGIN

typedef OSStatus (^RTCAudioDeviceGetPlayoutDataBlock)(AudioUnitRenderActionFlags *_Nonnull actionFlags,
                                                     const AudioTimeStamp *_Nonnull timestamp,
                                                     NSInteger inputBusNumber, UInt32 frameCount,
                                                     AudioBufferList *_Nonnull outputData);

typedef OSStatus (^RTCAudioDeviceRenderRecordedDataBlock)(AudioUnitRenderActionFlags *_Nonnull actionFlags,
                                                         const AudioTimeStamp *_Nonnull timestamp,
                                                         NSInteger inputBusNumber, UInt32 frameCount,
                                                         AudioBufferList *_Nonnull inputData,
                                                         void *_Nullable renderContext);

typedef OSStatus (^RTCAudioDeviceDeliverRecordedDataBlock)(
    AudioUnitRenderActionFlags *_Nonnull actionFlags, const AudioTimeStamp *_Nonnull timestamp,
    NSInteger inputBusNumber, UInt32 frameCount, const AudioBufferList *_Nullable inputData,
    void *_Nullable renderContext, NS_NOESCAPE RTCAudioDeviceRenderRecordedDataBlock _Nullable renderBlock);

@protocol RTCAudioDeviceDelegate <NSObject>
@property(readonly, nonnull) RTCAudioDeviceDeliverRecordedDataBlock deliverRecordedData;
@property(readonly) double preferredInputSampleRate;
@property(readonly) NSTimeInterval preferredInputIOBufferDuration;
@property(readonly) double preferredOutputSampleRate;
@property(readonly) NSTimeInterval preferredOutputIOBufferDuration;
@property(readonly, nonnull) RTCAudioDeviceGetPlayoutDataBlock getPlayoutData;
- (void)notifyAudioInputParametersChange;
- (void)notifyAudioOutputParametersChange;
- (void)notifyAudioInputInterrupted;
- (void)notifyAudioOutputInterrupted;
- (void)dispatchAsync:(dispatch_block_t)block;
- (void)dispatchSync:(dispatch_block_t)block;
@end

@protocol RTCAudioDevice <NSObject>
@property(readonly) double deviceInputSampleRate;
@property(readonly) NSTimeInterval inputIOBufferDuration;
@property(readonly) NSInteger inputNumberOfChannels;
@property(readonly) NSTimeInterval inputLatency;
@property(readonly) double deviceOutputSampleRate;
@property(readonly) NSTimeInterval outputIOBufferDuration;
@property(readonly) NSInteger outputNumberOfChannels;
@property(readonly) NSTimeInterval outputLatency;
@property(readonly) BOOL isInitialized;
- (BOOL)initializeWithDelegate:(id<RTCAudioDeviceDelegate>)delegate;
- (BOOL)terminateDevice;
@property(readonly) BOOL isPlayoutInitialized;
- (BOOL)initializePlayout;
@property(readonly) BOOL isPlaying;
- (BOOL)startPlayout;
- (BOOL)stopPlayout;
@property(readonly) BOOL isRecordingInitialized;
- (BOOL)initializeRecording;
@property(readonly) BOOL isRecording;
- (BOOL)startRecording;
- (BOOL)stopRecording;
@end

/// 48 kHz 16-bit stereo both ways. Sound handed to `record` reaches every audio track of the
/// factory made with this device while WebRTC records (some connection sends audio); `pull` gives
/// the mix of what the factory's connections receive, or silence while nothing plays.
@interface ShareAudioDevice : NSObject <RTCAudioDevice>
/// Interleaved stereo; from one thread (the capture's) at a time. NO while WebRTC is not recording.
- (BOOL)record:(const int16_t *)samples frames:(UInt32)frames;
/// Interleaved stereo into `samples`; NO (and silence) while WebRTC is not playing.
- (BOOL)pull:(int16_t *)samples frames:(UInt32)frames;
@end

/// A peer connection factory (H.264 on VideoToolbox first, as RTCDefault*Factory) whose audio goes
/// through `device`.
RTCPeerConnectionFactory *ShareAudioFactory(ShareAudioDevice *device);

NS_ASSUME_NONNULL_END
