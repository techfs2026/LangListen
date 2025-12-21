#include "waveformrenderer.h"
#include <QPainterPath>
#include <QtMath>
#include <QDebug>

WaveformRenderer::WaveformRenderer(QQuickItem* parent)
    : QQuickPaintedItem(parent)
    , m_currentPosition(0.0)
    , m_duration(0)
    , m_zoomLevel(1.0)
    , m_scrollPosition(0.0)
    , m_contentWidth(0.0)
    , m_minorGridInterval(1000)
    , m_majorGridInterval(5000)
{
    m_waveformColor = QColor(100, 150, 220);
    m_waveformShadowColor = QColor(150, 180, 230);
    m_backgroundColor = QColor(45, 45, 48);
    m_rulerColor = QColor(60, 60, 63);
    m_gridLineColor = QColor(80, 80, 85);
    m_timeTextColor = QColor(200, 200, 200);
    m_playheadColor = QColor(255, 255, 255);
    m_segmentMarkerColor = QColor(255, 215, 0, 50);

    setAntialiasing(true);
    setRenderTarget(QQuickPaintedItem::FramebufferObject);
}

void WaveformRenderer::setWaveformData(const QVariantList& data)
{
    m_waveformData = data;
    updateCachedData();
    emit waveformDataChanged();
    update();
}

void WaveformRenderer::setCurrentPosition(qreal position)
{
    if (qAbs(m_currentPosition - position) < 0.0001)
        return;
    m_currentPosition = position;
    emit currentPositionChanged();
    update();
}

void WaveformRenderer::setDuration(qint64 duration)
{
    if (m_duration == duration)
        return;
    m_duration = duration;
    updateContentWidth();
    updateGridIntervals();
    emit durationChanged();
    update();
}

void WaveformRenderer::setSegments(const QVariantList& segments)
{
    m_segments = segments;
    updateCachedData();
    emit segmentsChanged();
    update();
}

void WaveformRenderer::setZoomLevel(qreal zoom)
{
    zoom = qBound(m_minZoom, zoom, m_maxZoom);
    if (qAbs(m_zoomLevel - zoom) < 0.01)
        return;
    m_zoomLevel = zoom;
    updateContentWidth();
    updateGridIntervals();
    emit zoomLevelChanged();
    update();
}

void WaveformRenderer::setScrollPosition(qreal position)
{
    if (qAbs(m_scrollPosition - position) < 0.1)
        return;
    m_scrollPosition = position;
    emit scrollPositionChanged();
    update();
}

void WaveformRenderer::zoomIn()
{
    setZoomLevel(m_zoomLevel * 1.5);
}

void WaveformRenderer::zoomOut()
{
    setZoomLevel(m_zoomLevel / 1.5);
}

void WaveformRenderer::resetZoom()
{
    setZoomLevel(1.0);
}

void WaveformRenderer::fitToView()
{
    if (m_duration > 0 && width() > 0) {
        qreal targetPixelsPerSecond = (width() * 0.95) / (m_duration / 1000.0);
        qreal newZoom = targetPixelsPerSecond / m_basePixelsPerSecond;
        setZoomLevel(qBound(m_minZoom, newZoom, m_maxZoom));
    }
}

QString WaveformRenderer::formatTime(qint64 milliseconds)
{
    qint64 totalSeconds = milliseconds / 1000;
    qint64 minutes = totalSeconds / 60;
    qint64 seconds = totalSeconds % 60;
    if (minutes > 0) {
        return QString("%1:%2").arg(minutes).arg(seconds, 2, 10, QChar('0'));
    }
    return QString("%1s").arg(seconds);
}

void WaveformRenderer::updateContentWidth()
{
    if (m_duration > 0) {
        qreal pixelsPerSecond = m_basePixelsPerSecond * m_zoomLevel;
        m_contentWidth = qMax((m_duration / 1000.0) * pixelsPerSecond, width());
    }
    else {
        m_contentWidth = width();
    }
    emit contentWidthChanged();
}

void WaveformRenderer::updateGridIntervals()
{
    if (width() <= 0 || m_duration <= 0)
        return;

    qreal pixelsPerSecond = m_basePixelsPerSecond * m_zoomLevel;
    qreal visibleSeconds = width() / pixelsPerSecond;

    if (visibleSeconds <= 5) {
        m_minorGridInterval = 100;
        m_majorGridInterval = 500;
    }
    else if (visibleSeconds <= 30) {
        m_minorGridInterval = 500;
        m_majorGridInterval = 2000;
    }
    else if (visibleSeconds <= 120) {
        m_minorGridInterval = 1000;
        m_majorGridInterval = 5000;
    }
    else if (visibleSeconds <= 600) {
        m_minorGridInterval = 5000;
        m_majorGridInterval = 30000;
    }
    else {
        m_minorGridInterval = 10000;
        m_majorGridInterval = 60000;
    }
}

void WaveformRenderer::updateCachedData()
{
    m_waveformDataCache.clear();
    m_waveformDataCache.reserve(m_waveformData.size());
    for (const QVariant& v : m_waveformData) {
        m_waveformDataCache.append(v.toFloat());
    }

    m_segmentsCache.clear();
    for (const QVariant& v : m_segments) {
        QVariantMap map = v.toMap();
        WaveformSegment seg;
        seg.startTime = map["startTime"].toLongLong();
        seg.endTime = map["endTime"].toLongLong();
        seg.text = map["text"].toString();
        m_segmentsCache.append(seg);
    }
}

void WaveformRenderer::paint(QPainter* painter)
{
    if (width() <= 0 || height() <= 0)
        return;

    painter->setRenderHint(QPainter::Antialiasing, true);

    drawBackground(painter);
    drawGrid(painter);
    drawSegments(painter);
    drawWaveform(painter);
    drawRuler(painter);
    drawPlayhead(painter);
}

void WaveformRenderer::drawBackground(QPainter* painter)
{
    painter->fillRect(0, 0, width(), height(), m_backgroundColor);
    painter->fillRect(0, 0, width(), m_rulerHeight, m_rulerColor);
}

void WaveformRenderer::drawGrid(QPainter* painter)
{
    if (m_duration <= 0)
        return;

    painter->save();
    painter->setClipRect(0, m_rulerHeight, width(), height() - m_rulerHeight);

    qreal startTime = (m_scrollPosition / m_contentWidth) * m_duration;
    qreal endTime = ((m_scrollPosition + width()) / m_contentWidth) * m_duration;

    startTime = qFloor(startTime / m_minorGridInterval) * m_minorGridInterval;
    endTime = qCeil(endTime / m_minorGridInterval) * m_minorGridInterval;

    QPen gridPen;
    gridPen.setColor(m_gridLineColor);
    gridPen.setWidth(1);

    for (qint64 time = startTime; time <= endTime; time += m_minorGridInterval) {
        if (time < 0 || time > m_duration)
            continue;

        qreal xPos = (time / (qreal)m_duration) * m_contentWidth - m_scrollPosition;
        bool isMajor = (time % m_majorGridInterval == 0);

        gridPen.setColor(m_gridLineColor);
        if (isMajor) {
            gridPen.setWidthF(1.0);
            painter->setOpacity(0.3);
        }
        else {
            gridPen.setWidthF(0.5);
            painter->setOpacity(0.15);
        }

        painter->setPen(gridPen);
        painter->drawLine(QPointF(xPos, m_rulerHeight), QPointF(xPos, height()));
    }

    painter->restore();
}

void WaveformRenderer::drawSegments(QPainter* painter)
{
    if (m_segmentsCache.isEmpty() || m_duration <= 0)
        return;

    painter->save();
    painter->setClipRect(0, m_rulerHeight, width(), height() - m_rulerHeight);

    for (const WaveformSegment& seg : m_segmentsCache) {
        qreal startX = (seg.startTime / (qreal)m_duration) * m_contentWidth - m_scrollPosition;
        qreal endX = (seg.endTime / (qreal)m_duration) * m_contentWidth - m_scrollPosition;

        if (endX < 0 || startX > width())
            continue;

        QRectF rect(startX, m_rulerHeight, endX - startX, height() - m_rulerHeight);
        painter->fillRect(rect, m_segmentMarkerColor);
    }

    painter->restore();
}

void WaveformRenderer::drawWaveform(QPainter* painter)
{
    if (m_waveformDataCache.isEmpty())
        return;

    painter->save();
    painter->setClipRect(0, m_rulerHeight, width(), height() - m_rulerHeight);

    const qreal centerY = m_rulerHeight + (height() - m_rulerHeight) / 2.0;
    const qreal halfHeight = (height() - m_rulerHeight) / 2.0 * 0.9;

    const qreal visibleStartX = m_scrollPosition;
    const qreal visibleEndX = m_scrollPosition + width();

    const int numBins = m_waveformDataCache.size() / 2;
    if (numBins <= 1) {
        painter->restore();
        return;
    }

    const qreal pixelsPerBin = m_contentWidth / numBins;

    if (pixelsPerBin >= 2.0) {
        drawDetailedWaveform(painter, centerY, halfHeight, visibleStartX, visibleEndX, numBins, pixelsPerBin);
    }
    else if (pixelsPerBin >= 0.5) {
        drawMediumWaveform(painter, centerY, halfHeight, visibleStartX, visibleEndX, numBins, pixelsPerBin);
    }
    else {
        drawFilledWaveform(painter, centerY, halfHeight, visibleStartX, visibleEndX, numBins, pixelsPerBin);
    }

    painter->restore();
}

void WaveformRenderer::drawDetailedWaveform(QPainter* painter, qreal centerY, qreal halfHeight,
    qreal visibleStartX, qreal visibleEndX,
    int numBins, qreal pixelsPerBin)
{
    int startBin = qMax(0, (int)(visibleStartX / pixelsPerBin) - 1);
    int endBin = qMin(numBins - 1, (int)(visibleEndX / pixelsPerBin) + 1);

    if (startBin >= endBin)
        return;

    painter->setOpacity(0.5);
    QPen fillPen(m_waveformShadowColor);
    fillPen.setWidthF(qMax(1.0, pixelsPerBin * 0.8));
    fillPen.setCapStyle(Qt::FlatCap);
    painter->setPen(fillPen);

    for (int bin = startBin; bin <= endBin; ++bin) {
        const int idx = bin * 2;
        if (idx + 1 >= m_waveformDataCache.size())
            break;

        const float minVal = m_waveformDataCache[idx];
        const float maxVal = m_waveformDataCache[idx + 1];

        const qreal x = bin * pixelsPerBin - m_scrollPosition;

        const qreal topY = centerY - maxVal * halfHeight;
        const qreal bottomY = centerY - minVal * halfHeight;

        painter->drawLine(QPointF(x, topY), QPointF(x, bottomY));
    }

    QPen outlinePen(m_waveformColor);
    outlinePen.setWidthF(1.5);
    outlinePen.setCapStyle(Qt::RoundCap);
    outlinePen.setJoinStyle(Qt::RoundJoin);
    painter->setPen(outlinePen);
    painter->setOpacity(0.9);

    QPainterPath topPath;
    bool firstPoint = true;
    for (int bin = startBin; bin <= endBin; ++bin) {
        const int idx = bin * 2;
        if (idx + 1 >= m_waveformDataCache.size())
            break;

        const float maxVal = m_waveformDataCache[idx + 1];
        const qreal x = bin * pixelsPerBin - m_scrollPosition;
        const qreal topY = centerY - maxVal * halfHeight;

        if (firstPoint) {
            topPath.moveTo(x, topY);
            firstPoint = false;
        }
        else {
            topPath.lineTo(x, topY);
        }
    }
    painter->drawPath(topPath);

    QPainterPath bottomPath;
    firstPoint = true;
    for (int bin = startBin; bin <= endBin; ++bin) {
        const int idx = bin * 2;
        if (idx + 1 >= m_waveformDataCache.size())
            break;

        const float minVal = m_waveformDataCache[idx];
        const qreal x = bin * pixelsPerBin - m_scrollPosition;
        const qreal bottomY = centerY - minVal * halfHeight;

        if (firstPoint) {
            bottomPath.moveTo(x, bottomY);
            firstPoint = false;
        }
        else {
            bottomPath.lineTo(x, bottomY);
        }
    }
    painter->drawPath(bottomPath);
}

void WaveformRenderer::drawMediumWaveform(QPainter* painter, qreal centerY, qreal halfHeight,
    qreal visibleStartX, qreal visibleEndX,
    int numBins, qreal pixelsPerBin)
{
    int startBin = qMax(0, (int)(visibleStartX / pixelsPerBin) - 1);
    int endBin = qMin(numBins - 1, (int)(visibleEndX / pixelsPerBin) + 1);

    QPen wavePen(m_waveformColor);
    wavePen.setWidthF(1.0);
    wavePen.setCapStyle(Qt::FlatCap);
    painter->setPen(wavePen);
    painter->setOpacity(0.85);

    for (int bin = startBin; bin <= endBin; ++bin) {
        const int idx = bin * 2;
        if (idx + 1 >= m_waveformDataCache.size())
            break;

        const float minVal = m_waveformDataCache[idx];
        const float maxVal = m_waveformDataCache[idx + 1];

        const qreal x = bin * pixelsPerBin - m_scrollPosition;
        const qreal topY = centerY - maxVal * halfHeight;
        const qreal bottomY = centerY - minVal * halfHeight;

        painter->drawLine(QPointF(x, topY), QPointF(x, bottomY));
    }
}

void WaveformRenderer::drawFilledWaveform(QPainter* painter, qreal centerY, qreal halfHeight,
    qreal visibleStartX, qreal visibleEndX,
    int numBins, qreal pixelsPerBin)
{
    int startBin = qMax(0, (int)(visibleStartX / pixelsPerBin) - 1);
    int endBin = qMin(numBins - 1, (int)(visibleEndX / pixelsPerBin) + 1);

    if (startBin >= endBin)
        return;

    QPainterPath fillPath;
    bool firstPoint = true;

    for (int bin = startBin; bin <= endBin; ++bin) {
        const int idx = bin * 2;
        if (idx + 1 >= m_waveformDataCache.size())
            break;

        const float maxVal = m_waveformDataCache[idx + 1];
        const qreal x = bin * pixelsPerBin - m_scrollPosition;
        const qreal topY = centerY - maxVal * halfHeight;

        if (firstPoint) {
            fillPath.moveTo(x, topY);
            firstPoint = false;
        }
        else {
            fillPath.lineTo(x, topY);
        }
    }

    for (int bin = endBin; bin >= startBin; --bin) {
        const int idx = bin * 2;
        if (idx + 1 >= m_waveformDataCache.size())
            continue;

        const float minVal = m_waveformDataCache[idx];
        const qreal x = bin * pixelsPerBin - m_scrollPosition;
        const qreal bottomY = centerY - minVal * halfHeight;

        fillPath.lineTo(x, bottomY);
    }

    fillPath.closeSubpath();

    painter->setOpacity(0.7);
    painter->fillPath(fillPath, m_waveformColor);

    QPen outlinePen(m_waveformColor);
    outlinePen.setWidthF(1.0);
    painter->setPen(outlinePen);
    painter->setOpacity(0.9);
    painter->drawPath(fillPath);
}

void WaveformRenderer::drawRuler(QPainter* painter)
{
    if (m_duration <= 0)
        return;

    painter->save();
    painter->setClipRect(0, 0, width(), m_rulerHeight);

    qreal startTime = (m_scrollPosition / m_contentWidth) * m_duration;
    qreal endTime = ((m_scrollPosition + width()) / m_contentWidth) * m_duration;

    startTime = qFloor(startTime / m_minorGridInterval) * m_minorGridInterval;
    endTime = qCeil(endTime / m_minorGridInterval) * m_minorGridInterval;

    QPen tickPen(QColor(120, 120, 125), 1);
    painter->setPen(tickPen);

    QFont font("Segoe UI", 9);
    painter->setFont(font);

    for (qint64 time = startTime; time <= endTime; time += m_minorGridInterval) {
        if (time < 0 || time > m_duration)
            continue;

        qreal xPos = (time / (qreal)m_duration) * m_contentWidth - m_scrollPosition;
        bool isMajor = (time % m_majorGridInterval == 0);

        int tickHeight = isMajor ? 8 : 4;

        painter->setPen(tickPen);
        painter->drawLine(QPointF(xPos, m_rulerHeight - tickHeight), QPointF(xPos, m_rulerHeight));

        if (isMajor) {
            QString timeText = formatTime(time);
            QRectF textRect = painter->fontMetrics().boundingRect(timeText);
            painter->setPen(m_timeTextColor);
            painter->drawText(QPointF(xPos - textRect.width() / 2, 15), timeText);
        }
    }

    painter->restore();
}

void WaveformRenderer::drawPlayhead(QPainter* painter)
{
    if (m_duration <= 0 || m_currentPosition < 0)
        return;

    painter->save();

    qreal playheadX = m_currentPosition * m_contentWidth - m_scrollPosition;

    if (playheadX < 0 || playheadX > width()) {
        painter->restore();
        return;
    }

    QPen playheadPen(m_playheadColor, 2);
    painter->setPen(playheadPen);
    painter->setOpacity(0.9);
    painter->drawLine(QPointF(playheadX, m_rulerHeight), QPointF(playheadX, height()));

    QPainterPath triangle;
    triangle.moveTo(playheadX, m_rulerHeight);
    triangle.lineTo(playheadX - 5, m_rulerHeight - 8);
    triangle.lineTo(playheadX + 5, m_rulerHeight - 8);
    triangle.closeSubpath();
    painter->fillPath(triangle, m_playheadColor);

    QString timeText = formatTime(m_currentPosition * m_duration);
    QFont font("monospace", 9, QFont::Bold);
    painter->setFont(font);
    QRectF textRect = painter->fontMetrics().boundingRect(timeText);

    QRectF labelRect(playheadX - textRect.width() / 2 - 4,
        m_rulerHeight - 26,
        textRect.width() + 8,
        textRect.height() + 4);

    painter->fillRect(labelRect, QColor(0, 0, 0, 220));
    painter->setPen(Qt::white);
    painter->drawText(labelRect, Qt::AlignCenter, timeText);

    painter->restore();
}