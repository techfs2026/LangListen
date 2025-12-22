#ifndef APPLICATIONCONTROLLER_H
#define APPLICATIONCONTROLLER_H

#include <QObject>
#include <QThread>
#include <QString>
#include "whisperworker.h"
#include "subtitlegenerator.h"
#include "audioplaybackcontroller.h"
#include "waveformgenerator.h"  // 保留用于内部使用

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
        Q_PROPERTY(int segmentCount READ segmentCount NOTIFY segmentCountChanged)
        Q_PROPERTY(AudioPlaybackController* playbackController READ playbackController CONSTANT)
        Q_PROPERTY(WaveformGenerator* waveformGenerator READ waveformGenerator CONSTANT)

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
    int segmentCount() const;
    AudioPlaybackController* playbackController() const { return m_playbackController; }

    // ✅ 如果需要从 C++ 访问波形生成器，保留这个内部方法
    WaveformGenerator* waveformGenerator() const { return m_waveformGenerator; }

    Q_INVOKABLE void loadModel();
    Q_INVOKABLE void startTranscription();
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

    // ✅ 新增：获取波形数据的方法（供 QML 调用）
    Q_INVOKABLE QVariantList getWaveformLevel1Data() const;
    Q_INVOKABLE QVariantList getWaveformLevel2Data() const;
    Q_INVOKABLE QVariantList getWaveformLevel3Data() const;
    Q_INVOKABLE QVariantList getWaveformLevel4Data() const;
    Q_INVOKABLE qint64 getWaveformDuration() const;
    Q_INVOKABLE bool isWaveformLoaded() const;
    Q_INVOKABLE void loadWaveform();

signals:
    void modelPathChanged();
    void audioPathChanged();
    void logTextChanged();
    void resultTextChanged();
    void progressChanged();
    void isProcessingChanged();
    void modelLoadedChanged();
    void computeModeChanged();
    void segmentCountChanged();
    void showMessage(const QString& title, const QString& message, bool isError);
    void subtitleExported(const QString& format, const QString& path);

    // ✅ 新增：波形数据变化信号
    void waveformDataChanged();

private slots:
    void onModelLoaded(bool success, const QString& message);
    void onTranscriptionStarted();
    void onTranscriptionProgress(int progress);
    void onTranscriptionCompleted(const QString& text);
    void onTranscriptionFailed(const QString& error);
    void onLogMessage(const QString& message);
    void onComputeModeDetected(const QString& mode, const QString& details);
    void onSegmentTranscribed(const QString& segmentText);

    // ✅ 新增：波形加载完成槽
    void onWaveformLoadingCompleted();

private:
    WhisperWorker* m_worker;
    QThread* m_workerThread;
    SubtitleGenerator* m_subtitleGenerator;
    AudioPlaybackController* m_playbackController;
    WaveformGenerator* m_waveformGenerator;  // ✅ 保留用于内部管理

    QString m_modelPath;
    QString m_audioPath;
    QString m_logText;
    QString m_resultText;
    QString m_computeMode;
    int m_progress;
    bool m_isProcessing;
    bool m_modelLoaded;

    int64_t m_lastSegmentStartTime;
    int64_t m_lastSegmentEndTime;

    void appendLog(const QString& message);
    void parseSegmentTiming(const QString& segmentText, int64_t& startTime, int64_t& endTime, QString& text);
};

#endif