#include "waveformgenerator.h"
#include <QDebug>
#include <QtMath>
#include <algorithm>

WaveformGenerator::WaveformGenerator(QObject* parent)
    : QObject(parent)
    , m_duration(0)
    , m_isLoaded(false)
{
    m_audioConverter = new AudioConverter(this);

    connect(m_audioConverter, &AudioConverter::conversionProgress,
        this, &WaveformGenerator::loadingProgress);
    connect(m_audioConverter, &AudioConverter::logMessage,
        this, &WaveformGenerator::logMessage);
}

WaveformGenerator::~WaveformGenerator()
{
}

bool WaveformGenerator::loadAudio(const QString& filePath, int targetSamples)
{
    clear();

    emit logMessage("Loading audio for waveform: " + filePath);

    std::vector<float> audioData;
    AudioConverter::ConversionParams params;
    params.targetSampleRate = 44100;
    params.targetChannels = 1;
    params.targetFormat = AV_SAMPLE_FMT_S16;

    if (!m_audioConverter->convertToMemory(filePath, audioData, params)) {
        QString error = "Failed to load audio: " + m_audioConverter->getLastError();
        emit logMessage(error);
        emit loadingFailed(error);
        return false;
    }

    if (audioData.empty()) {
        emit logMessage("Audio data is empty");
        emit loadingFailed("Audio data is empty");
        return false;
    }

    int sampleRate = params.targetSampleRate;
    m_duration = static_cast<qint64>((audioData.size() * 1000.0) / sampleRate);

    emit logMessage(QString("Audio loaded: %1 samples, %2 ms duration, sample rate: %3 Hz")
        .arg(audioData.size())
        .arg(m_duration)
        .arg(sampleRate));

    if (targetSamples <= 0) {
        int samplesPerMs = sampleRate / 1000;
        targetSamples = m_duration;
        emit logMessage(QString("Auto-calculated targetSamples for 1ms precision: %1").arg(targetSamples));
    }

    generateWaveformData(audioData, sampleRate, targetSamples);

    m_isLoaded = true;
    emit isLoadedChanged();
    emit durationChanged();
    emit sampleCountChanged();
    emit loadingCompleted();

    return true;
}

void WaveformGenerator::clear()
{
    m_waveformData.clear();
    m_duration = 0;
    m_isLoaded = false;

    emit waveformDataChanged();
    emit durationChanged();
    emit sampleCountChanged();
    emit isLoadedChanged();
}

void WaveformGenerator::generateWaveformData(const std::vector<float>& audioData,
    int sampleRate,
    int targetSamples)
{
    m_waveformData.clear();

    if (audioData.empty()) {
        emit logMessage("ERROR: Audio data is empty in generateWaveformData");
        return;
    }

    int totalSamples = audioData.size();

    if (targetSamples <= 0) {
        targetSamples = 1000;
        emit logMessage(QString("Warning: Invalid targetSamples, using default: %1").arg(targetSamples));
    }

    int samplesPerBin = std::max(1, totalSamples / targetSamples);

    if (totalSamples < targetSamples) {
        targetSamples = totalSamples;
        samplesPerBin = 1;
        emit logMessage(QString("Warning: totalSamples (%1) < targetSamples, adjusting targetSamples to %2")
            .arg(totalSamples).arg(targetSamples));
    }

    emit logMessage(QString("Generating waveform: totalSamples=%1, targetSamples=%2, samplesPerBin=%3")
        .arg(totalSamples)
        .arg(targetSamples)
        .arg(samplesPerBin));

    for (int i = 0; i < targetSamples; ++i) {
        int startIdx = i * samplesPerBin;
        int endIdx = std::min(startIdx + samplesPerBin, totalSamples);

        if (startIdx >= totalSamples) {
            break;
        }

        float minVal = audioData[startIdx];
        float maxVal = audioData[startIdx];

        for (int j = startIdx; j < endIdx; ++j) {
            minVal = std::min(minVal, audioData[j]);
            maxVal = std::max(maxVal, audioData[j]);
        }

        m_waveformData.append(minVal);
        m_waveformData.append(maxVal);
    }

    emit waveformDataChanged();

    emit logMessage(QString("Waveform generated: %1 data points (%2 min/max pairs)")
        .arg(m_waveformData.size())
        .arg(m_waveformData.size() / 2));
}

float WaveformGenerator::calculateRMS(const float* samples, int count) const
{
    if (count <= 0) {
        return 0.0f;
    }

    double sum = 0.0;
    for (int i = 0; i < count; ++i) {
        sum += samples[i] * samples[i];
    }

    return static_cast<float>(std::sqrt(sum / count));
}

int WaveformGenerator::calculateOptimalTimeInterval(qint64 durationMs) const
{
    static const int intervals[] = { 1, 5, 10, 50, 100 };
    const int minMarkers = 8;
    const int maxMarkers = 20;

    for (int interval : intervals) {
        int markerCount = durationMs / interval;
        if (markerCount >= minMarkers && markerCount <= maxMarkers) {
            return interval;
        }
    }

    if (durationMs < 8000) {
        return 1000;
    }

    return 300000;
}

QVariantList WaveformGenerator::getTimeMarkers(int intervalMs) const
{
    QVariantList markers;

    if (!m_isLoaded || intervalMs <= 0) {
        return markers;
    }

    for (qint64 time = 0; time <= m_duration; time += intervalMs) {
        QVariantMap marker;
        marker["time"] = time;
        marker["position"] = static_cast<double>(time) / m_duration;

        qint64 totalSeconds = time / 1000;
        qint64 minutes = totalSeconds / 60;
        qint64 seconds = totalSeconds % 60;

        QString timeText;
        if (minutes > 0) {
            timeText = QString("%1:%2")
                .arg(minutes)
                .arg(seconds, 2, 10, QChar('0'));
        }
        else {
            timeText = QString("%1s").arg(seconds);
        }

        marker["text"] = timeText;
        markers.append(marker);
    }

    return markers;
}