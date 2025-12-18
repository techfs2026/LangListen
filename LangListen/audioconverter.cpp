#include "audioconverter.h"
#include <QFileInfo>
#include <QDir>
#include <fstream>
#include <cstring>

AudioConverter::AudioConverter(QObject* parent)
    : QObject(parent)
    , m_formatContext(nullptr)
    , m_codecContext(nullptr)
    , m_swrContext(nullptr)
    , m_audioStreamIndex(-1)
{
}

AudioConverter::~AudioConverter()
{
    cleanup();
}

bool AudioConverter::isFFmpegAvailable()
{
    return true;
}

void AudioConverter::cleanup()
{
    if (m_swrContext) {
        swr_free(&m_swrContext);
        m_swrContext = nullptr;
    }

    if (m_codecContext) {
        avcodec_free_context(&m_codecContext);
        m_codecContext = nullptr;
    }

    if (m_formatContext) {
        avformat_close_input(&m_formatContext);
        m_formatContext = nullptr;
    }

    m_audioStreamIndex = -1;
}

bool AudioConverter::openInputFile(const QString& inputPath)
{
    QFileInfo fileInfo(inputPath);
    if (!fileInfo.exists()) {
        m_lastError = QString("Input file does not exist: %1").arg(inputPath);
        emit logMessage("Error: " + m_lastError);
        return false;
    }

    m_formatContext = nullptr;
    if (avformat_open_input(&m_formatContext, inputPath.toUtf8().constData(), nullptr, nullptr) < 0) {
        m_lastError = "Failed to open input file";
        emit logMessage("Error: " + m_lastError);
        return false;
    }

    if (avformat_find_stream_info(m_formatContext, nullptr) < 0) {
        m_lastError = "Failed to find stream information";
        emit logMessage("Error: " + m_lastError);
        avformat_close_input(&m_formatContext);
        return false;
    }

    m_audioStreamIndex = -1;
    for (unsigned int i = 0; i < m_formatContext->nb_streams; i++) {
        if (m_formatContext->streams[i]->codecpar->codec_type == AVMEDIA_TYPE_AUDIO) {
            m_audioStreamIndex = i;
            break;
        }
    }

    if (m_audioStreamIndex == -1) {
        m_lastError = "No audio stream found in file";
        emit logMessage("Error: " + m_lastError);
        avformat_close_input(&m_formatContext);
        return false;
    }

    return true;
}

bool AudioConverter::initDecoder()
{
    AVCodecParameters* codecParams = m_formatContext->streams[m_audioStreamIndex]->codecpar;

    const AVCodec* codec = avcodec_find_decoder(codecParams->codec_id);
    if (!codec) {
        m_lastError = "Codec not found";
        emit logMessage("Error: " + m_lastError);
        return false;
    }

    m_codecContext = avcodec_alloc_context3(codec);
    if (!m_codecContext) {
        m_lastError = "Failed to allocate codec context";
        emit logMessage("Error: " + m_lastError);
        return false;
    }

    if (avcodec_parameters_to_context(m_codecContext, codecParams) < 0) {
        m_lastError = "Failed to copy codec parameters";
        emit logMessage("Error: " + m_lastError);
        avcodec_free_context(&m_codecContext);
        return false;
    }

    if (avcodec_open2(m_codecContext, codec, nullptr) < 0) {
        m_lastError = "Failed to open codec";
        emit logMessage("Error: " + m_lastError);
        avcodec_free_context(&m_codecContext);
        return false;
    }

    emit logMessage(QString("Input audio: %1Hz, %2 channels, format: %3")
        .arg(m_codecContext->sample_rate)
        .arg(m_codecContext->ch_layout.nb_channels)
        .arg(av_get_sample_fmt_name(m_codecContext->sample_fmt)));

    return true;
}

bool AudioConverter::initResampler(const ConversionParams& params)
{
    int ret;

    m_swrContext = swr_alloc();
    if (!m_swrContext) {
        m_lastError = "Failed to allocate resampler";
        emit logMessage("Error: " + m_lastError);
        return false;
    }

    AVChannelLayout outChannelLayout = AV_CHANNEL_LAYOUT_MONO;
    if (params.targetChannels == 2) {
        outChannelLayout = AV_CHANNEL_LAYOUT_STEREO;
    }

    av_opt_set_chlayout(m_swrContext, "in_chlayout", &m_codecContext->ch_layout, 0);
    av_opt_set_int(m_swrContext, "in_sample_rate", m_codecContext->sample_rate, 0);
    av_opt_set_sample_fmt(m_swrContext, "in_sample_fmt", m_codecContext->sample_fmt, 0);

    av_opt_set_chlayout(m_swrContext, "out_chlayout", &outChannelLayout, 0);
    av_opt_set_int(m_swrContext, "out_sample_rate", params.targetSampleRate, 0);
    av_opt_set_sample_fmt(m_swrContext, "out_sample_fmt", params.targetFormat, 0);

    ret = swr_init(m_swrContext);
    if (ret < 0) {
        m_lastError = "Failed to initialize resampler";
        emit logMessage("Error: " + m_lastError);
        swr_free(&m_swrContext);
        return false;
    }

    emit logMessage(QString("Resampler initialized: %1Hz → %2Hz, %3 → %4 channels")
        .arg(m_codecContext->sample_rate)
        .arg(params.targetSampleRate)
        .arg(m_codecContext->ch_layout.nb_channels)
        .arg(params.targetChannels));

    return true;
}

void AudioConverter::emitProgress(int64_t current, int64_t total)
{
    if (total > 0) {
        int progress = static_cast<int>((current * 100) / total);
        emit conversionProgress(progress);
    }
}

bool AudioConverter::decodeAndResample(std::vector<float>& audioData, const ConversionParams& params)
{
    AVPacket* packet = av_packet_alloc();
    AVFrame* frame = av_frame_alloc();
    AVFrame* resampledFrame = av_frame_alloc();

    if (!packet || !frame || !resampledFrame) {
        m_lastError = "Failed to allocate packet/frame";
        emit logMessage("Error: " + m_lastError);
        if (packet) av_packet_free(&packet);
        if (frame) av_frame_free(&frame);
        if (resampledFrame) av_frame_free(&resampledFrame);
        return false;
    }

    audioData.clear();

    int64_t totalDuration = m_formatContext->streams[m_audioStreamIndex]->duration;
    int64_t currentPts = 0;

    while (av_read_frame(m_formatContext, packet) >= 0) {
        if (packet->stream_index == m_audioStreamIndex) {
            if (avcodec_send_packet(m_codecContext, packet) >= 0) {
                while (avcodec_receive_frame(m_codecContext, frame) >= 0) {
                    currentPts = frame->pts;
                    emitProgress(currentPts, totalDuration);

                    int outSamples = av_rescale_rnd(
                        swr_get_delay(m_swrContext, m_codecContext->sample_rate) + frame->nb_samples,
                        params.targetSampleRate,
                        m_codecContext->sample_rate,
                        AV_ROUND_UP
                    );

                    uint8_t* outBuffer = nullptr;
                    int outLinesize;
                    av_samples_alloc(&outBuffer, &outLinesize, params.targetChannels,
                        outSamples, params.targetFormat, 0);

                    int convertedSamples = swr_convert(
                        m_swrContext,
                        &outBuffer, outSamples,
                        (const uint8_t**)frame->data, frame->nb_samples
                    );

                    if (convertedSamples > 0) {
                        int16_t* samples = reinterpret_cast<int16_t*>(outBuffer);
                        for (int i = 0; i < convertedSamples * params.targetChannels; i++) {
                            audioData.push_back(samples[i] / 32768.0f);
                        }
                    }

                    av_freep(&outBuffer);
                }
            }
        }
        av_packet_unref(packet);
    }

    avcodec_send_packet(m_codecContext, nullptr);
    while (avcodec_receive_frame(m_codecContext, frame) >= 0) {
        int outSamples = av_rescale_rnd(
            swr_get_delay(m_swrContext, m_codecContext->sample_rate) + frame->nb_samples,
            params.targetSampleRate,
            m_codecContext->sample_rate,
            AV_ROUND_UP
        );

        uint8_t* outBuffer = nullptr;
        int outLinesize;
        av_samples_alloc(&outBuffer, &outLinesize, params.targetChannels,
            outSamples, params.targetFormat, 0);

        int convertedSamples = swr_convert(
            m_swrContext,
            &outBuffer, outSamples,
            (const uint8_t**)frame->data, frame->nb_samples
        );

        if (convertedSamples > 0) {
            int16_t* samples = reinterpret_cast<int16_t*>(outBuffer);
            for (int i = 0; i < convertedSamples * params.targetChannels; i++) {
                audioData.push_back(samples[i] / 32768.0f);
            }
        }

        av_freep(&outBuffer);
    }

    av_packet_free(&packet);
    av_frame_free(&frame);
    av_frame_free(&resampledFrame);

    emit logMessage(QString("Decoded %1 samples").arg(audioData.size()));

    return true;
}

bool AudioConverter::writeWavFile(const QString& outputPath, const std::vector<float>& audioData, const ConversionParams& params)
{
    std::ofstream file(outputPath.toStdString(), std::ios::binary);
    if (!file.is_open()) {
        m_lastError = "Failed to create output file";
        emit logMessage("Error: " + m_lastError);
        return false;
    }

    uint32_t dataSize = audioData.size() * 2;
    uint32_t fileSize = dataSize + 36;
    uint16_t audioFormat = 1;
    uint16_t numChannels = params.targetChannels;
    uint32_t sampleRate = params.targetSampleRate;
    uint16_t bitsPerSample = 16;
    uint32_t byteRate = sampleRate * numChannels * bitsPerSample / 8;
    uint16_t blockAlign = numChannels * bitsPerSample / 8;

    file.write("RIFF", 4);
    file.write(reinterpret_cast<const char*>(&fileSize), 4);
    file.write("WAVE", 4);

    file.write("fmt ", 4);
    uint32_t fmtSize = 16;
    file.write(reinterpret_cast<const char*>(&fmtSize), 4);
    file.write(reinterpret_cast<const char*>(&audioFormat), 2);
    file.write(reinterpret_cast<const char*>(&numChannels), 2);
    file.write(reinterpret_cast<const char*>(&sampleRate), 4);
    file.write(reinterpret_cast<const char*>(&byteRate), 4);
    file.write(reinterpret_cast<const char*>(&blockAlign), 2);
    file.write(reinterpret_cast<const char*>(&bitsPerSample), 2);

    file.write("data", 4);
    file.write(reinterpret_cast<const char*>(&dataSize), 4);

    for (float sample : audioData) {
        int16_t intSample = static_cast<int16_t>(sample * 32767.0f);
        file.write(reinterpret_cast<const char*>(&intSample), 2);
    }

    file.close();

    emit logMessage(QString("WAV file written: %1").arg(outputPath));

    return true;
}

bool AudioConverter::convertToMemory(const QString& inputPath, std::vector<float>& audioData, const ConversionParams& params)
{
    emit conversionStarted();
    emit logMessage(QString("Converting: %1").arg(inputPath));
    emit logMessage(QString("Target: %1Hz, %2 channel(s)")
        .arg(params.targetSampleRate)
        .arg(params.targetChannels));

    cleanup();

    if (!openInputFile(inputPath)) {
        cleanup();
        emit conversionFailed(m_lastError);
        return false;
    }

    if (!initDecoder()) {
        cleanup();
        emit conversionFailed(m_lastError);
        return false;
    }

    if (!initResampler(params)) {
        cleanup();
        emit conversionFailed(m_lastError);
        return false;
    }

    if (!decodeAndResample(audioData, params)) {
        cleanup();
        emit conversionFailed(m_lastError);
        return false;
    }

    cleanup();

    float duration = audioData.size() / (float)params.targetSampleRate / params.targetChannels;
    emit logMessage(QString("Conversion completed: %1 seconds").arg(duration, 0, 'f', 2));

    return true;
}

bool AudioConverter::convert(const QString& inputPath, const QString& outputPath, const ConversionParams& params)
{
    std::vector<float> audioData;

    if (!convertToMemory(inputPath, audioData, params)) {
        return false;
    }

    if (!writeWavFile(outputPath, audioData, params)) {
        emit conversionFailed(m_lastError);
        return false;
    }

    emit conversionCompleted(outputPath);
    return true;
}