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
    const qreal amp = viewH * 0.48; // 略小于 0.5 以留边距

    const QVector<WaveformLevel>& levels = m_waveformGenerator->getLevels();
    if (m_currentLevelIndex < 0 || m_currentLevelIndex >= levels.size())
        return;

    const WaveformLevel& currentLevel = levels[m_currentLevelIndex];
    const qreal pixelsPerDataPoint = m_pixelsPerSecond / currentLevel.pixelsPerSecond;

    // ============================================================================
    // 根据 pixelsPerDataPoint 选择渲染模式
    // ============================================================================

    if (pixelsPerDataPoint >= 4.0) {
        // 模式 A: 高缩放 - 显示采样点和连线（类似 Audacity 最高 zoom）
        paintWaveformSampleLevel(painter, viewW, viewH, centerY, amp, pixelsPerDataPoint);
    }
    else if (pixelsPerDataPoint >= 0.8) {
        // 模式 B: 中等缩放 - Peak envelope 竖线（Audacity 默认模式）
        paintWaveformPeakLines(painter, viewW, viewH, centerY, amp, pixelsPerDataPoint);
    }
    else {
        // 模式 C: 低缩放 - 聚合 Peak envelope（类似 Subtitle Edit）
        paintWaveformDense(painter, viewW, viewH, centerY, amp, pixelsPerDataPoint);
    }
}

void WaveformView::paintWaveformSampleLevel(QPainter* painter, qreal viewW, qreal viewH,
    qreal centerY, qreal amp, qreal pixelsPerDataPoint)
{
    // 关闭抗锯齿，保持像素感
    painter->setRenderHint(QPainter::Antialiasing, false);

    QPen samplePen(QColor(30, 50, 100), 1.0); // 深蓝色，1px
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

        // 使用 max 作为采样值（或可改为 (min+max)/2）
        float sampleValue = m_currentLevelCache[idx].max;
        qreal y = centerY - sampleValue * amp;

        samplePoints.append(QPointF(pixelX, y));
    }

    // 绘制采样点（可选：圆点或方块）
    painter->setBrush(QColor(30, 50, 100));
    for (const QPointF& pt : samplePoints) {
        painter->drawEllipse(pt, 2, 2); // 2px 圆点
    }

    // 绘制采样点之间的连线（不平滑）
    if (samplePoints.size() > 1) {
        QPen linePen(QColor(30, 50, 100, 180), 0.8);
        painter->setPen(linePen);
        painter->drawPolyline(samplePoints.data(), samplePoints.size());
    }
}

void WaveformView::paintWaveformPeakLines(QPainter* painter, qreal viewW, qreal viewH,
    qreal centerY, qreal amp, qreal pixelsPerDataPoint)
{
    // 关闭抗锯齿 - 这是关键！
    painter->setRenderHint(QPainter::Antialiasing, false);

    // 使用不透明的实线
    QPen linePen(QColor(33, 66, 133), 1.0); // 深蓝色，完全不透明
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

        // 找到该像素列的真实峰值
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

        // 绘制竖线（不添加任何平滑）
        painter->drawLine(QPointF(pixelX, yMax), QPointF(pixelX, yMin));
    }

    // 不绘制边缘轮廓线！移除原代码中的 topPoints/bottomPoints polyline
}

void WaveformView::paintWaveformDense(QPainter* painter, qreal viewW, qreal viewH,
    qreal centerY, qreal amp, qreal pixelsPerDataPoint)
{
    // 低缩放时可以适当开启抗锯齿，但仍保持锐利
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

    int playheadX = m_playheadXInPage + 1;

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

    // 判断是否按下 Ctrl 键（精细调节）
    bool fineControl = event->modifiers() & Qt::ControlModifier;

    // 计算缩放量
    qreal delta = !numPixels.isNull() ? numPixels.y() : numDegrees.y();

    // 精细控制：1/3 速度
    qreal zoomFactor = fineControl ?
        1.0 + (delta / 720.0) :  // Ctrl: 约 2% per 15°
        1.0 + (delta / 240.0);   // 普通: 约 6% per 15°

    qreal newPPS = m_pixelsPerSecond * zoomFactor;
    newPPS = qBound(m_minPixelsPerSecond, newPPS, m_maxPixelsPerSecond);

    if (qAbs(newPPS - m_pixelsPerSecond) < 0.01) {
        event->accept();
        return;
    }

    // 计算鼠标位置对应的时间点（以鼠标为中心缩放）
    qreal mouseX = event->position().x();
    qreal globalX = m_scrollPosition + mouseX;
    qreal timeAtMouse = globalX / m_pixelsPerSecond;

    // 更新像素/秒
    setPixelsPerSecond(newPPS);

    // 调整滚动位置，使鼠标下的时间点保持不变
    qreal newGlobalX = timeAtMouse * newPPS;
    qreal newScrollPos = newGlobalX - mouseX;

    // 限制滚动范围
    qreal maxScroll = qMax(0.0, m_contentWidth - m_viewportWidth);
    newScrollPos = qBound(0.0, newScrollPos, maxScroll);

    setScrollPosition(newScrollPos);

    event->accept();

    // 可选：输出调试信息
    qDebug() << "Zoom:" << m_pixelsPerSecond
        << "| Level:" << m_currentLevelIndex
        << "| Fine:" << fineControl;
}