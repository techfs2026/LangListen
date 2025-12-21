#ifndef FFMPEGAUDIOENGINE_H
#define FFMPEGAUDIOENGINE_H

#include <QObject>
#include <QAudioSink>
#include <QAudioFormat>
#include <QIODevice>
#include <QThread>
#include <QMutex>
#include <QWaitCondition>
#include <QQueue>
#include <QDateTime>
#include <QTimer>
#include <atomic>
#include <memory>

#ifdef Q_OS_WIN
#include <windows.h>
#endif

extern "C" {
#include <libavformat/avformat.h>
#include <libavcodec/avcodec.h>
#include <libswresample/swresample.h>
#include <libavutil/opt.h>
#include <libavutil/time.h>
}

struct AudioPacket {
    QByteArray data;
    qint64 pts;

    AudioPacket() : pts(0) {}
    AudioPacket(const QByteArray& d, qint64 p) : data(d), pts(p) {}
};

enum class PlaybackState {
    Stopped,
    Playing,
    Paused
};

class FFmpegDecoder : public QThread
{
    Q_OBJECT

public:
    FFmpegDecoder(QObject* parent = nullptr);
    ~FFmpegDecoder();

    bool openFile(const QString& filePath);
    void close();

    void seekTo(qint64 positionMs);
    void setPlaybackRate(double rate);

    qint64 getDuration() const { return m_duration; }
    int getSampleRate() const { return m_sampleRate; }
    int getChannels() const { return m_channels; }
    int getOutputSampleRate() const { return m_outputSampleRate; }
    double getPlaybackRate() const { return m_playbackRate; }

    void stopDecoding();
    void pauseDecoding();
    void resumeDecoding();
    void resetEOF();

    bool getNextPacket(AudioPacket& packet, int timeoutMs = 100);
    void clearQueue();

    bool isDecoding() const { return isRunning() && !m_stopRequested; }

    int hasQueuedPackets();

signals:
    void decodingStarted();
    void decodingFinished();
    void errorOccurred(const QString& error);
    void durationChanged(qint64 duration);

protected:
    void run() override;

private:
    AVFormatContext* m_formatCtx;
    AVCodecContext* m_codecCtx;
    SwrContext* m_swrCtx;

    int m_audioStreamIndex;

    qint64 m_duration;
    int m_sampleRate;
    int m_channels;
    int m_outputSampleRate;

    std::atomic<bool> m_stopRequested;
    std::atomic<bool> m_pauseRequested;
    std::atomic<bool> m_seekRequested;
    std::atomic<qint64> m_seekTargetMs;
    std::atomic<double> m_playbackRate;
    bool m_needRebuildResampler;

    QQueue<AudioPacket> m_packetQueue;
    QMutex m_queueMutex;
    QWaitCondition m_queueNotFull;
    QWaitCondition m_queueNotEmpty;
    static const int MAX_QUEUE_SIZE = 50;

    QString m_filePath;

    bool initDecoder();
    void cleanupDecoder();
    bool initResampler();
    void cleanupResampler();
    bool rebuildResampler();
    bool resampleFrame(AVFrame* frame, QByteArray& outData);
    bool performSeek(qint64 targetMs);
};

class FFmpegAudioEngine : public QObject
{
    Q_OBJECT
        Q_PROPERTY(bool isPlaying READ isPlaying NOTIFY isPlayingChanged)
        Q_PROPERTY(qint64 position READ position NOTIFY positionChanged)
        Q_PROPERTY(qint64 duration READ duration NOTIFY durationChanged)
        Q_PROPERTY(qreal volume READ volume WRITE setVolume NOTIFY volumeChanged)
        Q_PROPERTY(qreal playbackRate READ playbackRate WRITE setPlaybackRate NOTIFY playbackRateChanged)

public:
    explicit FFmpegAudioEngine(QObject* parent = nullptr);
    ~FFmpegAudioEngine();

    Q_INVOKABLE bool loadAudio(const QString& filePath);
    Q_INVOKABLE void closeAudio();

    Q_INVOKABLE void play();
    Q_INVOKABLE void pause();
    Q_INVOKABLE void stop();
    Q_INVOKABLE void seekTo(qint64 positionMs);

    bool isPlaying() const { return m_state == PlaybackState::Playing; }
    qint64 position() const { return m_currentPosition; }
    qint64 duration() const { return m_duration; }
    qreal volume() const { return m_volume; }
    qreal playbackRate() const { return m_playbackRate; }

    void setVolume(qreal volume);
    void setPlaybackRate(qreal rate);

    Q_INVOKABLE void setLoopRange(qint64 startMs, qint64 endMs);
    Q_INVOKABLE void clearLoopRange();
    bool isLooping() const { return m_loopEnabled; }

signals:
    void isPlayingChanged();
    void positionChanged();
    void durationChanged();
    void volumeChanged();
    void playbackRateChanged();
    void audioLoaded(bool success, const QString& message);
    void errorOccurred(const QString& error);
    void playbackFinished();

private slots:
    void onDecoderFinished();
    void onDecoderError(const QString& error);
    void onAudioOutputStateChanged(QAudio::State state);

private:
    FFmpegDecoder* m_decoder;
    QThread* m_decoderThread;

    QAudioSink* m_audioSink;
    QIODevice* m_audioDevice;
    QAudioFormat m_audioFormat;

    PlaybackState m_state;
    qint64 m_currentPosition;
    qint64 m_duration;
    qreal m_volume;
    qreal m_playbackRate;
    bool m_decoderEOF;
    bool m_isSeeking;

    bool m_loopEnabled;
    qint64 m_loopStartMs;
    qint64 m_loopEndMs;

    QTimer* m_playbackTimer;
    QTimer* m_positionTimer;

    QByteArray m_audioBuffer;
    qint64 m_bufferPts;

    qint64 m_lastSeekPosition;
    qint64 m_lastBytesProcessed;

    qint64 m_audioSinkBaselineUs;

    bool initAudioOutput();
    void cleanupAudioOutput();
    void processAudioData();
    void updatePosition();
    bool hasPendingAudio();
    QString getErrorString(int errnum) const;

    void preventSystemSleep();
    void allowSystemSleep();
};

#endif