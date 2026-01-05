#ifndef APPLICATIONCONTROLLER_H
#define APPLICATIONCONTROLLER_H

#include <QObject>
#include <QString>
#include <QThread>
#include "whisperworker.h"
#include "subtitlegenerator.h"
#include "audioplaybackcontroller.h"
#include "waveformgenerator.h"

class ApplicationController : public QObject
{
    Q_OBJECT
        Q_PROPERTY(QString audioPath READ audioPath WRITE setAudioPath NOTIFY audioPathChanged)
        Q_PROPERTY(QString modelType READ modelType WRITE setModelType NOTIFY modelTypeChanged)
        Q_PROPERTY(QString modelBasePath READ modelBasePath WRITE setModelBasePath NOTIFY modelBasePathChanged)
        Q_PROPERTY(QString resultText READ resultText NOTIFY resultTextChanged)
        Q_PROPERTY(QString logText READ logText NOTIFY logTextChanged)
        Q_PROPERTY(int progress READ progress NOTIFY progressChanged)
        Q_PROPERTY(bool isProcessing READ isProcessing NOTIFY isProcessingChanged)
        Q_PROPERTY(bool modelLoaded READ modelLoaded NOTIFY modelLoadedChanged)
        Q_PROPERTY(QString computeMode READ computeMode NOTIFY computeModeChanged)
        Q_PROPERTY(QString currentStatus READ currentStatus NOTIFY currentStatusChanged)
        Q_PROPERTY(int segmentCount READ segmentCount NOTIFY segmentCountChanged)
        Q_PROPERTY(bool hasSubtitles READ hasSubtitles NOTIFY subtitlesLoadedChanged)
        Q_PROPERTY(AudioPlaybackController* playbackController READ playbackController CONSTANT)
        Q_PROPERTY(WaveformGenerator* waveformGenerator READ waveformGenerator CONSTANT)
        Q_PROPERTY(QString modeType READ modeType WRITE setModeType NOTIFY modeTypeChanged)
        Q_PROPERTY(bool loopSingleSegment READ loopSingleSegment WRITE setLoopSingleSegment NOTIFY loopSingleSegmentChanged)
        Q_PROPERTY(bool autoPause READ autoPause WRITE setAutoPause NOTIFY autoPauseChanged)

public:
    explicit ApplicationController(QObject* parent = nullptr);
    ~ApplicationController();

    QString audioPath() const { return m_audioPath; }
    QString modelType() const { return m_modelType; }
    QString modelBasePath() const { return m_modelBasePath; }
    QString resultText() const { return m_resultText; }
    QString logText() const { return m_logText; }
    int progress() const { return m_progress; }
    bool isProcessing() const { return m_isProcessing; }
    bool modelLoaded() const { return m_modelLoaded; }
    QString computeMode() const { return m_computeMode; }
    QString currentStatus() const { return m_currentStatus; }
    int segmentCount() const;
    bool hasSubtitles() const;
    QString modeType() const { return m_modeType; }
    bool loopSingleSegment() const { return m_loopSingleSegment; }
    bool autoPause() const { return m_autoPause; }

    void setAudioPath(const QString& path);
    void setModelType(const QString& type);
    void setModelBasePath(const QString& path);
    void setModeType(const QString& mode);
    void setLoopSingleSegment(bool enabled);
    void setAutoPause(bool enabled);

    QString getModelPath() const;

    AudioPlaybackController* playbackController() const { return m_playbackController; }
    WaveformGenerator* waveformGenerator() const { return m_waveformGenerator; }

public slots:
    void startOneClickTranscription();
    void clearLog();
    void clearResult();

    QString generateSRT();
    QString generateLRC();

    bool exportSRT(const QString& filePath);
    bool exportLRC(const QString& filePath);

    void loadAudioForPlayback();

    QString getSegmentText(int index);
    qint64 getSegmentStartTime(int index);
    qint64 getSegmentEndTime(int index);

    bool updateSegment(int index, qint64 startTime, qint64 endTime, const QString& text);
    bool deleteSegment(int index);
    bool addSegment(qint64 startTime, qint64 endTime, const QString& text);

    void playPause();
    void playPreviousSegment();
    void playNextSegment();

signals:
    void audioPathChanged();
    void modelTypeChanged();
    void modelBasePathChanged();
    void resultTextChanged();
    void logTextChanged();
    void progressChanged();
    void isProcessingChanged();
    void modelLoadedChanged();
    void computeModeChanged();
    void currentStatusChanged();
    void segmentCountChanged();
    void subtitlesLoadedChanged();
    void modeTypeChanged();
    void loopSingleSegmentChanged();
    void autoPauseChanged();

    void showMessage(const QString& title, const QString& message, bool isError);
    void subtitleExported(const QString& format, const QString& filePath);

    void segmentUpdated(int index);
    void segmentDeleted(int index);
    void segmentAdded(int index);

private slots:
    void onModelLoaded(bool success, const QString& message);
    void onTranscriptionStarted();
    void onTranscriptionProgress(int progress);
    void onTranscriptionCompleted(const QString& text);
    void onTranscriptionFailed(const QString& error);
    void onLogMessage(const QString& message);
    void onComputeModeDetected(const QString& mode, const QString& details);
    void onWaveformLoadingCompleted();
    void onSegmentTranscribed(const QString& segmentText);

private:
    void initializeDefaultModelPath();
    void loadModelAsync();
    void startTranscriptionAsync();
    void setCurrentStatus(const QString& status);
    void appendLog(const QString& message);
    void parseSegmentTiming(const QString& segmentText, int64_t& startTime, int64_t& endTime, QString& text);

    void checkAndLoadSubtitleFile();
    bool loadSRTFile(const QString& filePath);
    bool loadLRCFile(const QString& filePath);

    WhisperWorker* m_worker;
    QThread* m_workerThread;
    SubtitleGenerator* m_subtitleGenerator;
    AudioPlaybackController* m_playbackController;
    WaveformGenerator* m_waveformGenerator;

    QString m_audioPath;
    QString m_modelType;
    QString m_modelBasePath;
    QString m_resultText;
    QString m_logText;
    int m_progress;
    bool m_isProcessing;
    bool m_modelLoaded;
    QString m_computeMode;
    QString m_currentStatus;
    QString m_modeType;
    bool m_loopSingleSegment;
    bool m_autoPause;

    int64_t m_lastSegmentStartTime;
    int64_t m_lastSegmentEndTime;
};

#endif