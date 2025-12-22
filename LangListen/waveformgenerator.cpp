#include "waveformgenerator.h"
#include <QDebug>
#include <QtMath>
#include <algorithm>

// ============================================================================
// WaveformWorker 实现
// ============================================================================

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

    emit logMessage("Loading audio for waveform: " + filePath);
    emit progressUpdated(0);

    // 加载音频：使用16kHz（平衡质量和性能）
    std::vector<float> audioData;
    AudioConverter::ConversionParams params;
    params.targetSampleRate = 16000;  // 比8kHz更好的质量
    params.targetChannels = 1;
    params.targetFormat = AV_SAMPLE_FMT_S16;

    if (!m_audioConverter->convertToMemory(filePath, audioData, params)) {
        emit generationFailed("Failed to load audio: " + m_audioConverter->getLastError());
        return;
    }

    if (m_cancelled) {
        emit logMessage("Waveform generation cancelled");
        return;
    }

    if (audioData.empty()) {
        emit generationFailed("Audio data is empty");
        return;
    }

    emit progressUpdated(20);
    emit logMessage(QString("Audio loaded: %1 samples at 16kHz").arg(audioData.size()));

    // 生成多级波形数据
    QVector<WaveformLevel> levels;
    qint64 duration;

    try {
        generateMultiLevelWaveform(audioData, params.targetSampleRate, levels, duration);
    }
    catch (const std::exception& e) {
        emit generationFailed(QString("Waveform generation error: %1").arg(e.what()));
        return;
    }

    if (m_cancelled) {
        emit logMessage("Waveform generation cancelled");
        return;
    }

    // 转换为QVariantList
    QVariantList level1 = levelToVariantList(levels[0].data);
    QVariantList level2 = levelToVariantList(levels[1].data);
    QVariantList level3 = levelToVariantList(levels[2].data);
    QVariantList level4 = levelToVariantList(levels[3].data);
    QVariantList level5 = levelToVariantList(levels[4].data);

    emit progressUpdated(100);
    emit logMessage(QString("Multi-level waveform generated. L1:%1 L2:%2 L3:%3 L4:%4 L5:%5")
        .arg(levels[0].data.size())
        .arg(levels[1].data.size())
        .arg(levels[2].data.size())
        .arg(levels[3].data.size())
        .arg(levels[4].data.size()));

    emit waveformGenerated(level1, level2, level3, level4, level5, duration);
}

void WaveformWorker::generateRawSampleLevel(
    const std::vector<float>& audioData,
    QVector<MinMaxPair>& output)
{
    output.clear();
    output.reserve(audioData.size());

    for (float s : audioData) {
        // 每个 sample 占 1 像素，min == max
        output.append(MinMaxPair(s, s));
    }
}

void WaveformWorker::generateMultiLevelWaveform(
    const std::vector<float>& audioData,
    int sampleRate,
    QVector<WaveformLevel>& levels,
    qint64& duration)
{
    int totalSamples = audioData.size();
    duration = static_cast<qint64>((totalSamples * 1000.0) / sampleRate);

    levels.resize(5);  // 增加到5层

    // Level 1: 最缩小视图（1px = 256 samples）
    levels[0].samplesPerPixel = 256;
    emit logMessage("Generating Level 1 (1:256)...");
    generateLevel(audioData, 256, levels[0].data);
    emit progressUpdated(30);
    if (m_cancelled) return;

    // Level 2: 缩小视图（1px = 128 samples）
    levels[1].samplesPerPixel = 128;
    emit logMessage("Generating Level 2 (1:128)...");
    generateLevel(audioData, 128, levels[1].data);
    emit progressUpdated(45);
    if (m_cancelled) return;

    // Level 3: 正常视图（1px = 32 samples） - 默认层级
    levels[2].samplesPerPixel = 32;
    emit logMessage("Generating Level 3 (1:32)...");
    generateLevel(audioData, 32, levels[2].data);
    emit progressUpdated(60);
    if (m_cancelled) return;

    // Level 4: 放大视图（1px = 8 samples）
    levels[3].samplesPerPixel = 8;
    emit logMessage("Generating Level 4 (1:8)...");
    generateLevel(audioData, 8, levels[3].data);
    emit progressUpdated(75);
    if (m_cancelled) return;

    // Level 5: 最大放大（1px = 1 sample）
    levels[4].samplesPerPixel = 1;
    emit logMessage("Generating Level 5 (raw samples)...");
    generateRawSampleLevel(audioData, levels[4].data);
    emit progressUpdated(90);
}

void WaveformWorker::generateLevel(const std::vector<float>& audioData,
    int samplesPerPixel,
    QVector<MinMaxPair>& output)
{
    int totalSamples = audioData.size();
    int numPixels = (totalSamples + samplesPerPixel - 1) / samplesPerPixel;

    output.clear();
    output.reserve(numPixels);

    for (int pixel = 0; pixel < numPixels; ++pixel) {
        if (m_cancelled) return;

        int startIdx = pixel * samplesPerPixel;
        int endIdx = qMin(startIdx + samplesPerPixel, totalSamples);

        // 计算这个像素范围内的min/max
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

QVariantList WaveformWorker::levelToVariantList(const QVector<MinMaxPair>& level)
{
    QVariantList result;
    result.reserve(level.size() * 2);

    for (const MinMaxPair& pair : level) {
        result.append(pair.min);
        result.append(pair.max);
    }

    return result;
}

// ============================================================================
// WaveformGenerator 实现
// ============================================================================

WaveformGenerator::WaveformGenerator(QObject* parent)
    : QObject(parent)
    , m_duration(0)
    , m_isLoaded(false)
    , m_isProcessing(false)
{
    m_audioConverter = new AudioConverter(this);

    // 创建工作线程
    m_worker = new WaveformWorker();
    m_workerThread = new QThread(this);

    m_worker->setAudioConverter(m_audioConverter);
    m_worker->moveToThread(m_workerThread);

    // 连接信号
    connect(m_workerThread, &QThread::finished, m_worker, &QObject::deleteLater);

    connect(m_worker, &WaveformWorker::waveformGenerated,
        this, &WaveformGenerator::onWaveformGenerated);
    connect(m_worker, &WaveformWorker::generationFailed,
        this, &WaveformGenerator::onGenerationFailed);
    connect(m_worker, &WaveformWorker::progressUpdated,
        this, &WaveformGenerator::onProgressUpdated);
    connect(m_worker, &WaveformWorker::logMessage,
        this, &WaveformGenerator::logMessage);

    // 启动工作线程
    m_workerThread->start();

    emit logMessage("WaveformGenerator initialized (Audacity-style multi-level)");
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
        emit logMessage("Already processing, please wait...");
        return false;
    }

    clear();

    m_isProcessing = true;
    emit isProcessingChanged();

    // 在工作线程中异步处理
    QMetaObject::invokeMethod(m_worker, [this, filePath]() {
        m_worker->processAudio(filePath);
        }, Qt::QueuedConnection);

    return true;
}

void WaveformGenerator::clear()
{
    m_level1Data.clear();
    m_level2Data.clear();
    m_level3Data.clear();
    m_level4Data.clear();
    m_duration = 0;
    m_isLoaded = false;

    emit level1DataChanged();
    emit level2DataChanged();
    emit level3DataChanged();
    emit level4DataChanged();
    emit durationChanged();
    emit isLoadedChanged();
}

void WaveformGenerator::cancelLoading()
{
    if (m_isProcessing && m_worker) {
        m_worker->cancel();
        emit logMessage("Cancelling waveform generation...");
    }
}

void WaveformGenerator::onWaveformGenerated(QVariantList level1, QVariantList level2,
    QVariantList level3, QVariantList level4, QVariantList level5,
    qint64 duration)
{
    m_level1Data = level1;
    m_level2Data = level2;
    m_level3Data = level3;
    m_level4Data = level4;
    m_level5Data = level5;
    m_duration = duration;
    m_isLoaded = true;
    m_isProcessing = false;

    emit level1DataChanged();
    emit level2DataChanged();
    emit level3DataChanged();
    emit level4DataChanged();
    emit level5DataChanged();
    emit durationChanged();
    emit isLoadedChanged();
    emit isProcessingChanged();
    emit loadingCompleted();

    emit logMessage(QString("Multi-level waveform ready: %1 ms duration").arg(duration));
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