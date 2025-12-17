#include "applicationcontroller.h"
#include <QDateTime>
#include <QFileInfo>

ApplicationController::ApplicationController(QObject* parent)
    : QObject(parent)
    , m_worker(nullptr)
    , m_workerThread(nullptr)
    , m_progress(0)
    , m_isProcessing(false)
    , m_modelLoaded(false)
    , m_computeMode("未知")
{
    m_worker = new WhisperWorker();
    m_workerThread = new QThread(this);
    m_worker->moveToThread(m_workerThread);

    connect(m_worker, &WhisperWorker::modelLoaded, this, &ApplicationController::onModelLoaded);
    connect(m_worker, &WhisperWorker::transcriptionStarted, this, &ApplicationController::onTranscriptionStarted);
    connect(m_worker, &WhisperWorker::transcriptionProgress, this, &ApplicationController::onTranscriptionProgress);
    connect(m_worker, &WhisperWorker::transcriptionCompleted, this, &ApplicationController::onTranscriptionCompleted);
    connect(m_worker, &WhisperWorker::transcriptionFailed, this, &ApplicationController::onTranscriptionFailed);
    connect(m_worker, &WhisperWorker::logMessage, this, &ApplicationController::onLogMessage);
    connect(m_worker, &WhisperWorker::computeModeDetected, this, &ApplicationController::onComputeModeDetected);

    // Connect the new real-time segment signal
    connect(m_worker, &WhisperWorker::segmentTranscribed, this, &ApplicationController::onSegmentTranscribed);

    m_workerThread->start();

    appendLog("程序启动成功");
    appendLog("请先加载Whisper模型文件");
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

void ApplicationController::loadModel()
{
    if (m_modelPath.isEmpty()) {
        emit showMessage("错误", "请先选择模型文件", true);
        return;
    }

    QFileInfo fileInfo(m_modelPath);
    if (!fileInfo.exists()) {
        emit showMessage("错误", "模型文件不存在", true);
        return;
    }

    appendLog("正在加载模型: " + m_modelPath);
    m_isProcessing = true;
    emit isProcessingChanged();

    QMetaObject::invokeMethod(m_worker, [this]() {
        m_worker->initModel(m_modelPath);
        }, Qt::QueuedConnection);
}

void ApplicationController::startTranscription()
{
    if (m_modelPath.isEmpty() || m_audioPath.isEmpty()) {
        emit showMessage("警告", "请先加载模型和选择音频文件", true);
        return;
    }

    if (!m_modelLoaded) {
        emit showMessage("警告", "模型尚未加载完成", true);
        return;
    }

    QFileInfo fileInfo(m_audioPath);
    if (!fileInfo.exists()) {
        emit showMessage("错误", "音频文件不存在", true);
        return;
    }

    m_resultText.clear();
    emit resultTextChanged();

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
}

void ApplicationController::onModelLoaded(bool success, const QString& message)
{
    m_isProcessing = false;
    emit isProcessingChanged();

    m_modelLoaded = success;
    emit modelLoadedChanged();

    if (success) {
        emit showMessage("成功", message, false);
    }
    else {
        emit showMessage("错误", message, true);
    }
}

void ApplicationController::onTranscriptionStarted()
{
    appendLog("开始转写...");
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

    emit showMessage("完成", "转写完成!", false);
}

void ApplicationController::onTranscriptionFailed(const QString& error)
{
    appendLog("转写失败: " + error);

    m_progress = 0;
    emit progressChanged();

    m_isProcessing = false;
    emit isProcessingChanged();

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
    appendLog("详情: " + details);
}

void ApplicationController::onSegmentTranscribed(const QString& segmentText)
{
    m_resultText += segmentText;
    emit resultTextChanged();
}

void ApplicationController::appendLog(const QString& message)
{
    QString timestamp = QDateTime::currentDateTime().toString("hh:mm:ss");
    QString logEntry = QString("[%1] %2\n").arg(timestamp, message);
    m_logText += logEntry;
    emit logTextChanged();
}