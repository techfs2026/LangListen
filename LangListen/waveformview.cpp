#include "waveformview.h"
#include <QPainter>
#include <QPainterPath>
#include <QDebug>
#include <QtMath>
#include <QtConcurrent>
#include <QQuickWindow>

WaveformView::WaveformView(QQuickItem* parent)
    : QQuickPaintedItem(parent)
    , m_waveformGenerator(nullptr)
    , m_currentPosition(0.0)
    , m_pixelsPerSecond(100.0)
    , m_scrollPosition(0.0)
    , m_contentWidth(0.0)
    , m_viewportWidth(0.0)
    , m_pageStartTime(0.0)
    , m_playheadXInPage(0)
    , m_showPerformance(false)
    , m_lastPaintTime(0)
    , m_frameCount(0)
    , m_followPlayback(true)
    , m_currentLevelIndex(-1)
    , m_currentSentenceIndex(-1)
    , m_hoveredSentenceIndex(-1)
    , m_showSentenceHighlight(true)
    , m_hoveredTimeMs(-1)
{
    setAntialiasing(true);
    setRenderTarget(QQuickPaintedItem::FramebufferObject);
    setPerformanceHint(QQuickPaintedItem::FastFBOResizing, true);
    setAcceptedMouseButtons(Qt::LeftButton | Qt::RightButton);
    setAcceptHoverEvents(true);
}

WaveformView::~WaveformView() {}

void WaveformView::setWaveformGenerator(WaveformGenerator* generator)
{
    if (m_waveformGenerator == generator)
        return;

    if (m_waveformGenerator) {
        disconnect(m_waveformGenerator, nullptr, this, nullptr);
    }

    m_waveformGenerator = generator;

    if (m_waveformGenerator) {
        connect(m_waveformGenerator, &WaveformGenerator::levelsChanged,
            this, &WaveformView::onLevelsChanged);
        connect(m_waveformGenerator, &WaveformGenerator::durationChanged,
            this, &WaveformView::updateContentWidth);

        updateContentWidth();
        updateCurrentLevel();
    }

    emit waveformGeneratorChanged();
}

void WaveformView::setCurrentPosition(qreal position)
{
    position = qBound(0.0, position, 1.0);

    if (qAbs(m_currentPosition - position) < 0.0001)
        return;

    qreal positionDelta = qAbs(m_currentPosition - position);
    bool isLargeJump = positionDelta > 0.1;

    m_currentPosition = position;

    if (m_waveformGenerator && m_waveformGenerator->duration() > 0) {
        updateCurrentSentence();

        if (isLargeJump) {
            updatePlayheadPosition();
        }
        else if (m_followPlayback) {
            updatePlayheadPosition();
        }
        else {
            updatePlayheadPositionWithoutScroll();
        }
    }

    update();
    emit currentPositionChanged();
}

void WaveformView::updateCurrentSentence()
{
    if (!m_waveformGenerator || m_sentences.isEmpty())
        return;

    qint64 currentTimeMs = (m_currentPosition * m_waveformGenerator->duration());
    int newIndex = findSentenceAtTime(currentTimeMs);

    if (newIndex != m_currentSentenceIndex) {
        m_currentSentenceIndex = newIndex;
        update();
        emit currentSentenceIndexChanged();
    }
}

void WaveformView::updatePlayheadPositionWithoutScroll()
{
    if (!m_waveformGenerator || m_waveformGenerator->duration() <= 0) {
        return;
    }

    qint64 durationMs = m_waveformGenerator->duration();
    qreal currentSeconds = (m_currentPosition * durationMs) / 1000.0;

    qreal timeInPage = currentSeconds - m_pageStartTime;
    m_playheadXInPage = qRound(timeInPage * m_pixelsPerSecond);
}

void WaveformView::updatePlayheadPosition()
{
    if (!m_waveformGenerator || m_waveformGenerator->duration() <= 0) {
        return;
    }

    qint64 durationMs = m_waveformGenerator->duration();
    qreal currentSeconds = (m_currentPosition * durationMs) / 1000.0;
    qreal durationSeconds = durationMs / 1000.0;

    qreal pageWidth = getPageWidthInSeconds();
    qreal timeInPage = currentSeconds - m_pageStartTime;

    if (timeInPage >= pageWidth) {
        qreal viewWidth = m_viewportWidth > 0 ? m_viewportWidth : width();
        qreal maxScrollSeconds = durationSeconds - (viewWidth / m_pixelsPerSecond);
        if (maxScrollSeconds < 0) maxScrollSeconds = 0;

        m_pageStartTime = qMin(currentSeconds, maxScrollSeconds);
        int newScrollPos = qRound(m_pageStartTime * m_pixelsPerSecond);
        emit requestDirectScroll(newScrollPos);

        timeInPage = currentSeconds - m_pageStartTime;
        m_playheadXInPage = qRound(timeInPage * m_pixelsPerSecond);
        return;
    }
    else if (timeInPage < 0) {
        int pageIndex = qFloor(currentSeconds / pageWidth);
        m_pageStartTime = pageIndex * pageWidth;
        if (m_pageStartTime < 0) m_pageStartTime = 0;

        timeInPage = currentSeconds - m_pageStartTime;
        int newScrollPos = qRound(m_pageStartTime * m_pixelsPerSecond);
        emit requestDirectScroll(newScrollPos);

        m_playheadXInPage = qRound(timeInPage * m_pixelsPerSecond);
        return;
    }

    m_playheadXInPage = qRound(timeInPage * m_pixelsPerSecond);
    qreal viewWidth = m_viewportWidth > 0 ? m_viewportWidth : width();

    if (m_playheadXInPage > viewWidth - 10) {
        if (currentSeconds >= durationSeconds - 2.0) {
            qreal maxScrollSeconds = durationSeconds - (viewWidth / m_pixelsPerSecond);
            if (maxScrollSeconds < 0) maxScrollSeconds = 0;

            if (m_pageStartTime < maxScrollSeconds - 0.1) {
                m_pageStartTime = maxScrollSeconds;
                int newScrollPos = qRound(m_pageStartTime * m_pixelsPerSecond);
                emit requestDirectScroll(newScrollPos);

                timeInPage = currentSeconds - m_pageStartTime;
                m_playheadXInPage = qRound(timeInPage * m_pixelsPerSecond);
            }
        }
    }

    m_playheadXInPage = qBound(0, m_playheadXInPage, (int)viewWidth);
}

qreal WaveformView::getPageWidthInSeconds() const
{
    qreal viewWidth = m_viewportWidth > 0 ? m_viewportWidth : width();
    return pixelsToSeconds(viewWidth);
}

void WaveformView::setPixelsPerSecond(qreal pps)
{
    pps = qBound(m_minPixelsPerSecond, pps, m_maxPixelsPerSecond);
    if (qAbs(m_pixelsPerSecond - pps) < 0.01) return;

    m_pixelsPerSecond = pps;

    if (m_waveformGenerator && m_waveformGenerator->duration() > 0) {
        qint64 durationMs = m_waveformGenerator->duration();
        qreal currentSeconds = (m_currentPosition * durationMs) / 1000.0;

        qreal pageWidth = getPageWidthInSeconds();
        m_pageStartTime = qFloor(currentSeconds / pageWidth) * pageWidth;

        int newScrollPos = qRound(m_pageStartTime * m_pixelsPerSecond);
        emit requestDirectScroll(newScrollPos);

        updatePlayheadPosition();
    }

    updateContentWidth();
    updateCurrentLevel();
    update();
    emit pixelsPerSecondChanged();
}

void WaveformView::setScrollPosition(qreal position)
{
    position = qBound(0.0, position, qMax(0.0, m_contentWidth - m_viewportWidth));

    if (qAbs(m_scrollPosition - position) < 0.5) return;

    m_scrollPosition = position;
    m_pageStartTime = pixelsToSeconds(position);

    update();
    emit scrollPositionChanged();
}

void WaveformView::setShowPerformance(bool show)
{
    if (m_showPerformance == show) return;
    m_showPerformance = show;
    emit showPerformanceChanged();
    update();
}

void WaveformView::setFollowPlayback(bool follow)
{
    if (m_followPlayback == follow) return;
    m_followPlayback = follow;

    if (follow && m_waveformGenerator && m_waveformGenerator->duration() > 0) {
        qint64 durationMs = m_waveformGenerator->duration();
        qreal currentSeconds = (m_currentPosition * durationMs) / 1000.0;
        qreal pageWidth = getPageWidthInSeconds();
        m_pageStartTime = qFloor(currentSeconds / pageWidth) * pageWidth;

        int newScrollPos = qRound(m_pageStartTime * m_pixelsPerSecond);
        emit requestDirectScroll(newScrollPos);

        updatePlayheadPosition();
    }

    emit followPlaybackChanged();
}

void WaveformView::setShowSentenceHighlight(bool show)
{
    if (m_showSentenceHighlight == show) return;
    m_showSentenceHighlight = show;
    update();
    emit showSentenceHighlightChanged();
}

void WaveformView::setViewportWidth(qreal width)
{
    if (qAbs(m_viewportWidth - width) < 0.5) return;
    m_viewportWidth = width;
    emit viewportWidthChanged();
}

void WaveformView::addSentence(qint64 startMs, qint64 endMs, const QString& text)
{
    if (startMs >= endMs) {
        qWarning() << "Invalid sentence range:" << startMs << "-" << endMs;
        return;
    }

    SentenceSegment segment(startMs, endMs, text);
    m_sentences.append(segment);

    std::sort(m_sentences.begin(), m_sentences.end(),
        [](const SentenceSegment& a, const SentenceSegment& b) {
            return a.startTimeMs < b.startTimeMs;
        });

    update();
    updateCurrentSentence();
}

void WaveformView::clearSentences()
{
    m_sentences.clear();
    m_currentSentenceIndex = -1;
    m_hoveredSentenceIndex = -1;
    update();
    emit currentSentenceIndexChanged();
}

QVariantMap WaveformView::getSentenceAt(int index) const
{
    QVariantMap result;
    if (index >= 0 && index < m_sentences.size()) {
        const SentenceSegment& seg = m_sentences[index];
        result["startMs"] = seg.startTimeMs;
        result["endMs"] = seg.endTimeMs;
        result["text"] = seg.text;
        result["duration"] = seg.endTimeMs - seg.startTimeMs;
    }
    return result;
}

int WaveformView::findSentenceAtTime(qint64 timeMs) const
{
    for (int i = 0; i < m_sentences.size(); ++i) {
        if (m_sentences[i].contains(timeMs)) {
            return i;
        }
    }
    return -1;
}

void WaveformView::seekToPosition(qreal normalizedPosition)
{
    normalizedPosition = qBound(0.0, normalizedPosition, 1.0);
    setCurrentPosition(normalizedPosition);

    if (m_waveformGenerator && m_waveformGenerator->duration() > 0) {
        qint64 timeMs = qRound(normalizedPosition * m_waveformGenerator->duration());
        emit clicked(normalizedPosition, timeMs);
    }
}

void WaveformView::seekToTime(qint64 timeMs)
{
    if (!m_waveformGenerator || m_waveformGenerator->duration() <= 0)
        return;

    qreal position = static_cast<qreal>(timeMs) / m_waveformGenerator->duration();
    seekToPosition(position);
}

void WaveformView::seekToSentence(int sentenceIndex)
{
    if (sentenceIndex < 0 || sentenceIndex >= m_sentences.size())
        return;

    const SentenceSegment& seg = m_sentences[sentenceIndex];
    seekToTime(seg.startTimeMs);
    emit sentenceClicked(sentenceIndex);
}

void WaveformView::zoomIn()
{
    qreal newPPS = m_pixelsPerSecond * 1.5;
    if (newPPS <= m_maxPixelsPerSecond) {
        setPixelsPerSecond(newPPS);
    }
}

void WaveformView::zoomOut()
{
    qreal newPPS = m_pixelsPerSecond / 1.5;
    if (newPPS >= m_minPixelsPerSecond) {
        setPixelsPerSecond(newPPS);
    }
}

void WaveformView::resetZoom()
{
    m_pageStartTime = 0.0;
    setPixelsPerSecond(m_basePixelsPerSecond);
    emit requestDirectScroll(0);
}

void WaveformView::fitToView()
{
    if (!m_waveformGenerator || m_waveformGenerator->duration() <= 0) return;

    qreal durationSeconds = m_waveformGenerator->duration() / 1000.0;
    if (width() > 0) {
        qreal targetPPS = (width() * 0.95) / durationSeconds;
        m_pageStartTime = 0.0;
        setPixelsPerSecond(qBound(m_minPixelsPerSecond, targetPPS, m_maxPixelsPerSecond));
        emit requestDirectScroll(0);
    }
}

bool WaveformView::canZoomIn() const
{
    return m_pixelsPerSecond * 1.5 <= m_maxPixelsPerSecond;
}

bool WaveformView::canZoomOut() const
{
    return m_pixelsPerSecond / 1.5 >= m_minPixelsPerSecond;
}

qreal WaveformView::timeToPixel(qint64 timeMs) const
{
    qreal seconds = timeMs / 1000.0;
    return seconds * m_pixelsPerSecond;
}

qint64 WaveformView::pixelToTime(qreal pixel) const
{
    qreal seconds = pixel / m_pixelsPerSecond;
    return qRound(seconds * 1000.0);
}

qreal WaveformView::secondsToPixels(qreal seconds) const
{
    return seconds * m_pixelsPerSecond;
}

qreal WaveformView::pixelsToSeconds(qreal pixels) const
{
    if (m_pixelsPerSecond <= 0) return 0.0;
    return pixels / m_pixelsPerSecond;
}

void WaveformView::mousePressEvent(QMouseEvent* event)
{
    if (!m_waveformGenerator || m_waveformGenerator->duration() <= 0) {
        event->ignore();
        return;
    }

    if (event->button() == Qt::LeftButton) {
        qreal clickX = event->position().x();
        qreal globalX = m_scrollPosition + clickX;
        qint64 clickTimeMs = pixelToTime(globalX);

        qint64 durationMs = m_waveformGenerator->duration();
        clickTimeMs = qBound(0LL, clickTimeMs, durationMs);

        qreal normalizedPos = static_cast<qreal>(clickTimeMs) / durationMs;

        int sentenceIndex = findSentenceAtTime(clickTimeMs);
        if (sentenceIndex >= 0) {
            emit sentenceClicked(sentenceIndex);
        }

        seekToPosition(normalizedPos);

        event->accept();
    }
}

void WaveformView::mouseMoveEvent(QMouseEvent* event)
{
    if (!m_waveformGenerator || m_waveformGenerator->duration() <= 0) {
        event->ignore();
        return;
    }

    qreal mouseX = event->position().x();
    qreal globalX = m_scrollPosition + mouseX;
    qint64 timeMs = pixelToTime(globalX);

    if (timeMs != m_hoveredTimeMs) {
        m_hoveredTimeMs = timeMs;
        m_hoveredSentenceIndex = findSentenceAtTime(timeMs);
        emit hoveredTimeChanged(timeMs);
        update();
    }

    event->accept();
}

void WaveformView::hoverMoveEvent(QHoverEvent* event)
{
    if (!m_waveformGenerator || m_waveformGenerator->duration() <= 0) {
        return;
    }

    qreal mouseX = event->position().x();
    qreal globalX = m_scrollPosition + mouseX;
    qint64 timeMs = pixelToTime(globalX);

    if (timeMs != m_hoveredTimeMs) {
        m_hoveredTimeMs = timeMs;
        m_hoveredSentenceIndex = findSentenceAtTime(timeMs);
        emit hoveredTimeChanged(timeMs);
        update();
    }
}

void WaveformView::hoverLeaveEvent(QHoverEvent* event)
{
    Q_UNUSED(event);
    m_hoveredTimeMs = -1;
    m_hoveredSentenceIndex = -1;
    update();
}

void WaveformView::wheelEvent(QWheelEvent* event)
{
    if (!m_waveformGenerator || !m_waveformGenerator->isLoaded()) {
        event->ignore();
        return;
    }

    QPoint numPixels = event->pixelDelta();
    QPoint numDegrees = event->angleDelta() / 8;

    if (numPixels.isNull() && numDegrees.isNull()) {
        event->ignore();
        return;
    }

    bool fineControl = event->modifiers() & Qt::ControlModifier;
    qreal delta = !numPixels.isNull() ? numPixels.y() : numDegrees.y();

    qreal zoomFactor = fineControl ?
        1.0 + (delta / 720.0) :
        1.0 + (delta / 240.0);

    qreal newPPS = m_pixelsPerSecond * zoomFactor;
    newPPS = qBound(m_minPixelsPerSecond, newPPS, m_maxPixelsPerSecond);

    if (qAbs(newPPS - m_pixelsPerSecond) < 0.01) {
        event->accept();
        return;
    }

    qreal mouseX = event->position().x();
    qreal globalX = m_scrollPosition + mouseX;
    qreal timeAtMouse = globalX / m_pixelsPerSecond;

    setPixelsPerSecond(newPPS);

    qreal newGlobalX = timeAtMouse * newPPS;
    qreal newScrollPos = newGlobalX - mouseX;

    qreal maxScroll = qMax(0.0, m_contentWidth - m_viewportWidth);
    newScrollPos = qBound(0.0, newScrollPos, maxScroll);

    setScrollPosition(newScrollPos);
    event->accept();
}

void WaveformView::geometryChange(const QRectF& newGeometry, const QRectF& oldGeometry)
{
    QQuickPaintedItem::geometryChange(newGeometry, oldGeometry);
    if (newGeometry.size() != oldGeometry.size()) {
        updateContentWidth();
        update();
    }
}

void WaveformView::onLevelsChanged()
{
    updateCurrentLevel();
    update();
}

void WaveformView::updateCurrentLevel()
{
    if (!m_waveformGenerator || !m_waveformGenerator->isLoaded()) {
        m_currentLevelCache.clear();
        m_currentLevelIndex = -1;
        return;
    }

    int newLevelIndex = m_waveformGenerator->findBestLevel(m_pixelsPerSecond);

    if (newLevelIndex != m_currentLevelIndex || m_currentLevelCache.isEmpty()) {
        m_currentLevelIndex = newLevelIndex;
        QVariantList levelData = m_waveformGenerator->getLevelData(newLevelIndex);
        variantListToCache(levelData, m_currentLevelCache);
    }
}

void WaveformView::variantListToCache(const QVariantList& data, QVector<MinMaxPair>& cache)
{
    cache.clear();
    cache.reserve(data.size() / 2);
    for (int i = 0; i < data.size() - 1; i += 2) {
        MinMaxPair pair;
        pair.min = data[i].toFloat();
        pair.max = data[i + 1].toFloat();
        cache.append(pair);
    }
}

void WaveformView::paint(QPainter* painter)
{
    painter->fillRect(boundingRect(), QColor(245, 245, 245));
    painter->setRenderHint(QPainter::Antialiasing, true);

    paintCenterLine(painter);
    paintWaveform(painter);
    paintTimeAxis(painter);

    if (m_showSentenceHighlight) {
        paintSentenceHighlights(painter);
    }

    paintPlayhead(painter);

    if (m_hoveredTimeMs >= 0) {
        paintHoverInfo(painter);
    }

    if (m_showPerformance) {
        paintPerformanceInfo(painter);
    }
}

void WaveformView::paintSentenceHighlights(QPainter* painter)
{
    if (m_sentences.isEmpty() || !m_waveformGenerator)
        return;

    painter->save();

    for (int i = 0; i < m_sentences.size(); ++i) {
        const SentenceSegment& seg = m_sentences[i];

        qreal startPixel = timeToPixel(seg.startTimeMs) - m_scrollPosition;
        qreal endPixel = timeToPixel(seg.endTimeMs) - m_scrollPosition;
        qreal segWidth = endPixel - startPixel;

        if (endPixel < 0 || startPixel > width())
            continue;

        QColor bgColor;
        if (i == m_currentSentenceIndex) {
            bgColor = QColor(255, 235, 59, 80);
        }
        else if (i == m_hoveredSentenceIndex) {
            bgColor = QColor(100, 181, 246, 60);
        }
        else {
            bgColor = QColor(200, 200, 200, 30);
        }

        QRectF rect(startPixel, 0, segWidth, height());
        painter->fillRect(rect, bgColor);

        if (i == m_currentSentenceIndex || i == m_hoveredSentenceIndex) {
            QPen borderPen(i == m_currentSentenceIndex ?
                QColor(255, 193, 7) : QColor(33, 150, 243), 1.5);
            painter->setPen(borderPen);
            painter->drawRect(rect);
        }
    }

    painter->restore();
}

void WaveformView::paintWaveform(QPainter* painter, const QSizeF& size)
{
    if (m_currentLevelCache.isEmpty() || m_contentWidth <= 0 || !m_waveformGenerator) {
        return;
    }

    const qreal viewW = size.isEmpty() ? width() : size.width();
    const qreal viewH = size.isEmpty() ? height() : size.height();
    const qreal centerY = viewH * 0.5;
    const qreal amp = viewH * 0.48;

    const QVector<WaveformLevel>& levels = m_waveformGenerator->getLevels();
    if (m_currentLevelIndex < 0 || m_currentLevelIndex >= levels.size()) {
        return;
    }

    const WaveformLevel& currentLevel = levels[m_currentLevelIndex];
    const qreal pixelsPerDataPoint = m_pixelsPerSecond / currentLevel.pixelsPerSecond;

    if (pixelsPerDataPoint >= 4.0) {
        paintWaveformSampleLevel(painter, viewW, viewH, centerY, amp, pixelsPerDataPoint);
    }
    else if (pixelsPerDataPoint >= 0.8) {
        paintWaveformPeakLines(painter, viewW, viewH, centerY, amp, pixelsPerDataPoint);
    }
    else {
        paintWaveformDense(painter, viewW, viewH, centerY, amp, pixelsPerDataPoint);
    }
}

void WaveformView::paintWaveformSampleLevel(QPainter* painter, qreal viewW, qreal viewH,
    qreal centerY, qreal amp, qreal pixelsPerDataPoint)
{
    painter->setRenderHint(QPainter::Antialiasing, false);

    QPen samplePen(QColor(30, 50, 100), 1.0);
    samplePen.setCapStyle(Qt::FlatCap);
    painter->setPen(samplePen);

    int startPixel = qMax(0, int(0));
    int endPixel = qMin(int(viewW) + 1, int(viewW) + 1);

    QVector<QPointF> samplePoints;
    samplePoints.reserve(endPixel - startPixel);

    for (int pixelX = startPixel; pixelX < endPixel; ++pixelX) {
        qreal globalPixelPos = m_scrollPosition + pixelX;
        qreal dataIndex = globalPixelPos / pixelsPerDataPoint;

        int idx = qRound(dataIndex);
        if (idx < 0 || idx >= m_currentLevelCache.size())
            continue;

        float sampleValue = m_currentLevelCache[idx].max;
        qreal y = centerY - sampleValue * amp;

        samplePoints.append(QPointF(pixelX, y));
    }

    painter->setBrush(QColor(30, 50, 100));
    for (const QPointF& pt : samplePoints) {
        painter->drawEllipse(pt, 2, 2);
    }

    if (samplePoints.size() > 1) {
        QPen linePen(QColor(30, 50, 100, 180), 0.8);
        painter->setPen(linePen);
        painter->drawPolyline(samplePoints.data(), samplePoints.size());
    }
}

void WaveformView::paintWaveformPeakLines(QPainter* painter, qreal viewW, qreal viewH,
    qreal centerY, qreal amp, qreal pixelsPerDataPoint)
{

    painter->setRenderHint(QPainter::Antialiasing, false);

    QPen linePen(QColor(33, 66, 133), 1.0);
    linePen.setCapStyle(Qt::FlatCap);
    painter->setPen(linePen);

    int startPixel = qMax(0, int(0));
    int endPixel = qMin(int(viewW) + 1, int(viewW) + 1);

    for (int pixelX = startPixel; pixelX < endPixel; ++pixelX) {
        qreal globalPixelPos = m_scrollPosition + pixelX;
        qreal dataIndexStart = globalPixelPos / pixelsPerDataPoint;
        qreal dataIndexEnd = (globalPixelPos + 1.0) / pixelsPerDataPoint;

        int idxStart = qFloor(dataIndexStart);
        int idxEnd = qCeil(dataIndexEnd);

        idxStart = qMax(0, idxStart);
        idxEnd = qMin(m_currentLevelCache.size(), idxEnd);

        if (idxStart >= idxEnd || idxStart >= m_currentLevelCache.size())
            continue;

        float columnMin = m_currentLevelCache[idxStart].min;
        float columnMax = m_currentLevelCache[idxStart].max;

        for (int dataIdx = idxStart + 1; dataIdx < idxEnd; ++dataIdx) {
            if (dataIdx >= m_currentLevelCache.size()) break;
            float minVal = m_currentLevelCache[dataIdx].min;
            float maxVal = m_currentLevelCache[dataIdx].max;
            if (minVal < columnMin) columnMin = minVal;
            if (maxVal > columnMax) columnMax = maxVal;
        }

        qreal yMax = centerY - columnMax * amp;
        qreal yMin = centerY - columnMin * amp;

        painter->drawLine(QPointF(pixelX, yMax), QPointF(pixelX, yMin));
    }
}

void WaveformView::paintWaveformDense(QPainter* painter, qreal viewW, qreal viewH,
    qreal centerY, qreal amp, qreal pixelsPerDataPoint)
{
    painter->setRenderHint(QPainter::Antialiasing, false);

    QPen linePen(QColor(33, 66, 133), 1.0);
    linePen.setCapStyle(Qt::FlatCap);
    painter->setPen(linePen);

    int startPixel = qMax(0, int(0));
    int endPixel = qMin(int(viewW) + 1, int(viewW) + 1);

    for (int pixelX = startPixel; pixelX < endPixel; ++pixelX) {
        qreal globalPixelPos = m_scrollPosition + pixelX;
        qreal dataIndexStart = globalPixelPos / pixelsPerDataPoint;
        qreal dataIndexEnd = (globalPixelPos + 1.0) / pixelsPerDataPoint;

        int idxStart = qFloor(dataIndexStart);
        int idxEnd = qCeil(dataIndexEnd);

        idxStart = qMax(0, idxStart);
        idxEnd = qMin(m_currentLevelCache.size(), idxEnd);

        if (idxStart >= idxEnd || idxStart >= m_currentLevelCache.size())
            continue;

        float columnMin = m_currentLevelCache[idxStart].min;
        float columnMax = m_currentLevelCache[idxStart].max;

        for (int dataIdx = idxStart + 1; dataIdx < idxEnd; ++dataIdx) {
            if (dataIdx >= m_currentLevelCache.size()) break;
            float minVal = m_currentLevelCache[dataIdx].min;
            float maxVal = m_currentLevelCache[dataIdx].max;
            if (minVal < columnMin) columnMin = minVal;
            if (maxVal > columnMax) columnMax = maxVal;
        }

        qreal yMax = centerY - columnMax * amp;
        qreal yMin = centerY - columnMin * amp;

        painter->drawLine(QPointF(pixelX, yMax), QPointF(pixelX, yMin));
    }
}

void WaveformView::paintCenterLine(QPainter* painter, const QSizeF& size)
{
    const qreal viewW = size.isEmpty() ? width() : size.width();
    const qreal viewH = size.isEmpty() ? height() : size.height();
    qreal centerY = viewH / 2.0;

    QPen pen(QColor(200, 200, 200), 1, Qt::DashLine);
    painter->setPen(pen);
    painter->setRenderHint(QPainter::Antialiasing, true);
    painter->drawLine(QPointF(0, centerY), QPointF(viewW, centerY));
}

void WaveformView::paintPlayhead(QPainter* painter)
{
    if (!m_waveformGenerator || m_waveformGenerator->duration() <= 0)
        return;

    int playheadX = m_playheadXInPage + 2;

    qint64 durationMs = m_waveformGenerator->duration();
    qreal currentSeconds = (m_currentPosition * durationMs) / 1000.0;
    qreal durationSeconds = durationMs / 1000.0;
    qreal viewWidth = m_viewportWidth > 0 ? m_viewportWidth : width();

    bool isAtEnd = (currentSeconds >= durationSeconds - 0.2);

    if (isAtEnd && playheadX > viewWidth) {
        playheadX = qRound(viewWidth) - 2;
    }

    if (playheadX < 2 || (playheadX > viewWidth - 2 && !isAtEnd)) {
        return;
    }

    painter->setRenderHint(QPainter::Antialiasing, true);

    QPen mainPen(QColor(244, 67, 54), 2);
    mainPen.setCapStyle(Qt::RoundCap);
    painter->setPen(mainPen);
    painter->drawLine(QPointF(playheadX, 0), QPointF(playheadX, height()));

    painter->setBrush(QColor(244, 67, 54));
    painter->setPen(Qt::NoPen);
}

void WaveformView::paintHoverInfo(QPainter* painter)
{
    if (m_hoveredTimeMs < 0)
        return;

    painter->save();

    int totalMs = m_hoveredTimeMs;
    int hours = totalMs / 3600000;
    int minutes = (totalMs % 3600000) / 60000;
    int seconds = (totalMs % 60000) / 1000;
    int ms = totalMs % 1000;

    QString timeText;
    if (hours > 0) {
        timeText = QString("%1:%2:%3.%4")
            .arg(hours)
            .arg(minutes, 2, 10, QChar('0'))
            .arg(seconds, 2, 10, QChar('0'))
            .arg(ms, 3, 10, QChar('0'));
    }
    else {
        timeText = QString("%1:%2.%3")
            .arg(minutes, 2, 10, QChar('0'))
            .arg(seconds, 2, 10, QChar('0'))
            .arg(ms, 3, 10, QChar('0'));
    }

    if (m_hoveredSentenceIndex >= 0) {
        const SentenceSegment& seg = m_sentences[m_hoveredSentenceIndex];
        if (!seg.text.isEmpty()) {
            timeText += QString(" | Sentence %1").arg(m_hoveredSentenceIndex + 1);
        }
    }

    qreal hoverX = timeToPixel(m_hoveredTimeMs) - m_scrollPosition;
    if (hoverX >= 0 && hoverX <= width()) {
        QPen hoverPen(QColor(100, 100, 100, 150), 1, Qt::DashLine);
        painter->setPen(hoverPen);
        painter->drawLine(QPointF(hoverX, 0), QPointF(hoverX, height()));
    }

    QFont font("sans-serif", 9);
    painter->setFont(font);
    QFontMetrics fm(font);
    int textWidth = fm.horizontalAdvance(timeText);
    int textHeight = fm.height();

    qreal labelX = hoverX + 5;
    if (labelX + textWidth + 10 > width()) {
        labelX = hoverX - textWidth - 15;
    }

    QRectF bgRect(labelX, 5, textWidth + 10, textHeight + 6);
    painter->fillRect(bgRect, QColor(50, 50, 50, 200));
    painter->setPen(QColor(255, 255, 255));
    painter->drawText(bgRect, Qt::AlignCenter, timeText);

    painter->restore();
}

void WaveformView::paintTimeAxis(QPainter* painter)
{
    if (!m_waveformGenerator || m_waveformGenerator->duration() <= 0)
        return;

    painter->save();

    qreal viewW = width();
    qreal viewH = height();
    qreal axisY = viewH - 25;

    painter->setPen(QPen(QColor(180, 180, 180), 1.5));
    painter->drawLine(0, axisY, viewW, axisY);

    qint64 durationMs = m_waveformGenerator->duration();
    qreal durationSec = durationMs / 1000.0;

    qreal visibleStartSec = m_scrollPosition / m_pixelsPerSecond;
    qreal visibleEndSec = (m_scrollPosition + viewW) / m_pixelsPerSecond;

    qreal majorIntervalSec;
    qreal minorIntervalSec;

    if (m_pixelsPerSecond > 800) {
        majorIntervalSec = 0.2;
        minorIntervalSec = 0.05;
    }
    else if (m_pixelsPerSecond > 400) {
        majorIntervalSec = 0.5;
        minorIntervalSec = 0.1;
    }
    else if (m_pixelsPerSecond > 200) {
        majorIntervalSec = 1.0;
        minorIntervalSec = 0.2;
    }
    else if (m_pixelsPerSecond > 100) {
        majorIntervalSec = 2.0;
        minorIntervalSec = 0.5;
    }
    else if (m_pixelsPerSecond > 50) {
        majorIntervalSec = 5.0;
        minorIntervalSec = 1.0;
    }
    else if (m_pixelsPerSecond > 20) {
        majorIntervalSec = 10.0;
        minorIntervalSec = 2.0;
    }
    else if (m_pixelsPerSecond > 10) {
        majorIntervalSec = 20.0;
        minorIntervalSec = 5.0;
    }
    else if (m_pixelsPerSecond > 5) {
        majorIntervalSec = 30.0;
        minorIntervalSec = 10.0;
    }
    else {
        majorIntervalSec = 60.0;
        minorIntervalSec = 20.0;
    }

    painter->setFont(QFont("Arial", 9));

    if (minorIntervalSec > 0) {
        int minorStartTick = qCeil(visibleStartSec / minorIntervalSec);
        int minorEndTick = qFloor(visibleEndSec / minorIntervalSec);

        painter->setPen(QColor(160, 160, 160));
        for (int i = minorStartTick; i <= minorEndTick; ++i) {
            qreal timeSec = i * minorIntervalSec;
            if (timeSec > durationSec)
                break;

            if (qAbs(fmod(timeSec, majorIntervalSec)) < 0.001)
                continue;

            qreal pixelPos = (timeSec * m_pixelsPerSecond) - m_scrollPosition;

            if (pixelPos >= 0 && pixelPos <= viewW) {
                painter->drawLine(pixelPos, axisY, pixelPos, axisY + 3);
            }
        }
    }

    int majorStartTick = qCeil(visibleStartSec / majorIntervalSec);
    int majorEndTick = qFloor(visibleEndSec / majorIntervalSec);

    for (int i = majorStartTick; i <= majorEndTick; ++i) {
        qreal timeSec = i * majorIntervalSec;
        if (timeSec > durationSec)
            break;

        qreal pixelPos = (timeSec * m_pixelsPerSecond) - m_scrollPosition;

        if (pixelPos < 0 || pixelPos > viewW)
            continue;

        painter->setPen(QColor(120, 120, 120));
        painter->drawLine(pixelPos, axisY, pixelPos, axisY + 6);

        int minutes = (int)timeSec / 60;
        int seconds = (int)timeSec % 60;
        QString timeText;

        if (majorIntervalSec < 1.0) {
            int ms = (int)((timeSec - (int)timeSec) * 1000);
            timeText = QString("%1:%2.%3")
                .arg(minutes)
                .arg(seconds, 2, 10, QChar('0'))
                .arg(ms, 3, 10, QChar('0'));
        }
        else {
            timeText = QString("%1:%2")
                .arg(minutes)
                .arg(seconds, 2, 10, QChar('0'));
        }

        QFontMetrics fm(painter->font());
        int textWidth = fm.horizontalAdvance(timeText);
        painter->setPen(QColor(80, 80, 80));
        painter->drawText(pixelPos - textWidth / 2, axisY + 18, timeText);
    }

    painter->restore();
}

void WaveformView::paintPerformanceInfo(QPainter* painter)
{
    if (!m_waveformGenerator) return;

    qint64 durationMs = m_waveformGenerator->duration();
    qreal currentSeconds = (m_currentPosition * durationMs) / 1000.0;

    int currentMinutes = static_cast<int>(currentSeconds) / 60;
    int currentSecs = static_cast<int>(currentSeconds) % 60;
    QString currentTime = QString("%1:%2")
        .arg(currentMinutes, 2, 10, QChar('0'))
        .arg(currentSecs, 2, 10, QChar('0'));

    qreal totalSeconds = durationMs / 1000.0;
    int totalMinutes = static_cast<int>(totalSeconds) / 60;
    int totalSecs = static_cast<int>(totalSeconds) % 60;
    QString totalTime = QString("%1:%2")
        .arg(totalMinutes, 2, 10, QChar('0'))
        .arg(totalSecs, 2, 10, QChar('0'));

    QString info = QString("PPS: %1 | Level: %2 | PlayheadX: %3 | PageStart: %4s | Time: %5/%6 | Scroll: %7 | Sentence: %8/%9")
        .arg(m_pixelsPerSecond, 0, 'f', 1)
        .arg(m_currentLevelIndex)
        .arg(m_playheadXInPage)
        .arg(m_pageStartTime, 0, 'f', 2)
        .arg(currentTime)
        .arg(totalTime)
        .arg(m_scrollPosition, 0, 'f', 0)
        .arg(m_currentSentenceIndex + 1)
        .arg(m_sentences.size());

    painter->setPen(QColor(244, 67, 54));
    painter->setFont(QFont("monospace", 9, QFont::Bold));
    painter->drawText(10, 20, info);
}

void WaveformView::updateContentWidth()
{
    qreal newContentWidth = m_viewportWidth > 0 ? m_viewportWidth : width();

    if (m_waveformGenerator && m_waveformGenerator->duration() > 0) {
        qreal durationSeconds = m_waveformGenerator->duration() / 1000.0;
        newContentWidth = qMax(durationSeconds * m_pixelsPerSecond, newContentWidth);
    }

    if (qAbs(newContentWidth - m_contentWidth) > 0.5) {
        m_contentWidth = newContentWidth;
        emit contentWidthChanged();
    }
}