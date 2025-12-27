#include "ffmpegaudioengine.h"
#include "audioringbuffer.h"
#include <QDebug>
#include <QMutexLocker>
#include <QtMath>
#include <cstring>

#define ENABLE_DECODER_LOG 0

#if ENABLE_DECODER_LOG
#define LOG_DECODER qDebug() << "[DECODER]"
#else
#define LOG_DECODER QNoDebug()
#endif

#define LOG_ENGINE qDebug() << "[ENGINE]"
#define LOG_CLOCK qDebug() << "[CLOCK]"
#define LOG_PA qDebug() << "[PORTAUDIO]"

FFmpegDecoder::FFmpegDecoder(AudioRingBuffer* ringBuffer, QObject* parent)
    : QThread(parent)
    , m_formatCtx(nullptr)
    , m_codecCtx(nullptr)
    , m_swrCtx(nullptr)
    , m_audioStreamIndex(-1)
    , m_duration(0)
    , m_sampleRate(0)
    , m_channels(0)
    , m_ringBuffer(ringBuffer)
    , m_running(true)
    , m_decoding(false)
    , m_pauseRequested(false)
    , m_seekRequested(false)
    , m_seekTargetMs(0)
{
    start();
    LOG_DECODER << "Decoder thread created and started";
}

FFmpegDecoder::~FFmpegDecoder()
{
    LOG_DECODER << "Decoder destructor called";
    m_running = false;
    m_decoding = false;
    if (m_ringBuffer) {
        m_ringBuffer->cancel();
    }
    if (isRunning()) {
        wait(2000);
        if (isRunning()) {
            LOG_DECODER << "Force terminating decoder thread";
            terminate();
            wait();
        }
    }
    close();
}

bool FFmpegDecoder::openFile(const QString& filePath)
{
    close();

    m_formatCtx = nullptr;
    int ret = avformat_open_input(&m_formatCtx, filePath.toUtf8().constData(), nullptr, nullptr);
    if (ret < 0) {
        emit errorOccurred(QString("Failed to open file: %1").arg(getErrorString(ret)));
        return false;
    }

    ret = avformat_find_stream_info(m_formatCtx, nullptr);
    if (ret < 0) {
        emit errorOccurred("Failed to find stream info");
        cleanupDecoder();
        return false;
    }

    m_audioStreamIndex = -1;
    for (unsigned int i = 0; i < m_formatCtx->nb_streams; i++) {
        if (m_formatCtx->streams[i]->codecpar->codec_type == AVMEDIA_TYPE_AUDIO) {
            m_audioStreamIndex = i;
            break;
        }
    }

    if (m_audioStreamIndex == -1) {
        emit errorOccurred("No audio stream found");
        cleanupDecoder();
        return false;
    }

    if (!initDecoder()) {
        cleanupDecoder();
        return false;
    }

    AVStream* audioStream = m_formatCtx->streams[m_audioStreamIndex];
    if (audioStream->duration != AV_NOPTS_VALUE) {
        m_duration = av_rescale_q(audioStream->duration, audioStream->time_base, { 1, 1000 });
    }
    else if (m_formatCtx->duration != AV_NOPTS_VALUE) {
        m_duration = m_formatCtx->duration / 1000;
    }
    else {
        m_duration = 0;
    }

    LOG_DECODER << "File opened: duration=" << m_duration << "ms, sampleRate="
        << m_sampleRate << "Hz, channels=" << m_channels;

    emit durationChanged(m_duration);
    return true;
}

bool FFmpegDecoder::initDecoder()
{
    AVCodecParameters* codecParams = m_formatCtx->streams[m_audioStreamIndex]->codecpar;

    const AVCodec* codec = avcodec_find_decoder(codecParams->codec_id);
    if (!codec) {
        emit errorOccurred("Codec not found");
        return false;
    }

    m_codecCtx = avcodec_alloc_context3(codec);
    if (!m_codecCtx) {
        emit errorOccurred("Failed to allocate codec context");
        return false;
    }

    int ret = avcodec_parameters_to_context(m_codecCtx, codecParams);
    if (ret < 0) {
        emit errorOccurred("Failed to copy codec parameters");
        avcodec_free_context(&m_codecCtx);
        return false;
    }

    ret = avcodec_open2(m_codecCtx, codec, nullptr);
    if (ret < 0) {
        emit errorOccurred("Failed to open codec");
        avcodec_free_context(&m_codecCtx);
        return false;
    }

    m_sampleRate = m_codecCtx->sample_rate;
    m_channels = m_codecCtx->ch_layout.nb_channels;

    LOG_DECODER << "Decoder initialized: codec=" << codec->name;

    if (!initResampler()) {
        avcodec_free_context(&m_codecCtx);
        return false;
    }

    return true;
}

bool FFmpegDecoder::initResampler()
{
    AVChannelLayout outChannelLayout;
    if (m_channels == 1) {
        av_channel_layout_default(&outChannelLayout, 1);
    }
    else {
        av_channel_layout_default(&outChannelLayout, 2);
    }

    int ret = swr_alloc_set_opts2(
        &m_swrCtx,
        &outChannelLayout,
        AV_SAMPLE_FMT_S16,
        m_sampleRate,
        &m_codecCtx->ch_layout,
        m_codecCtx->sample_fmt,
        m_codecCtx->sample_rate,
        0,
        nullptr
    );

    av_channel_layout_uninit(&outChannelLayout);

    if (ret < 0) {
        emit errorOccurred("Failed to allocate resampler");
        return false;
    }

    ret = swr_init(m_swrCtx);
    if (ret < 0) {
        emit errorOccurred("Failed to initialize resampler");
        swr_free(&m_swrCtx);
        return false;
    }

    LOG_DECODER << "Resampler initialized";
    return true;
}

void FFmpegDecoder::cleanupResampler()
{
    if (m_swrCtx) {
        swr_free(&m_swrCtx);
        m_swrCtx = nullptr;
    }
}

void FFmpegDecoder::cleanupDecoder()
{
    if (m_codecCtx) {
        avcodec_free_context(&m_codecCtx);
        m_codecCtx = nullptr;
    }

    if (m_formatCtx) {
        avformat_close_input(&m_formatCtx);
        m_formatCtx = nullptr;
    }

    m_audioStreamIndex = -1;
}

void FFmpegDecoder::close()
{
    cleanupResampler();
    cleanupDecoder();
}

void FFmpegDecoder::seekTo(qint64 positionMs)
{
    m_seekTargetMs = positionMs;
    m_seekRequested = true;
}

void FFmpegDecoder::startDecoding()
{
    m_decoding = true;
    m_pauseRequested = false;
    LOG_DECODER << "Decoding started";
}

void FFmpegDecoder::stopDecoding()
{
    m_decoding = false;
    LOG_DECODER << "Decoding stopped";
}

void FFmpegDecoder::pauseDecoding()
{
    m_pauseRequested = true;
    LOG_DECODER << "Decoding paused";
}

void FFmpegDecoder::resumeDecoding()
{
    m_pauseRequested = false;
    LOG_DECODER << "Decoding resumed";
}

bool FFmpegDecoder::performSeek(qint64 targetMs)
{
    if (!m_formatCtx || m_audioStreamIndex < 0) {
        return false;
    }

    AVStream* stream = m_formatCtx->streams[m_audioStreamIndex];
    int64_t targetPts = av_rescale_q(targetMs, { 1, 1000 }, stream->time_base);

    int ret = av_seek_frame(m_formatCtx, m_audioStreamIndex, targetPts, AVSEEK_FLAG_BACKWARD);
    if (ret < 0) {
        LOG_DECODER << "Seek failed:" << getErrorString(ret);
        return false;
    }

    avcodec_flush_buffers(m_codecCtx);

    LOG_DECODER << "Seek to" << targetMs << "ms completed";
    return true;
}

bool FFmpegDecoder::resampleFrame(AVFrame* frame, QByteArray& outData)
{
    if (!m_swrCtx) {
        return false;
    }

    int outSamples = av_rescale_rnd(
        swr_get_delay(m_swrCtx, m_sampleRate) + frame->nb_samples,
        m_sampleRate,
        m_sampleRate,
        AV_ROUND_UP
    );

    int outChannels = (m_channels == 1) ? 1 : 2;
    int outBufferSize = outSamples * outChannels * sizeof(int16_t);
    outData.resize(outBufferSize);

    uint8_t* outBuffer = reinterpret_cast<uint8_t*>(outData.data());

    int convertedSamples = swr_convert(
        m_swrCtx,
        &outBuffer,
        outSamples,
        const_cast<const uint8_t**>(frame->data),
        frame->nb_samples
    );

    if (convertedSamples < 0) {
        return false;
    }

    int actualSize = convertedSamples * outChannels * sizeof(int16_t);
    outData.resize(actualSize);

    return true;
}

void FFmpegDecoder::run()
{
    LOG_DECODER << "Decoder thread loop started";

    AVPacket* packet = av_packet_alloc();
    AVFrame* frame = av_frame_alloc();

    if (!packet || !frame) {
        LOG_DECODER << "Failed to allocate packet or frame";
        if (packet) av_packet_free(&packet);
        if (frame) av_frame_free(&frame);
        return;
    }

    while (m_running) {
        if (!m_decoding) {
            QThread::msleep(10);
            continue;
        }

        if (m_pauseRequested) {
            QThread::msleep(10);
            continue;
        }

        if (m_seekRequested) {
            qint64 targetMs = m_seekTargetMs.load();
            m_seekRequested = false;

            LOG_DECODER << "Processing seek request to" << targetMs << "ms";

            m_ringBuffer->clear();

            if (performSeek(targetMs)) {
                LOG_DECODER << "Seek completed, resuming decoding";
            }
            else {
                LOG_DECODER << "Seek failed";
            }
            continue;
        }

        int ret = av_read_frame(m_formatCtx, packet);

        if (ret == AVERROR_EOF) {
            LOG_DECODER << "End of file reached";
            emit decodingFinished();
            av_packet_unref(packet);

            while (m_decoding && !m_seekRequested && m_running) {
                QThread::msleep(100);
            }
            continue;
        }

        if (ret < 0) {
            LOG_DECODER << "Read frame error:" << getErrorString(ret);
            QThread::msleep(10);
            continue;
        }

        if (packet->stream_index != m_audioStreamIndex) {
            av_packet_unref(packet);
            continue;
        }

        ret = avcodec_send_packet(m_codecCtx, packet);
        av_packet_unref(packet);

        if (ret < 0) {
            LOG_DECODER << "Send packet error:" << getErrorString(ret);
            continue;
        }

        while (ret >= 0 && m_running && m_decoding) {
            ret = avcodec_receive_frame(m_codecCtx, frame);

            if (ret == AVERROR(EAGAIN) || ret == AVERROR_EOF) {
                break;
            }

            if (ret < 0) {
                LOG_DECODER << "Receive frame error:" << getErrorString(ret);
                break;
            }

            QByteArray pcmData;
            if (resampleFrame(frame, pcmData)) {
                m_ringBuffer->write(pcmData);
                LOG_DECODER << "RingBuffer write buffer:" << pcmData.size();
            }

            av_frame_unref(frame);
        }
    }

    av_packet_free(&packet);
    av_frame_free(&frame);

    LOG_DECODER << "Decoder thread loop ended";
}

QString FFmpegDecoder::getErrorString(int errnum) const
{
    char errbuf[AV_ERROR_MAX_STRING_SIZE];
    av_strerror(errnum, errbuf, AV_ERROR_MAX_STRING_SIZE);
    return QString::fromUtf8(errbuf);
}

FFmpegAudioEngine::FFmpegAudioEngine(QObject* parent)
    : QObject(parent)
    , m_decoder(nullptr)
    , m_ringBuffer(nullptr)
    , m_paStream(nullptr)
    , m_sampleRate(0)
    , m_channels(0)
    , m_state(PlaybackState::Stopped)
    , m_duration(0)
    , m_volume(1.0)
    , m_volumeAtomic(1.0)
    , m_totalFramesPlayed(0)
    , m_seekPositionMs(0)
    , m_currentSentenceIndex(-1)
    , m_singleSentenceLoop(false)
    , m_autoPauseEnabled(false)
    , m_loopRangeEnabled(false)
    , m_loopStartMs(0)
    , m_loopEndMs(0)
    , m_decoderEOF(false)
{
    PaError err = Pa_Initialize();
    if (err != paNoError) {
        LOG_PA << "PortAudio initialization failed:" << Pa_GetErrorText(err);
    }
    else {
        LOG_PA << "PortAudio initialized successfully";
    }

    m_ringBuffer = new AudioRingBuffer(512 * 1024);
    m_decoder = new FFmpegDecoder(m_ringBuffer, this);

    connect(m_decoder, &FFmpegDecoder::errorOccurred,
        this, &FFmpegAudioEngine::onDecoderError);
    connect(m_decoder, &FFmpegDecoder::decodingFinished,
        this, &FFmpegAudioEngine::onDecoderFinished);
    connect(m_decoder, &FFmpegDecoder::durationChanged,
        this, [this](qint64 duration) {
            m_duration = duration;
            emit durationChanged();
        });

    m_positionTimer = new QTimer(this);
    m_positionTimer->setInterval(40);
    connect(m_positionTimer, &QTimer::timeout,
        this, &FFmpegAudioEngine::onPositionUpdateTimer);

    LOG_ENGINE << "FFmpegAudioEngine created with PortAudio";
}

FFmpegAudioEngine::~FFmpegAudioEngine()
{
    closeAudio();
    delete m_ringBuffer;
    Pa_Terminate();
    LOG_PA << "PortAudio terminated";
}

bool FFmpegAudioEngine::loadAudio(const QString& filePath)
{
    LOG_ENGINE << "Loading audio:" << filePath;

    stop();
    cleanupPortAudio();

    if (!m_decoder->openFile(filePath)) {
        emit audioLoaded(false, "Failed to open audio file");
        return false;
    }

    m_sampleRate = m_decoder->getSampleRate();
    m_channels = m_decoder->getChannels();

    if (!initPortAudio()) {
        emit audioLoaded(false, "Failed to initialize audio output");
        return false;
    }

    m_decoderEOF = false;
    m_currentSentenceIndex = -1;
    m_state = PlaybackState::Stopped;

    emit audioLoaded(true, "Audio loaded successfully");
    LOG_ENGINE << "Audio loaded successfully, duration:" << m_duration << "ms";

    return true;
}

void FFmpegAudioEngine::closeAudio()
{
    stop();
    cleanupPortAudio();
    m_decoder->close();
    m_sentences.clear();
    m_currentSentenceIndex = -1;
}

bool FFmpegAudioEngine::initPortAudio()
{
    cleanupPortAudio();

    PaStreamParameters outputParams;
    outputParams.device = Pa_GetDefaultOutputDevice();

    if (outputParams.device == paNoDevice) {
        LOG_PA << "No default output device";
        return false;
    }

    outputParams.channelCount = m_channels;
    outputParams.sampleFormat = paInt16;
    outputParams.suggestedLatency = Pa_GetDeviceInfo(outputParams.device)->defaultLowOutputLatency;
    outputParams.hostApiSpecificStreamInfo = nullptr;

    PaError err = Pa_OpenStream(
        &m_paStream,
        nullptr,
        &outputParams,
        m_sampleRate,
        256,
        paClipOff,
        &FFmpegAudioEngine::paCallback,
        this
    );

    if (err != paNoError) {
        LOG_PA << "Failed to open stream:" << Pa_GetErrorText(err);
        return false;
    }

    LOG_PA << "PortAudio stream opened: sampleRate=" << m_sampleRate
        << ", channels=" << m_channels
        << ", device=" << Pa_GetDeviceInfo(outputParams.device)->name;

    return true;
}

void FFmpegAudioEngine::cleanupPortAudio()
{
    if (m_paStream) {
        Pa_StopStream(m_paStream);
        Pa_CloseStream(m_paStream);
        m_paStream = nullptr;
        LOG_PA << "PortAudio stream closed";
    }
}

void FFmpegAudioEngine::play()
{
    LOG_ENGINE << "Play requested, current state:" << (int)m_state;

    if (m_state == PlaybackState::Playing) {
        return;
    }

    qint64 currentPos = position();
    if (currentPos >= m_duration - 100) {
        LOG_ENGINE << "At end position, restarting from beginning";
        performSeek(0);
    }
    else if (m_state == PlaybackState::Stopped) {
        if (m_currentSentenceIndex >= 0 && m_currentSentenceIndex < m_sentences.size()) {
            qint64 startMs = m_sentences[m_currentSentenceIndex].startTimeMs;
            performSeek(startMs);
        }
        else {
            performSeek(currentPos);
        }
    }

    startPlayback();
}

void FFmpegAudioEngine::pause()
{
    LOG_ENGINE << "Pause requested";

    if (m_state != PlaybackState::Playing) {
        return;
    }

    if (m_paStream) {
        Pa_StopStream(m_paStream);
    }

    m_decoder->pauseDecoding();
    m_positionTimer->stop();

    m_state = PlaybackState::Paused;
    emit isPlayingChanged();

    LOG_ENGINE << "Paused at position:" << position() << "ms";
}

void FFmpegAudioEngine::stop()
{
    LOG_ENGINE << "Stop requested, current state:" << (int)m_state
        << ", position:" << position() << "ms";

    bool shouldReset = true;

    if (m_state == PlaybackState::Stopped) {
        qint64 currentPos = position();

        if (currentPos >= m_duration - 100) {
            LOG_ENGINE << "At end, resetting to beginning";
            shouldReset = true;
        }
        else {
            LOG_ENGINE << "Already stopped, ignoring";
            return;
        }
    }
    else {
        stopPlayback();
        shouldReset = true;
    }

    if (shouldReset) {
        m_decoderEOF = false;
        m_seekPositionMs = 0;
        m_totalFramesPlayed = 0;
        m_currentSentenceIndex = -1;

        m_state = PlaybackState::Stopped;

        emit positionChanged();
        emit isPlayingChanged();

        LOG_ENGINE << "Stopped and reset to beginning";
    }
}

void FFmpegAudioEngine::seekTo(qint64 positionMs)
{
    LOG_ENGINE << "Seek to" << positionMs << "ms";

    positionMs = qBound(0LL, positionMs, m_duration);

    bool wasPlaying = (m_state == PlaybackState::Playing);

    if (wasPlaying) {
        stopPlayback();
    }

    performSeek(positionMs);

    if (wasPlaying) {
        startPlayback();
    }

    updateCurrentSentence();
}

void FFmpegAudioEngine::performSeek(qint64 targetMs)
{
    LOG_ENGINE << "Performing seek to" << targetMs << "ms";

    m_positionTimer->stop();

    m_ringBuffer->clear();
    m_ringBuffer->reset();

    {
        QMutexLocker locker(&m_seekMutex);
        m_seekPositionMs = targetMs;
        m_totalFramesPlayed = 0;
    }

    m_decoder->seekTo(targetMs);
    m_decoderEOF = false;

    emit positionChanged();
}

void FFmpegAudioEngine::startPlayback()
{
    LOG_ENGINE << "Starting playback";

    if (!m_paStream) {
        LOG_ENGINE << "PortAudio stream not initialized";
        emit errorOccurred("Audio output not initialized");
        return;
    }

    m_decoderEOF = false;
    m_ringBuffer->reset();

    if (m_state == PlaybackState::Paused) {
        m_decoder->resumeDecoding();
    }
    else {
        m_decoder->startDecoding();
    }

    PaError err = Pa_StartStream(m_paStream);
    if (err != paNoError) {
        LOG_PA << "Failed to start stream:" << Pa_GetErrorText(err);
        emit errorOccurred("Failed to start audio playback");
        return;
    }

    m_positionTimer->start();

    m_state = PlaybackState::Playing;
    emit isPlayingChanged();

    LOG_ENGINE << "Playback started, position:" << getAudioClockMs() << "ms";
}

void FFmpegAudioEngine::stopPlayback()
{
    LOG_ENGINE << "Stopping playback";

    m_positionTimer->stop();

    m_ringBuffer->cancel();
    m_decoder->stopDecoding();

    if (m_paStream) {
        Pa_StopStream(m_paStream);
    }

    m_ringBuffer->clear();
    m_ringBuffer->reset();

    LOG_ENGINE << "Playback stopped";
}

qint64 FFmpegAudioEngine::getAudioClockMs() const
{
    if (m_state == PlaybackState::Stopped || m_sampleRate == 0) {
        return m_seekPositionMs;
    }

    QMutexLocker locker(const_cast<QMutex*>(&m_seekMutex));

    qint64 framesPlayed = m_totalFramesPlayed.load();

    if (m_paStream) {
        const PaStreamInfo* streamInfo = Pa_GetStreamInfo(m_paStream);
        if (streamInfo) {
            qint64 outputLatencyFrames = static_cast<qint64>(streamInfo->outputLatency * m_sampleRate);
            framesPlayed = qMax(0LL, framesPlayed - outputLatencyFrames);
        }
    }

    qint64 elapsedMs = (framesPlayed * 1000) / m_sampleRate;
    qint64 currentMs = m_seekPositionMs + elapsedMs;

    return qBound(0LL, currentMs, m_duration);
}

void FFmpegAudioEngine::resetAudioClock(qint64 positionMs)
{
    QMutexLocker locker(&m_seekMutex);
    m_seekPositionMs = positionMs;
    m_totalFramesPlayed = 0;

    LOG_CLOCK << "Audio clock reset: position=" << positionMs << "ms";
}

qint64 FFmpegAudioEngine::position() const
{
    return getAudioClockMs();
}

void FFmpegAudioEngine::setVolume(qreal volume)
{
    volume = qBound(0.0, volume, 1.0);
    if (qAbs(m_volume - volume) < 0.01) {
        return;
    }

    m_volume = volume;
    m_volumeAtomic.store(volume);

    emit volumeChanged();
    LOG_ENGINE << "Volume set to:" << volume;
}

void FFmpegAudioEngine::setPlaybackRate(qreal rate)
{
    Q_UNUSED(rate);
    LOG_ENGINE << "PlaybackRate not supported in this version";
}

void FFmpegAudioEngine::setSentenceSegments(const QVector<SentenceSegment>& segments)
{
    m_sentences = segments;
    m_currentSentenceIndex = -1;
    LOG_ENGINE << "Sentence segments set, count:" << m_sentences.size();
}

void FFmpegAudioEngine::setCurrentSentenceIndex(int index)
{
    if (index < 0 || index >= m_sentences.size()) {
        return;
    }

    m_currentSentenceIndex = index;
    emit sentenceChanged(index);
    LOG_ENGINE << "Current sentence index set to:" << index;
}

void FFmpegAudioEngine::setSingleSentenceLoop(bool enable)
{
    m_singleSentenceLoop = enable;
    LOG_ENGINE << "Single sentence loop:" << (enable ? "enabled" : "disabled");
}

void FFmpegAudioEngine::setAutoPauseAtSentenceEnd(bool enable)
{
    m_autoPauseEnabled = enable;
    LOG_ENGINE << "Auto pause:" << (enable ? "enabled" : "disabled");
}

void FFmpegAudioEngine::setLoopRange(qint64 startMs, qint64 endMs)
{
    m_loopRangeEnabled = true;
    m_loopStartMs = startMs;
    m_loopEndMs = endMs;
    LOG_ENGINE << "Loop range set:" << startMs << "-" << endMs << "ms";
}

void FFmpegAudioEngine::clearLoopRange()
{
    m_loopRangeEnabled = false;
    LOG_ENGINE << "Loop range cleared";
}

int FFmpegAudioEngine::paCallback(
    const void* inputBuffer,
    void* outputBuffer,
    unsigned long framesPerBuffer,
    const PaStreamCallbackTimeInfo* timeInfo,
    PaStreamCallbackFlags statusFlags,
    void* userData)
{
    Q_UNUSED(inputBuffer);
    Q_UNUSED(timeInfo);

    FFmpegAudioEngine* engine = static_cast<FFmpegAudioEngine*>(userData);
    int16_t* out = static_cast<int16_t*>(outputBuffer);

    int bytesToRead = framesPerBuffer * engine->m_channels * sizeof(int16_t);
    QByteArray data = engine->m_ringBuffer->read(bytesToRead);

    if (data.size() > 0) {
        qreal volume = engine->m_volumeAtomic.load();
        int16_t* samples = reinterpret_cast<int16_t*>(data.data());
        int sampleCount = data.size() / sizeof(int16_t);

        for (int i = 0; i < sampleCount; ++i) {
            samples[i] = static_cast<int16_t>(samples[i] * volume);
        }

        memcpy(out, data.constData(), data.size());

        if (data.size() < bytesToRead) {
            memset(reinterpret_cast<char*>(out) + data.size(), 0, bytesToRead - data.size());
        }

        int actualFrames = data.size() / (engine->m_channels * sizeof(int16_t));
        engine->m_totalFramesPlayed.fetch_add(actualFrames);
    }
    else {
        memset(out, 0, bytesToRead);

        if (engine->m_decoderEOF.load()) {
            return paComplete;
        }
    }

    if (statusFlags & paOutputUnderflow) {
        LOG_PA << "Output underflow detected";
    }

    return paContinue;
}

void FFmpegAudioEngine::onPositionUpdateTimer()
{
    if (m_state != PlaybackState::Playing) {
        return;
    }

    qint64 currentMs = getAudioClockMs();

    emit positionChanged();

    updateCurrentSentence();

    if ((m_autoPauseEnabled || m_singleSentenceLoop) &&
        m_currentSentenceIndex >= 0 &&
        m_currentSentenceIndex < m_sentences.size()) {

        const SentenceSegment& seg = m_sentences[m_currentSentenceIndex];

        if (currentMs >= seg.endTimeMs - 20) {
            handleSentenceEnd();
        }
    }

    if (m_loopRangeEnabled && currentMs >= m_loopEndMs) {
        LOG_ENGINE << "Loop range end reached, seeking to" << m_loopStartMs;
        seekTo(m_loopStartMs);
    }

    if (m_decoderEOF) {
        bool bufferEmpty = m_ringBuffer->isEmpty();
        bool audioFinished = false;
        if (m_paStream) {
            audioFinished = (Pa_IsStreamActive(m_paStream) == 0);
        }

        if (bufferEmpty || audioFinished) {
            LOG_ENGINE << "Playback finished at" << currentMs << "ms (EOF + buffer empty)";

            m_positionTimer->stop();
            m_decoder->stopDecoding();

            if (m_paStream) {
                Pa_StopStream(m_paStream);
            }

            m_ringBuffer->clear();
            m_ringBuffer->reset();

            m_state = PlaybackState::Stopped;

            {
                QMutexLocker locker(&m_seekMutex);
                m_seekPositionMs = m_duration;
                m_totalFramesPlayed = 0;
            }

            emit positionChanged();
            emit isPlayingChanged();
            emit playbackFinished();

            LOG_ENGINE << "Playback stopped at end, position=" << m_duration << "ms";
        }
    }
}

void FFmpegAudioEngine::updateCurrentSentence()
{
    if (m_sentences.isEmpty()) {
        return;
    }

    qint64 currentMs = getAudioClockMs();

    for (int i = 0; i < m_sentences.size(); ++i) {
        if (m_sentences[i].contains(currentMs)) {
            if (m_currentSentenceIndex != i) {
                m_currentSentenceIndex = i;
                emit sentenceChanged(i);
                LOG_ENGINE << "Sentence changed to:" << i;
            }
            return;
        }
    }
}

void FFmpegAudioEngine::handleSentenceEnd()
{
    LOG_ENGINE << "Sentence end reached, index:" << m_currentSentenceIndex;

    if (m_singleSentenceLoop) {
        const SentenceSegment& seg = m_sentences[m_currentSentenceIndex];
        LOG_ENGINE << "Single sentence loop: seeking to" << seg.startTimeMs;
        seekTo(seg.startTimeMs);
    }
    else if (m_autoPauseEnabled) {
        LOG_ENGINE << "Auto pause at sentence end";
        pause();
    }
    else {
        playNextSentence();
    }
}

void FFmpegAudioEngine::playNextSentence()
{
    if (m_currentSentenceIndex + 1 < m_sentences.size()) {
        m_currentSentenceIndex++;
        const SentenceSegment& seg = m_sentences[m_currentSentenceIndex];
        LOG_ENGINE << "Playing next sentence:" << m_currentSentenceIndex;
        seekTo(seg.startTimeMs);
        emit sentenceChanged(m_currentSentenceIndex);
    }
    else {
        LOG_ENGINE << "Last sentence reached, stopping";
        stop();
        emit playbackFinished();
    }
}

void FFmpegAudioEngine::playPreviousSentence()
{
    if (m_currentSentenceIndex > 0) {
        m_currentSentenceIndex--;
        const SentenceSegment& seg = m_sentences[m_currentSentenceIndex];
        LOG_ENGINE << "Playing previous sentence:" << m_currentSentenceIndex;
        seekTo(seg.startTimeMs);
        emit sentenceChanged(m_currentSentenceIndex);
    }
}

void FFmpegAudioEngine::onDecoderError(const QString& error)
{
    LOG_ENGINE << "Decoder error:" << error;
    emit errorOccurred(error);
}

void FFmpegAudioEngine::onDecoderFinished()
{
    LOG_ENGINE << "Decoder finished (EOF)";
    m_decoderEOF = true;
}