#ifndef AUDIOPLAYBACKCONTROLLER_H
#define AUDIOPLAYBACKCONTROLLER_H

#include <QObject>
#include <QString>
#include <QVector>
#include "subtitlegenerator.h"

class FFmpegAudioEngine;

class AudioPlaybackController : public QObject
{
    Q_OBJECT
        Q_PROPERTY(bool isPlaying READ isPlaying NOTIFY isPlayingChanged)
        Q_PROPERTY(qint64 position READ position NOTIFY positionChanged)
        Q_PROPERTY(qint64 duration READ duration NOTIFY durationChanged)
        Q_PROPERTY(int currentSegmentIndex READ currentSegmentIndex NOTIFY currentSegmentIndexChanged)
        Q_PROPERTY(QString currentSegmentText READ currentSegmentText NOTIFY currentSegmentTextChanged)
        Q_PROPERTY(qreal volume READ volume WRITE setVolume NOTIFY volumeChanged)
        Q_PROPERTY(qreal playbackRate READ playbackRate WRITE setPlaybackRate NOTIFY playbackRateChanged)

public:
    explicit AudioPlaybackController(QObject* parent = nullptr);
    ~AudioPlaybackController();

    bool isPlaying() const;
    qint64 position() const;
    qint64 duration() const;
    int currentSegmentIndex() const;
    QString currentSegmentText() const;
    qreal volume() const;
    qreal playbackRate() const;

    Q_INVOKABLE void loadAudio(const QString& filePath);
    Q_INVOKABLE void setSubtitles(const QVector<SubtitleSegment>& segments);
    Q_INVOKABLE void play();
    Q_INVOKABLE void pause();
    Q_INVOKABLE void stop();
    Q_INVOKABLE void seekTo(qint64 position);
    Q_INVOKABLE void playSegment(int index);
    Q_INVOKABLE void playPreviousSegment();
    Q_INVOKABLE void playNextSegment();
    Q_INVOKABLE void replayCurrentSegment();
    Q_INVOKABLE void skipBackward(qint64 milliseconds = 5000);
    Q_INVOKABLE void skipForward(qint64 milliseconds = 5000);

    Q_INVOKABLE void setAutoPauseEnabled(bool enabled);
    Q_INVOKABLE void setSingleSentenceLoop(bool enabled);

    void setVolume(qreal volume);
    void setPlaybackRate(qreal rate);

signals:
    void isPlayingChanged();
    void positionChanged();
    void durationChanged();
    void currentSegmentIndexChanged();
    void currentSegmentTextChanged();
    void volumeChanged();
    void playbackRateChanged();
    void audioLoaded(bool success, const QString& message);
    void segmentChanged(int index, const QString& text, qint64 startTime, qint64 endTime);

private slots:
    void onPositionChanged();
    void onDurationChanged();
    void onSentenceChanged(int index);

private:
    FFmpegAudioEngine* m_engine;
    QVector<SubtitleSegment> m_segments;
    int m_currentSegmentIndex;
    QString m_currentSegmentText;
};

#endif // AUDIOPLAYBACKCONTROLLER_H