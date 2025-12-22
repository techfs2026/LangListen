#include "waveformview.h"
#include <QPainter>
#include <QPainterPath>
#include <QDebug>
#include <QtMath>
#include <QtConcurrent>
#include <QQuickWindow>

static bool s_firstBuild = true;

WaveformView::WaveformView(QQuickItem* parent)
    : QQuickPaintedItem(parent)
    , m_currentPosition(0.0)
    , m_duration(0)
    , m_zoomLevel(1.0)
    , m_scrollPosition(0.0)
    , m_contentWidth(0.0)
    , m_waveformDirty(true)
    , m_cacheValid(false)
    , m_showPerformance(false)
    , m_lastPaintTime(0)
    , m_frameCount(0)
    , m_rebuildPending(false)
    , m_followPlayback(true)
    , m_followThreshold(0.7)
{
    setAntialiasing(true);  // 启用抗锯齿
    setRenderTarget(QQuickPaintedItem::FramebufferObject);
    setPerformanceHint(QQuickPaintedItem::FastFBOResizing, true);
}

WaveformView::~WaveformView() {}

void WaveformView::setLevel1Data(const QVariantList& data)
{
    if (m_level1Data == data) return;
    m_level1Data = data;
    variantListToCache(data, m_level1Cache);
    invalidateCache();
    emit level1DataChanged();
}

void WaveformView::setLevel2Data(const QVariantList& data)
{
    if (m_level2Data == data) return;
    m_level2Data = data;
    variantListToCache(data, m_level2Cache);
    invalidateCache();
    emit level2DataChanged();
}

void WaveformView::setLevel3Data(const QVariantList& data)
{
    if (m_level3Data == data) return;
    m_level3Data = data;
    variantListToCache(data, m_level3Cache);
    invalidateCache();
    emit level3DataChanged();
}

void WaveformView::setLevel4Data(const QVariantList& data)
{
    if (m_level4Data == data) return;
    m_level4Data = data;
    variantListToCache(data, m_level4Cache);
    invalidateCache();
    emit level4DataChanged();
}

void WaveformView::setLevel5Data(const QVariantList& data)
{
    if (m_level5Data == data) return;
    m_level5Data = data;
    variantListToCache(data, m_level5Cache);
    invalidateCache();
    emit level5DataChanged();
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

void WaveformView::setCurrentPosition(qreal position)
{
    if (qAbs(m_currentPosition - position) < 0.0001)
        return;

    m_currentPosition = qBound(0.0, position, 1.0);

    if (m_followPlayback && m_contentWidth > width()) {
        qreal playheadX = m_currentPosition * m_contentWidth;
        qreal viewportRight = m_scrollPosition + width();
        qreal triggerX = m_scrollPosition + width() * m_followThreshold;

        qDebug() << "🎵 Position:" << QString::number(m_currentPosition, 'f', 3)
            << "| PlayheadX:" << QString::number(playheadX, 'f', 1)
            << "| TriggerX:" << QString::number(triggerX, 'f', 1)
            << "| ScrollPos:" << QString::number(m_scrollPosition, 'f', 1)
            << "| FollowEnabled:" << m_followPlayback;

        if (playheadX > triggerX) {
            qreal targetScroll = playheadX - width() * 0.3;
            qreal maxScroll = qMax(0.0, m_contentWidth - width());
            qreal clamped = qBound(0.0, targetScroll, maxScroll);

            qDebug() << "🚀 EMIT requestScrollTo:" << QString::number(clamped, 'f', 1)
                << "(target was:" << QString::number(targetScroll, 'f', 1) << ")";
            emit requestScrollTo(clamped);
        }
    }

    update();
    emit currentPositionChanged();
}

void WaveformView::setDuration(qint64 duration)
{
    if (m_duration == duration) return;
    m_duration = duration;
    updateContentWidth();
    invalidateCache();
    emit durationChanged();
}

void WaveformView::setZoomLevel(qreal zoom)
{
    zoom = qBound(m_minZoom, zoom, m_maxZoom);
    if (qAbs(m_zoomLevel - zoom) < 0.01) return;

    m_zoomLevel = zoom;
    updateContentWidth();
    invalidateCache();
    emit zoomLevelChanged();
}

void WaveformView::setScrollPosition(qreal position)
{
    position = qBound(0.0, position, qMax(0.0, m_contentWidth - width()));
    if (qAbs(m_scrollPosition - position) < 0.5) return;

    qreal delta = qAbs(position - m_scrollPosition);
    m_scrollPosition = position;

    if (delta > width() * 0.5) {
        invalidateCache();
    }
    else {
        update();
    }

    emit scrollPositionChanged();
}

void WaveformView::setShowPerformance(bool show)
{
    if (m_showPerformance == show) return;
    m_showPerformance = show;
    emit showPerformanceChanged();
    update();
}

void WaveformView::zoomIn()
{
    setZoomLevel(m_zoomLevel * 1.5);
}

void WaveformView::zoomOut()
{
    setZoomLevel(m_zoomLevel / 1.5);
}

void WaveformView::resetZoom()
{
    setZoomLevel(1.0);
    setScrollPosition(0);
}

void WaveformView::fitToView()
{
    if (m_duration > 0 && width() > 0) {
        qreal targetPixelsPerSecond = (width() * 0.95) / (m_duration / 1000.0);
        qreal newZoom = targetPixelsPerSecond / m_basePixelsPerSecond;
        setZoomLevel(qBound(m_minZoom, newZoom, m_maxZoom));
        setScrollPosition(0);
    }
}

void WaveformView::geometryChange(const QRectF& newGeometry, const QRectF& oldGeometry)
{
    QQuickPaintedItem::geometryChange(newGeometry, oldGeometry);
    if (newGeometry.size() != oldGeometry.size()) {
        updateContentWidth();
        invalidateCache();
    }
}

void WaveformView::paint(QPainter* painter)
{
    if (m_waveformDirty || s_firstBuild) {
        requestAsyncRebuild();
        s_firstBuild = false;
    }

    if (!m_waveformCache.isNull()) {
        painter->setRenderHint(QPainter::SmoothPixmapTransform, true);
        painter->drawPixmap(0, 0, m_waveformCache);
    }
    else {
        // 使用深色背景
        painter->fillRect(boundingRect(), QColor(32, 33, 36));
    }

    // playhead需要抗锯齿以获得平滑边缘
    painter->setRenderHint(QPainter::Antialiasing, true);
    paintPlayhead(painter);
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
        // 使用更深的背景色以提高对比度
        image.fill(QColor(32, 33, 36));  // 深灰色背景

        QPainter p(&image);
        // 启用抗锯齿和高质量渲染
        p.setRenderHint(QPainter::Antialiasing, true);
        p.setRenderHint(QPainter::SmoothPixmapTransform, true);
        p.setRenderHint(QPainter::TextAntialiasing, true);

        // 绘制时使用逻辑坐标
        paintCenterLine(&p, logicalSize);
        paintWaveform(&p, logicalSize);

        p.end();

        QMetaObject::invokeMethod(this, [this, image]() {
            m_waveformCache = QPixmap::fromImage(image);
            m_cacheValid = true;
            m_waveformDirty = false;
            m_rebuildPending = false;
            qDebug() << "✅ Waveform cache rebuilt";
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
    const QVector<MinMaxPair>& data = selectLevelData();
    if (data.isEmpty() || m_contentWidth <= 0)
        return;

    const qreal viewW = size.isEmpty() ? width() : size.width();
    const qreal viewH = size.isEmpty() ? height() : size.height();
    const qreal centerY = viewH * 0.5;
    const qreal amp = viewH * 0.45;
    const qreal pixelsPerPoint = m_contentWidth / data.size();

    const int start = qMax(0, int(m_scrollPosition / pixelsPerPoint) - 1);
    const int end = qMin(data.size(), int((m_scrollPosition + viewW) / pixelsPerPoint) + 1);

    painter->setRenderHint(QPainter::Antialiasing, true);

    // 方案：绘制填充区域 + 描边
    QPainterPath fillPath;
    bool firstPoint = true;

    // 构建上半部分路径
    for (int i = start; i < end; ++i) {
        qreal x = i * pixelsPerPoint - m_scrollPosition;
        if (x < -2 || x > viewW + 2)
            continue;

        qreal yMax = centerY - data[i].max * amp;

        if (firstPoint) {
            fillPath.moveTo(x, centerY);
            fillPath.lineTo(x, yMax);
            firstPoint = false;
        }
        else {
            fillPath.lineTo(x, yMax);
        }
    }

    // 构建下半部分路径（反向）
    for (int i = end - 1; i >= start; --i) {
        qreal x = i * pixelsPerPoint - m_scrollPosition;
        if (x < -2 || x > viewW + 2)
            continue;

        qreal yMin = centerY - data[i].min * amp;
        fillPath.lineTo(x, yMin);
    }

    fillPath.closeSubpath();

    // 绘制填充（半透明）
    QColor fillColor(100, 160, 255, 100);  // 亮蓝色，半透明
    painter->fillPath(fillPath, fillColor);

    // 绘制描边线条（清晰可见）
    QPen pen(QColor(120, 180, 255));  // 更亮的蓝色
    pen.setWidthF(1.2);
    pen.setCapStyle(Qt::RoundCap);
    painter->setPen(pen);

    // 绘制上边界
    for (int i = start; i < end - 1; ++i) {
        qreal x1 = i * pixelsPerPoint - m_scrollPosition;
        qreal x2 = (i + 1) * pixelsPerPoint - m_scrollPosition;

        if (x1 > viewW + 2) break;
        if (x2 < -2) continue;

        qreal y1 = centerY - data[i].max * amp;
        qreal y2 = centerY - data[i + 1].max * amp;

        painter->drawLine(QPointF(x1, y1), QPointF(x2, y2));
    }

    // 绘制下边界
    for (int i = start; i < end - 1; ++i) {
        qreal x1 = i * pixelsPerPoint - m_scrollPosition;
        qreal x2 = (i + 1) * pixelsPerPoint - m_scrollPosition;

        if (x1 > viewW + 2) break;
        if (x2 < -2) continue;

        qreal y1 = centerY - data[i].min * amp;
        qreal y2 = centerY - data[i + 1].min * amp;

        painter->drawLine(QPointF(x1, y1), QPointF(x2, y2));
    }
}

void WaveformView::paintCenterLine(QPainter* painter, const QSizeF& size)
{
    const qreal viewW = size.isEmpty() ? width() : size.width();
    const qreal viewH = size.isEmpty() ? height() : size.height();
    qreal centerY = viewH / 2.0;

    QPen pen(QColor(60, 60, 65), 1, Qt::DotLine);  // 稍亮的灰色以匹配深色背景
    painter->setPen(pen);
    painter->setRenderHint(QPainter::Antialiasing, false);
    painter->drawLine(QPointF(0, centerY), QPointF(viewW, centerY));
}

void WaveformView::paintPlayhead(QPainter* painter)
{
    if (m_duration <= 0) return;

    qreal playheadX = (m_currentPosition * m_contentWidth) - m_scrollPosition;
    if (playheadX < -2 || playheadX > width() + 2) return;

    painter->setRenderHint(QPainter::Antialiasing, true);

    // 绘制阴影 - 稍微偏移
    QPen shadowPen(QColor(0, 0, 0, 80), 2.5);
    painter->setPen(shadowPen);
    painter->drawLine(QPointF(playheadX + 0.8, 0), QPointF(playheadX + 0.8, height()));

    // 绘制主线条 - 更亮更清晰
    QPen mainPen(QColor(255, 255, 255, 250), 2.0);
    mainPen.setCapStyle(Qt::RoundCap);
    painter->setPen(mainPen);
    painter->drawLine(QPointF(playheadX, 0), QPointF(playheadX, height()));
}

void WaveformView::paintPerformanceInfo(QPainter* painter)
{
    QString info = QString("Paint: %1 μs | FPS: %2 | Zoom: %3x | Samples/px: %4")
        .arg(m_lastPaintTime)
        .arg(m_frameCount)
        .arg(m_zoomLevel, 0, 'f', 2)
        .arg(getSamplesPerPixel());

    painter->setPen(Qt::yellow);
    painter->setFont(QFont("monospace", 10));
    painter->drawText(10, 20, info);

    static qint64 lastReset = 0;
    qint64 now = QDateTime::currentMSecsSinceEpoch();
    if (now - lastReset > 1000) {
        m_frameCount = 0;
        lastReset = now;
    }
}

const QVector<MinMaxPair>& WaveformView::selectLevelData() const
{
    // Level 1: 256 samples/px - zoom < 0.5
    // Level 2: 128 samples/px - 0.5 <= zoom < 1.0  
    // Level 3: 32 samples/px  - 1.0 <= zoom < 3.0 (默认)
    // Level 4: 8 samples/px   - 3.0 <= zoom < 8.0
    // Level 5: 1 sample/px    - zoom >= 8.0

    if (m_zoomLevel >= 8.0 && !m_level5Cache.isEmpty()) {
        return m_level5Cache;
    }
    else if (m_zoomLevel >= 3.0 && !m_level4Cache.isEmpty()) {
        return m_level4Cache;
    }
    else if (m_zoomLevel >= 1.0 && !m_level3Cache.isEmpty()) {
        return m_level3Cache;
    }
    else if (m_zoomLevel >= 0.5 && !m_level2Cache.isEmpty()) {
        return m_level2Cache;
    }
    else if (!m_level1Cache.isEmpty()) {
        return m_level1Cache;
    }
    return m_level1Cache;
}

int WaveformView::getSamplesPerPixel() const
{
    if (m_zoomLevel >= 8.0) return 1;
    else if (m_zoomLevel >= 3.0) return 8;
    else if (m_zoomLevel >= 1.0) return 32;
    else if (m_zoomLevel >= 0.5) return 128;
    else return 256;
}

void WaveformView::updateContentWidth()
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

qreal WaveformView::pixelToTime(qreal pixel) const
{
    if (m_contentWidth <= 0) return 0.0;
    return (pixel / m_contentWidth) * m_duration;
}

qreal WaveformView::timeToPixel(qreal time) const
{
    if (m_duration <= 0) return 0.0;
    return (time / m_duration) * m_contentWidth;
}