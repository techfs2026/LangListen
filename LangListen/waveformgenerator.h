#ifndef WAVEFORMGENERATOR_H
#define WAVEFORMGENERATOR_H

#include <QObject>
#include <QString>
#include <QVector>
#include <QVariantList>
#include "audioconverter.h"

class WaveformGenerator : public QObject
{
    Q_OBJECT
        Q_PROPERTY(QVariantList waveformData READ waveformData NOTIFY waveformDataChanged)
        Q_PROPERTY(qint64 duration READ duration NOTIFY durationChanged)
        Q_PROPERTY(int sampleCount READ sampleCount NOTIFY sampleCountChanged)
        Q_PROPERTY(bool isLoaded READ isLoaded NOTIFY isLoadedChanged)

public:
    explicit WaveformGenerator(QObject* parent = nullptr);
    ~WaveformGenerator();

    QVariantList waveformData() const { return m_waveformData; }
    qint64 duration() const { return m_duration; }
    int sampleCount() const { return m_waveformData.size(); }
    bool isLoaded() const { return m_isLoaded; }

    Q_INVOKABLE bool loadAudio(const QString& filePath, int targetSamples = 1000);
    Q_INVOKABLE void clear();
    Q_INVOKABLE int calculateOptimalTimeInterval(qint64 durationMs) const;
    Q_INVOKABLE QVariantList getTimeMarkers(int intervalMs) const;

signals:
    void waveformDataChanged();
    void durationChanged();
    void sampleCountChanged();
    void isLoadedChanged();
    void loadingProgress(int progress);
    void loadingCompleted();
    void loadingFailed(const QString& error);
    void logMessage(const QString& message);

private:
    QVariantList m_waveformData;
    qint64 m_duration;
    bool m_isLoaded;
    AudioConverter* m_audioConverter;
    QVariantList m_waveformMinMax;

    void generateWaveformData(const std::vector<float>& audioData, int sampleRate, int targetSamples);
    float calculateRMS(const float* samples, int count) const;
};

#endif // WAVEFORMGENERATOR_H