#import "CShareAudio.h"

#import <mach/mach_time.h>
#import <stdatomic.h>

@implementation ShareAudioDevice {
    id<RTCAudioDeviceDelegate> _delegate;
    RTCAudioDeviceDeliverRecordedDataBlock _deliver;
    RTCAudioDeviceGetPlayoutDataBlock _playout;
    atomic_bool _initialized;
    atomic_bool _playoutInitialized;
    atomic_bool _playing;
    atomic_bool _recordingInitialized;
    atomic_bool _recording;
    Float64 _recordedFrames;
    Float64 _playedFrames;
}

- (double)deviceInputSampleRate { return 48000; }
- (NSTimeInterval)inputIOBufferDuration { return 0.01; }
- (NSInteger)inputNumberOfChannels { return 2; }
- (NSTimeInterval)inputLatency { return 0; }
- (double)deviceOutputSampleRate { return 48000; }
- (NSTimeInterval)outputIOBufferDuration { return 0.01; }
- (NSInteger)outputNumberOfChannels { return 2; }
- (NSTimeInterval)outputLatency { return 0; }

- (BOOL)isInitialized { return atomic_load(&_initialized); }
- (BOOL)isPlayoutInitialized { return atomic_load(&_playoutInitialized); }
- (BOOL)isPlaying { return atomic_load(&_playing); }
- (BOOL)isRecordingInitialized { return atomic_load(&_recordingInitialized); }
- (BOOL)isRecording { return atomic_load(&_recording); }

- (BOOL)initializeWithDelegate:(id<RTCAudioDeviceDelegate>)delegate {
    @synchronized(self) {
        _delegate = delegate;
        _deliver = delegate.deliverRecordedData;
        _playout = delegate.getPlayoutData;
    }
    atomic_store(&_initialized, true);
    return YES;
}

- (BOOL)terminateDevice {
    atomic_store(&_playing, false);
    atomic_store(&_recording, false);
    atomic_store(&_playoutInitialized, false);
    atomic_store(&_recordingInitialized, false);
    atomic_store(&_initialized, false);
    return YES;
}

- (BOOL)initializePlayout { atomic_store(&_playoutInitialized, true); return YES; }
- (BOOL)startPlayout { atomic_store(&_playing, true); return YES; }
- (BOOL)stopPlayout { atomic_store(&_playing, false); return YES; }
- (BOOL)initializeRecording { atomic_store(&_recordingInitialized, true); return YES; }
- (BOOL)startRecording { atomic_store(&_recording, true); return YES; }
- (BOOL)stopRecording { atomic_store(&_recording, false); return YES; }

static AudioTimeStamp ShareTimeStamp(Float64 sampleTime) {
    AudioTimeStamp stamp = {0};
    stamp.mSampleTime = sampleTime;
    stamp.mHostTime = mach_absolute_time();
    stamp.mFlags = kAudioTimeStampSampleTimeValid | kAudioTimeStampHostTimeValid;
    return stamp;
}

- (BOOL)record:(const int16_t *)samples frames:(UInt32)frames {
    if (!atomic_load(&_recording) || frames == 0) return NO;
    RTCAudioDeviceDeliverRecordedDataBlock deliver;
    @synchronized(self) { deliver = _deliver; }
    if (!deliver) return NO;
    AudioUnitRenderActionFlags flags = 0;
    AudioTimeStamp stamp = ShareTimeStamp(_recordedFrames);
    _recordedFrames += frames;
    // Through the render block, not `inputData`: the module reads a filled buffer as mono-sized
    // (frames samples), but sizes its own buffer for both channels before rendering into it.
    deliver(&flags, &stamp, 1, frames, NULL, NULL,
            ^OSStatus(AudioUnitRenderActionFlags *actionFlags, const AudioTimeStamp *timestamp, NSInteger bus,
                      UInt32 frameCount, AudioBufferList *inputData, void *context) {
                AudioBuffer *buffer = &inputData->mBuffers[0];
                size_t wanted = (size_t)frameCount * 2 * sizeof(int16_t);
                size_t room = buffer->mDataByteSize;
                memcpy(buffer->mData, samples, MIN(wanted, room));
                if (room > wanted) memset((uint8_t *)buffer->mData + wanted, 0, room - wanted);
                return noErr;
            });
    return YES;
}

- (BOOL)pull:(int16_t *)samples frames:(UInt32)frames {
    RTCAudioDeviceGetPlayoutDataBlock playout;
    @synchronized(self) { playout = _playout; }
    if (!atomic_load(&_playing) || !playout) {
        memset(samples, 0, (size_t)frames * 2 * sizeof(int16_t));
        return NO;
    }
    AudioBufferList list;
    list.mNumberBuffers = 1;
    list.mBuffers[0].mNumberChannels = 2;
    list.mBuffers[0].mDataByteSize = frames * 2 * sizeof(int16_t);
    list.mBuffers[0].mData = samples;
    AudioUnitRenderActionFlags flags = 0;
    AudioTimeStamp stamp = ShareTimeStamp(_playedFrames);
    _playedFrames += frames;
    playout(&flags, &stamp, 0, frames, &list);
    return YES;
}

@end

RTCPeerConnectionFactory *ShareAudioFactory(ShareAudioDevice *device) {
    return [[RTCPeerConnectionFactory alloc] initWithEncoderFactory:[[RTCDefaultVideoEncoderFactory alloc] init]
                                                     decoderFactory:[[RTCDefaultVideoDecoderFactory alloc] init]
                                                        audioDevice:(id)device];
}
