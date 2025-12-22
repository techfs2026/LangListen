#include "applicationcontroller.h"
#include <QDateTime>
#include <QFileInfo>
#include <QRegularExpression>

ApplicationController::ApplicationController(QObject* parent)
    : QObject(parent)
    , m_worker(nullptr)
    , m_workerThread(nullptr)
    , m_subtitleGenerator(nullptr)
    , m_playbackController(nullptr)
    , m_waveformGenerator(nullptr)
    , m_progress(0)
    , m_isProcessing(false)
    , m_modelLoaded(false)
    , m_computeMode("Unknown")
    , m_lastSegmentStartTime(0)
    , m_lastSegmentEndTime(0)
{
    m_worker = new WhisperWorker();
    m_workerThread = new QThread(this);
    m_worker->moveToThread(m_workerThread);

    m_subtitleGenerator = new SubtitleGenerator(this);
    m_playbackController = new AudioPlaybackController(this);
    m_waveformGenerator = new WaveformGenerator(this);

    // ✅ 连接波形生成器信号
    connect(m_waveformGenerator, &WaveformGenerator::logMessage, this, &ApplicationController::onLogMessage);
    connect(m_waveformGenerator, &WaveformGenerator::loadingCompleted, this, &ApplicationController::onWaveformLoadingCompleted);
    connect(m_waveformGenerator, &WaveformGenerator::level1DataChanged, this, &ApplicationController::waveformDataChanged);
    connect(m_waveformGenerator, &WaveformGenerator::level2DataChanged, this, &ApplicationController::waveformDataChanged);
    connect(m_waveformGenerator, &WaveformGenerator::level3DataChanged, this, &ApplicationController::waveformDataChanged);
    connect(m_waveformGenerator, &WaveformGenerator::level4DataChanged, this, &ApplicationController::waveformDataChanged);

    connect(m_worker, &WhisperWorker::modelLoaded, this, &ApplicationController::onModelLoaded);
    connect(m_worker, &WhisperWorker::transcriptionStarted, this, &ApplicationController::onTranscriptionStarted);
    connect(m_worker, &WhisperWorker::transcriptionProgress, this, &ApplicationController::onTranscriptionProgress);
    connect(m_worker, &WhisperWorker::transcriptionCompleted, this, &ApplicationController::onTranscriptionCompleted);
    connect(m_worker, &WhisperWorker::transcriptionFailed, this, &ApplicationController::onTranscriptionFailed);
    connect(m_worker, &WhisperWorker::logMessage, this, &ApplicationController::onLogMessage);
    connect(m_worker, &WhisperWorker::computeModeDetected, this, &ApplicationController::onComputeModeDetected);
    connect(m_worker, &WhisperWorker::segmentTranscribed, this, &ApplicationController::onSegmentTranscribed);

    connect(m_subtitleGenerator, &SubtitleGenerator::segmentAdded, this, &ApplicationController::segmentCountChanged);

    m_workerThread->start();

    appendLog("Program started successfully");
    appendLog("Please load the Whisper model file first");
}

ApplicationController::~ApplicationController()
{
    if (m_workerThread) {
        m_workerThread->quit();
        m_workerThread->wait();
    }

    delete m_worker;
}

void ApplicationController::setModelPath(const QString& path)
{
    if (m_modelPath != path) {
        m_modelPath = path;
        emit modelPathChanged();
    }
}

void ApplicationController::setAudioPath(const QString& path)
{
    if (m_audioPath != path) {
        m_audioPath = path;
        emit audioPathChanged();
    }
}

int ApplicationController::segmentCount() const
{
    return m_subtitleGenerator->segmentCount();
}

// ✅ 新增：波形数据访问方法
QVariantList ApplicationController::getWaveformLevel1Data() const
{
    return m_waveformGenerator->level1Data();
}

QVariantList ApplicationController::getWaveformLevel2Data() const
{
    return m_waveformGenerator->level2Data();
}

QVariantList ApplicationController::getWaveformLevel3Data() const
{
    return m_waveformGenerator->level3Data();
}

QVariantList ApplicationController::getWaveformLevel4Data() const
{
    return m_waveformGenerator->level4Data();
}

qint64 ApplicationController::getWaveformDuration() const
{
    return m_waveformGenerator->duration();
}

bool ApplicationController::isWaveformLoaded() const
{
    return m_waveformGenerator->isLoaded();
}

void ApplicationController::loadWaveform()
{
    if (m_audioPath.isEmpty()) {
        appendLog("Error: No audio file selected for waveform");
        return;
    }

    appendLog("Loading waveform for: " + m_audioPath);
    m_waveformGenerator->loadAudio(m_audioPath);
}

void ApplicationController::loadModel()
{
    if (m_modelPath.isEmpty()) {
        emit showMessage("Error", "Please select a model file first", true);
        return;
    }

    QFileInfo fileInfo(m_modelPath);
    if (!fileInfo.exists()) {
        emit showMessage("Error", "Model file does not exist", true);
        return;
    }

    appendLog("Loading model: " + m_modelPath);
    m_isProcessing = true;
    emit isProcessingChanged();

    QMetaObject::invokeMethod(m_worker, [this]() {
        m_worker->initModel(m_modelPath);
        }, Qt::QueuedConnection);
}

void ApplicationController::startTranscription()
{
    if (m_modelPath.isEmpty() || m_audioPath.isEmpty()) {
        emit showMessage("Warning", "Please load model and select audio file first", true);
        return;
    }

    if (!m_modelLoaded) {
        emit showMessage("Warning", "Model not yet loaded", true);
        return;
    }

    QFileInfo fileInfo(m_audioPath);
    if (!fileInfo.exists()) {
        emit showMessage("Error", "Audio file does not exist", true);
        return;
    }

    m_resultText.clear();
    emit resultTextChanged();

    m_subtitleGenerator->clearSegments();
    emit segmentCountChanged();

    m_isProcessing = true;
    emit isProcessingChanged();

    QMetaObject::invokeMethod(m_worker, [this]() {
        m_worker->transcribe(m_audioPath);
        }, Qt::QueuedConnection);
}

void ApplicationController::clearLog()
{
    m_logText.clear();
    emit logTextChanged();
}

void ApplicationController::clearResult()
{
    m_resultText.clear();
    emit resultTextChanged();

    m_subtitleGenerator->clearSegments();
    emit segmentCountChanged();
}

QString ApplicationController::generateSRT()
{
    return m_subtitleGenerator->generateSRT();
}

QString ApplicationController::generateLRC()
{
    return m_subtitleGenerator->generateLRC();
}

QString ApplicationController::generatePlainText()
{
    return m_subtitleGenerator->generatePlainText();
}

bool ApplicationController::exportSRT(const QString& filePath)
{
    bool success = m_subtitleGenerator->saveSRT(filePath);
    if (success) {
        appendLog("SRT file exported: " + filePath);
        emit subtitleExported("SRT", filePath);
        emit showMessage("Success", "SRT file exported successfully", false);
    }
    else {
        emit showMessage("Error", "Failed to export SRT file", true);
    }
    return success;
}

bool ApplicationController::exportLRC(const QString& filePath)
{
    bool success = m_subtitleGenerator->saveLRC(filePath);
    if (success) {
        appendLog("LRC file exported: " + filePath);
        emit subtitleExported("LRC", filePath);
        emit showMessage("Success", "LRC file exported successfully", false);
    }
    else {
        emit showMessage("Error", "Failed to export LRC file", true);
    }
    return success;
}

bool ApplicationController::exportPlainText(const QString& filePath)
{
    bool success = m_subtitleGenerator->savePlainText(filePath);
    if (success) {
        appendLog("Text file exported: " + filePath);
        emit subtitleExported("TXT", filePath);
        emit showMessage("Success", "Text file exported successfully", false);
    }
    else {
        emit showMessage("Error", "Failed to export text file", true);
    }
    return success;
}

void ApplicationController::loadAudioForPlayback()
{
    if (m_audioPath.isEmpty()) {
        emit showMessage("Warning", "No audio file selected", true);
        return;
    }

    m_playbackController->loadAudio(m_audioPath);
    m_playbackController->setSubtitles(m_subtitleGenerator->getAllSegments());

    appendLog("Audio loaded for playback: " + m_audioPath);
}

QString ApplicationController::getSegmentText(int index)
{
    SubtitleSegment segment = m_subtitleGenerator->getSegment(index);
    return segment.text;
}

qint64 ApplicationController::getSegmentStartTime(int index)
{
    SubtitleSegment segment = m_subtitleGenerator->getSegment(index);
    return segment.startTime;
}

qint64 ApplicationController::getSegmentEndTime(int index)
{
    SubtitleSegment segment = m_subtitleGenerator->getSegment(index);
    return segment.endTime;
}

void ApplicationController::onModelLoaded(bool success, const QString& message)
{
    m_isProcessing = false;
    emit isProcessingChanged();

    m_modelLoaded = success;
    emit modelLoadedChanged();

    if (success) {
        emit showMessage("Success", message, false);
    }
    else {
        emit showMessage("Error", message, true);
    }
}

void ApplicationController::onTranscriptionStarted()
{
    appendLog("Starting transcription...");
    m_progress = 0;
    emit progressChanged();
}

void ApplicationController::onTranscriptionProgress(int progress)
{
    m_progress = progress;
    emit progressChanged();
}

void ApplicationController::onTranscriptionCompleted(const QString& text)
{
    m_progress = 100;
    emit progressChanged();

    m_isProcessing = false;
    emit isProcessingChanged();

    appendLog(QString("Transcription completed! Total segments: %1").arg(m_subtitleGenerator->segmentCount()));
    emit showMessage("Complete", "Transcription completed! You can now export subtitles.", false);
}

void ApplicationController::onTranscriptionFailed(const QString& error)
{
    appendLog("Transcription failed: " + error);

    m_progress = 0;
    emit progressChanged();

    m_isProcessing = false;
    emit isProcessingChanged();

    emit showMessage("Error", "Transcription failed: " + error, true);
}

void ApplicationController::onLogMessage(const QString& message)
{
    appendLog(message);
}

void ApplicationController::onComputeModeDetected(const QString& mode, const QString& details)
{
    m_computeMode = mode;
    emit computeModeChanged();

    appendLog("Compute mode: " + mode);
    appendLog("Details: " + details);
}

// ✅ 新增：波形加载完成处理
void ApplicationController::onWaveformLoadingCompleted()
{
    appendLog("Waveform loading completed");
    emit waveformDataChanged();
}

void ApplicationController::parseSegmentTiming(const QString& segmentText, int64_t& startTime, int64_t& endTime, QString& text)
{
    QRegularExpression regex(R"(\[(\d+\.\d+) -> (\d+\.\d+)\]\s*(.+))");
    QRegularExpressionMatch match = regex.match(segmentText);

    if (match.hasMatch()) {
        startTime = static_cast<int64_t>(match.captured(1).toDouble() * 1000.0);
        endTime = static_cast<int64_t>(match.captured(2).toDouble() * 1000.0);
        text = match.captured(3).trimmed();

        m_lastSegmentStartTime = startTime;
        m_lastSegmentEndTime = endTime;
    }
    else {
        startTime = m_lastSegmentEndTime;
        endTime = m_lastSegmentEndTime + 2000;
        text = segmentText.trimmed();

        m_lastSegmentEndTime = endTime;
    }
}

void ApplicationController::onSegmentTranscribed(const QString& segmentText)
{
    m_resultText += segmentText;
    emit resultTextChanged();

    int64_t startTime, endTime;
    QString text;
    parseSegmentTiming(segmentText, startTime, endTime, text);

    if (!text.isEmpty()) {
        m_subtitleGenerator->addSegment(startTime, endTime, text);
    }
}

void ApplicationController::appendLog(const QString& message)
{
    QString timestamp = QDateTime::currentDateTime().toString("hh:mm:ss");
    QString logEntry = QString("[%1] %2\n").arg(timestamp, message);
    m_logText += logEntry;
    emit logTextChanged();
}