#include "audioplaybackcontroller.h"
#include <QUrl>

AudioPlaybackController::AudioPlaybackController(QObject* parent)
    : QObject(parent)
    , m_player(nullptr)
    , m_audioOutput(nullptr)
    , m_isPlaying(false)
    , m_position(0)
    , m_duration(0)
    , m_currentSegmentIndex(-1)
    , m_volume(1.0)
    , m_playbackRate(1.0)
{
    m_player = new QMediaPlayer(this);
    m_audioOutput = new QAudioOutput(this);
    m_player->setAudioOutput(m_audioOutput);

    m_audioOutput->setVolume(m_volume);

    connect(m_player, &QMediaPlayer::positionChanged, this, &AudioPlaybackController::onPositionChanged);
    connect(m_player, &QMediaPlayer::durationChanged, this, &AudioPlaybackController::onDurationChanged);
    connect(m_player, &QMediaPlayer::playbackStateChanged, this, &AudioPlaybackController::onPlaybackStateChanged);
}

AudioPlaybackController::~AudioPlaybackController()
{
}

void AudioPlaybackController::loadAudio(const QString& filePath)
{
    m_player->stop();
    m_player->setSource(QUrl::fromLocalFile(filePath));

    if (m_player->error() == QMediaPlayer::NoError) {
        emit audioLoaded(true, "Audio loaded successfully");
    }
    else {
        emit audioLoaded(false, "Failed to load audio: " + m_player->errorString());
    }
}

void AudioPlaybackController::setSubtitles(const QVector<SubtitleSegment>& segments)
{
    m_segments = segments;
    m_currentSegmentIndex = -1;
    m_currentSegmentText.clear();
    emit currentSegmentIndexChanged();
    emit currentSegmentTextChanged();
}

void AudioPlaybackController::play()
{
    m_player->play();
}

void AudioPlaybackController::pause()
{
    m_player->pause();
}

void AudioPlaybackController::stop()
{
    m_player->stop();
    m_currentSegmentIndex = -1;
    m_currentSegmentText.clear();
    emit currentSegmentIndexChanged();
    emit currentSegmentTextChanged();
}

void AudioPlaybackController::seekTo(qint64 position)
{
    m_player->setPosition(position);
}

void AudioPlaybackController::playSegment(int index)
{
    if (index < 0 || index >= m_segments.size()) {
        return;
    }

    const SubtitleSegment& segment = m_segments[index];

    m_currentSegmentIndex = index;
    m_currentSegmentText = segment.text;

    m_player->setPosition(segment.startTime);

    emit currentSegmentIndexChanged();
    emit currentSegmentTextChanged();
    emit segmentChanged(index, segment.text, segment.startTime, segment.endTime);

    m_player->play();
}

void AudioPlaybackController::playPreviousSegment()
{
    if (m_currentSegmentIndex > 0) {
        playSegment(m_currentSegmentIndex - 1);
    }
}

void AudioPlaybackController::playNextSegment()
{
    if (m_currentSegmentIndex < m_segments.size() - 1) {
        playSegment(m_currentSegmentIndex + 1);
    }
}

void AudioPlaybackController::replayCurrentSegment()
{
    if (m_currentSegmentIndex >= 0 && m_currentSegmentIndex < m_segments.size()) {
        const SubtitleSegment& segment = m_segments[m_currentSegmentIndex];
        m_player->setPosition(segment.startTime);
        emit segmentChanged(m_currentSegmentIndex, segment.text, segment.startTime, segment.endTime);
        m_player->play();
    }
}

void AudioPlaybackController::skipBackward(qint64 milliseconds)
{
    qint64 newPosition = qMax(0LL, m_position - milliseconds);
    m_player->setPosition(newPosition);
}

void AudioPlaybackController::skipForward(qint64 milliseconds)
{
    qint64 newPosition = qMin(m_duration, m_position + milliseconds);
    m_player->setPosition(newPosition);
}

void AudioPlaybackController::setVolume(qreal volume)
{
    if (qAbs(m_volume - volume) > 0.01) {
        m_volume = qBound(0.0, volume, 1.0);
        m_audioOutput->setVolume(m_volume);
        emit volumeChanged();
    }
}

void AudioPlaybackController::setPlaybackRate(qreal rate)
{
    if (qAbs(m_playbackRate - rate) > 0.01) {
        m_playbackRate = qBound(0.25, rate, 2.0);
        m_player->setPlaybackRate(m_playbackRate);
        emit playbackRateChanged();
    }
}

void AudioPlaybackController::onPositionChanged(qint64 position)
{
    m_position = position;
    emit positionChanged();
    updateCurrentSegment();
}

void AudioPlaybackController::onDurationChanged(qint64 duration)
{
    m_duration = duration;
    emit durationChanged();
}

void AudioPlaybackController::onPlaybackStateChanged(QMediaPlayer::PlaybackState state)
{
    bool wasPlaying = m_isPlaying;
    m_isPlaying = (state == QMediaPlayer::PlayingState);

    if (wasPlaying != m_isPlaying) {
        emit isPlayingChanged();
    }
}

void AudioPlaybackController::updateCurrentSegment()
{
    int newIndex = findSegmentAtPosition(m_position);

    if (newIndex != m_currentSegmentIndex && newIndex >= 0) {
        m_currentSegmentIndex = newIndex;

        if (m_currentSegmentIndex < m_segments.size()) {
            const SubtitleSegment& segment = m_segments[m_currentSegmentIndex];
            m_currentSegmentText = segment.text;
            emit currentSegmentIndexChanged();
            emit currentSegmentTextChanged();
            emit segmentChanged(m_currentSegmentIndex, segment.text, segment.startTime, segment.endTime);
        }
    }
}

int AudioPlaybackController::findSegmentAtPosition(qint64 position) const
{
    for (int i = 0; i < m_segments.size(); ++i) {
        const SubtitleSegment& segment = m_segments[i];
        if (position >= segment.startTime && position < segment.endTime) {
            return i;
        }
    }
    return -1;
}