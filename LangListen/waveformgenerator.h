#ifndef WAVEFORMGENERATOR_H
#define WAVEFORMGENERATOR_H

#include <QObject>
#include <QString>
#include <QVector>
#include <QVariantList>
#include <QThread>
#include <QMutex>
#include <atomic>
#include "audioconverter.h"

// 多级波形数据结构（Audacity风格）
struct MinMaxPair {
    float min;
    float max;

    MinMaxPair() : min(0.0f), max(0.0f) {}
    MinMaxPair(float _min, float _max) : min(_min), max(_max) {}
};

struct WaveformLevel {
    QVector<MinMaxPair> data;
    int samplesPerPixel;  // 每个像素代表多少个原始样本
};

// 工作线程：生成多级波形数据
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
    void waveformGenerated(QVariantList level1, QVariantList level2,
        QVariantList level3, QVariantList level4, QVariantList level5, qint64 duration);
    void generationFailed(const QString& error);
    void logMessage(const QString& message);

private:
    AudioConverter* m_audioConverter;
    std::atomic<bool> m_cancelled;

    // 生成多级波形数据（Audacity方式）
    void generateMultiLevelWaveform(const std::vector<float>& audioData,
        int sampleRate,
        QVector<WaveformLevel>& levels,
        qint64& duration);

    void generateRawSampleLevel(
        const std::vector<float>& audioData,
        QVector<MinMaxPair>& output);

    // 从音频数据生成指定级别的min/max数据
    void generateLevel(const std::vector<float>& audioData,
        int samplesPerPixel,
        QVector<MinMaxPair>& output);

    // 转换为QVariantList供QML使用
    QVariantList levelToVariantList(const QVector<MinMaxPair>& level);
};

// 主类：管理波形数据和工作线程
class WaveformGenerator : public QObject
{
    Q_OBJECT
        Q_PROPERTY(QVariantList level1Data READ level1Data NOTIFY level1DataChanged)
        Q_PROPERTY(QVariantList level2Data READ level2Data NOTIFY level2DataChanged)
        Q_PROPERTY(QVariantList level3Data READ level3Data NOTIFY level3DataChanged)
        Q_PROPERTY(QVariantList level4Data READ level4Data NOTIFY level4DataChanged)
        Q_PROPERTY(qint64 duration READ duration NOTIFY durationChanged)
        Q_PROPERTY(bool isLoaded READ isLoaded NOTIFY isLoadedChanged)
        Q_PROPERTY(bool isProcessing READ isProcessing NOTIFY isProcessingChanged)

public:
    explicit WaveformGenerator(QObject* parent = nullptr);
    ~WaveformGenerator();

    QVariantList level1Data() const { return m_level1Data; }
    QVariantList level2Data() const { return m_level2Data; }
    QVariantList level3Data() const { return m_level3Data; }
    QVariantList level4Data() const { return m_level4Data; }
    QVariantList level5Data() const { return m_level5Data; }
    qint64 duration() const { return m_duration; }
    bool isLoaded() const { return m_isLoaded; }
    bool isProcessing() const { return m_isProcessing; }

    Q_INVOKABLE bool loadAudio(const QString& filePath);
    Q_INVOKABLE void clear();
    Q_INVOKABLE void cancelLoading();

signals:
    void level1DataChanged();
    void level2DataChanged();
    void level3DataChanged();
    void level4DataChanged();
    void level5DataChanged();
    void durationChanged();
    void isLoadedChanged();
    void isProcessingChanged();
    void loadingProgress(int progress);
    void loadingCompleted();
    void loadingFailed(const QString& error);
    void logMessage(const QString& message);

private slots:
    void onWaveformGenerated(QVariantList level1, QVariantList level2,
        QVariantList level3, QVariantList level4, QVariantList level5, qint64 duration);
    void onGenerationFailed(const QString& error);
    void onProgressUpdated(int progress);

private:
    QVariantList m_level1Data;
    QVariantList m_level2Data;
    QVariantList m_level3Data;
    QVariantList m_level4Data;
    QVariantList m_level5Data;
    qint64 m_duration;
    bool m_isLoaded;
    bool m_isProcessing;

    AudioConverter* m_audioConverter;
    WaveformWorker* m_worker;
    QThread* m_workerThread;
};

#endif // WAVEFORMGENERATOR_H