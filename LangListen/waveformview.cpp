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
    , m_waveformDirty(true)
    , m_cacheValid(false)
    , m_showPerformance(false)
    , m_lastPaintTime(0)
    , m_frameCount(0)
    , m_rebuildPending(false)
    , m_followPlayback(true)
    , m_currentLevelIndex(-1)
{
    setAntialiasing(true);
    setRenderTarget(QQuickPaintedItem::FramebufferObject);
    setPerformanceHint(QQuickPaintedItem::FastFBOResizing, true);
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
    if (qAbs(m_currentPosition - position) < 0.0001)
        return;

    m_currentPosition = qBound(0.0, position, 1.0);

    if (m_followPlayback && m_waveformGenerator && m_waveformGenerator->duration() > 0) {
        updatePlayheadPosition();
    }

    update();
    emit currentPositionChanged();
}

void WaveformView::updatePlayheadPosition()
{
    qint64 durationMs = m_waveformGenerator->duration();
    qreal currentSeconds = (m_currentPosition * durationMs) / 1000.0;

    qreal pageWidth = getPageWidthInSeconds();

    qreal timeInPage = currentSeconds - m_pageStartTime;

    if (timeInPage >= pageWidth) {
        m_pageStartTime = currentSeconds;

        int newScrollPos = qRound(m_pageStartTime * m_pixelsPerSecond);

        emit requestDirectScroll(newScrollPos);

        m_playheadXInPage = 0;
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
    if (m_playheadXInPage < 0) m_playheadXInPage = 0;
    if (m_playheadXInPage > viewWidth) m_playheadXInPage = qRound(viewWidth);
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
    invalidateCache();
    emit pixelsPerSecondChanged();
}

void WaveformView::setScrollPosition(qreal position)
{
    position = qBound(0.0, position, qMax(0.0, m_contentWidth - m_viewportWidth));

    if (qAbs(m_scrollPosition - position) < 0.5) return;

    m_scrollPosition = position;

    invalidateCache();

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

void WaveformView::setViewportWidth(qreal width)
{
    if (qAbs(m_viewportWidth - width) < 0.5) return;
    m_viewportWidth = width;
    emit viewportWidthChanged();
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

void WaveformView::geometryChange(const QRectF& newGeometry, const QRectF& oldGeometry)
{
    QQuickPaintedItem::geometryChange(newGeometry, oldGeometry);
    if (newGeometry.size() != oldGeometry.size()) {
        updateContentWidth();
        invalidateCache();
    }
}

void WaveformView::onLevelsChanged()
{
    updateCurrentLevel();
    invalidateCache();
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

        const QVector<WaveformLevel>& levels = m_waveformGenerator->getLevels();
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
    if (m_waveformDirty) {
        requestAsyncRebuild();
    }

    if (!m_waveformCache.isNull()) {
        painter->setRenderHint(QPainter::SmoothPixmapTransform, true);
        painter->drawPixmap(0, 0, m_waveformCache);
    }
    else {
        painter->fillRect(boundingRect(), QColor(245, 245, 245));
    }

    painter->setRenderHint(QPainter::Antialiasing, true);
    paintPlayhead(painter);

    if (m_showPerformance) {
        paintPerformanceInfo(painter);
    }
}

void WaveformView::requestAsyncRebuild()
{
    if (!m_waveformDirty || m_rebuildPending)
        return;

    m_rebuildPending = true;

    qreal dpr = 1.0;
    if (window())
        dpr = window()->devicePixelRatio();

    const QSizeF logicalSize(width(), height());
    const QSize physicalSize = (logicalSize * dpr).toSize();

    QtConcurrent::run([this, physicalSize, dpr, logicalSize]() {
        QImage image(physicalSize, QImage::Format_ARGB32_Premultiplied);
        image.setDevicePixelRatio(dpr);
        image.fill(QColor(245, 245, 245));

        QPainter p(&image);
        p.setRenderHint(QPainter::Antialiasing, true);

        paintCenterLine(&p, logicalSize);
        paintWaveform(&p, logicalSize);

        p.end();

        QMetaObject::invokeMethod(this, [this, image]() {
            m_waveformCache = QPixmap::fromImage(image);
            m_cacheValid = true;
            m_waveformDirty = false;
            m_rebuildPending = false;
            update();
            }, Qt::QueuedConnection);
        });
}

void WaveformView::invalidateCache()
{
    m_waveformDirty = true;
    m_cacheValid = false;
    update();
}

void WaveformView::paintWaveform(QPainter* painter, const QSizeF& size)
{
    if (m_currentLevelCache.isEmpty() || m_contentWidth <= 0 || !m_waveformGenerator)
        return;

    const qreal viewW = size.isEmpty() ? width() : size.width();
    const qreal viewH = size.isEmpty() ? height() : size.height();
    const qreal centerY = viewH * 0.5;
    const qreal amp = viewH * 0.4;

    const QVector<WaveformLevel>& levels = m_waveformGenerator->getLevels();
    if (m_currentLevelIndex < 0 || m_currentLevelIndex >= levels.size())
        return;

    const WaveformLevel& currentLevel = levels[m_currentLevelIndex];
    const qreal pixelsPerDataPoint = m_pixelsPerSecond / currentLevel.pixelsPerSecond;

    const int start = qMax(0, int((m_scrollPosition / pixelsPerDataPoint)) - 2);
    const int end = qMin(m_currentLevelCache.size(), int(((m_scrollPosition + viewW) / pixelsPerDataPoint)) + 2);

    if (start >= end) return;

    QPainterPath fillPath;
    QPainterPath topLine;
    QPainterPath bottomLine;

    for (int i = start; i < end; ++i) {
        qreal x = i * pixelsPerDataPoint - m_scrollPosition;

        float minVal = m_currentLevelCache[i].min;
        float maxVal = m_currentLevelCache[i].max;

        if (i + 1 < end) {
            float nextMin = m_currentLevelCache[i + 1].min;
            float nextMax = m_currentLevelCache[i + 1].max;

            qreal t = (x - int(x));
            minVal = minVal * (1.0f - t) + nextMin * t;
            maxVal = maxVal * (1.0f - t) + nextMax * t;
        }

        qreal yMax = centerY - maxVal * amp;
        qreal yMin = centerY - minVal * amp;

        if (i == start) {
            fillPath.moveTo(x, centerY);
            fillPath.lineTo(x, yMax);
            topLine.moveTo(x, yMax);
            bottomLine.moveTo(x, yMin);
        }
        else {
            fillPath.lineTo(x, yMax);
            topLine.lineTo(x, yMax);
            bottomLine.lineTo(x, yMin);
        }
    }

    for (int i = end - 1; i >= start; --i) {
        qreal x = i * pixelsPerDataPoint - m_scrollPosition;

        float minVal = m_currentLevelCache[i].min;
        float maxVal = m_currentLevelCache[i].max;

        if (i + 1 < end) {
            float nextMin = m_currentLevelCache[i + 1].min;
            float nextMax = m_currentLevelCache[i + 1].max;

            qreal t = (x - int(x));
            minVal = minVal * (1.0f - t) + nextMin * t;
            maxVal = maxVal * (1.0f - t) + nextMax * t;
        }

        qreal yMin = centerY - minVal * amp;
        fillPath.lineTo(x, yMin);
    }

    fillPath.closeSubpath();

    QLinearGradient gradient(0, 0, 0, viewH);
    gradient.setColorAt(0.0, QColor(66, 133, 244, 100));
    gradient.setColorAt(0.5, QColor(66, 133, 244, 140));
    gradient.setColorAt(1.0, QColor(66, 133, 244, 100));
    painter->fillPath(fillPath, gradient);

    QPen outlinePen(QColor(66, 133, 244, 200), 1.5);
    outlinePen.setCapStyle(Qt::RoundCap);
    outlinePen.setJoinStyle(Qt::RoundJoin);
    painter->setPen(outlinePen);
    painter->drawPath(topLine);
    painter->drawPath(bottomLine);
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

    int playheadX = m_playheadXInPage;

    qint64 durationMs = m_waveformGenerator->duration();
    qreal currentSeconds = (m_currentPosition * durationMs) / 1000.0;

    if (playheadX < -1 || playheadX > width() + 1) {
        return;
    }

    painter->setRenderHint(QPainter::Antialiasing, true);

    QPen mainPen(QColor(244, 67, 54), 2.5);
    mainPen.setCapStyle(Qt::RoundCap);
    painter->setPen(mainPen);
    painter->drawLine(QPointF(playheadX, 0), QPointF(playheadX, height()));

    painter->setBrush(QColor(244, 67, 54));
    painter->setPen(Qt::NoPen);
}

void WaveformView::paintPerformanceInfo(QPainter* painter)
{
    if (!m_waveformGenerator) return;

    qint64 durationMs = m_waveformGenerator->duration();
    qreal currentSeconds = (m_currentPosition * durationMs) / 1000.0;

    QString info = QString("PPS: %1 | Level: %2 | PlayheadX: %3 | PageStart: %4s | Current: %5s | Scroll: %6")
        .arg(m_pixelsPerSecond, 0, 'f', 1)
        .arg(m_currentLevelIndex)
        .arg(m_playheadXInPage)
        .arg(m_pageStartTime, 0, 'f', 2)
        .arg(currentSeconds, 0, 'f', 2)
        .arg(m_scrollPosition, 0, 'f', 0);

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
        qreal viewWidth = m_viewportWidth > 0 ? m_viewportWidth : width();
        emit contentWidthChanged();
    }
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