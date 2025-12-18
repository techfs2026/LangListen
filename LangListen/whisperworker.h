#ifndef WHISPERWORKER_H
#define WHISPERWORKER_H

#include <QObject>
#include <QString>
#include <QThread>
#include <memory>
#include "audioconverter.h"

extern "C" {
#include "whisper.h"
}

enum class ComputeMode {
    CPU_ONLY,
    GPU_ACCELERATED,
    UNKNOWN
};

struct SystemCapabilities {
    bool hasNvidiaGpu;
    bool hasCudaRuntime;
    bool hasWhisperGpuSupport;
    QString gpuName;
    QString cudaVersion;
    QString failureReason;

    SystemCapabilities()
        : hasNvidiaGpu(false)
        , hasCudaRuntime(false)
        , hasWhisperGpuSupport(false)
    {
    }
};

class WhisperWorker : public QObject
{
    Q_OBJECT

public:
    explicit WhisperWorker(QObject* parent = nullptr);
    ~WhisperWorker();

    Q_INVOKABLE bool initModel(const QString& modelPath);
    Q_INVOKABLE void transcribe(const QString& audioPath);
    Q_INVOKABLE ComputeMode getComputeMode() const { return m_computeMode; }
    Q_INVOKABLE SystemCapabilities getSystemCapabilities() const { return m_capabilities; }

    QString getLastError() const { return m_lastError; }

signals:
    void transcriptionStarted();
    void transcriptionProgress(int progress);
    void transcriptionCompleted(const QString& text);
    void transcriptionFailed(const QString& error);
    void logMessage(const QString& message);
    void modelLoaded(bool success, const QString& message);
    void computeModeDetected(const QString& mode, const QString& details);
    void segmentTranscribed(const QString& segmentText);

private:
    struct whisper_context* m_ctx;
    QString m_lastError;
    ComputeMode m_computeMode;
    SystemCapabilities m_capabilities;
    AudioConverter* m_audioConverter;

    SystemCapabilities detectSystemCapabilities();
    bool checkCudaRuntime(QString& version);
    bool checkNvidiaGpu(QString& gpuName);
    bool tryInitWithGpu(const QString& modelPath, QString& errorMsg);
    bool tryInitWithCpu(const QString& modelPath, QString& errorMsg);
    QString formatCapabilities(const SystemCapabilities& caps);
    bool loadAndConvertAudio(const QString& audioPath, std::vector<float>& audioData);
    bool needsConversion(const QString& filePath);
    bool readWavFile(const QString& path, std::vector<float>& audio);

    static void newSegmentCallback(struct whisper_context* ctx, struct whisper_state* state, int n_new, void* user_data);
};

#endif