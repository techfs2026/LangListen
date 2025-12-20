#include "audioplaybackcontroller.h"
#include "ffmpegaudioengine.h"
#include <QUrl>

class AudioPlaybackControllerPrivate
{
public:
    FFmpegAudioEngine* engine;
    QVector<SubtitleSegment> segments;
    int currentSegmentIndex;
    QString currentSegmentText;

    AudioPlaybackControllerPrivate()
        : engine(nullptr)
        , currentSegmentIndex(-1)
    {
    }
};

AudioPlaybackController::AudioPlaybackController(QObject* parent)
    : QObject(parent)
    , d(new AudioPlaybackControllerPrivate)
{
    d->engine = new FFmpegAudioEngine(this);

    connect(d->engine, &FFmpegAudioEngine::isPlayingChanged,
        this, &AudioPlaybackController::isPlayingChanged);
    connect(d->engine, &FFmpegAudioEngine::positionChanged,
        this, &AudioPlaybackController::onPositionChanged);
    connect(d->engine, &FFmpegAudioEngine::durationChanged,
        this, &AudioPlaybackController::onDurationChanged);
    connect(d->engine, &FFmpegAudioEngine::volumeChanged,
        this, &AudioPlaybackController::volumeChanged);
    connect(d->engine, &FFmpegAudioEngine::playbackRateChanged,
        this, &AudioPlaybackController::playbackRateChanged);
    connect(d->engine, &FFmpegAudioEngine::audioLoaded,
        this, &AudioPlaybackController::audioLoaded);
    connect(d->engine, &FFmpegAudioEngine::errorOccurred,
        this, [this](const QString& error) {
            emit audioLoaded(false, error);
        });
}

AudioPlaybackController::~AudioPlaybackController()
{
    delete d;
}

void AudioPlaybackController::loadAudio(const QString& filePath)
{
    d->engine->stop();

    bool success = d->engine->loadAudio(filePath);

    if (!success) {
        emit audioLoaded(false, "Failed to load audio: " + filePath);
    }
}

void AudioPlaybackController::setSubtitles(const QVector<SubtitleSegment>& segments)
{
    d->segments = segments;
    d->currentSegmentIndex = -1;
    d->currentSegmentText.clear();
    emit currentSegmentIndexChanged();
    emit currentSegmentTextChanged();
}

void AudioPlaybackController::play()
{
    d->engine->play();
}

void AudioPlaybackController::pause()
{
    d->engine->pause();
}

void AudioPlaybackController::stop()
{
    d->engine->stop();
    d->currentSegmentIndex = -1;
    d->currentSegmentText.clear();
    emit currentSegmentIndexChanged();
    emit currentSegmentTextChanged();
}

void AudioPlaybackController::seekTo(qint64 position)
{
    d->engine->seekTo(position);
}

void AudioPlaybackController::playSegment(int index)
{
    if (index < 0 || index >= d->segments.size()) {
        return;
    }

    const SubtitleSegment& segment = d->segments[index];

    d->currentSegmentIndex = index;
    d->currentSegmentText = segment.text;

    d->engine->clearLoopRange();
    d->engine->seekTo(segment.startTime);

    emit currentSegmentIndexChanged();
    emit currentSegmentTextChanged();
    emit segmentChanged(index, segment.text, segment.startTime, segment.endTime);

    d->engine->play();
}

void AudioPlaybackController::playPreviousSegment()
{
    if (d->currentSegmentIndex > 0) {
        playSegment(d->currentSegmentIndex - 1);
    }
}

void AudioPlaybackController::playNextSegment()
{
    if (d->currentSegmentIndex < d->segments.size() - 1) {
        playSegment(d->currentSegmentIndex + 1);
    }
}

void AudioPlaybackController::replayCurrentSegment()
{
    if (d->currentSegmentIndex >= 0 && d->currentSegmentIndex < d->segments.size()) {
        const SubtitleSegment& segment = d->segments[d->currentSegmentIndex];
        d->engine->seekTo(segment.startTime);
        emit segmentChanged(d->currentSegmentIndex, segment.text, segment.startTime, segment.endTime);
        d->engine->play();
    }
}

void AudioPlaybackController::skipBackward(qint64 milliseconds)
{
    qint64 newPosition = qMax(0LL, position() - milliseconds);
    d->engine->seekTo(newPosition);
}

void AudioPlaybackController::skipForward(qint64 milliseconds)
{
    qint64 newPosition = qMin(duration(), position() + milliseconds);
    d->engine->seekTo(newPosition);
}

void AudioPlaybackController::setVolume(qreal volume)
{
    d->engine->setVolume(volume);
}

void AudioPlaybackController::setPlaybackRate(qreal rate)
{
    d->engine->setPlaybackRate(rate);
}

bool AudioPlaybackController::isPlaying() const
{
    return d->engine->isPlaying();
}

qint64 AudioPlaybackController::position() const
{
    return d->engine->position();
}

qint64 AudioPlaybackController::duration() const
{
    return d->engine->duration();
}

int AudioPlaybackController::currentSegmentIndex() const
{
    return d->currentSegmentIndex;
}

QString AudioPlaybackController::currentSegmentText() const
{
    return d->currentSegmentText;
}

qreal AudioPlaybackController::volume() const
{
    return d->engine->volume();
}

qreal AudioPlaybackController::playbackRate() const
{
    return d->engine->playbackRate();
}

void AudioPlaybackController::onPositionChanged()
{
    emit positionChanged();
    updateCurrentSegment();
}

void AudioPlaybackController::onDurationChanged()
{
    emit durationChanged();
}

void AudioPlaybackController::updateCurrentSegment()
{
    qint64 pos = d->engine->position();
    int newIndex = findSegmentAtPosition(pos);

    if (newIndex != d->currentSegmentIndex && newIndex >= 0) {
        d->currentSegmentIndex = newIndex;

        if (d->currentSegmentIndex < d->segments.size()) {
            const SubtitleSegment& segment = d->segments[d->currentSegmentIndex];
            d->currentSegmentText = segment.text;
            emit currentSegmentIndexChanged();
            emit currentSegmentTextChanged();
            emit segmentChanged(d->currentSegmentIndex, segment.text, segment.startTime, segment.endTime);
        }
    }
}

int AudioPlaybackController::findSegmentAtPosition(qint64 position) const
{
    for (int i = 0; i < d->segments.size(); ++i) {
        const SubtitleSegment& segment = d->segments[i];
        if (position >= segment.startTime && position < segment.endTime) {
            return i;
        }
    }
    return -1;
}