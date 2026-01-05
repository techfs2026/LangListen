#include "applicationcontroller.h"
#include <QDateTime>
#include <QFileInfo>
#include <QRegularExpression>
#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QTextStream>

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
    , m_modeType("edit")
    , m_loopSingleSegment(false)
    , m_autoPause(false)
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
    connect(m_subtitleGenerator, &SubtitleGenerator::segmentUpdated, this, &ApplicationController::segmentUpdated);
    connect(m_subtitleGenerator, &SubtitleGenerator::segmentRemoved, this, &ApplicationController::segmentDeleted);

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
        checkAndLoadSubtitleFile();
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

void ApplicationController::setModeType(const QString& mode)
{
    if (m_modeType != mode) {
        m_modeType = mode;
        emit modeTypeChanged();
        appendLog(QString("切换模式: %1").arg(mode));
    }
}

void ApplicationController::setLoopSingleSegment(bool enabled)
{
    if (m_loopSingleSegment != enabled) {
        m_loopSingleSegment = enabled;
        emit loopSingleSegmentChanged();
        if (m_playbackController) {
            m_playbackController->setSingleSentenceLoop(enabled);
        }
    }
}

void ApplicationController::setAutoPause(bool enabled)
{
    if (m_autoPause != enabled) {
        m_autoPause = enabled;
        emit autoPauseChanged();
        if (m_playbackController) {
            m_playbackController->setAutoPauseEnabled(enabled);
        }
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

bool ApplicationController::hasSubtitles() const
{
    return m_subtitleGenerator->segmentCount() > 0;
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

void ApplicationController::checkAndLoadSubtitleFile()
{
    if (m_audioPath.isEmpty()) {
        return;
    }

    QFileInfo audioInfo(m_audioPath);
    QString basePath = audioInfo.absolutePath() + "/" + audioInfo.completeBaseName();

    QString srtPath = basePath + ".srt";
    if (QFile::exists(srtPath)) {
        if (loadSRTFile(srtPath)) {
            appendLog("✓ 已加载同名字幕文件: " + srtPath);
            emit showMessage("提示", "已自动加载字幕文件，转写功能已禁用", false);
            emit subtitlesLoadedChanged();
            return;
        }
    }

    QString lrcPath = basePath + ".lrc";
    if (QFile::exists(lrcPath)) {
        if (loadLRCFile(lrcPath)) {
            appendLog("✓ 已加载同名歌词文件: " + lrcPath);
            emit showMessage("提示", "已自动加载歌词文件，转写功能已禁用", false);
            emit subtitlesLoadedChanged();
            return;
        }
    }

    if (m_subtitleGenerator->segmentCount() > 0) {
        m_subtitleGenerator->clearSegments();
        emit segmentCountChanged();
        emit subtitlesLoadedChanged();
        appendLog("未找到同名字幕文件，转写功能已启用");
    }
}

bool ApplicationController::loadSRTFile(const QString& filePath)
{
    QFile file(filePath);
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        appendLog("无法打开SRT文件: " + filePath);
        return false;
    }

    m_subtitleGenerator->clearSegments();

    QTextStream in(&file);
    in.setEncoding(QStringConverter::Utf8);

    QString line;
    int state = 0;
    qint64 startTime = 0, endTime = 0;
    QString text;

    while (!in.atEnd()) {
        line = in.readLine().trimmed();

        if (line.isEmpty()) {
            if (state == 2 && !text.isEmpty()) {
                m_subtitleGenerator->addSegment(startTime, endTime, text);
                text.clear();
            }
            state = 0;
            continue;
        }

        if (state == 0) {
            state = 1;
        }
        else if (state == 1) {
            QRegularExpression timeRegex(R"((\d{2}):(\d{2}):(\d{2}),(\d{3})\s*-->\s*(\d{2}):(\d{2}):(\d{2}),(\d{3}))");
            QRegularExpressionMatch match = timeRegex.match(line);
            if (match.hasMatch()) {
                int h1 = match.captured(1).toInt();
                int m1 = match.captured(2).toInt();
                int s1 = match.captured(3).toInt();
                int ms1 = match.captured(4).toInt();
                startTime = (h1 * 3600 + m1 * 60 + s1) * 1000 + ms1;

                int h2 = match.captured(5).toInt();
                int m2 = match.captured(6).toInt();
                int s2 = match.captured(7).toInt();
                int ms2 = match.captured(8).toInt();
                endTime = (h2 * 3600 + m2 * 60 + s2) * 1000 + ms2;

                state = 2;
            }
        }
        else if (state == 2) {
            if (!text.isEmpty()) {
                text += " ";
            }
            text += line;
        }
    }

    if (state == 2 && !text.isEmpty()) {
        m_subtitleGenerator->addSegment(startTime, endTime, text);
    }

    file.close();
    emit segmentCountChanged();

    if (m_playbackController) {
        m_playbackController->setSubtitles(m_subtitleGenerator->getAllSegments());
    }

    return m_subtitleGenerator->segmentCount() > 0;
}

bool ApplicationController::loadLRCFile(const QString& filePath)
{
    QFile file(filePath);
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        appendLog("无法打开LRC文件: " + filePath);
        return false;
    }

    m_subtitleGenerator->clearSegments();

    QTextStream in(&file);
    in.setEncoding(QStringConverter::Utf8);

    QRegularExpression timeRegex(R"(\[(\d{2}):(\d{2})\.(\d{2})\])");
    QString line;
    qint64 lastTime = 0;
    QString lastText;

    while (!in.atEnd()) {
        line = in.readLine();

        if (line.trimmed().isEmpty() || line.startsWith("[ti:") ||
            line.startsWith("[ar:") || line.startsWith("[al:") ||
            line.startsWith("[by:")) {
            continue;
        }

        QRegularExpressionMatch match = timeRegex.match(line);
        if (match.hasMatch()) {
            int minutes = match.captured(1).toInt();
            int seconds = match.captured(2).toInt();
            int centiseconds = match.captured(3).toInt();
            qint64 currentTime = (minutes * 60 + seconds) * 1000 + centiseconds * 10;

            QString text = line.mid(match.capturedEnd()).trimmed();

            if (!lastText.isEmpty() && lastTime < currentTime) {
                m_subtitleGenerator->addSegment(lastTime, currentTime, lastText);
            }

            lastTime = currentTime;
            lastText = text;
        }
    }

    if (!lastText.isEmpty()) {
        m_subtitleGenerator->addSegment(lastTime, lastTime + 3000, lastText);
    }

    file.close();
    emit segmentCountChanged();

    if (m_playbackController) {
        m_playbackController->setSubtitles(m_subtitleGenerator->getAllSegments());
    }

    return m_subtitleGenerator->segmentCount() > 0;
}

void ApplicationController::startOneClickTranscription()
{
    if (m_audioPath.isEmpty()) {
        emit showMessage("错误", "请先选择音频文件", true);
        return;
    }

    if (m_modelBasePath.isEmpty()) {
        emit showMessage("错误", "请先设置模型路径", true);
        return;
    }

    if (hasSubtitles()) {
        emit showMessage("警告", "已加载字幕文件，无需转写", true);
        return;
    }

    if (m_isProcessing) {
        emit showMessage("提示", "正在处理中，请稍候", false);
        return;
    }

    m_isProcessing = true;
    emit isProcessingChanged();

    m_progress = 0;
    emit progressChanged();

    m_subtitleGenerator->clearSegments();
    emit segmentCountChanged();

    m_resultText.clear();
    emit resultTextChanged();

    setCurrentStatus("正在加载模型...");
    appendLog("开始一键转写流程");

    loadModelAsync();
}

void ApplicationController::loadModelAsync()
{
    QString modelPath = getModelPath();
    appendLog("模型路径: " + modelPath);

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
    appendLog("日志已清空");
}

void ApplicationController::clearResult()
{
    m_resultText.clear();
    emit resultTextChanged();
    appendLog("结果已清空");
}

QString ApplicationController::generateSRT()
{
    return m_subtitleGenerator->generateSRT();
}

QString ApplicationController::generateLRC()
{
    return m_subtitleGenerator->generateLRC();
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

void ApplicationController::loadAudioForPlayback()
{
    if (m_audioPath.isEmpty()) {
        emit showMessage("警告", "未选择音频文件", true);
        return;
    }

    m_playbackController->loadAudio(m_audioPath);

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

bool ApplicationController::updateSegment(int index, qint64 startTime, qint64 endTime, const QString& text)
{
    if (!m_subtitleGenerator) {
        return false;
    }

    if (index < 0 || index >= m_subtitleGenerator->segmentCount()) {
        appendLog(QString("更新失败: 索引 %1 超出范围").arg(index));
        return false;
    }

    if (startTime >= endTime) {
        appendLog("更新失败: 起始时间必须小于结束时间");
        return false;
    }

    if (text.trimmed().isEmpty()) {
        appendLog("更新失败: 字幕文本不能为空");
        return false;
    }

    bool success = m_subtitleGenerator->updateSegment(index, startTime, endTime, text.trimmed());

    if (success) {
        appendLog(QString("句子 #%1 已更新").arg(index + 1));

        if (m_playbackController) {
            m_playbackController->setSubtitles(m_subtitleGenerator->getAllSegments());
        }

        return true;
    }

    appendLog(QString("句子 #%1 更新失败").arg(index + 1));
    return false;
}

bool ApplicationController::deleteSegment(int index)
{
    if (!m_subtitleGenerator) {
        return false;
    }

    if (index < 0 || index >= m_subtitleGenerator->segmentCount()) {
        appendLog(QString("删除失败: 索引 %1 超出范围").arg(index));
        return false;
    }

    bool success = m_subtitleGenerator->deleteSegment(index);

    if (success) {
        appendLog(QString("句子 #%1 已删除").arg(index + 1));

        if (m_playbackController) {
            m_playbackController->setSubtitles(m_subtitleGenerator->getAllSegments());
        }

        emit segmentCountChanged();
        return true;
    }

    appendLog(QString("句子 #%1 删除失败").arg(index + 1));
    return false;
}

bool ApplicationController::addSegment(qint64 startTime, qint64 endTime, const QString& text)
{
    if (!m_subtitleGenerator) {
        return false;
    }

    if (startTime >= endTime) {
        appendLog("添加失败: 起始时间必须小于结束时间");
        return false;
    }

    if (text.trimmed().isEmpty()) {
        appendLog("添加失败: 字幕文本不能为空");
        return false;
    }

    m_subtitleGenerator->addSegment(startTime, endTime, text.trimmed());

    int newIndex = m_subtitleGenerator->segmentCount() - 1;
    appendLog(QString("新句子已创建 (#%1)").arg(newIndex + 1));

    if (m_playbackController) {
        m_playbackController->setSubtitles(m_subtitleGenerator->getAllSegments());
    }

    emit segmentCountChanged();
    return true;
}

void ApplicationController::playPause()
{
    if (m_playbackController) {
        if (m_playbackController->isPlaying()) {
            m_playbackController->pause();
        }
        else {
            m_playbackController->play();
        }
    }
}

void ApplicationController::playPreviousSegment()
{
    if (m_playbackController) {
        m_playbackController->playPreviousSegment();
    }
}

void ApplicationController::playNextSegment()
{
    if (m_playbackController) {
        m_playbackController->playNextSegment();
    }
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

    m_playbackController->setSubtitles(m_subtitleGenerator->getAllSegments());

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