#ifndef WAVEFORMGENERATOR_H
#define WAVEFORMGENERATOR_H

#include <QObject>
#include <QString>
#include <QVector>
#include <QVariantList>
#include <QThread>
#include <QMutex>
#include <QMap>
#include <atomic>
#include "audioconverter.h"

struct MinMaxPair {
    float min;
    float max;

    MinMaxPair() : min(0.0f), max(0.0f) {}
    MinMaxPair(float _min, float _max) : min(_min), max(_max) {}
};

struct WaveformLevel {
    QVector<MinMaxPair> data;
    int samplesPerPixel;
    double pixelsPerSecond;

    WaveformLevel() : samplesPerPixel(0), pixelsPerSecond(0.0) {}
};

class WaveformWorker : public QObject
{
    Q_OBJECT

public:
    explicit WaveformWorker(QObject* parent = nullptr);
    ~WaveformWorker();

    void setAudioConverter(AudioConverter* converter) { m_audioConverter = converter; }

public slots:
    void processAudio(const QString& filePath);
    void cancel();

signals:
    void progressUpdated(int progress);
    void waveformGenerated(QVector<WaveformLevel> levels, qint64 duration);
    void generationFailed(const QString& error);
    void logMessage(const QString& message);

private:
    AudioConverter* m_audioConverter;
    std::atomic<bool> m_cancelled;

    void generateMultiLevelWaveform(const std::vector<float>& audioData,
        int sampleRate,
        QVector<WaveformLevel>& levels,
        qint64& duration);

    void generateLevel(const std::vector<float>& audioData,
        int sampleRate,
        int samplesPerPixel,
        QVector<MinMaxPair>& output);
};

class WaveformGenerator : public QObject
{
    Q_OBJECT
        Q_PROPERTY(qint64 duration READ duration NOTIFY durationChanged)
        Q_PROPERTY(bool isLoaded READ isLoaded NOTIFY isLoadedChanged)
        Q_PROPERTY(bool isProcessing READ isProcessing NOTIFY isProcessingChanged)

public:
    explicit WaveformGenerator(QObject* parent = nullptr);
    ~WaveformGenerator();

    qint64 duration() const { return m_duration; }
    bool isLoaded() const { return m_isLoaded; }
    bool isProcessing() const { return m_isProcessing; }

    const QVector<WaveformLevel>& getLevels() const { return m_levels; }

    Q_INVOKABLE bool loadAudio(const QString& filePath);
    Q_INVOKABLE void clear();
    Q_INVOKABLE void cancelLoading();
    Q_INVOKABLE int findBestLevel(double pixelsPerSecond) const;
    Q_INVOKABLE QVariantList getLevelData(int levelIndex) const;

signals:
    void durationChanged();
    void isLoadedChanged();
    void isProcessingChanged();
    void loadingProgress(int progress);
    void loadingCompleted();
    void loadingFailed(const QString& error);
    void logMessage(const QString& message);
    void levelsChanged();

private slots:
    void onWaveformGenerated(QVector<WaveformLevel> levels, qint64 duration);
    void onGenerationFailed(const QString& error);
    void onProgressUpdated(int progress);

private:
    QVector<WaveformLevel> m_levels;
    qint64 m_duration;
    bool m_isLoaded;
    bool m_isProcessing;

    AudioConverter* m_audioConverter;
    WaveformWorker* m_worker;
    QThread* m_workerThread;
};

#endif