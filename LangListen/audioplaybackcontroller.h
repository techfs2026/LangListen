#ifndef AUDIOPLAYBACKCONTROLLER_H
#define AUDIOPLAYBACKCONTROLLER_H

#include <QObject>
#include <QMediaPlayer>
#include <QAudioOutput>
#include <QString>
#include "subtitlegenerator.h"

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

    bool isPlaying() const { return m_isPlaying; }
    qint64 position() const { return m_position; }
    qint64 duration() const { return m_duration; }
    int currentSegmentIndex() const { return m_currentSegmentIndex; }
    QString currentSegmentText() const { return m_currentSegmentText; }
    qreal volume() const { return m_volume; }
    qreal playbackRate() const { return m_playbackRate; }

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
    void onPositionChanged(qint64 position);
    void onDurationChanged(qint64 duration);
    void onPlaybackStateChanged(QMediaPlayer::PlaybackState state);

private:
    QMediaPlayer* m_player;
    QAudioOutput* m_audioOutput;
    QVector<SubtitleSegment> m_segments;

    bool m_isPlaying;
    qint64 m_position;
    qint64 m_duration;
    int m_currentSegmentIndex;
    QString m_currentSegmentText;
    qreal m_volume;
    qreal m_playbackRate;

    void updateCurrentSegment();
    int findSegmentAtPosition(qint64 position) const;
};

#endif