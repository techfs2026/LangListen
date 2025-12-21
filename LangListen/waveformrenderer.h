#ifndef WAVEFORMRENDERER_H
#define WAVEFORMRENDERER_H

#include <QQuickPaintedItem>
#include <QPainter>
#include <QVariantList>
#include <QColor>
#include <QVector>

struct WaveformSegment {
    qint64 startTime;
    qint64 endTime;
    QString text;
};

class WaveformRenderer : public QQuickPaintedItem
{
    Q_OBJECT
        Q_PROPERTY(QVariantList waveformData READ waveformData WRITE setWaveformData NOTIFY waveformDataChanged)
        Q_PROPERTY(qreal currentPosition READ currentPosition WRITE setCurrentPosition NOTIFY currentPositionChanged)
        Q_PROPERTY(qint64 duration READ duration WRITE setDuration NOTIFY durationChanged)
        Q_PROPERTY(QVariantList segments READ segments WRITE setSegments NOTIFY segmentsChanged)
        Q_PROPERTY(qreal zoomLevel READ zoomLevel WRITE setZoomLevel NOTIFY zoomLevelChanged)
        Q_PROPERTY(qreal scrollPosition READ scrollPosition WRITE setScrollPosition NOTIFY scrollPositionChanged)
        Q_PROPERTY(qreal contentWidth READ contentWidth NOTIFY contentWidthChanged)

public:
    explicit WaveformRenderer(QQuickItem* parent = nullptr);

    QVariantList waveformData() const { return m_waveformData; }
    void setWaveformData(const QVariantList& data);

    qreal currentPosition() const { return m_currentPosition; }
    void setCurrentPosition(qreal position);

    qint64 duration() const { return m_duration; }
    void setDuration(qint64 duration);

    QVariantList segments() const { return m_segments; }
    void setSegments(const QVariantList& segments);

    qreal zoomLevel() const { return m_zoomLevel; }
    void setZoomLevel(qreal zoom);

    qreal scrollPosition() const { return m_scrollPosition; }
    void setScrollPosition(qreal position);

    qreal contentWidth() const { return m_contentWidth; }

    Q_INVOKABLE void zoomIn();
    Q_INVOKABLE void zoomOut();
    Q_INVOKABLE void resetZoom();
    Q_INVOKABLE void fitToView();
    Q_INVOKABLE QString formatTime(qint64 milliseconds);

signals:
    void waveformDataChanged();
    void currentPositionChanged();
    void durationChanged();
    void segmentsChanged();
    void zoomLevelChanged();
    void scrollPositionChanged();
    void contentWidthChanged();

protected:
    void paint(QPainter* painter) override;

private:
    QVariantList m_waveformData;
    qreal m_currentPosition;
    qint64 m_duration;
    QVariantList m_segments;
    qreal m_zoomLevel;
    qreal m_scrollPosition;
    qreal m_contentWidth;

    QVector<float> m_waveformDataCache;
    QVector<WaveformSegment> m_segmentsCache;

    const qreal m_basePixelsPerSecond = 100.0;
    const qreal m_minZoom = 0.1;
    const qreal m_maxZoom = 10.0;
    const int m_rulerHeight = 26;

    QColor m_waveformColor;
    QColor m_waveformShadowColor;
    QColor m_backgroundColor;
    QColor m_rulerColor;
    QColor m_gridLineColor;
    QColor m_timeTextColor;
    QColor m_playheadColor;
    QColor m_segmentMarkerColor;

    int m_minorGridInterval;
    int m_majorGridInterval;

    void updateContentWidth();
    void updateGridIntervals();
    void updateCachedData();

    void drawBackground(QPainter* painter);
    void drawGrid(QPainter* painter);
    void drawSegments(QPainter* painter);
    void drawWaveform(QPainter* painter);
    void drawRuler(QPainter* painter);
    void drawPlayhead(QPainter* painter);

    void drawDetailedWaveform(QPainter* painter, qreal centerY, qreal halfHeight,
        qreal visibleStartX, qreal visibleEndX,
        int numBins, qreal pixelsPerBin);
    void drawMediumWaveform(QPainter* painter, qreal centerY, qreal halfHeight,
        qreal visibleStartX, qreal visibleEndX,
        int numBins, qreal pixelsPerBin);
    void drawFilledWaveform(QPainter* painter, qreal centerY, qreal halfHeight,
        qreal visibleStartX, qreal visibleEndX,
        int numBins, qreal pixelsPerBin);
};

#endif