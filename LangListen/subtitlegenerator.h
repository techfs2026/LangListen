#ifndef SUBTITLEGENERATOR_H
#define SUBTITLEGENERATOR_H

#include <QObject>
#include <QString>
#include <QVector>

struct SubtitleSegment
{
    int64_t startTime;
    int64_t endTime;
    QString text;

    SubtitleSegment()
        : startTime(0)
        , endTime(0)
        , text("")
    {
    }

    SubtitleSegment(int64_t start, int64_t end, const QString& txt)
        : startTime(start)
        , endTime(end)
        , text(txt)
    {
    }

    bool contains(qint64 timeMs) const {
        return timeMs >= startTime && timeMs < endTime;
    }
};

class SubtitleGenerator : public QObject
{
    Q_OBJECT

public:
    explicit SubtitleGenerator(QObject* parent = nullptr);
    ~SubtitleGenerator();

    void addSegment(int64_t startTime, int64_t endTime, const QString& text);
    void clearSegments();
    SubtitleSegment getSegment(int index) const;
    QVector<SubtitleSegment> getAllSegments() const;
    int segmentCount() const;

    bool updateSegment(int index, int64_t startTime, int64_t endTime, const QString& text);
    bool deleteSegment(int index);

    QString generateSRT() const;
    QString generateLRC() const;

    bool saveSRT(const QString& filePath);
    bool saveLRC(const QString& filePath);

signals:
    void segmentAdded(int index);
    void generationCompleted(const QString& format);
    void saveFailed(const QString& error);
    void segmentUpdated(int index);
    void segmentRemoved(int index);

private:
    QString formatTimeSRT(int64_t milliseconds) const;
    QString formatTimeLRC(int64_t milliseconds) const;
    bool saveToFile(const QString& filePath, const QString& content) const;

    QVector<SubtitleSegment> m_segments;
};

#endif // SUBTITLEGENERATOR_H