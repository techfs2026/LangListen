#ifndef SUBTITLEGENERATOR_H
#define SUBTITLEGENERATOR_H

#include <QObject>
#include <QString>
#include <QVector>

struct SubtitleSegment {
    int64_t startTime;
    int64_t endTime;
    QString text;

    SubtitleSegment()
        : startTime(0)
        , endTime(0)
    {
    }

    SubtitleSegment(int64_t start, int64_t end, const QString& txt)
        : startTime(start)
        , endTime(end)
        , text(txt)
    {
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

    QString generateSRT() const;
    QString generateLRC() const;
    QString generatePlainText() const;

    bool saveSRT(const QString& filePath);
    bool saveLRC(const QString& filePath);
    bool savePlainText(const QString& filePath);

    int segmentCount() const { return m_segments.size(); }
    SubtitleSegment getSegment(int index) const;
    QVector<SubtitleSegment> getAllSegments() const { return m_segments; }

signals:
    void segmentAdded(int index);
    void generationCompleted(const QString& format);
    void saveFailed(const QString& error);

private:
    QVector<SubtitleSegment> m_segments;

    QString formatTimeSRT(int64_t milliseconds) const;
    QString formatTimeLRC(int64_t milliseconds) const;
    bool saveToFile(const QString& filePath, const QString& content) const;
};

#endif