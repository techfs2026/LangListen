#include "ffmpegaudioengine.h"
#include <QDebug>
#include <QMutexLocker>
#include <algorithm>
#include <cmath>

#define ENABLE_DECODER_LOG 1
#define ENABLE_ENGINE_LOG 1
#define ENABLE_POSITION_LOG 0
#define ENABLE_DATA_LOG 0

#if ENABLE_DECODER_LOG
#define LOG_DECODER qDebug() << "[DECODER]"
#else
#define LOG_DECODER if(false) qDebug()
#endif

#if ENABLE_ENGINE_LOG
#define LOG_ENGINE qDebug() << "[ENGINE]"
#else
#define LOG_ENGINE if(false) qDebug()
#endif

#if ENABLE_POSITION_LOG
#define LOG_POSITION qDebug() << "[POSITION]"
#else
#define LOG_POSITION if(false) qDebug()
#endif

#if ENABLE_DATA_LOG
#define LOG_DATA qDebug() << "[DATA]"
#else
#define LOG_DATA if(false) qDebug()
#endif

FFmpegDecoder::FFmpegDecoder(QObject* parent)
    : QThread(parent)
    , m_formatCtx(nullptr)
    , m_codecCtx(nullptr)
    , m_swrCtx(nullptr)
    , m_audioStreamIndex(-1)
    , m_duration(0)
    , m_sampleRate(0)
    , m_channels(0)
    , m_outputSampleRate(0)
    , m_stopRequested(false)
    , m_pauseRequested(false)
    , m_seekRequested(false)
    , m_seekTargetMs(0)
    , m_playbackRate(1.0)
    , m_needRebuildResampler(false)
{
}

FFmpegDecoder::~FFmpegDecoder()
{
    stopDecoding();
    if (isRunning()) {
        quit();
        wait();
    }
    close();
}

bool FFmpegDecoder::openFile(const QString& filePath)
{
    close();

    m_filePath = filePath;

    m_formatCtx = nullptr;
    int ret = avformat_open_input(&m_formatCtx, filePath.toUtf8().constData(), nullptr, nullptr);
    if (ret < 0) {
        emit errorOccurred(QString("Failed to open file: error %1").arg(ret));
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

    LOG_DECODER << "Audio loaded: duration =" << m_duration << "ms, sample rate ="
        << m_sampleRate << "Hz, channels =" << m_channels;
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

    m_outputSampleRate = m_sampleRate;

    LOG_DECODER << "Decoder initialized: codec=" << codec->name
        << ", sample_rate=" << m_sampleRate
        << ", channels=" << m_channels;

    if (!initResampler()) {
        avcodec_free_context(&m_codecCtx);
        return false;
    }

    return true;
}

bool FFmpegDecoder::initResampler()
{
    m_swrCtx = swr_alloc();
    if (!m_swrCtx) {
        emit errorOccurred("Failed to allocate resampler");
        return false;
    }

    AVChannelLayout outChannelLayout = AV_CHANNEL_LAYOUT_STEREO;
    if (m_channels == 1) {
        outChannelLayout = AV_CHANNEL_LAYOUT_MONO;
    }

    av_opt_set_chlayout(m_swrCtx, "in_chlayout", &m_codecCtx->ch_layout, 0);
    av_opt_set_int(m_swrCtx, "in_sample_rate", m_codecCtx->sample_rate, 0);
    av_opt_set_sample_fmt(m_swrCtx, "in_sample_fmt", m_codecCtx->sample_fmt, 0);

    av_opt_set_chlayout(m_swrCtx, "out_chlayout", &outChannelLayout, 0);

    av_opt_set_int(m_swrCtx, "out_sample_rate", m_outputSampleRate, 0);
    av_opt_set_sample_fmt(m_swrCtx, "out_sample_fmt", AV_SAMPLE_FMT_S16, 0);

    int ret = swr_init(m_swrCtx);
    if (ret < 0) {
        emit errorOccurred("Failed to initialize resampler");
        swr_free(&m_swrCtx);
        return false;
    }

    LOG_DECODER << "Resampler initialized: in_rate=" << m_codecCtx->sample_rate
        << ", out_rate=" << m_outputSampleRate
        << ", playback_rate=" << m_playbackRate.load();
    return true;
}

bool FFmpegDecoder::rebuildResampler()
{
    cleanupResampler();

    double rate = m_playbackRate.load();
    m_outputSampleRate = static_cast<int>(m_sampleRate * rate);

    LOG_DECODER << "Rebuilding resampler for playback rate:" << rate
        << ", output sample rate:" << m_outputSampleRate;

    return initResampler();
}

void FFmpegDecoder::close()
{
    cleanupResampler();
    cleanupDecoder();
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

void FFmpegDecoder::cleanupResampler()
{
    if (m_swrCtx) {
        swr_free(&m_swrCtx);
        m_swrCtx = nullptr;
    }
}

void FFmpegDecoder::seekTo(qint64 positionMs)
{
    m_seekTargetMs = positionMs;
    m_seekRequested = true;
}

void FFmpegDecoder::setPlaybackRate(double rate)
{
    rate = qBound(0.5, rate, 2.0);
    double oldRate = m_playbackRate.load();
    m_playbackRate = rate;

    if (qAbs(rate - oldRate) > 0.01) {
        LOG_DECODER << "Playback rate changed from" << oldRate << "to" << rate;
        m_needRebuildResampler = true;
    }
}

void FFmpegDecoder::stopDecoding()
{
    m_stopRequested = true;
    m_queueNotFull.wakeAll();
    m_queueNotEmpty.wakeAll();
}

void FFmpegDecoder::resetEOF()
{
    m_stopRequested = false;
}

int FFmpegDecoder::hasQueuedPackets()  // 修改返回类型
{
    QMutexLocker locker(&m_queueMutex);
    return m_packetQueue.size();
}

void FFmpegDecoder::pauseDecoding()
{
    m_pauseRequested = true;
}

void FFmpegDecoder::resumeDecoding()
{
    m_pauseRequested = false;
}

bool FFmpegDecoder::getNextPacket(AudioPacket& packet, int timeoutMs)
{
    QMutexLocker locker(&m_queueMutex);

    if (m_packetQueue.isEmpty()) {
        if (!m_queueNotEmpty.wait(&m_queueMutex, timeoutMs)) {
            return false;
        }
    }

    if (m_packetQueue.isEmpty()) {
        return false;
    }

    packet = m_packetQueue.dequeue();
    m_queueNotFull.wakeOne();

    return true;
}

void FFmpegDecoder::clearQueue()
{
    QMutexLocker locker(&m_queueMutex);
    m_packetQueue.clear();
    m_queueNotFull.wakeAll();
}

void FFmpegDecoder::run()
{
    emit decodingStarted();

    AVPacket* packet = av_packet_alloc();
    AVFrame* frame = av_frame_alloc();

    if (!packet || !frame) {
        emit errorOccurred("Failed to allocate packet or frame");
        if (packet) av_packet_free(&packet);
        if (frame) av_frame_free(&frame);
        return;
    }

    LOG_DECODER << "Decoding thread started";

    while (!m_stopRequested) {
        if (m_pauseRequested) {
            QThread::msleep(10);
            continue;
        }

        if (m_seekRequested) {
            qint64 targetMs = m_seekTargetMs.load();
            if (performSeek(targetMs)) {
                LOG_DECODER << "Seek completed to" << targetMs << "ms";
            }
            m_seekRequested = false;
            continue;
        }

        if (m_needRebuildResampler) {
            if (rebuildResampler()) {
                LOG_DECODER << "Resampler rebuilt successfully";
            }
            m_needRebuildResampler = false;
        }

        {
            QMutexLocker locker(&m_queueMutex);
            if (m_packetQueue.size() >= MAX_QUEUE_SIZE) {
                m_queueNotFull.wait(&m_queueMutex, 100);
                continue;
            }
        }

        int ret = av_read_frame(m_formatCtx, packet);
        if (ret == AVERROR_EOF) {
            LOG_DECODER << "End of file reached";
            break;
        }
        else if (ret < 0) {
            LOG_DECODER << "Error reading frame:" << ret;
            break;
        }

        if (packet->stream_index != m_audioStreamIndex) {
            av_packet_unref(packet);
            continue;
        }

        ret = avcodec_send_packet(m_codecCtx, packet);
        av_packet_unref(packet);

        if (ret < 0) {
            LOG_DECODER << "Error sending packet to decoder:" << ret;
            continue;
        }

        while (ret >= 0 && !m_stopRequested) {
            ret = avcodec_receive_frame(m_codecCtx, frame);
            if (ret == AVERROR(EAGAIN) || ret == AVERROR_EOF) {
                break;
            }
            else if (ret < 0) {
                LOG_DECODER << "Error receiving frame from decoder:" << ret;
                break;
            }

            QByteArray resampledData;
            if (resampleFrame(frame, resampledData)) {
                qint64 pts = av_rescale_q(frame->pts, m_formatCtx->streams[m_audioStreamIndex]->time_base, { 1, 1000 });

                AudioPacket audioPacket(resampledData, pts);

                {
                    QMutexLocker locker(&m_queueMutex);
                    while (m_packetQueue.size() >= MAX_QUEUE_SIZE && !m_stopRequested) {
                        m_queueNotFull.wait(&m_queueMutex, 100);
                    }

                    if (!m_stopRequested) {
                        m_packetQueue.enqueue(audioPacket);
                        m_queueNotEmpty.wakeOne();
                    }
                }
            }
        }
    }

    av_packet_free(&packet);
    av_frame_free(&frame);

    LOG_DECODER << "Decoding thread finished";
    emit decodingFinished();
}

bool FFmpegDecoder::performSeek(qint64 targetMs)
{
    LOG_DECODER << "Performing seek to" << targetMs << "ms";

    clearQueue();

    AVStream* audioStream = m_formatCtx->streams[m_audioStreamIndex];
    int64_t seekTarget = av_rescale_q(targetMs, { 1, 1000 }, audioStream->time_base);

    int ret = av_seek_frame(m_formatCtx, m_audioStreamIndex, seekTarget, AVSEEK_FLAG_BACKWARD);
    if (ret < 0) {
        LOG_DECODER << "Seek failed with error:" << ret;
        return false;
    }

    avcodec_flush_buffers(m_codecCtx);

    LOG_DECODER << "Seek successful";
    return true;
}

bool FFmpegDecoder::resampleFrame(AVFrame* frame, QByteArray& outData)
{
    if (!m_swrCtx) {
        return false;
    }

    int outSamples = av_rescale_rnd(
        swr_get_delay(m_swrCtx, frame->sample_rate) + frame->nb_samples,
        m_outputSampleRate,
        frame->sample_rate,
        AV_ROUND_UP
    );

    int bufferSize = av_samples_get_buffer_size(nullptr, m_channels, outSamples, AV_SAMPLE_FMT_S16, 1);
    outData.resize(bufferSize);

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

    int actualSize = av_samples_get_buffer_size(nullptr, m_channels, convertedSamples, AV_SAMPLE_FMT_S16, 1);
    outData.resize(actualSize);

    return true;
}

FFmpegAudioEngine::FFmpegAudioEngine(QObject* parent)
    : QObject(parent)
    , m_decoder(nullptr)
    , m_decoderThread(nullptr)
    , m_audioSink(nullptr)
    , m_audioDevice(nullptr)
    , m_state(PlaybackState::Stopped)
    , m_currentPosition(0)
    , m_duration(0)
    , m_volume(1.0)
    , m_playbackRate(1.0)
    , m_decoderEOF(false)
    , m_isSeeking(false)
    , m_loopEnabled(false)
    , m_loopStartMs(0)
    , m_loopEndMs(0)
    , m_bufferPts(0)
    , m_lastSeekPosition(0)
    , m_lastBytesProcessed(0)
    , m_audioSinkBaselineUs(0)
{
    m_decoder = new FFmpegDecoder();
    m_decoderThread = new QThread(this);
    m_decoder->moveToThread(m_decoderThread);

    connect(m_decoder, &FFmpegDecoder::decodingFinished, this, &FFmpegAudioEngine::onDecoderFinished);
    connect(m_decoder, &FFmpegDecoder::errorOccurred, this, &FFmpegAudioEngine::onDecoderError);

    m_playbackTimer = new QTimer(this);
    m_playbackTimer->setInterval(10);
    connect(m_playbackTimer, &QTimer::timeout, this, &FFmpegAudioEngine::processAudioData);

    m_positionTimer = new QTimer(this);
    m_positionTimer->setInterval(50);
    connect(m_positionTimer, &QTimer::timeout, this, &FFmpegAudioEngine::updatePosition);

    m_decoderThread->start();
}

FFmpegAudioEngine::~FFmpegAudioEngine()
{
    closeAudio();

    if (m_decoderThread) {
        m_decoderThread->quit();
        m_decoderThread->wait();
    }

    delete m_decoder;
}

bool FFmpegAudioEngine::loadAudio(const QString& filePath)
{
    LOG_ENGINE << "Loading audio:" << filePath;

    closeAudio();

    if (!m_decoder->openFile(filePath)) {
        return false;
    }

    m_duration = m_decoder->getDuration();
    emit durationChanged();

    if (!initAudioOutput()) {
        m_decoder->close();
        return false;
    }

    m_decoderEOF = false;
    m_currentPosition = 0;
    m_audioBuffer.clear();
    m_bufferPts = 0;

    QMetaObject::invokeMethod(m_decoder, "start", Qt::QueuedConnection);

    emit audioLoaded(true, "Audio loaded successfully");

    LOG_ENGINE << "Audio loaded successfully, duration:" << m_duration << "ms";
    return true;
}

void FFmpegAudioEngine::closeAudio()
{
    LOG_ENGINE << "Closing audio";

    stop();

    if (m_decoder) {
        m_decoder->stopDecoding();
        if (m_decoder->isRunning()) {
            m_decoder->wait(1000);
        }
    }

    cleanupAudioOutput();

    if (m_decoder) {
        m_decoder->close();
    }

    m_duration = 0;
    m_currentPosition = 0;
    m_decoderEOF = false;

    emit durationChanged();
}

bool FFmpegAudioEngine::initAudioOutput()
{
    cleanupAudioOutput();

    m_audioFormat.setSampleRate(m_decoder->getOutputSampleRate());
    m_audioFormat.setChannelCount(m_decoder->getChannels());
    m_audioFormat.setSampleFormat(QAudioFormat::Int16);

    m_audioSink = new QAudioSink(m_audioFormat, this);
    m_audioSink->setBufferSize(m_audioFormat.sampleRate() * m_audioFormat.bytesPerFrame() / 2);
    m_audioSink->setVolume(m_volume);

    connect(m_audioSink, &QAudioSink::stateChanged, this, &FFmpegAudioEngine::onAudioOutputStateChanged);

    LOG_ENGINE << "Audio output initialized: sampleRate =" << m_audioFormat.sampleRate()
        << ", channels =" << m_audioFormat.channelCount()
        << ", buffer =" << m_audioSink->bufferSize();

    return true;
}

void FFmpegAudioEngine::cleanupAudioOutput()
{
    if (m_audioSink) {
        m_audioSink->stop();
        m_audioSink->deleteLater();
        m_audioSink = nullptr;
        m_audioDevice = nullptr;
    }
}

void FFmpegAudioEngine::play()
{
    LOG_ENGINE << "Play called, current state:" << (int)m_state << ", decoderEOF:" << m_decoderEOF;

    if (m_state == PlaybackState::Playing) {
        LOG_ENGINE << "Already playing, ignoring";
        return;
    }

    if (!m_decoder || m_duration <= 0) {
        LOG_ENGINE << "Cannot play: audio not loaded";
        return;
    }

    if (m_decoderEOF) {
        LOG_ENGINE << "Resetting playback from EOF state";
        m_decoderEOF = false;
        m_decoder->resetEOF();

        if (!m_decoder->isRunning()) {
            m_decoder->clearQueue();
            QMetaObject::invokeMethod(m_decoder, "start", Qt::QueuedConnection);
        }
        else {
            m_decoder->resumeDecoding();
        }
    }

    if (!m_decoder->isRunning()) {
        LOG_ENGINE << "Starting decoder thread";
        m_decoder->clearQueue();
        QMetaObject::invokeMethod(m_decoder, "start", Qt::QueuedConnection);
        QThread::msleep(30);
    }
    else if (m_decoder->hasQueuedPackets() < 5) {
        m_decoder->resumeDecoding();
        QThread::msleep(20);
    }

    if (m_state == PlaybackState::Paused) {
        LOG_ENGINE << "Resuming from paused state";

        QAudio::State audioState = m_audioSink->state();

        if (audioState == QAudio::SuspendedState && m_audioDevice) {
            // ✅ 从暂停恢复：记录当前 processedUSecs 作为基准
            m_audioSinkBaselineUs = m_audioSink->processedUSecs();
            m_lastSeekPosition = m_currentPosition;  // 当前位置作为新起点
            m_audioSink->resume();
            LOG_ENGINE << "Resumed AudioSink from suspended state, baseline:" << m_audioSinkBaselineUs;
        }
        else {
            LOG_ENGINE << "AudioSink state is" << audioState << ", restarting";
            m_audioDevice = m_audioSink->start();
            // ✅ start() 后基准是 0
            m_audioSinkBaselineUs = 0;
            m_lastSeekPosition = m_currentPosition;
            if (!m_audioDevice) {
                LOG_ENGINE << "Failed to start audio sink from paused state";
                emit errorOccurred("Failed to start audio playback");
                return;
            }
            LOG_ENGINE << "Restarted audio sink from paused state, baseline: 0";
        }

        m_decoder->resumeDecoding();
    }
    else if (m_state == PlaybackState::Stopped) {
        LOG_ENGINE << "Starting from stopped state";

        if (!m_audioSink) {
            if (!initAudioOutput()) {
                emit errorOccurred("Failed to init audio output");
                return;
            }
        }

        m_audioBuffer.clear();
        m_lastSeekPosition = m_currentPosition;
        m_lastBytesProcessed = 0;

        m_decoder->resumeDecoding();

        m_audioDevice = m_audioSink->start();
        // ✅ start() 后基准是 0
        m_audioSinkBaselineUs = 0;
        if (!m_audioDevice) {
            emit errorOccurred("Failed to start audio playback");
            return;
        }

        processAudioData();
    }

    m_state = PlaybackState::Playing;
    emit isPlayingChanged();

    preventSystemSleep();

    m_playbackTimer->start();
    m_positionTimer->start();

    LOG_ENGINE << "Playing - lastSeekPosition:" << m_lastSeekPosition
        << ", baseline:" << m_audioSinkBaselineUs;
}

void FFmpegAudioEngine::pause()
{
    LOG_ENGINE << "Pause called";

    if (m_state != PlaybackState::Playing) {
        return;
    }

    m_decoder->pauseDecoding();

    if (m_audioSink) {
        m_audioSink->suspend();
    }

    m_state = PlaybackState::Paused;
    emit isPlayingChanged();

    allowSystemSleep();

    m_playbackTimer->stop();
    m_positionTimer->stop();

    LOG_ENGINE << "Paused";
}

void FFmpegAudioEngine::stop()
{
    LOG_ENGINE << "Stop called";

    if (m_state == PlaybackState::Stopped)
        return;

    m_playbackTimer->stop();
    m_positionTimer->stop();

    m_decoder->pauseDecoding();

    cleanupAudioOutput();

    m_state = PlaybackState::Stopped;

    allowSystemSleep();

    m_currentPosition = 0;
    m_lastSeekPosition = 0;
    m_bufferPts = 0;
    m_audioBuffer.clear();
    m_lastBytesProcessed = 0;

    emit positionChanged();
    emit isPlayingChanged();

    LOG_ENGINE << "Stopped (hard stop)";
}

void FFmpegAudioEngine::seekTo(qint64 positionMs)
{
    positionMs = qBound(0LL, positionMs, m_duration);

    if (m_isSeeking) {
        LOG_ENGINE << "seekTo ignored (already seeking)";
        return;
    }

    LOG_ENGINE << "SeekTo:" << positionMs << "ms, state:" << (int)m_state;

    const bool wasPlaying = (m_state == PlaybackState::Playing);

    m_isSeeking = true;

    m_playbackTimer->stop();
    m_positionTimer->stop();

    if (m_audioSink && m_audioSink->state() == QAudio::ActiveState) {
        m_audioSink->suspend();
        LOG_ENGINE << "AudioSink suspended for seek";
    }

    m_decoder->pauseDecoding();
    m_decoder->resetEOF();

    m_decoder->clearQueue();
    m_audioBuffer.clear();

    m_decoder->seekTo(positionMs);

    QThread::msleep(10);

    m_lastSeekPosition = positionMs;
    m_currentPosition = positionMs;
    m_bufferPts = positionMs;
    m_lastBytesProcessed = 0;

    emit positionChanged();

    m_decoder->resumeDecoding();

    if (wasPlaying) {
        LOG_ENGINE << "Resuming playback after seek";

        if (!m_audioSink) {
            LOG_ENGINE << "AudioSink missing, reinitializing";
            if (!initAudioOutput()) {
                emit errorOccurred("Failed to reinitialize audio output");
                m_isSeeking = false;
                return;
            }
        }

        if (m_audioSink->state() == QAudio::SuspendedState) {
            // ✅ 关键修复：记录 resume 时的 processedUSecs 作为基准
            m_audioSinkBaselineUs = m_audioSink->processedUSecs();
            m_audioSink->resume();
            LOG_ENGINE << "AudioSink resumed after seek, baseline:" << m_audioSinkBaselineUs;
        }
        else if (m_audioSink->state() != QAudio::ActiveState) {
            m_audioDevice = m_audioSink->start();
            // ✅ start() 后 processedUSecs 从 0 开始，所以基准是 0
            m_audioSinkBaselineUs = 0;
            LOG_ENGINE << "AudioSink restarted after seek, baseline:" << m_audioSinkBaselineUs;
        }

        m_state = PlaybackState::Playing;
        emit isPlayingChanged();

        m_playbackTimer->start();
        m_positionTimer->start();

        processAudioData();
    }

    m_isSeeking = false;

    LOG_ENGINE << "Seek completed at" << positionMs << "ms";
}

void FFmpegAudioEngine::setVolume(qreal volume)
{
    volume = qBound(0.0, volume, 1.0);
    if (qAbs(m_volume - volume) < 0.01) {
        return;
    }

    m_volume = volume;
    if (m_audioSink) {
        m_audioSink->setVolume(m_volume);
    }

    emit volumeChanged();
}

void FFmpegAudioEngine::setPlaybackRate(qreal rate)
{
    rate = qBound(0.5, rate, 2.0);
    if (qAbs(m_playbackRate - rate) < 0.01) {
        return;
    }

    LOG_ENGINE << "Setting playback rate:" << rate;

    bool wasPlaying = (m_state == PlaybackState::Playing);
    qint64 savedPosition = m_currentPosition;

    if (wasPlaying) {
        pause();
    }

    m_playbackRate = rate;
    m_decoder->setPlaybackRate(m_playbackRate);

    cleanupAudioOutput();
    if (!initAudioOutput()) {
        emit errorOccurred("Failed to reinitialize audio output");
        return;
    }

    if (wasPlaying) {
        play();
    }

    emit playbackRateChanged();
}

void FFmpegAudioEngine::setLoopRange(qint64 startMs, qint64 endMs)
{
    m_loopEnabled = true;
    m_loopStartMs = startMs;
    m_loopEndMs = endMs;
    LOG_ENGINE << "Loop range set:" << startMs << "-" << endMs;
}

void FFmpegAudioEngine::clearLoopRange()
{
    m_loopEnabled = false;
    LOG_ENGINE << "Loop range cleared";
}

void FFmpegAudioEngine::processAudioData()
{
    if (m_state != PlaybackState::Playing || !m_audioDevice) {
        return;
    }

    qint64 bytesAvailable = m_audioSink->bytesFree();

    int packetsProcessed = 0;
    qint64 totalBytesWritten = 0;

    while (packetsProcessed < 10) {
        if (m_audioBuffer.size() > m_audioSink->bufferSize() * 2) {
            break;
        }

        AudioPacket packet;
        if (!m_decoder->getNextPacket(packet, 10)) {
            break;
        }

        m_audioBuffer.append(packet.data);
        if (packet.pts > 0) {
            m_bufferPts = packet.pts;
        }

        packetsProcessed++;
    }

    if (bytesAvailable > 0 && !m_audioBuffer.isEmpty()) {
        qint64 bytesToWrite = qMin(bytesAvailable, (qint64)m_audioBuffer.size());
        qint64 bytesWritten = m_audioDevice->write(m_audioBuffer.constData(), bytesToWrite);

        if (bytesWritten > 0) {
            m_audioBuffer.remove(0, bytesWritten);
            totalBytesWritten += bytesWritten;
        }
    }

    static int logCounter = 0;
    if (++logCounter % 100 == 0) {
        LOG_DATA << "processAudioData: bytesFree=" << bytesAvailable
            << ", audioBuffer=" << m_audioBuffer.size()
            << ", packets=" << packetsProcessed
            << ", written=" << totalBytesWritten
            << ", decoderEOF=" << m_decoderEOF
            << ", hasQueuedPackets=" << m_decoder->hasQueuedPackets()
            << ", currentPos=" << m_currentPosition
            << ", duration=" << m_duration;
    }
}

void FFmpegAudioEngine::updatePosition()
{
    if (m_state != PlaybackState::Playing || !m_audioSink) {
        return;
    }

    // ✅ 关键修复：计算相对于基准点的增量
    qint64 currentUs = m_audioSink->processedUSecs();
    qint64 elapsedUs = currentUs - m_audioSinkBaselineUs;  // 计算增量
    qint64 elapsedMs = elapsedUs / 1000;

    qint64 oldPosition = m_currentPosition;

    if (elapsedMs > 0) {
        m_currentPosition = m_lastSeekPosition + elapsedMs;
    }

    if (m_currentPosition > m_duration) {
        if (m_decoderEOF && !hasPendingAudio()) {
            m_currentPosition = m_duration;
            LOG_POSITION << "Reached end of audio, position clamped to duration";
        }
        else {
            m_currentPosition = qMin(m_currentPosition, m_duration);
        }
    }

    m_currentPosition = qBound(0LL, m_currentPosition, m_duration);

    static int posLogCounter = 0;
    if (++posLogCounter % 25 == 0) {
        LOG_POSITION << "Position update:"
            << "currentUs=" << currentUs
            << ", baselineUs=" << m_audioSinkBaselineUs
            << ", elapsedMs=" << elapsedMs
            << ", lastSeek=" << m_lastSeekPosition
            << ", currentPos=" << m_currentPosition
            << ", duration=" << m_duration
            << ", delta=" << (m_currentPosition - oldPosition) << "ms"
            << ", playbackRate=" << m_playbackRate
            << ", buffer=" << m_audioBuffer.size()
            << ", decoderEOF=" << m_decoderEOF;
    }

    emit positionChanged();

    if (m_loopEnabled && m_currentPosition >= m_loopEndMs) {
        LOG_ENGINE << "Loop point reached, jumping back to" << m_loopStartMs;
        seekTo(m_loopStartMs);
    }
}

void FFmpegAudioEngine::onDecoderFinished()
{
    LOG_ENGINE << "Decoder finished, EOF flag set";
    m_decoderEOF = true;
}

void FFmpegAudioEngine::onDecoderError(const QString& error)
{
    LOG_ENGINE << "Decoder error:" << error;
    emit errorOccurred(error);
}

void FFmpegAudioEngine::onAudioOutputStateChanged(QAudio::State state)
{
    LOG_ENGINE << "Audio output state changed:" << state
        << ", playback state:" << (int)m_state
        << ", isSeeking:" << m_isSeeking
        << ", decoderEOF:" << m_decoderEOF
        << ", hasPendingAudio:" << hasPendingAudio()
        << ", buffer size:" << m_audioBuffer.size()
        << ", currentPos:" << m_currentPosition
        << ", duration:" << m_duration;

    if (m_isSeeking) {
        LOG_ENGINE << "Ignoring state change during seek operation";
        return;
    }

    if (state == QAudio::IdleState &&
        m_state == PlaybackState::Playing &&
        m_decoderEOF &&
        !hasPendingAudio())
    {
        LOG_ENGINE << "Playback finished (all data drained)";
        LOG_ENGINE << "Final position:" << m_currentPosition << ", duration:" << m_duration;

        m_playbackTimer->stop();
        m_positionTimer->stop();

        m_state = PlaybackState::Stopped;

        m_currentPosition = m_duration;

        emit positionChanged();
        emit isPlayingChanged();
        emit playbackFinished();
    }
    else if (state == QAudio::StoppedState) {
        if (m_state == PlaybackState::Playing) {
            QAudio::Error error = m_audioSink->error();
            if (error != QAudio::NoError && error != QAudio::UnderrunError) {
                LOG_ENGINE << "Audio sink stopped with error:" << error;

                qint64 savedPosition = m_currentPosition;
                LOG_ENGINE << "Attempting to recover playback from position:" << savedPosition;

                cleanupAudioOutput();
                if (initAudioOutput()) {
                    seekTo(savedPosition);

                    m_audioDevice = m_audioSink->start();
                    if (m_audioDevice) {
                        LOG_ENGINE << "Audio output recovered successfully";
                    }
                    else {
                        emit errorOccurred("Failed to recover audio output");
                    }
                }
                else {
                    emit errorOccurred("Audio output stopped unexpectedly");
                }
            }
        }
    }
    else if (state == QAudio::SuspendedState) {
        LOG_ENGINE << "Audio output suspended";
    }
}

bool FFmpegAudioEngine::hasPendingAudio()
{
    if (!m_audioBuffer.isEmpty()) {
        return true;
    }

    if (m_decoder && m_decoder->hasQueuedPackets()) {
        return true;
    }

    if (m_audioSink) {
        qint64 bufferedBytes = m_audioSink->bufferSize() - m_audioSink->bytesFree();
        if (bufferedBytes > 0) {
            LOG_ENGINE << "Audio sink has buffered data:" << bufferedBytes << "bytes";
            return true;
        }
    }

    return false;
}

void FFmpegAudioEngine::preventSystemSleep()
{
#ifdef Q_OS_WIN
    SetThreadExecutionState(ES_CONTINUOUS | ES_SYSTEM_REQUIRED | ES_DISPLAY_REQUIRED);
    LOG_ENGINE << "Prevented system sleep";
#endif
}

void FFmpegAudioEngine::allowSystemSleep()
{
#ifdef Q_OS_WIN
    SetThreadExecutionState(ES_CONTINUOUS);
    LOG_ENGINE << "Allowed system sleep";
#endif
}

QString FFmpegAudioEngine::getErrorString(int errnum) const
{
    char errbuf[AV_ERROR_MAX_STRING_SIZE];
    av_strerror(errnum, errbuf, AV_ERROR_MAX_STRING_SIZE);
    return QString::fromUtf8(errbuf);
}