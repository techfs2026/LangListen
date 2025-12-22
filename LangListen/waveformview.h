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

        Q_PROPERTY(QVariantList level1Data READ level1Data WRITE setLevel1Data NOTIFY level1DataChanged)
        Q_PROPERTY(QVariantList level2Data READ level2Data WRITE setLevel2Data NOTIFY level2DataChanged)
        Q_PROPERTY(QVariantList level3Data READ level3Data WRITE setLevel3Data NOTIFY level3DataChanged)
        Q_PROPERTY(QVariantList level4Data READ level4Data WRITE setLevel4Data NOTIFY level4DataChanged)
        Q_PROPERTY(QVariantList level5Data READ level5Data WRITE setLevel5Data NOTIFY level5DataChanged)

        Q_PROPERTY(qreal currentPosition READ currentPosition WRITE setCurrentPosition NOTIFY currentPositionChanged)
        Q_PROPERTY(qint64 duration READ duration WRITE setDuration NOTIFY durationChanged)

        Q_PROPERTY(qreal zoomLevel READ zoomLevel WRITE setZoomLevel NOTIFY zoomLevelChanged)
        Q_PROPERTY(qreal scrollPosition READ scrollPosition WRITE setScrollPosition NOTIFY scrollPositionChanged)
        Q_PROPERTY(qreal contentWidth READ contentWidth NOTIFY contentWidthChanged)
        Q_PROPERTY(bool followPlayback MEMBER m_followPlayback NOTIFY followPlaybackChanged)

        Q_PROPERTY(bool showPerformance READ showPerformance WRITE setShowPerformance NOTIFY showPerformanceChanged)

public:
    explicit WaveformView(QQuickItem* parent = nullptr);
    ~WaveformView();

    QVariantList level1Data() const { return m_level1Data; }
    QVariantList level2Data() const { return m_level2Data; }
    QVariantList level3Data() const { return m_level3Data; }
    QVariantList level4Data() const { return m_level4Data; }
    QVariantList level5Data() const { return m_level5Data; }

    qreal currentPosition() const { return m_currentPosition; }
    qint64 duration() const { return m_duration; }
    qreal zoomLevel() const { return m_zoomLevel; }
    qreal scrollPosition() const { return m_scrollPosition; }
    qreal contentWidth() const { return m_contentWidth; }
    bool showPerformance() const { return m_showPerformance; }

    void setLevel1Data(const QVariantList& data);
    void setLevel2Data(const QVariantList& data);
    void setLevel3Data(const QVariantList& data);
    void setLevel4Data(const QVariantList& data);
    void setLevel5Data(const QVariantList& data);

    void setCurrentPosition(qreal position);
    void setDuration(qint64 duration);
    void setZoomLevel(qreal zoom);
    void setScrollPosition(qreal position);
    void setShowPerformance(bool show);

    Q_INVOKABLE void zoomIn();
    Q_INVOKABLE void zoomOut();
    Q_INVOKABLE void resetZoom();
    Q_INVOKABLE void fitToView();

signals:
    void level1DataChanged();
    void level2DataChanged();
    void level3DataChanged();
    void level4DataChanged();
    void level5DataChanged();
    void currentPositionChanged();
    void durationChanged();
    void zoomLevelChanged();
    void scrollPositionChanged();
    void contentWidthChanged();
    void showPerformanceChanged();
    void followPlaybackChanged();
    void requestScrollTo(qreal targetX);

protected:
    void paint(QPainter* painter) override;
    void geometryChange(const QRectF& newGeometry, const QRectF& oldGeometry) override;

private:
    QVariantList m_level1Data;
    QVariantList m_level2Data;
    QVariantList m_level3Data;
    QVariantList m_level4Data;
    QVariantList m_level5Data;

    QVector<MinMaxPair> m_level1Cache;
    QVector<MinMaxPair> m_level2Cache;
    QVector<MinMaxPair> m_level3Cache;
    QVector<MinMaxPair> m_level4Cache;
    QVector<MinMaxPair> m_level5Cache;

    qreal m_currentPosition;
    qint64 m_duration;
    qreal m_zoomLevel;
    qreal m_scrollPosition;
    qreal m_contentWidth;

    QPixmap m_waveformCache;
    bool m_waveformDirty;
    bool m_cacheValid;

    const qreal m_basePixelsPerSecond = 100.0;
    const qreal m_minZoom = 0.1;
    const qreal m_maxZoom = 20.0;

    bool m_showPerformance;
    QElapsedTimer m_paintTimer;
    qint64 m_lastPaintTime;
    int m_frameCount;

    bool m_rebuildPending;
    bool m_followPlayback;
    qreal m_followThreshold;

    void updateCachedData();
    void variantListToCache(const QVariantList& data, QVector<MinMaxPair>& cache);

    const QVector<MinMaxPair>& selectLevelData() const;
    int getSamplesPerPixel() const;

    void invalidateCache();
    void requestAsyncRebuild();

    void paintWaveform(QPainter* painter, const QSizeF& size = QSizeF());
    void paintPlayhead(QPainter* painter);
    void paintCenterLine(QPainter* painter, const QSizeF& size = QSizeF());
    void paintPerformanceInfo(QPainter* painter);

    void updateContentWidth();
    qreal pixelToTime(qreal pixel) const;
    qreal timeToPixel(qreal time) const;
};

#endif