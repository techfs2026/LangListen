#include "waveformgenerator.h"
#include <QDebug>
#include <QtMath>
#include <algorithm>
#include <QThreadPool>
#include <QRunnable>
#include <QMutex>
#include <QWaitCondition>

WaveformWorker::WaveformWorker(QObject* parent)
    : QObject(parent)
    , m_audioConverter(nullptr)
    , m_cancelled(false)
{
}

WaveformWorker::~WaveformWorker()
{
}

void WaveformWorker::cancel()
{
    m_cancelled = true;
}

void WaveformWorker::processAudio(const QString& filePath)
{
    m_cancelled = false;

    emit logMessage("Loading audio: " + filePath);
    emit progressUpdated(0);

    std::vector<float> audioData;
    AudioConverter::ConversionParams params;
    params.targetSampleRate = 44100;
    params.targetChannels = 1;
    params.targetFormat = AV_SAMPLE_FMT_S16;

    if (!m_audioConverter->convertToMemory(filePath, audioData, params)) {
        emit generationFailed("Failed to load audio: " + m_audioConverter->getLastError());
        return;
    }

    if (m_cancelled) {
        emit logMessage("Cancelled");
        return;
    }

    if (audioData.empty()) {
        emit generationFailed("Audio data is empty");
        return;
    }

    emit progressUpdated(10);
    emit logMessage(QString("Loaded %1 samples at %2Hz").arg(audioData.size()).arg(params.targetSampleRate));

    QVector<WaveformLevel> levels;
    qint64 duration;

    try {
        generateMultiLevelWaveform(audioData, params.targetSampleRate, levels, duration);
    }
    catch (const std::exception& e) {
        emit generationFailed(QString("Generation error: %1").arg(e.what()));
        return;
    }

    if (m_cancelled) {
        emit logMessage("Cancelled");
        return;
    }

    emit progressUpdated(100);
    emit logMessage(QString("Generated %1 LOD levels").arg(levels.size()));

    emit waveformGenerated(levels, duration);
}

class LevelGeneratorTask : public QRunnable
{
public:
    LevelGeneratorTask(const std::vector<float>* audioData,
        int sampleRate,
        WaveformLevel* level,
        std::atomic<bool>* cancelled,
        QMutex* mutex,
        int* completed,
        QWaitCondition* condition)
        : m_audioData(audioData)
        , m_sampleRate(sampleRate)
        , m_level(level)
        , m_cancelled(cancelled)
        , m_mutex(mutex)
        , m_completed(completed)
        , m_condition(condition)
    {
        setAutoDelete(true);
    }

    void run() override
    {
        if (m_cancelled->load()) return;

        int samplesPerPixel = m_level->samplesPerPixel;
        if (samplesPerPixel < 1) samplesPerPixel = 1;

        int totalSamples = m_audioData->size();
        int numPixels = (totalSamples + samplesPerPixel - 1) / samplesPerPixel;

        m_level->data.clear();
        m_level->data.reserve(numPixels);

        for (int pixel = 0; pixel < numPixels; ++pixel) {
            if (m_cancelled->load()) return;

            int startIdx = pixel * samplesPerPixel;
            int endIdx = qMin(startIdx + samplesPerPixel, totalSamples);

            float minVal = 0.0f;
            float maxVal = 0.0f;

            if (startIdx < totalSamples) {
                minVal = (*m_audioData)[startIdx];
                maxVal = (*m_audioData)[startIdx];

                for (int i = startIdx + 1; i < endIdx; ++i) {
                    float sample = (*m_audioData)[i];
                    if (sample < minVal) minVal = sample;
                    if (sample > maxVal) maxVal = sample;
                }
            }

            m_level->data.append(MinMaxPair(minVal, maxVal));
        }

        QMutexLocker locker(m_mutex);
        (*m_completed)++;
        m_condition->wakeAll();
    }

private:
    const std::vector<float>* m_audioData;
    int m_sampleRate;
    WaveformLevel* m_level;
    std::atomic<bool>* m_cancelled;
    QMutex* m_mutex;
    int* m_completed;
    QWaitCondition* m_condition;
};

void WaveformWorker::generateMultiLevelWaveform(
    const std::vector<float>& audioData,
    int sampleRate,
    QVector<WaveformLevel>& levels,
    qint64& duration)
{
    int totalSamples = audioData.size();
    duration = static_cast<qint64>((totalSamples * 1000.0) / sampleRate);

    QVector<int> lodLevels = {
        1, 2, 4, 8, 16, 32, 64, 128, 256, 512,
        1024, 2048, 4096, 8192, 16384, 32768
    };

    levels.clear();
    levels.reserve(lodLevels.size());

    for (int i = 0; i < lodLevels.size(); ++i) {
        if (m_cancelled) return;

        int samplesPerPixel = lodLevels[i];
        double pixelsPerSecond = static_cast<double>(sampleRate) / samplesPerPixel;

        WaveformLevel level;
        level.samplesPerPixel = samplesPerPixel;
        level.pixelsPerSecond = pixelsPerSecond;

        levels.append(level);

        emit logMessage(QString("LOD %1: %2 samples/px, %3 px/s")
            .arg(i)
            .arg(samplesPerPixel)
            .arg(pixelsPerSecond, 0, 'f', 2));
    }

    QMutex mutex;
    QWaitCondition condition;
    int completed = 0;

    QThreadPool* pool = QThreadPool::globalInstance();
    int maxThreads = pool->maxThreadCount();

    for (int i = 0; i < levels.size(); ++i) {
        if (m_cancelled) return;

        LevelGeneratorTask* task = new LevelGeneratorTask(
            &audioData,
            sampleRate,
            &levels[i],
            &m_cancelled,
            &mutex,
            &completed,
            &condition
        );
        pool->start(task);
    }

    while (completed < levels.size()) {
        {
            QMutexLocker locker(&mutex);
            condition.wait(&mutex, 100);
        }

        if (m_cancelled) return;

        int progress = 10 + (completed * 90) / levels.size();
        emit progressUpdated(progress);
    }

    pool->waitForDone();
}

void WaveformWorker::generateLevel(const std::vector<float>& audioData,
    int sampleRate,
    int samplesPerPixel,
    QVector<MinMaxPair>& output)
{
    if (samplesPerPixel < 1) samplesPerPixel = 1;

    int totalSamples = audioData.size();
    int numPixels = (totalSamples + samplesPerPixel - 1) / samplesPerPixel;

    output.clear();
    output.reserve(numPixels);

    for (int pixel = 0; pixel < numPixels; ++pixel) {
        if (m_cancelled) return;

        int startIdx = pixel * samplesPerPixel;
        int endIdx = qMin(startIdx + samplesPerPixel, totalSamples);

        float minVal = audioData[startIdx];
        float maxVal = audioData[startIdx];

        for (int i = startIdx + 1; i < endIdx; ++i) {
            float sample = audioData[i];
            if (sample < minVal) minVal = sample;
            if (sample > maxVal) maxVal = sample;
        }

        output.append(MinMaxPair(minVal, maxVal));
    }
}

WaveformGenerator::WaveformGenerator(QObject* parent)
    : QObject(parent)
    , m_duration(0)
    , m_isLoaded(false)
    , m_isProcessing(false)
{
    m_audioConverter = new AudioConverter(this);

    m_worker = new WaveformWorker();
    m_workerThread = new QThread(this);

    m_worker->setAudioConverter(m_audioConverter);
    m_worker->moveToThread(m_workerThread);

    connect(m_workerThread, &QThread::finished, m_worker, &QObject::deleteLater);

    connect(m_worker, &WaveformWorker::waveformGenerated,
        this, &WaveformGenerator::onWaveformGenerated);
    connect(m_worker, &WaveformWorker::generationFailed,
        this, &WaveformGenerator::onGenerationFailed);
    connect(m_worker, &WaveformWorker::progressUpdated,
        this, &WaveformGenerator::onProgressUpdated);
    connect(m_worker, &WaveformWorker::logMessage,
        this, &WaveformGenerator::logMessage);

    m_workerThread->start();

    emit logMessage("WaveformGenerator initialized");
}

WaveformGenerator::~WaveformGenerator()
{
    if (m_workerThread) {
        m_workerThread->quit();
        m_workerThread->wait(3000);
    }
}

bool WaveformGenerator::loadAudio(const QString& filePath)
{
    if (m_isProcessing) {
        emit logMessage("Already processing");
        return false;
    }

    clear();

    m_isProcessing = true;
    emit isProcessingChanged();

    QMetaObject::invokeMethod(m_worker, [this, filePath]() {
        m_worker->processAudio(filePath);
        }, Qt::QueuedConnection);

    return true;
}

void WaveformGenerator::clear()
{
    m_levels.clear();
    m_duration = 0;
    m_isLoaded = false;

    emit levelsChanged();
    emit durationChanged();
    emit isLoadedChanged();
}

void WaveformGenerator::cancelLoading()
{
    if (m_isProcessing && m_worker) {
        m_worker->cancel();
        emit logMessage("Cancelling...");
    }
}

int WaveformGenerator::findBestLevel(double pixelsPerSecond) const
{
    if (m_levels.isEmpty()) {
        return -1;
    }

    int bestIndex = 0;
    double minDiff = qAbs(m_levels[0].pixelsPerSecond - pixelsPerSecond);

    for (int i = 1; i < m_levels.size(); ++i) {
        double diff = qAbs(m_levels[i].pixelsPerSecond - pixelsPerSecond);
        if (diff < minDiff) {
            minDiff = diff;
            bestIndex = i;
        }
    }

    return bestIndex;
}

QVariantList WaveformGenerator::getLevelData(int levelIndex) const
{
    if (levelIndex < 0 || levelIndex >= m_levels.size()) {
        return QVariantList();
    }

    const QVector<MinMaxPair>& data = m_levels[levelIndex].data;
    QVariantList result;
    result.reserve(data.size() * 2);

    for (const MinMaxPair& pair : data) {
        result.append(pair.min);
        result.append(pair.max);
    }

    return result;
}

void WaveformGenerator::onWaveformGenerated(QVector<WaveformLevel> levels, qint64 duration)
{
    m_levels = levels;
    m_duration = duration;
    m_isLoaded = true;
    m_isProcessing = false;

    emit levelsChanged();
    emit durationChanged();
    emit isLoadedChanged();
    emit isProcessingChanged();
    emit loadingCompleted();

    emit logMessage(QString("Ready: %1ms, %2 levels")
        .arg(duration)
        .arg(levels.size()));
}

void WaveformGenerator::onGenerationFailed(const QString& error)
{
    m_isProcessing = false;
    emit isProcessingChanged();
    emit loadingFailed(error);
    emit logMessage("ERROR: " + error);
}

void WaveformGenerator::onProgressUpdated(int progress)
{
    emit loadingProgress(progress);
}