#ifndef WAVEFORMVIEW_H
#define WAVEFORMVIEW_H

#include <QQuickPaintedItem>
#include <QPainter>
#include <QPixmap>
#include <QVariantList>
#include <QVector>
#include <QElapsedTimer>
#include "waveformgenerator.h"

class WaveformView : public QQuickPaintedItem
{
    Q_OBJECT

        Q_PROPERTY(WaveformGenerator* waveformGenerator READ waveformGenerator WRITE setWaveformGenerator NOTIFY waveformGeneratorChanged)
        Q_PROPERTY(qreal currentPosition READ currentPosition WRITE setCurrentPosition NOTIFY currentPositionChanged)
        Q_PROPERTY(qreal pixelsPerSecond READ pixelsPerSecond WRITE setPixelsPerSecond NOTIFY pixelsPerSecondChanged)
        Q_PROPERTY(qreal scrollPosition READ scrollPosition WRITE setScrollPosition NOTIFY scrollPositionChanged)
        Q_PROPERTY(qreal contentWidth READ contentWidth NOTIFY contentWidthChanged)
        Q_PROPERTY(qreal viewportWidth READ viewportWidth WRITE setViewportWidth NOTIFY viewportWidthChanged)
        Q_PROPERTY(qreal playheadPosition READ playheadPosition WRITE setPlayheadPosition NOTIFY playheadPositionChanged)
        Q_PROPERTY(bool followPlayback READ followPlayback WRITE setFollowPlayback NOTIFY followPlaybackChanged)
        Q_PROPERTY(bool showPerformance READ showPerformance WRITE setShowPerformance NOTIFY showPerformanceChanged)

public:
    explicit WaveformView(QQuickItem* parent = nullptr);
    ~WaveformView();

    WaveformGenerator* waveformGenerator() const { return m_waveformGenerator; }
    qreal currentPosition() const { return m_currentPosition; }
    qreal pixelsPerSecond() const { return m_pixelsPerSecond; }
    qreal scrollPosition() const { return m_scrollPosition; }
    qreal contentWidth() const { return m_contentWidth; }
    qreal viewportWidth() const { return m_viewportWidth; }
    qreal playheadPosition() const { return m_playheadPosition; }
    bool showPerformance() const { return m_showPerformance; }
    bool followPlayback() const { return m_followPlayback; }

    void setWaveformGenerator(WaveformGenerator* generator);
    void setCurrentPosition(qreal position);
    void setPixelsPerSecond(qreal pps);
    void setScrollPosition(qreal position);
    void setViewportWidth(qreal width);
    void setPlayheadPosition(qreal position);
    void setShowPerformance(bool show);
    void setFollowPlayback(bool follow);

    Q_INVOKABLE void zoomIn();
    Q_INVOKABLE void zoomOut();
    Q_INVOKABLE void resetZoom();
    Q_INVOKABLE void fitToView();
    Q_INVOKABLE bool canZoomIn() const;
    Q_INVOKABLE bool canZoomOut() const;

signals:
    void waveformGeneratorChanged();
    void currentPositionChanged();
    void pixelsPerSecondChanged();
    void scrollPositionChanged();
    void contentWidthChanged();
    void viewportWidthChanged();
    void playheadPositionChanged();
    void showPerformanceChanged();
    void followPlaybackChanged();
    void requestScrollTo(qreal targetX);

protected:
    void paint(QPainter* painter) override;
    void geometryChange(const QRectF& newGeometry, const QRectF& oldGeometry) override;

private slots:
    void onLevelsChanged();

private:
    WaveformGenerator* m_waveformGenerator;
    QVector<MinMaxPair> m_currentLevelCache;

    qreal m_currentPosition;
    qreal m_pixelsPerSecond;
    qreal m_scrollPosition;
    qreal m_contentWidth;
    qreal m_viewportWidth;
    qreal m_playheadPosition;

    QPixmap m_waveformCache;
    bool m_waveformDirty;
    bool m_cacheValid;

    const qreal m_basePixelsPerSecond = 100.0;
    const qreal m_minPixelsPerSecond = 1.0;
    const qreal m_maxPixelsPerSecond = 10000.0;

    bool m_showPerformance;
    QElapsedTimer m_paintTimer;
    qint64 m_lastPaintTime;
    int m_frameCount;

    bool m_rebuildPending;
    bool m_followPlayback;
    int m_currentLevelIndex;

    void updateCurrentLevel();
    void variantListToCache(const QVariantList& data, QVector<MinMaxPair>& cache);

    void invalidateCache();
    void requestAsyncRebuild();

    void paintWaveform(QPainter* painter, const QSizeF& size = QSizeF());
    void paintPlayhead(QPainter* painter);
    void paintCenterLine(QPainter* painter, const QSizeF& size = QSizeF());
    void paintPerformanceInfo(QPainter* painter);

    void updateContentWidth();
    qreal secondsToPixels(qreal seconds) const;
    qreal pixelsToSeconds(qreal pixels) const;
};

#endif