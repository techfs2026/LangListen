#ifndef APPLICATIONCONTROLLER_H
#define APPLICATIONCONTROLLER_H

#include <QObject>
#include <QString>
#include <QThread>
#include <QCoreApplication>
#include "whisperworker.h"
#include "subtitlegenerator.h"
#include "audioplaybackcontroller.h"
#include "waveformgenerator.h"

class ApplicationController : public QObject
{
    Q_OBJECT
        Q_PROPERTY(QString audioPath READ audioPath WRITE setAudioPath NOTIFY audioPathChanged)
        Q_PROPERTY(QString resultText READ resultText NOTIFY resultTextChanged)
        Q_PROPERTY(QString logText READ logText NOTIFY logTextChanged)
        Q_PROPERTY(int progress READ progress NOTIFY progressChanged)
        Q_PROPERTY(bool isProcessing READ isProcessing NOTIFY isProcessingChanged)
        Q_PROPERTY(QString computeMode READ computeMode NOTIFY computeModeChanged)
        Q_PROPERTY(int segmentCount READ segmentCount NOTIFY segmentCountChanged)
        Q_PROPERTY(QString currentStatus READ currentStatus NOTIFY currentStatusChanged)
        Q_PROPERTY(QString modelType READ modelType WRITE setModelType NOTIFY modelTypeChanged)
        Q_PROPERTY(QString modelBasePath READ modelBasePath WRITE setModelBasePath NOTIFY modelBasePathChanged)
        Q_PROPERTY(AudioPlaybackController* playbackController READ playbackController CONSTANT)
        Q_PROPERTY(WaveformGenerator* waveformGenerator READ waveformGenerator CONSTANT)

public:
    explicit ApplicationController(QObject* parent = nullptr);
    ~ApplicationController();

    QString audioPath() const { return m_audioPath; }
    void setAudioPath(const QString& path);

    QString resultText() const { return m_resultText; }
    QString logText() const { return m_logText; }
    int progress() const { return m_progress; }
    bool isProcessing() const { return m_isProcessing; }
    QString computeMode() const { return m_computeMode; }
    int segmentCount() const;
    QString currentStatus() const { return m_currentStatus; }
    QString modelType() const { return m_modelType; }
    void setModelType(const QString& type);
    QString modelBasePath() const { return m_modelBasePath; }
    void setModelBasePath(const QString& path);

    AudioPlaybackController* playbackController() { return m_playbackController; }
    WaveformGenerator* waveformGenerator() { return m_waveformGenerator; }

    Q_INVOKABLE void startOneClickTranscription();
    Q_INVOKABLE void clearLog();
    Q_INVOKABLE void clearResult();
    Q_INVOKABLE QString generateSRT();
    Q_INVOKABLE QString generateLRC();
    Q_INVOKABLE QString generatePlainText();
    Q_INVOKABLE bool exportSRT(const QString& filePath);
    Q_INVOKABLE bool exportLRC(const QString& filePath);
    Q_INVOKABLE bool exportPlainText(const QString& filePath);
    Q_INVOKABLE void loadAudioForPlayback();
    Q_INVOKABLE QString getSegmentText(int index);
    Q_INVOKABLE qint64 getSegmentStartTime(int index);
    Q_INVOKABLE qint64 getSegmentEndTime(int index);
    Q_INVOKABLE QString getModelPath() const;

signals:
    void audioPathChanged();
    void resultTextChanged();
    void logTextChanged();
    void progressChanged();
    void isProcessingChanged();
    void computeModeChanged();
    void segmentCountChanged();
    void currentStatusChanged();
    void modelTypeChanged();
    void modelBasePathChanged();
    void showMessage(const QString& title, const QString& message, bool isError);
    void subtitleExported(const QString& type, const QString& filePath);

private slots:
    void onModelLoaded(bool success, const QString& message);
    void onTranscriptionStarted();
    void onTranscriptionProgress(int progress);
    void onTranscriptionCompleted(const QString& text);
    void onTranscriptionFailed(const QString& error);
    void onLogMessage(const QString& message);
    void onComputeModeDetected(const QString& mode, const QString& details);
    void onSegmentTranscribed(const QString& segmentText);
    void onWaveformLoadingCompleted();

private:
    void appendLog(const QString& message);
    void parseSegmentTiming(const QString& segmentText, int64_t& startTime, int64_t& endTime, QString& text);
    void setCurrentStatus(const QString& status);
    void loadModelAsync();
    void startTranscriptionAsync();
    void initializeDefaultModelPath();

    WhisperWorker* m_worker;
    QThread* m_workerThread;
    SubtitleGenerator* m_subtitleGenerator;
    AudioPlaybackController* m_playbackController;
    WaveformGenerator* m_waveformGenerator;

    QString m_audioPath;
    QString m_resultText;
    QString m_logText;
    int m_progress;
    bool m_isProcessing;
    QString m_computeMode;
    QString m_currentStatus;
    QString m_modelType;
    QString m_modelBasePath;
    bool m_modelLoaded;

    int64_t m_lastSegmentStartTime;
    int64_t m_lastSegmentEndTime;
};

#endif // APPLICATIONCONTROLLER_H