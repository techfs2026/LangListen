#ifndef AUDIOCONVERTER_H
#define AUDIOCONVERTER_H

#include <QObject>
#include <QString>
#include <vector>

extern "C" {
#include <libavformat/avformat.h>
#include <libavcodec/avcodec.h>
#include <libswresample/swresample.h>
#include <libavutil/opt.h>
}

class AudioConverter : public QObject
{
    Q_OBJECT

public:
    struct ConversionParams {
        int targetSampleRate;
        int targetChannels;
        AVSampleFormat targetFormat;

        ConversionParams()
            : targetSampleRate(16000)
            , targetChannels(1)
            , targetFormat(AV_SAMPLE_FMT_S16)
        {
        }
    };

    explicit AudioConverter(QObject* parent = nullptr);
    ~AudioConverter();

    bool convert(const QString& inputPath, const QString& outputPath, const ConversionParams& params = ConversionParams());
    bool convertToMemory(const QString& inputPath, std::vector<float>& audioData, const ConversionParams& params = ConversionParams());

    QString getLastError() const { return m_lastError; }
    static bool isFFmpegAvailable();

signals:
    void conversionStarted();
    void conversionProgress(int progress);
    void conversionCompleted(const QString& outputPath);
    void conversionFailed(const QString& error);
    void logMessage(const QString& message);

private:
    QString m_lastError;
    AVFormatContext* m_formatContext;
    AVCodecContext* m_codecContext;
    SwrContext* m_swrContext;
    int m_audioStreamIndex;

    bool openInputFile(const QString& inputPath);
    bool initDecoder();
    bool initResampler(const ConversionParams& params);
    bool decodeAndResample(std::vector<float>& audioData, const ConversionParams& params);
    bool writeWavFile(const QString& outputPath, const std::vector<float>& audioData, const ConversionParams& params);
    void cleanup();
    void emitProgress(int64_t current, int64_t total);
};

#endif