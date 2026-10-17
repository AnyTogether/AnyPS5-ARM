#ifndef CORE_LIBS_PRX_LIBSCEOPUSDEC_INCLUDE_OPUSDECODER_HPP
#define CORE_LIBS_PRX_LIBSCEOPUSDEC_INCLUDE_OPUSDECODER_HPP

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <limits>
#include <memory>
#include <mutex>
#include <stdexcept>
#include <string>
#include <unordered_map>
#include <utility>
#include <vector>

extern "C" {
#include <libavcodec/avcodec.h>
#include <libswresample/swresample.h>
}

namespace {

class OpusDecoderLibrary {
public:
    OpusDecoderLibrary(const char* libraryName, bool celtPacketsOnly) : name(libraryName), celtOnly(celtPacketsOnly) {}

    int Initialize(std::uint32_t* context) {
        if (!context) fail("null context output");
        std::lock_guard lock(mutex);
        for (const auto& [id, owner] : contexts)
            if (owner == context) fail("context already initialized");
        if (nextContext == 0) fail("context identifiers exhausted");
        const auto id = nextContext++;
        contexts.emplace(id, context);
        *context = id;
        return 0;
    }

    int Terminate(std::uint32_t* context) {
        if (!context) fail("null context");
        std::lock_guard lock(mutex);
        if (!contexts.contains(*context)) fail("unknown context");
        for (const auto& [state, decoder] : decoders)
            if (decoder->context == *context) fail("termination with live decoders is not implemented");
        contexts.erase(*context);
        return 0;
    }

    int GetSize(int channels) {
        if (channels != 1 && channels != 2) fail("only mono and stereo are supported");
        return 640;
    }

    int CreateEx(std::uint32_t* context, void* state, int sampleRate, int channels) {
        if (!context || !state) fail("null context or state");
        GetSize(channels);
        if (sampleRate != 8000 && sampleRate != 12000 && sampleRate != 16000 && sampleRate != 24000 && sampleRate != 48000)
            fail("sample rates other than 8000, 12000, 16000, 24000 and 48000 Hz are not supported");
        std::lock_guard lock(mutex);
        if (!contexts.contains(*context)) fail("unknown context");
        if (decoders.contains(state)) fail("state already owns a decoder");
        auto decoder = std::make_unique<Decoder>();
        decoder->context = *context;
        decoder->channels = channels;
        decoder->sampleRate = sampleRate;
        const auto* codec = avcodec_find_decoder(AV_CODEC_ID_OPUS);
        if (!codec) fail("FFmpeg Opus decoder unavailable");
        decoder->codec = avcodec_alloc_context3(codec);
        if (!decoder->codec) throw std::bad_alloc();
        av_channel_layout_default(&decoder->codec->ch_layout, channels);
        decoder->codec->sample_rate = 48000;
        if (avcodec_open2(decoder->codec, codec, nullptr) < 0) fail("cannot open FFmpeg decoder");
        if (sampleRate != 48000) {
            AVChannelLayout layout{};
            av_channel_layout_default(&layout, channels);
            if (swr_alloc_set_opts2(&decoder->resampler, &layout, AV_SAMPLE_FMT_FLT, sampleRate, &layout, AV_SAMPLE_FMT_FLT, 48000, 0, nullptr) < 0 ||
                swr_init(decoder->resampler) < 0)
                fail("cannot open FFmpeg resampler");
        }
        decoders.emplace(state, std::move(decoder));
        return 0;
    }

    int Decode(void* state, const std::uint8_t* data, int bytes, std::int16_t* pcm, int capacity) {
        if (!data || bytes <= 0 || bytes > std::numeric_limits<int>::max() - AV_INPUT_BUFFER_PADDING_SIZE || !pcm || capacity < 0)
            fail("invalid packet or PCM buffer; packet loss concealment is not implemented");
        std::lock_guard lock(mutex);
        const auto found = decoders.find(state);
        if (found == decoders.end()) fail("unknown decoder state");
        auto& decoder = *found->second;
        if (celtOnly && (data[0] >> 3) < 16) fail("SILK and hybrid packets are not implemented");
        const int samples = packetSamples(data, bytes) / (48000 / decoder.sampleRate);
        const int outputBytes = samples * decoder.channels * 2;
        if (capacity / 2 * 2 < outputBytes) fail("PCM buffer is too small");
        std::unique_ptr<AVPacket, void (*)(AVPacket*)> packet(av_packet_alloc(), [](AVPacket* p) { av_packet_free(&p); });
        std::unique_ptr<AVFrame, void (*)(AVFrame*)> frame(av_frame_alloc(), [](AVFrame* f) { av_frame_free(&f); });
        if (!packet || !frame || av_new_packet(packet.get(), bytes) < 0) throw std::bad_alloc();
        std::memcpy(packet->data, data, bytes);
        if (avcodec_send_packet(decoder.codec, packet.get()) < 0 || avcodec_receive_frame(decoder.codec, frame.get()) < 0)
            fail("FFmpeg rejected the packet");
        const auto format = static_cast<AVSampleFormat>(frame->format);
        if (frame->ch_layout.nb_channels != decoder.channels || frame->sample_rate != 48000 ||
            (format != AV_SAMPLE_FMT_FLTP && format != AV_SAMPLE_FMT_FLT))
            fail("unexpected FFmpeg PCM format");
        std::vector<float> decoded;
        decoded.reserve(static_cast<std::size_t>(frame->nb_samples) * decoder.channels);
        for (int sample = 0; sample < frame->nb_samples; ++sample) {
            for (int channel = 0; channel < decoder.channels; ++channel) {
                const auto* source = reinterpret_cast<const float*>(frame->extended_data[format == AV_SAMPLE_FMT_FLTP ? channel : 0]);
                decoded.push_back(source[format == AV_SAMPLE_FMT_FLTP ? sample : sample * decoder.channels + channel]);
            }
        }
        if (decoder.resampler) {
            const int capacitySamples = swr_get_out_samples(decoder.resampler, frame->nb_samples);
            if (capacitySamples < 0) fail("FFmpeg resampler rejected the frame");
            std::vector<float> resampled(static_cast<std::size_t>(capacitySamples) * decoder.channels);
            auto* output = reinterpret_cast<std::uint8_t*>(resampled.data());
            const auto* input = reinterpret_cast<const std::uint8_t*>(decoded.data());
            const int converted = swr_convert(decoder.resampler, &output, capacitySamples, &input, frame->nb_samples);
            if (converted < 0) fail("FFmpeg resampler rejected the frame");
            resampled.resize(static_cast<std::size_t>(converted) * decoder.channels);
            decoded = std::move(resampled);
        }
        decoder.pending.insert(decoder.pending.end(), decoded.begin(), decoded.end());
        const auto count = static_cast<std::size_t>(samples) * decoder.channels;
        if (decoder.pending.size() < count) decoder.pending.insert(decoder.pending.begin(), count - decoder.pending.size(), 0.0f);
        for (std::size_t index = 0; index < count; ++index) {
            const auto converted = static_cast<std::int16_t>(std::lrint(std::clamp(decoder.pending[index] * 32768.0f, -32768.0f, 32767.0f)));
            std::memcpy(reinterpret_cast<std::uint8_t*>(pcm) + index * 2, &converted, 2);
        }
        decoder.pending.erase(decoder.pending.begin(), decoder.pending.begin() + static_cast<std::ptrdiff_t>(count));
        return outputBytes;
    }

    int Destroy(void* state) {
        std::lock_guard lock(mutex);
        if (decoders.erase(state) == 0) fail("unknown decoder state");
        return 0;
    }

private:
    struct Decoder {
        std::uint32_t context;
        int channels;
        int sampleRate;
        AVCodecContext* codec = nullptr;
        SwrContext* resampler = nullptr;
        std::vector<float> pending;
        ~Decoder() {
            swr_free(&resampler);
            avcodec_free_context(&codec);
        }
    };

    const char* name;
    bool celtOnly;
    std::mutex mutex;
    std::unordered_map<std::uint32_t, std::uint32_t*> contexts;
    std::unordered_map<void*, std::unique_ptr<Decoder>> decoders;
    std::uint32_t nextContext = 1;

    [[noreturn]] void fail(const char* message) const {
        throw std::runtime_error(std::string(name) + ": " + message);
    }

    int packetSamples(const std::uint8_t* packet, int size) const {
        const unsigned config = packet[0] >> 3;
        const int frameSamples = config < 12 ? ((config & 3) == 3 ? 2880 : 480 << (config & 3))
                                : config < 16 ? 480 << (config & 1) : 120 << (config & 3);
        int frames = 1;
        switch (packet[0] & 3) {
        case 1:
        case 2: frames = 2; break;
        case 3:
            if (size < 2) fail("truncated packet frame count");
            frames = packet[1] & 63;
            break;
        }
        if (frames == 0 || frames * frameSamples > 5760) fail("invalid packet duration");
        return frames * frameSamples;
    }
};

} // namespace

#endif
