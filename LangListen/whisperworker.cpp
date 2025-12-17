#include "whisperworker.h"
#include <QFile>
#include <QDebug>
#include <QLibrary>
#include <QProcess>
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
{
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

            emit logMessage(QString("✓ 找到CUDA运行时: %1 (版本 %2)").arg(dllName, version));
            return true;
        }
    }

    emit logMessage("✗ 未找到CUDA运行时DLL");
    emit logMessage("  提示：如果您有NVIDIA GPU，请安装CUDA Toolkit");
    emit logMessage("  下载地址：https://developer.nvidia.com/cuda-downloads");
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
                emit logMessage(QString("✓ 检测到NVIDIA GPU: %1").arg(gpuName));
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
                    emit logMessage(QString("✓ 检测到NVIDIA GPU: %1").arg(gpuName));
                    SetupDiDestroyDeviceInfoList(hDevInfo);
                    return true;
                }
            }
        }
        SetupDiDestroyDeviceInfoList(hDevInfo);
    }

    emit logMessage("✗ 未检测到NVIDIA GPU");
    return false;
#endif
}

SystemCapabilities WhisperWorker::detectSystemCapabilities()
{
    SystemCapabilities caps;

    emit logMessage("=== 开始检测系统GPU能力 ===");

    caps.hasNvidiaGpu = checkNvidiaGpu(caps.gpuName);

    if (caps.hasNvidiaGpu) {
        caps.hasCudaRuntime = checkCudaRuntime(caps.cudaVersion);

        if (!caps.hasCudaRuntime) {
            caps.failureReason = "CUDA运行时未安装或版本不匹配";
        }
    }
    else {
        caps.failureReason = "未检测到NVIDIA GPU";
        emit logMessage("⚠ 系统中没有NVIDIA GPU，将使用CPU模式");
    }

#ifdef GGML_USE_CUDA
    caps.hasWhisperGpuSupport = true;
    emit logMessage("✓ Whisper库已编译GPU支持");
#else
    caps.hasWhisperGpuSupport = false;
    caps.failureReason = "Whisper库未编译GPU支持";
    emit logMessage("✗ Whisper库未编译GPU支持，将使用CPU模式");
#endif

    emit logMessage("=== 检测完成 ===");

    return caps;
}

bool WhisperWorker::tryInitWithGpu(const QString& modelPath, QString& errorMsg)
{
    emit logMessage("→ 尝试使用GPU模式初始化...");

    struct whisper_context_params cparams = whisper_context_default_params();
    cparams.use_gpu = true;

    struct whisper_context* ctx = whisper_init_from_file_with_params(
        modelPath.toUtf8().constData(), cparams);

    if (ctx) {
        m_ctx = ctx;
        m_computeMode = ComputeMode::GPU_ACCELERATED;
        emit logMessage("✓ GPU模式初始化成功！");
        return true;
    }
    else {
        errorMsg = "GPU模式初始化失败（可能是CUDA版本不匹配）";
        emit logMessage("✗ " + errorMsg);
        return false;
    }
}

bool WhisperWorker::tryInitWithCpu(const QString& modelPath, QString& errorMsg)
{
    emit logMessage("→ 使用CPU模式初始化...");

    struct whisper_context_params cparams = whisper_context_default_params();
    cparams.use_gpu = false;

    struct whisper_context* ctx = whisper_init_from_file_with_params(
        modelPath.toUtf8().constData(), cparams);

    if (ctx) {
        m_ctx = ctx;
        m_computeMode = ComputeMode::CPU_ONLY;
        emit logMessage("✓ CPU模式初始化成功");
        return true;
    }
    else {
        errorMsg = "CPU模式初始化失败（模型文件可能损坏）";
        emit logMessage("✗ " + errorMsg);
        return false;
    }
}

QString WhisperWorker::formatCapabilities(const SystemCapabilities& caps)
{
    QString info;
    info += "系统GPU能力检测结果:\n";
    info += QString("• GPU: %1\n").arg(caps.hasNvidiaGpu ? "✓ " + caps.gpuName : "✗ 未检测到");
    info += QString("• CUDA运行时: %1\n").arg(caps.hasCudaRuntime ? "✓ 版本 " + caps.cudaVersion : "✗ 未安装");
    info += QString("• Whisper GPU支持: %1\n").arg(caps.hasWhisperGpuSupport ? "✓ 已启用" : "✗ 未编译");

    if (!caps.failureReason.isEmpty()) {
        info += QString("• 限制原因: %1\n").arg(caps.failureReason);
    }

    return info;
}

bool WhisperWorker::initModel(const QString& modelPath)
{
    emit logMessage("====================================");
    emit logMessage("开始初始化Whisper模型...");
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
        emit logMessage("→ 系统满足GPU运行条件，尝试GPU模式");
        success = tryInitWithGpu(modelPath, errorMsg);

        if (!success) {
            emit logMessage("⚠ GPU模式失败，这可能是因为：");
            emit logMessage("  1. CUDA版本与编译时不匹配");
            emit logMessage("  2. GPU驱动版本过旧");
            emit logMessage("  3. GPU内存不足");
            emit logMessage("→ 自动回退到CPU模式...");

            success = tryInitWithCpu(modelPath, errorMsg);
        }
    }
    else {
        emit logMessage("→ 系统不满足GPU运行条件，使用CPU模式");

        if (!m_capabilities.hasNvidiaGpu) {
            emit logMessage("  原因: 未检测到NVIDIA GPU");
        }
        else if (!m_capabilities.hasCudaRuntime) {
            emit logMessage("  原因: CUDA运行时未安装");
            emit logMessage("  解决: 访问 https://developer.nvidia.com/cuda-downloads");
        }
        else if (!m_capabilities.hasWhisperGpuSupport) {
            emit logMessage("  原因: Whisper库未编译GPU支持");
        }

        success = tryInitWithCpu(modelPath, errorMsg);
    }

    if (!success) {
        m_lastError = "模型初始化失败: " + errorMsg;
        m_computeMode = ComputeMode::UNKNOWN;
        emit modelLoaded(false, m_lastError);
        return false;
    }

    QString modeStr = (m_computeMode == ComputeMode::GPU_ACCELERATED) ?
        "GPU加速" : "CPU模式";
    QString details = QString("使用%1，模型路径: %2").arg(modeStr, modelPath);

    emit computeModeDetected(modeStr, details);
    emit logMessage("====================================");
    emit logMessage(QString("✓ 模型加载成功！使用模式: %1").arg(modeStr));
    emit logMessage("====================================");
    emit modelLoaded(true, QString("模型加载成功 (%1)").arg(modeStr));

    return true;
}

bool WhisperWorker::readWavFile(const QString& path, std::vector<float>& audio)
{
    std::ifstream file(path.toStdString(), std::ios::binary);
    if (!file.is_open()) {
        m_lastError = "无法打开音频文件: " + path;
        return false;
    }

    char header[44];
    file.read(header, 44);

    if (strncmp(header, "RIFF", 4) != 0) {
        m_lastError = "不是有效的WAV文件";
        return false;
    }

    int sampleRate = *reinterpret_cast<int*>(&header[24]);
    short bitsPerSample = *reinterpret_cast<short*>(&header[34]);
    short numChannels = *reinterpret_cast<short*>(&header[22]);

    emit logMessage(QString("采样率: %1 Hz, 位深: %2 bit, 声道: %3")
        .arg(sampleRate).arg(bitsPerSample).arg(numChannels));

    if (sampleRate != 16000) {
        emit logMessage(QString("警告: 采样率为 %1 Hz, 推荐使用 16000 Hz").arg(sampleRate));
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
        m_lastError = "只支持16位PCM格式";
        return false;
    }

    file.close();

    emit logMessage(QString("音频加载成功,长度: %1 秒")
        .arg(audio.size() / (float)sampleRate, 0, 'f', 2));

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
        int progress = qMin(90, static_cast<int>((t_end / 100.0) / 2));
        emit worker->transcriptionProgress(progress);
    }
}

void WhisperWorker::transcribe(const QString& audioPath)
{
    if (!m_ctx) {
        emit transcriptionFailed("模型未初始化");
        return;
    }

    emit transcriptionStarted();

    QString modeStr = (m_computeMode == ComputeMode::GPU_ACCELERATED) ? "GPU" : "CPU";
    emit logMessage(QString("开始转写音频（%1模式）...").arg(modeStr));

    std::vector<float> audio;
    if (!readWavFile(audioPath, audio)) {
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

    emit logMessage(QString("正在使用%1进行转写...").arg(modeStr));
    emit transcriptionProgress(10);

    int ret = whisper_full(m_ctx, params, audio.data(), audio.size());

    if (ret != 0) {
        emit transcriptionFailed("转写失败,错误码: " + QString::number(ret));
        return;
    }

    emit transcriptionProgress(100);
    emit logMessage(QString("转写完成！（使用%1模式）").arg(modeStr));

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