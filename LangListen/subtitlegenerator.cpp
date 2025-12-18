#include "subtitlegenerator.h"
#include <QFile>
#include <QTextStream>

SubtitleGenerator::SubtitleGenerator(QObject* parent)
    : QObject(parent)
{
}

SubtitleGenerator::~SubtitleGenerator()
{
}

void SubtitleGenerator::addSegment(int64_t startTime, int64_t endTime, const QString& text)
{
    m_segments.append(SubtitleSegment(startTime, endTime, text.trimmed()));
    emit segmentAdded(m_segments.size() - 1);
}

void SubtitleGenerator::clearSegments()
{
    m_segments.clear();
}

SubtitleSegment SubtitleGenerator::getSegment(int index) const
{
    if (index >= 0 && index < m_segments.size()) {
        return m_segments[index];
    }
    return SubtitleSegment();
}

QString SubtitleGenerator::formatTimeSRT(int64_t milliseconds) const
{
    int hours = milliseconds / 3600000;
    int minutes = (milliseconds % 3600000) / 60000;
    int seconds = (milliseconds % 60000) / 1000;
    int millis = milliseconds % 1000;

    return QString("%1:%2:%3,%4")
        .arg(hours, 2, 10, QChar('0'))
        .arg(minutes, 2, 10, QChar('0'))
        .arg(seconds, 2, 10, QChar('0'))
        .arg(millis, 3, 10, QChar('0'));
}

QString SubtitleGenerator::formatTimeLRC(int64_t milliseconds) const
{
    int minutes = milliseconds / 60000;
    int seconds = (milliseconds % 60000) / 1000;
    int centiseconds = (milliseconds % 1000) / 10;

    return QString("[%1:%2.%3]")
        .arg(minutes, 2, 10, QChar('0'))
        .arg(seconds, 2, 10, QChar('0'))
        .arg(centiseconds, 2, 10, QChar('0'));
}

QString SubtitleGenerator::generateSRT() const
{
    QString result;

    for (int i = 0; i < m_segments.size(); ++i) {
        const SubtitleSegment& segment = m_segments[i];

        result += QString::number(i + 1) + "\n";
        result += formatTimeSRT(segment.startTime) + " --> " + formatTimeSRT(segment.endTime) + "\n";
        result += segment.text + "\n";
        result += "\n";
    }

    return result;
}

QString SubtitleGenerator::generateLRC() const
{
    QString result;

    result += "[ti:Transcription]\n";
    result += "[ar:Whisper]\n";
    result += "[al:]\n";
    result += "[by:Whisper AI]\n";
    result += "\n";

    for (const SubtitleSegment& segment : m_segments) {
        result += formatTimeLRC(segment.startTime) + segment.text + "\n";
    }

    return result;
}

QString SubtitleGenerator::generatePlainText() const
{
    QString result;

    for (const SubtitleSegment& segment : m_segments) {
        result += segment.text;
        if (!result.endsWith(' ')) {
            result += " ";
        }
    }

    return result.trimmed();
}

bool SubtitleGenerator::saveToFile(const QString& filePath, const QString& content) const
{
    QFile file(filePath);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Text)) {
        return false;
    }

    QTextStream stream(&file);
    stream.setEncoding(QStringConverter::Utf8);
    stream << content;

    file.close();
    return true;
}

bool SubtitleGenerator::saveSRT(const QString& filePath)
{
    QString content = generateSRT();
    bool success = saveToFile(filePath, content);

    if (success) {
        emit generationCompleted("SRT");
    }
    else {
        emit saveFailed("Failed to save SRT file: " + filePath);
    }

    return success;
}

bool SubtitleGenerator::saveLRC(const QString& filePath)
{
    QString content = generateLRC();
    bool success = saveToFile(filePath, content);

    if (success) {
        emit generationCompleted("LRC");
    }
    else {
        emit saveFailed("Failed to save LRC file: " + filePath);
    }

    return success;
}

bool SubtitleGenerator::savePlainText(const QString& filePath)
{
    QString content = generatePlainText();
    bool success = saveToFile(filePath, content);

    if (success) {
        emit generationCompleted("TXT");
    }
    else {
        emit saveFailed("Failed to save text file: " + filePath);
    }

    return success;
}