#include "whisperworker.h"
#include <QFile>
#include <QDebug>
#include <QLibrary>
#include <QProcess>
#include <QDir>
#include <cstring>
#include <fstream>
#include <cstdlib>

#ifdef _WIN32
#include <windows.h>
#include <setupapi.h>
#include <initguid.h>
#include <devguid.h>
#pragma comment(lib, "setupapi.lib")
#endif

WhisperWorker::WhisperWorker(QObject* parent)
    : QObject(parent)
    , m_ctx(nullptr)
    , m_computeMode(ComputeMode::UNKNOWN)
    , m_audioConverter(nullptr)
{
    m_audioConverter = new AudioConverter(this);

    connect(m_audioConverter, &AudioConverter::logMessage, this, &WhisperWorker::logMessage);
    connect(m_audioConverter, &AudioConverter::conversionStarted, this, [this]() {
        emit logMessage("Starting audio format conversion...");
        });
    connect(m_audioConverter, &AudioConverter::conversionProgress, this, [this](int progress) {
        emit transcriptionProgress(progress / 2);
        });
}

WhisperWorker::~WhisperWorker()
{
    if (m_ctx) {
        whisper_free(m_ctx);
        m_ctx = nullptr;
    }
}

bool WhisperWorker::checkCudaRuntime(QString& version)
{
#ifdef _WIN32
    QStringList cudaVersions = {
        "cudart64_12.dll",
        "cudart64_11.dll",
        "cudart64_10.dll"
    };

    for (const QString& dllName : cudaVersions) {
        HMODULE hCudart = LoadLibraryA(dllName.toStdString().c_str());
        if (hCudart) {
            FreeLibrary(hCudart);

            if (dllName.contains("_12")) {
                version = "12.x";
            }
            else if (dllName.contains("_11")) {
                version = "11.x";
            }
            else if (dllName.contains("_10")) {
                version = "10.x";
            }

            emit logMessage(QString("✓ Found CUDA runtime: %1 (version %2)").arg(dllName, version));
            return true;
        }
    }

    emit logMessage("✗ CUDA runtime DLL not found");
    emit logMessage("  Tip: If you have an NVIDIA GPU, please install CUDA Toolkit");
    emit logMessage("  Download: https://developer.nvidia.com/cuda-downloads");
    return false;
#else
    return false;
#endif
}

bool WhisperWorker::checkNvidiaGpu(QString& gpuName)
{
#ifdef _WIN32
    QProcess process;
    process.start("nvidia-smi", QStringList() << "--query-gpu=name" << "--format=csv,noheader");

    if (process.waitForFinished(3000)) {
        if (process.exitCode() == 0) {
            gpuName = QString::fromLocal8Bit(process.readAllStandardOutput()).trimmed();
            if (!gpuName.isEmpty()) {
                emit logMessage(QString("✓ Detected NVIDIA GPU: %1").arg(gpuName));
                return true;
            }
        }
    }

    HDEVINFO hDevInfo = SetupDiGetClassDevs(&GUID_DEVCLASS_DISPLAY, NULL, NULL, DIGCF_PRESENT);
    if (hDevInfo != INVALID_HANDLE_VALUE) {
        SP_DEVINFO_DATA devInfoData;
        devInfoData.cbSize = sizeof(SP_DEVINFO_DATA);

        for (DWORD i = 0; SetupDiEnumDeviceInfo(hDevInfo, i, &devInfoData); i++) {
            char buffer[256];
            if (SetupDiGetDeviceRegistryPropertyA(hDevInfo, &devInfoData,
                SPDRP_DEVICEDESC, NULL, (PBYTE)buffer, sizeof(buffer), NULL)) {
                QString desc = QString::fromLocal8Bit(buffer);
                if (desc.contains("NVIDIA", Qt::CaseInsensitive) ||
                    desc.contains("GeForce", Qt::CaseInsensitive) ||
                    desc.contains("Quadro", Qt::CaseInsensitive) ||
                    desc.contains("Tesla", Qt::CaseInsensitive)) {
                    gpuName = desc;
                    emit logMessage(QString("✓ Detected NVIDIA GPU: %1").arg(gpuName));
                    SetupDiDestroyDeviceInfoList(hDevInfo);
                    return true;
                }
            }
        }
        SetupDiDestroyDeviceInfoList(hDevInfo);
    }

    emit logMessage("✗ No NVIDIA GPU detected");
    return false;
#else
    return false;
#endif
}

SystemCapabilities WhisperWorker::detectSystemCapabilities()
{
    SystemCapabilities caps;

    emit logMessage("=== Detecting system GPU capabilities ===");

    caps.hasNvidiaGpu = checkNvidiaGpu(caps.gpuName);

    if (caps.hasNvidiaGpu) {
        caps.hasCudaRuntime = checkCudaRuntime(caps.cudaVersion);

        if (!caps.hasCudaRuntime) {
            caps.failureReason = "CUDA runtime not installed or version mismatch";
        }
    }
    else {
        caps.failureReason = "No NVIDIA GPU detected";
        emit logMessage("⚠ No NVIDIA GPU found, will use CPU mode");
    }

#ifdef GGML_USE_CUDA
    caps.hasWhisperGpuSupport = true;
    emit logMessage("✓ Whisper library compiled with GPU support");
#else
    caps.hasWhisperGpuSupport = false;
    caps.failureReason = "Whisper library not compiled with GPU support";
    emit logMessage("✗ Whisper library not compiled with GPU support, will use CPU mode");
#endif

    emit logMessage("=== Detection complete ===");

    return caps;
}

bool WhisperWorker::tryInitWithGpu(const QString& modelPath, QString& errorMsg)
{
    emit logMessage("→ Attempting GPU mode initialization...");

    struct whisper_context_params cparams = whisper_context_default_params();
    cparams.use_gpu = true;

    struct whisper_context* ctx = whisper_init_from_file_with_params(
        modelPath.toUtf8().constData(), cparams);

    if (ctx) {
        m_ctx = ctx;
        m_computeMode = ComputeMode::GPU_ACCELERATED;
        emit logMessage("✓ GPU mode initialization successful!");
        return true;
    }
    else {
        errorMsg = "GPU mode initialization failed (possibly CUDA version mismatch)";
        emit logMessage("✗ " + errorMsg);
        return false;
    }
}

bool WhisperWorker::tryInitWithCpu(const QString& modelPath, QString& errorMsg)
{
    emit logMessage("→ Using CPU mode initialization...");

    struct whisper_context_params cparams = whisper_context_default_params();
    cparams.use_gpu = false;

    struct whisper_context* ctx = whisper_init_from_file_with_params(
        modelPath.toUtf8().constData(), cparams);

    if (ctx) {
        m_ctx = ctx;
        m_computeMode = ComputeMode::CPU_ONLY;
        emit logMessage("✓ CPU mode initialization successful");
        return true;
    }
    else {
        errorMsg = "CPU mode initialization failed (model file may be corrupted)";
        emit logMessage("✗ " + errorMsg);
        return false;
    }
}

QString WhisperWorker::formatCapabilities(const SystemCapabilities& caps)
{
    QString info;
    info += "System GPU capability detection results:\n";
    info += QString("• GPU: %1\n").arg(caps.hasNvidiaGpu ? "✓ " + caps.gpuName : "✗ Not detected");
    info += QString("• CUDA runtime: %1\n").arg(caps.hasCudaRuntime ? "✓ Version " + caps.cudaVersion : "✗ Not installed");
    info += QString("• Whisper GPU support: %1\n").arg(caps.hasWhisperGpuSupport ? "✓ Enabled" : "✗ Not compiled");

    if (!caps.failureReason.isEmpty()) {
        info += QString("• Limitation: %1\n").arg(caps.failureReason);
    }

    return info;
}

bool WhisperWorker::initModel(const QString& modelPath)
{
    emit logMessage("====================================");
    emit logMessage("Initializing Whisper model...");
    emit logMessage("====================================");

    if (m_ctx) {
        whisper_free(m_ctx);
        m_ctx = nullptr;
    }

    m_capabilities = detectSystemCapabilities();

    QString capInfo = formatCapabilities(m_capabilities);
    emit logMessage(capInfo);

    bool shouldTryGpu = m_capabilities.hasNvidiaGpu &&
        m_capabilities.hasCudaRuntime &&
        m_capabilities.hasWhisperGpuSupport;

    QString errorMsg;
    bool success = false;

    if (shouldTryGpu) {
        emit logMessage("→ System meets GPU requirements, attempting GPU mode");
        success = tryInitWithGpu(modelPath, errorMsg);

        if (!success) {
            emit logMessage("⚠ GPU mode failed, this may be due to:");
            emit logMessage("  1. CUDA version mismatch with compilation");
            emit logMessage("  2. Outdated GPU driver");
            emit logMessage("  3. Insufficient GPU memory");
            emit logMessage("→ Auto-falling back to CPU mode...");

            success = tryInitWithCpu(modelPath, errorMsg);
        }
    }
    else {
        emit logMessage("→ System does not meet GPU requirements, using CPU mode");

        if (!m_capabilities.hasNvidiaGpu) {
            emit logMessage("  Reason: No NVIDIA GPU detected");
        }
        else if (!m_capabilities.hasCudaRuntime) {
            emit logMessage("  Reason: CUDA runtime not installed");
            emit logMessage("  Solution: Visit https://developer.nvidia.com/cuda-downloads");
        }
        else if (!m_capabilities.hasWhisperGpuSupport) {
            emit logMessage("  Reason: Whisper library not compiled with GPU support");
        }

        success = tryInitWithCpu(modelPath, errorMsg);
    }

    if (!success) {
        m_lastError = "Model initialization failed: " + errorMsg;
        m_computeMode = ComputeMode::UNKNOWN;
        emit modelLoaded(false, m_lastError);
        return false;
    }

    QString modeStr = (m_computeMode == ComputeMode::GPU_ACCELERATED) ?
        "GPU accelerated" : "CPU mode";
    QString details = QString("Using %1, model path: %2").arg(modeStr, modelPath);

    emit computeModeDetected(modeStr, details);
    emit logMessage("====================================");
    emit logMessage(QString("✓ Model loaded successfully! Mode: %1").arg(modeStr));
    emit logMessage("====================================");
    emit modelLoaded(true, QString("Model loaded successfully (%1)").arg(modeStr));

    return true;
}

bool WhisperWorker::needsConversion(const QString& filePath)
{
    QFileInfo fileInfo(filePath);
    QString suffix = fileInfo.suffix().toLower();

    if (suffix != "wav") {
        return true;
    }

    std::ifstream file(filePath.toStdString(), std::ios::binary);
    if (!file.is_open()) {
        return false;
    }

    char header[44];
    file.read(header, 44);

    if (strncmp(header, "RIFF", 4) != 0) {
        return true;
    }

    int sampleRate = *reinterpret_cast<int*>(&header[24]);
    short numChannels = *reinterpret_cast<short*>(&header[22]);
    short bitsPerSample = *reinterpret_cast<short*>(&header[34]);

    file.close();

    return (sampleRate != 16000 || numChannels != 1 || bitsPerSample != 16);
}

bool WhisperWorker::readWavFile(const QString& path, std::vector<float>& audio)
{
    std::ifstream file(path.toStdString(), std::ios::binary);
    if (!file.is_open()) {
        m_lastError = "Cannot open audio file: " + path;
        return false;
    }

    char header[44];
    file.read(header, 44);

    if (strncmp(header, "RIFF", 4) != 0) {
        m_lastError = "Not a valid WAV file";
        return false;
    }

    int sampleRate = *reinterpret_cast<int*>(&header[24]);
    short bitsPerSample = *reinterpret_cast<short*>(&header[34]);
    short numChannels = *reinterpret_cast<short*>(&header[22]);

    emit logMessage(QString("Sample rate: %1 Hz, bit depth: %2 bit, channels: %3")
        .arg(sampleRate).arg(bitsPerSample).arg(numChannels));

    if (sampleRate != 16000) {
        emit logMessage(QString("Warning: Sample rate is %1 Hz, recommended: 16000 Hz").arg(sampleRate));
    }

    file.seekg(0, std::ios::end);
    size_t fileSize = file.tellg();
    size_t dataSize = fileSize - 44;
    file.seekg(44, std::ios::beg);

    if (bitsPerSample == 16) {
        std::vector<int16_t> samples(dataSize / 2);
        file.read(reinterpret_cast<char*>(samples.data()), dataSize);

        audio.resize(samples.size() / numChannels);
        for (size_t i = 0; i < audio.size(); ++i) {
            float sum = 0.0f;
            for (int ch = 0; ch < numChannels; ++ch) {
                sum += samples[i * numChannels + ch];
            }
            audio[i] = (sum / numChannels) / 32768.0f;
        }
    }
    else {
        m_lastError = "Only 16-bit PCM format is supported";
        return false;
    }

    file.close();

    emit logMessage(QString("Audio loaded successfully, duration: %1 seconds")
        .arg(audio.size() / (float)sampleRate, 0, 'f', 2));

    return true;
}

bool WhisperWorker::loadAndConvertAudio(const QString& audioPath, std::vector<float>& audioData)
{
    if (!needsConversion(audioPath)) {
        emit logMessage("Audio file already in correct format (16kHz, mono, 16-bit WAV)");
        return readWavFile(audioPath, audioData);
    }

    emit logMessage(QString("Audio needs conversion, using FFmpeg library..."));

    AudioConverter::ConversionParams params;
    params.targetSampleRate = 16000;
    params.targetChannels = 1;
    params.targetFormat = AV_SAMPLE_FMT_S16;

    if (!m_audioConverter->convertToMemory(audioPath, audioData, params)) {
        m_lastError = "Audio conversion failed: " + m_audioConverter->getLastError();
        emit logMessage(m_lastError);
        return false;
    }

    return true;
}

void WhisperWorker::newSegmentCallback(struct whisper_context* ctx, struct whisper_state* state, int n_new, void* user_data)
{
    WhisperWorker* worker = static_cast<WhisperWorker*>(user_data);

    const int n_segments = whisper_full_n_segments(ctx);

    for (int i = n_segments - n_new; i < n_segments; ++i) {
        const char* text = whisper_full_get_segment_text(ctx, i);
        int64_t t0 = whisper_full_get_segment_t0(ctx, i);
        int64_t t1 = whisper_full_get_segment_t1(ctx, i);

        QString timestamp = QString("[%1 -> %2] ")
            .arg(t0 / 100.0, 0, 'f', 2)
            .arg(t1 / 100.0, 0, 'f', 2);

        QString segmentText = timestamp + QString::fromUtf8(text) + "\n";

        emit worker->segmentTranscribed(segmentText);
    }

    if (n_segments > 0) {
        int64_t t_end = whisper_full_get_segment_t1(ctx, n_segments - 1);
        int progress = qMin(90, static_cast<int>((t_end / 100.0) / 2)) + 50;
        emit worker->transcriptionProgress(progress);
    }
}

void WhisperWorker::transcribe(const QString& audioPath)
{
    if (!m_ctx) {
        emit transcriptionFailed("Model not initialized");
        return;
    }

    emit transcriptionStarted();

    QString modeStr = (m_computeMode == ComputeMode::GPU_ACCELERATED) ? "GPU" : "CPU";
    emit logMessage(QString("Starting transcription (%1 mode)...").arg(modeStr));

    std::vector<float> audio;
    if (!loadAndConvertAudio(audioPath, audio)) {
        emit transcriptionFailed(m_lastError);
        return;
    }

    struct whisper_full_params params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
    params.print_progress = false;
    params.print_timestamps = true;
    params.print_special = false;
    params.translate = false;
    params.language = "en";
    params.n_threads = (m_computeMode == ComputeMode::CPU_ONLY) ? 4 : 1;
    params.offset_ms = 0;
    params.duration_ms = 0;

    params.new_segment_callback = WhisperWorker::newSegmentCallback;
    params.new_segment_callback_user_data = this;

    emit logMessage(QString("Transcribing using %1...").arg(modeStr));
    emit transcriptionProgress(50);

    int ret = whisper_full(m_ctx, params, audio.data(), audio.size());

    if (ret != 0) {
        emit transcriptionFailed("Transcription failed, error code: " + QString::number(ret));
        return;
    }

    emit transcriptionProgress(100);
    emit logMessage(QString("Transcription completed! (using %1 mode)").arg(modeStr));

    int n_segments = whisper_full_n_segments(m_ctx);
    QString result;

    for (int i = 0; i < n_segments; ++i) {
        const char* text = whisper_full_get_segment_text(m_ctx, i);
        int64_t t0 = whisper_full_get_segment_t0(m_ctx, i);
        int64_t t1 = whisper_full_get_segment_t1(m_ctx, i);

        QString timestamp = QString("[%1 -> %2] ")
            .arg(t0 / 100.0, 0, 'f', 2)
            .arg(t1 / 100.0, 0, 'f', 2);

        result += timestamp + QString::fromUtf8(text) + "\n";
    }

    emit transcriptionCompleted(result);
}