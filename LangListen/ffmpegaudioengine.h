#ifndef FFMPEGAUDIOENGINE_PORTAUDIO_H
#define FFMPEGAUDIOENGINE_PORTAUDIO_H

#include <QObject>
#include <QThread>
#include <QMutex>
#include <QTimer>
#include <atomic>
#include <memory>
#include <portaudio.h>

extern "C" {
#include <libavformat/avformat.h>
#include <libavcodec/avcodec.h>
#include <libswresample/swresample.h>
}

class AudioRingBuffer;

class FFmpegDecoder : public QThread
{
    Q_OBJECT

public:
    explicit FFmpegDecoder(AudioRingBuffer* ringBuffer, QObject* parent = nullptr);
    ~FFmpegDecoder();

    bool openFile(const QString& filePath);
    void close();

    void seekTo(qint64 positionMs);

    void startDecoding();
    void stopDecoding();
    void pauseDecoding();
    void resumeDecoding();

    qint64 getDuration() const { return m_duration; }
    int getSampleRate() const { return m_sampleRate; }
    int getChannels() const { return m_channels; }

signals:
    void errorOccurred(const QString& error);
    void durationChanged(qint64 duration);
    void decodingFinished();

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

    AudioRingBuffer* m_ringBuffer;

    std::atomic<bool> m_running;
    std::atomic<bool> m_decoding;
    std::atomic<bool> m_pauseRequested;
    std::atomic<bool> m_seekRequested;
    std::atomic<qint64> m_seekTargetMs;

    bool initDecoder();
    void cleanupDecoder();
    bool initResampler();
    void cleanupResampler();
    bool performSeek(qint64 targetMs);
    bool resampleFrame(AVFrame* frame, QByteArray& outData);
    QString getErrorString(int errnum) const;
};


struct SentenceSegment {
    qint64 startTimeMs;
    qint64 endTimeMs;
    QString text;

    SentenceSegment() : startTimeMs(0), endTimeMs(0) {}
    SentenceSegment(qint64 start, qint64 end, const QString& txt = QString())
        : startTimeMs(start), endTimeMs(end), text(txt) {
    }

    bool contains(qint64 timeMs) const {
        return timeMs >= startTimeMs && timeMs < endTimeMs;
    }
};

enum class PlaybackState {
    Stopped,
    Playing,
    Paused
};

class FFmpegAudioEngine : public QObject
{
    Q_OBJECT
        Q_PROPERTY(bool isPlaying READ isPlaying NOTIFY isPlayingChanged)
        Q_PROPERTY(qint64 position READ position NOTIFY positionChanged)
        Q_PROPERTY(qint64 duration READ duration NOTIFY durationChanged)
        Q_PROPERTY(qreal volume READ volume WRITE setVolume NOTIFY volumeChanged)
        Q_PROPERTY(qreal playbackRate READ playbackRate NOTIFY playbackRateChanged)

public:
    explicit FFmpegAudioEngine(QObject* parent = nullptr);
    ~FFmpegAudioEngine();

    Q_INVOKABLE bool loadAudio(const QString& filePath);
    Q_INVOKABLE void closeAudio();

    Q_INVOKABLE void play();
    Q_INVOKABLE void pause();
    Q_INVOKABLE void stop();
    Q_INVOKABLE void seekTo(qint64 positionMs);

    void setSentenceSegments(const QVector<SentenceSegment>& segments);
    void setCurrentSentenceIndex(int index);
    int getCurrentSentenceIndex() const { return m_currentSentenceIndex; }

    void setSingleSentenceLoop(bool enable);
    void setAutoPauseAtSentenceEnd(bool enable);
    bool isSingleSentenceLoop() const { return m_singleSentenceLoop; }
    bool isAutoPauseEnabled() const { return m_autoPauseEnabled; }

    Q_INVOKABLE void setLoopRange(qint64 startMs, qint64 endMs);
    Q_INVOKABLE void clearLoopRange();

    bool isPlaying() const { return m_state == PlaybackState::Playing; }
    qint64 position() const;
    qint64 duration() const { return m_duration; }
    qreal volume() const { return m_volume; }
    qreal playbackRate() const { return 1.0; }

    void setVolume(qreal volume);
    void setPlaybackRate(qreal rate);

signals:
    void isPlayingChanged();
    void positionChanged();
    void durationChanged();
    void volumeChanged();
    void playbackRateChanged();
    void audioLoaded(bool success, const QString& message);
    void errorOccurred(const QString& error);
    void playbackFinished();
    void sentenceChanged(int index);

private slots:
    void onDecoderError(const QString& error);
    void onDecoderFinished();
    void onPositionUpdateTimer();

private:
    FFmpegDecoder* m_decoder;
    AudioRingBuffer* m_ringBuffer;

    PaStream* m_paStream;
    int m_sampleRate;
    int m_channels;

    PlaybackState m_state;
    qint64 m_duration;
    qreal m_volume;
    std::atomic<qreal> m_volumeAtomic;

    std::atomic<qint64> m_totalFramesPlayed;
    qint64 m_seekPositionMs;
    QMutex m_seekMutex;

    QVector<SentenceSegment> m_sentences;
    int m_currentSentenceIndex;
    bool m_singleSentenceLoop;
    bool m_autoPauseEnabled;

    bool m_loopRangeEnabled;
    qint64 m_loopStartMs;
    qint64 m_loopEndMs;

    QTimer* m_positionTimer;

    std::atomic<bool> m_decoderEOF;

    bool initPortAudio();
    void cleanupPortAudio();

    void startPlayback();
    void stopPlayback();
    void performSeek(qint64 targetMs);

    qint64 getAudioClockMs() const;
    void resetAudioClock(qint64 positionMs);

    void updateCurrentSentence();
    void handleSentenceEnd();
    void playNextSentence();
    void playPreviousSentence();

    static int paCallback(
        const void* inputBuffer,
        void* outputBuffer,
        unsigned long framesPerBuffer,
        const PaStreamCallbackTimeInfo* timeInfo,
        PaStreamCallbackFlags statusFlags,
        void* userData
    );
};

#endif // FFMPEGAUDIOENGINE_PORTAUDIO_H