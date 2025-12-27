#include "audioplaybackcontroller.h"
#include "ffmpegaudioengine.h"

AudioPlaybackController::AudioPlaybackController(QObject* parent)
    : QObject(parent)
    , m_engine(nullptr)
    , m_currentSegmentIndex(-1)
{
    m_engine = new FFmpegAudioEngine(this);

    connect(m_engine, &FFmpegAudioEngine::isPlayingChanged,
        this, &AudioPlaybackController::isPlayingChanged);
    connect(m_engine, &FFmpegAudioEngine::positionChanged,
        this, &AudioPlaybackController::onPositionChanged);
    connect(m_engine, &FFmpegAudioEngine::durationChanged,
        this, &AudioPlaybackController::onDurationChanged);
    connect(m_engine, &FFmpegAudioEngine::volumeChanged,
        this, &AudioPlaybackController::volumeChanged);
    connect(m_engine, &FFmpegAudioEngine::playbackRateChanged,
        this, &AudioPlaybackController::playbackRateChanged);
    connect(m_engine, &FFmpegAudioEngine::audioLoaded,
        this, &AudioPlaybackController::audioLoaded);
    connect(m_engine, &FFmpegAudioEngine::errorOccurred,
        this, [this](const QString& error) {
            emit audioLoaded(false, error);
        });

    connect(m_engine, &FFmpegAudioEngine::sentenceChanged,
        this, &AudioPlaybackController::onSentenceChanged);
}

AudioPlaybackController::~AudioPlaybackController()
{
}

void AudioPlaybackController::loadAudio(const QString& filePath)
{
    m_engine->stop();

    bool success = m_engine->loadAudio(filePath);

    if (!success) {
        emit audioLoaded(false, "Failed to load audio: " + filePath);
    }
}

void AudioPlaybackController::setSubtitles(const QVector<SubtitleSegment>& segments)
{
    m_segments = segments;
    m_currentSegmentIndex = -1;
    m_currentSegmentText.clear();

    QVector<SentenceSegment> sentences;
    for (const SubtitleSegment& seg : segments) {
        sentences.append(SentenceSegment(seg.startTime, seg.endTime));
    }
    m_engine->setSentenceSegments(sentences);

    emit currentSegmentIndexChanged();
    emit currentSegmentTextChanged();
}

void AudioPlaybackController::play()
{
    m_engine->play();
}

void AudioPlaybackController::pause()
{
    m_engine->pause();
}

void AudioPlaybackController::stop()
{
    m_engine->stop();
    m_currentSegmentIndex = -1;
    m_currentSegmentText.clear();
    emit currentSegmentIndexChanged();
    emit currentSegmentTextChanged();
}

void AudioPlaybackController::seekTo(qint64 position)
{
    m_engine->seekTo(position);
}

void AudioPlaybackController::playSegment(int index)
{
    if (index < 0 || index >= m_segments.size()) {
        return;
    }

    const SubtitleSegment& segment = m_segments[index];

    m_currentSegmentIndex = index;
    m_currentSegmentText = segment.text;

    m_engine->setCurrentSentenceIndex(index);
    m_engine->clearLoopRange();
    m_engine->seekTo(segment.startTime);

    emit currentSegmentIndexChanged();
    emit currentSegmentTextChanged();
    emit segmentChanged(index, segment.text, segment.startTime, segment.endTime);

    m_engine->play();
}

void AudioPlaybackController::playPreviousSegment()
{
    qint64 currentPos = m_engine->position();

    if (m_currentSegmentIndex >= 0 && m_currentSegmentIndex < m_segments.size()) {
        const SubtitleSegment& currentSeg = m_segments[m_currentSegmentIndex];

        if (currentPos > currentSeg.startTime + 300) {
            playSegment(m_currentSegmentIndex);
            return;
        }
    }

    if (m_currentSegmentIndex > 0) {
        playSegment(m_currentSegmentIndex - 1);
    }
}

void AudioPlaybackController::playNextSegment()
{
    if (m_currentSegmentIndex < m_segments.size() - 1) {
        playSegment(m_currentSegmentIndex + 1);
    }
    else {
        stop();
    }
}

void AudioPlaybackController::replayCurrentSegment()
{
    if (m_currentSegmentIndex >= 0 && m_currentSegmentIndex < m_segments.size()) {
        playSegment(m_currentSegmentIndex);
    }
}

void AudioPlaybackController::skipBackward(qint64 milliseconds)
{
    qint64 newPosition = qMax(0LL, position() - milliseconds);
    m_engine->seekTo(newPosition);
}

void AudioPlaybackController::skipForward(qint64 milliseconds)
{
    qint64 newPosition = qMin(duration(), position() + milliseconds);
    m_engine->seekTo(newPosition);
}

void AudioPlaybackController::setVolume(qreal volume)
{
    m_engine->setVolume(volume);
}

void AudioPlaybackController::setPlaybackRate(qreal rate)
{
    m_engine->setPlaybackRate(rate);
}

void AudioPlaybackController::setAutoPauseEnabled(bool enabled)
{
    m_engine->setAutoPauseAtSentenceEnd(enabled);
}

void AudioPlaybackController::setSingleSentenceLoop(bool enabled)
{
    m_engine->setSingleSentenceLoop(enabled);
}

bool AudioPlaybackController::isPlaying() const
{
    return m_engine->isPlaying();
}

qint64 AudioPlaybackController::position() const
{
    return m_engine->position();
}

qint64 AudioPlaybackController::duration() const
{
    return m_engine->duration();
}

int AudioPlaybackController::currentSegmentIndex() const
{
    return m_currentSegmentIndex;
}

QString AudioPlaybackController::currentSegmentText() const
{
    return m_currentSegmentText;
}

qreal AudioPlaybackController::volume() const
{
    return m_engine->volume();
}

qreal AudioPlaybackController::playbackRate() const
{
    return m_engine->playbackRate();
}

void AudioPlaybackController::onPositionChanged()
{
    emit positionChanged();
}

void AudioPlaybackController::onDurationChanged()
{
    emit durationChanged();
}

void AudioPlaybackController::onSentenceChanged(int index)
{
    if (index < 0 || index >= m_segments.size()) {
        return;
    }

    if (m_currentSegmentIndex != index) {
        m_currentSegmentIndex = index;
        const SubtitleSegment& segment = m_segments[index];
        m_currentSegmentText = segment.text;

        emit currentSegmentIndexChanged();
        emit currentSegmentTextChanged();
        emit segmentChanged(index, segment.text, segment.startTime, segment.endTime);
    }
}