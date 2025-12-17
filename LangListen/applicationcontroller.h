#ifndef APPLICATIONCONTROLLER_H
#define APPLICATIONCONTROLLER_H

#include <QObject>
#include <QThread>
#include <QString>
#include "whisperworker.h"

class ApplicationController : public QObject
{
    Q_OBJECT
        Q_PROPERTY(QString modelPath READ modelPath WRITE setModelPath NOTIFY modelPathChanged)
        Q_PROPERTY(QString audioPath READ audioPath WRITE setAudioPath NOTIFY audioPathChanged)
        Q_PROPERTY(QString logText READ logText NOTIFY logTextChanged)
        Q_PROPERTY(QString resultText READ resultText NOTIFY resultTextChanged)
        Q_PROPERTY(int progress READ progress NOTIFY progressChanged)
        Q_PROPERTY(bool isProcessing READ isProcessing NOTIFY isProcessingChanged)
        Q_PROPERTY(bool modelLoaded READ modelLoaded NOTIFY modelLoadedChanged)
        Q_PROPERTY(QString computeMode READ computeMode NOTIFY computeModeChanged)

public:
    explicit ApplicationController(QObject* parent = nullptr);
    ~ApplicationController();

    QString modelPath() const { return m_modelPath; }
    void setModelPath(const QString& path);

    QString audioPath() const { return m_audioPath; }
    void setAudioPath(const QString& path);

    QString logText() const { return m_logText; }
    QString resultText() const { return m_resultText; }
    int progress() const { return m_progress; }
    bool isProcessing() const { return m_isProcessing; }
    bool modelLoaded() const { return m_modelLoaded; }
    QString computeMode() const { return m_computeMode; }

    Q_INVOKABLE void loadModel();
    Q_INVOKABLE void startTranscription();
    Q_INVOKABLE void clearLog();
    Q_INVOKABLE void clearResult();

signals:
    void modelPathChanged();
    void audioPathChanged();
    void logTextChanged();
    void resultTextChanged();
    void progressChanged();
    void isProcessingChanged();
    void modelLoadedChanged();
    void computeModeChanged();
    void showMessage(const QString& title, const QString& message, bool isError);

private slots:
    void onModelLoaded(bool success, const QString& message);
    void onTranscriptionStarted();
    void onTranscriptionProgress(int progress);
    void onTranscriptionCompleted(const QString& text);
    void onTranscriptionFailed(const QString& error);
    void onLogMessage(const QString& message);
    void onComputeModeDetected(const QString& mode, const QString& details);
    void onSegmentTranscribed(const QString& segmentText);

private:
    WhisperWorker* m_worker;
    QThread* m_workerThread;

    QString m_modelPath;
    QString m_audioPath;
    QString m_logText;
    QString m_resultText;
    QString m_computeMode;
    int m_progress;
    bool m_isProcessing;
    bool m_modelLoaded;

    void appendLog(const QString& message);
};

#endif // APPLICATIONCONTROLLER_H