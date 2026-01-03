#include "applicationcontroller.h"
#include <QDateTime>
#include <QFileInfo>
#include <QRegularExpression>
#include <QDir>

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
    , m_currentStatus("就绪")
    , m_modelType("medium")
    , m_modelBasePath("")
    , m_lastSegmentStartTime(0)
    , m_lastSegmentEndTime(0)
{
    m_worker = new WhisperWorker();
    m_workerThread = new QThread(this);
    m_worker->moveToThread(m_workerThread);

    m_subtitleGenerator = new SubtitleGenerator(this);
    m_playbackController = new AudioPlaybackController(this);
    m_waveformGenerator = new WaveformGenerator(this);

    connect(m_waveformGenerator, &WaveformGenerator::logMessage, this, &ApplicationController::onLogMessage);
    connect(m_waveformGenerator, &WaveformGenerator::loadingCompleted, this, &ApplicationController::onWaveformLoadingCompleted);

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

    initializeDefaultModelPath();

    appendLog("程序启动成功");
    appendLog(QString("模型目录: %1").arg(m_modelBasePath));
}

ApplicationController::~ApplicationController()
{
    if (m_workerThread) {
        m_workerThread->quit();
        m_workerThread->wait();
    }

    delete m_worker;
}

void ApplicationController::setAudioPath(const QString& path)
{
    if (m_audioPath != path) {
        m_audioPath = path;
        emit audioPathChanged();
    }
}

void ApplicationController::setModelType(const QString& type)
{
    if (m_modelType != type) {
        m_modelType = type;
        m_modelLoaded = false;
        emit modelTypeChanged();
        appendLog(QString("切换模型类型为: %1").arg(type));
    }
}

void ApplicationController::setModelBasePath(const QString& path)
{
    if (m_modelBasePath != path) {
        m_modelBasePath = path;
        emit modelBasePathChanged();
        appendLog(QString("设置模型目录: %1").arg(path));
    }
}

QString ApplicationController::getModelPath() const
{
    if (m_modelBasePath.isEmpty()) {
        return QString();
    }

    QString modelFile;
    if (m_modelType == "base") {
        modelFile = "ggml-base.en.bin";
    }
    else if (m_modelType == "small") {
        modelFile = "ggml-small.en.bin";
    }
    else if (m_modelType == "medium") {
        modelFile = "ggml-medium.en.bin";
    }
    else {
        modelFile = "ggml-large-v3-turbo.bin";
    }

    return QDir(m_modelBasePath).filePath(modelFile);
}

int ApplicationController::segmentCount() const
{
    return m_subtitleGenerator->segmentCount();
}

void ApplicationController::setCurrentStatus(const QString& status)
{
    if (m_currentStatus != status) {
        m_currentStatus = status;
        emit currentStatusChanged();
    }
}

void ApplicationController::initializeDefaultModelPath()
{
    QStringList candidatePaths;

    candidatePaths << QCoreApplication::applicationDirPath() + "/models";

    candidatePaths << "D:/models";

    for (const QString& path : candidatePaths) {
        if (QDir(path).exists()) {
            m_modelBasePath = path;
            emit modelBasePathChanged();
            appendLog(QString("找到模型目录: %1").arg(path));
            return;
        }
    }

    if (!candidatePaths.isEmpty()) {
        m_modelBasePath = candidatePaths.first();
        emit modelBasePathChanged();
        appendLog(QString("使用默认模型目录: %1").arg(m_modelBasePath));
        appendLog("提示: 请将模型文件放置在此目录");
    }
}

void ApplicationController::startOneClickTranscription()
{
    if (m_audioPath.isEmpty()) {
        emit showMessage("错误", "请先选择音频文件", true);
        return;
    }

    QFileInfo audioInfo(m_audioPath);
    if (!audioInfo.exists()) {
        emit showMessage("错误", "音频文件不存在", true);
        return;
    }

    QString modelPath = getModelPath();
    QFileInfo modelInfo(modelPath);
    if (!modelInfo.exists()) {
        emit showMessage("错误",
            QString("模型文件不存在: %1\n\n请将模型文件放置在: %2\n文件名应为: %3")
            .arg(modelPath)
            .arg(m_modelBasePath)
            .arg(m_modelType == "base" ? "ggml-base.bin" :
                m_modelType == "small" ? "ggml-small.bin" : "ggml-medium.bin"),
            true);
        return;
    }

    m_resultText.clear();
    emit resultTextChanged();

    m_subtitleGenerator->clearSegments();
    emit segmentCountChanged();

    m_isProcessing = true;
    emit isProcessingChanged();

    m_progress = 0;
    emit progressChanged();

    if (!m_modelLoaded) {
        setCurrentStatus("正在加载模型...");
        appendLog(QString("开始加载模型: %1 (%2)").arg(m_modelType).arg(modelPath));
        loadModelAsync();
    }
    else {
        setCurrentStatus("正在加载音频...");
        appendLog("模型已加载，直接开始转写");
        startTranscriptionAsync();
    }
}

void ApplicationController::loadModelAsync()
{
    QString modelPath = getModelPath();
    QMetaObject::invokeMethod(m_worker, [this, modelPath]() {
        m_worker->initModel(modelPath);
        }, Qt::QueuedConnection);
}

void ApplicationController::startTranscriptionAsync()
{
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
        appendLog("SRT文件导出成功: " + filePath);
        emit subtitleExported("SRT", filePath);
        emit showMessage("成功", "SRT文件导出成功", false);
    }
    else {
        emit showMessage("错误", "SRT文件导出失败", true);
    }
    return success;
}

bool ApplicationController::exportLRC(const QString& filePath)
{
    bool success = m_subtitleGenerator->saveLRC(filePath);
    if (success) {
        appendLog("LRC文件导出成功: " + filePath);
        emit subtitleExported("LRC", filePath);
        emit showMessage("成功", "LRC文件导出成功", false);
    }
    else {
        emit showMessage("错误", "LRC文件导出失败", true);
    }
    return success;
}

bool ApplicationController::exportPlainText(const QString& filePath)
{
    bool success = m_subtitleGenerator->savePlainText(filePath);
    if (success) {
        appendLog("文本文件导出成功: " + filePath);
        emit subtitleExported("TXT", filePath);
        emit showMessage("成功", "文本文件导出成功", false);
    }
    else {
        emit showMessage("错误", "文本文件导出失败", true);
    }
    return success;
}

void ApplicationController::loadAudioForPlayback()
{
    if (m_audioPath.isEmpty()) {
        emit showMessage("警告", "未选择音频文件", true);
        return;
    }

    m_playbackController->loadAudio(m_audioPath);
    m_playbackController->setSubtitles(m_subtitleGenerator->getAllSegments());

    appendLog("已加载音频用于播放: " + m_audioPath);
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
    if (success) {
        m_modelLoaded = true;
        appendLog("✓ 模型加载成功");
        setCurrentStatus("正在加载音频...");

        m_progress = 10;
        emit progressChanged();

        startTranscriptionAsync();
    }
    else {
        m_isProcessing = false;
        emit isProcessingChanged();

        m_modelLoaded = false;
        setCurrentStatus("模型加载失败");
        emit showMessage("错误", message, true);
    }
}

void ApplicationController::onTranscriptionStarted()
{
    setCurrentStatus("正在转写...");
    appendLog("✓ 音频加载成功，开始转写");

    m_progress = 20;
    emit progressChanged();
}

void ApplicationController::onTranscriptionProgress(int progress)
{
    m_progress = 20 + (progress * 80 / 100);
    emit progressChanged();
}

void ApplicationController::onTranscriptionCompleted(const QString& text)
{
    m_progress = 100;
    emit progressChanged();

    m_isProcessing = false;
    emit isProcessingChanged();

    setCurrentStatus("转写完成");
    appendLog(QString("✓ 转写完成！共生成 %1 个字幕段").arg(m_subtitleGenerator->segmentCount()));
    emit showMessage("完成", "转写完成！现在可以导出字幕文件了。", false);
}

void ApplicationController::onTranscriptionFailed(const QString& error)
{
    appendLog("✗ 转写失败: " + error);

    m_progress = 0;
    emit progressChanged();

    m_isProcessing = false;
    emit isProcessingChanged();

    setCurrentStatus("转写失败");
    emit showMessage("错误", "转写失败: " + error, true);
}

void ApplicationController::onLogMessage(const QString& message)
{
    appendLog(message);
}

void ApplicationController::onComputeModeDetected(const QString& mode, const QString& details)
{
    m_computeMode = mode;
    emit computeModeChanged();

    appendLog("计算模式: " + mode);
    appendLog("详细信息: " + details);
}

void ApplicationController::onWaveformLoadingCompleted()
{
    appendLog("波形加载完成");
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