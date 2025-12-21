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
        if (m_duration <= 10000) {
            targetSamples = 1000;
        }
        else if (m_duration <= 60000) {
            targetSamples = 3000;
        }
        else if (m_duration <= 600000) {
            targetSamples = 6000;
        }
        else {
            targetSamples = 10000;
        }
        emit logMessage(QString("Auto-calculated targetSamples: %1 (duration: %2 ms)")
            .arg(targetSamples).arg(m_duration));
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

    if (totalSamples < targetSamples) {
        targetSamples = totalSamples;
        emit logMessage(QString("Adjusted targetSamples to %1 (total samples: %2)")
            .arg(targetSamples).arg(totalSamples));
    }

    float samplesPerBinFloat = static_cast<float>(totalSamples) / targetSamples;
    int samplesPerBin = std::max(1, static_cast<int>(samplesPerBinFloat));

    emit logMessage(QString("Generating waveform: totalSamples=%1, targetSamples=%2, samplesPerBin=%3, samplesPerBinFloat=%4")
        .arg(totalSamples)
        .arg(targetSamples)
        .arg(samplesPerBin)
        .arg(samplesPerBinFloat));

    for (int i = 0; i < targetSamples; ++i) {
        float startIdxFloat = i * samplesPerBinFloat;
        float endIdxFloat = (i + 1) * samplesPerBinFloat;

        int startIdx = static_cast<int>(startIdxFloat);
        int endIdx = static_cast<int>(std::ceil(endIdxFloat));

        endIdx = std::min(endIdx, totalSamples);

        if (startIdx >= totalSamples) {
            emit logMessage(QString("Warning: startIdx (%1) >= totalSamples (%2) at bin %3")
                .arg(startIdx).arg(totalSamples).arg(i));
            break;
        }

        float minVal = audioData[startIdx];
        float maxVal = audioData[startIdx];

        for (int j = startIdx; j < endIdx; ++j) {
            float sample = audioData[j];
            minVal = std::min(minVal, sample);
            maxVal = std::max(maxVal, sample);
        }

        m_waveformData.append(minVal);
        m_waveformData.append(maxVal);

        if (i % 1000 == 0 && i < 3000) {
            emit logMessage(QString("Bin %1: startIdx=%2, endIdx=%3, samples=%4, minVal=%5, maxVal=%6")
                .arg(i)
                .arg(startIdx)
                .arg(endIdx)
                .arg(endIdx - startIdx)
                .arg(minVal, 0, 'f', 6)
                .arg(maxVal, 0, 'f', 6));
        }
    }

    emit waveformDataChanged();

    emit logMessage(QString("Waveform generated: %1 data points (%2 min/max pairs), targetSamples=%3")
        .arg(m_waveformData.size())
        .arg(m_waveformData.size() / 2)
        .arg(targetSamples));

    int invalidPairs = 0;
    for (int i = 0; i < m_waveformData.size() / 2; ++i) {
        float min = m_waveformData[i * 2].toFloat();
        float max = m_waveformData[i * 2 + 1].toFloat();
        if (min > max) {
            invalidPairs++;
            if (invalidPairs <= 5) {
                emit logMessage(QString("WARNING: Invalid pair at index %1: min=%2 > max=%3")
                    .arg(i).arg(min, 0, 'f', 6).arg(max, 0, 'f', 6));
            }
        }
    }
    if (invalidPairs > 0) {
        emit logMessage(QString("WARNING: Found %1 invalid min/max pairs (min > max)")
            .arg(invalidPairs));
    }
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