#ifndef WAVEFORMVIEW_H
#define WAVEFORMVIEW_H

#include <QQuickPaintedItem>
#include <QPainter>
#include <QPixmap>
#include <QVariantList>
#include <QVector>
#include <QElapsedTimer>
#include <QWheelEvent>
#include <QMouseEvent>
#include <QHoverEvent>
#include "waveformgenerator.h"
#include "ffmpegaudioengine.h"

class WaveformView : public QQuickPaintedItem
{
    Q_OBJECT

        Q_PROPERTY(WaveformGenerator* waveformGenerator READ waveformGenerator WRITE setWaveformGenerator NOTIFY waveformGeneratorChanged)
        Q_PROPERTY(qreal currentPosition READ currentPosition WRITE setCurrentPosition NOTIFY currentPositionChanged)
        Q_PROPERTY(qreal pixelsPerSecond READ pixelsPerSecond WRITE setPixelsPerSecond NOTIFY pixelsPerSecondChanged)
        Q_PROPERTY(qreal scrollPosition READ scrollPosition WRITE setScrollPosition NOTIFY scrollPositionChanged)
        Q_PROPERTY(qreal contentWidth READ contentWidth NOTIFY contentWidthChanged)
        Q_PROPERTY(qreal viewportWidth READ viewportWidth WRITE setViewportWidth NOTIFY viewportWidthChanged)
        Q_PROPERTY(bool followPlayback READ followPlayback WRITE setFollowPlayback NOTIFY followPlaybackChanged)
        Q_PROPERTY(bool showPerformance READ showPerformance WRITE setShowPerformance NOTIFY showPerformanceChanged)
        Q_PROPERTY(bool showSentenceHighlight READ showSentenceHighlight WRITE setShowSentenceHighlight NOTIFY showSentenceHighlightChanged)
        Q_PROPERTY(int currentSentenceIndex READ currentSentenceIndex NOTIFY currentSentenceIndexChanged)
        Q_PROPERTY(bool enableBoundaryEdit READ enableBoundaryEdit WRITE setEnableBoundaryEdit NOTIFY enableBoundaryEditChanged)

public:
    explicit WaveformView(QQuickItem* parent = nullptr);
    ~WaveformView();

    WaveformGenerator* waveformGenerator() const { return m_waveformGenerator; }
    qreal currentPosition() const { return m_currentPosition; }
    qreal pixelsPerSecond() const { return m_pixelsPerSecond; }
    qreal scrollPosition() const { return m_scrollPosition; }
    qreal contentWidth() const { return m_contentWidth; }
    qreal viewportWidth() const { return m_viewportWidth; }
    bool showPerformance() const { return m_showPerformance; }
    bool followPlayback() const { return m_followPlayback; }
    bool showSentenceHighlight() const { return m_showSentenceHighlight; }
    int currentSentenceIndex() const { return m_currentSentenceIndex; }
    bool enableBoundaryEdit() const { return m_enableBoundaryEdit; }

    void setWaveformGenerator(WaveformGenerator* generator);
    void setCurrentPosition(qreal position);
    void setPixelsPerSecond(qreal pps);
    void setScrollPosition(qreal position);
    void setViewportWidth(qreal width);
    void setShowPerformance(bool show);
    void setFollowPlayback(bool follow);
    void setShowSentenceHighlight(bool show);
    void setEnableBoundaryEdit(bool enable);

    Q_INVOKABLE void addSentence(qint64 startMs, qint64 endMs, const QString& text = QString());
    Q_INVOKABLE void clearSentences();
    Q_INVOKABLE int getSentenceCount() const { return m_sentences.size(); }
    Q_INVOKABLE QVariantMap getSentenceAt(int index) const;
    Q_INVOKABLE int findSentenceAtTime(qint64 timeMs) const;

    Q_INVOKABLE void zoomIn();
    Q_INVOKABLE void zoomOut();
    Q_INVOKABLE void resetZoom();
    Q_INVOKABLE void fitToView();
    Q_INVOKABLE bool canZoomIn() const;
    Q_INVOKABLE bool canZoomOut() const;

    Q_INVOKABLE void seekToPosition(qreal normalizedPosition);
    Q_INVOKABLE void seekToTime(qint64 timeMs);
    Q_INVOKABLE void seekToSentence(int sentenceIndex);

    Q_INVOKABLE void centerCurrentSentence();

signals:
    void waveformGeneratorChanged();
    void currentPositionChanged();
    void pixelsPerSecondChanged();
    void scrollPositionChanged();
    void contentWidthChanged();
    void viewportWidthChanged();
    void showPerformanceChanged();
    void followPlaybackChanged();
    void showSentenceHighlightChanged();
    void currentSentenceIndexChanged();
    void enableBoundaryEditChanged();
    void requestDirectScroll(qreal targetX);
    void clicked(qreal normalizedPosition, qint64 timeMs);
    void sentenceClicked(int sentenceIndex);
    void hoveredTimeChanged(qint64 timeMs);
    void sentenceBoundaryChanged(int sentenceIndex, qint64 newStartMs, qint64 newEndMs);
    void boundaryDragStarted();
    void boundaryDragEnded();

protected:
    void paint(QPainter* painter) override;
    void geometryChange(const QRectF& newGeometry, const QRectF& oldGeometry) override;
    void wheelEvent(QWheelEvent* event) override;
    void mousePressEvent(QMouseEvent* event) override;
    void mouseMoveEvent(QMouseEvent* event) override;
    void mouseReleaseEvent(QMouseEvent* event) override;
    void hoverMoveEvent(QHoverEvent* event) override;
    void hoverLeaveEvent(QHoverEvent* event) override;

private slots:
    void onLevelsChanged();

private:
    enum class DragMode {
        None,
        StartBoundary,
        EndBoundary
    };

    WaveformGenerator* m_waveformGenerator;
    QVector<MinMaxPair> m_currentLevelCache;

    qreal m_currentPosition;
    qreal m_pixelsPerSecond;
    qreal m_scrollPosition;
    qreal m_contentWidth;
    qreal m_viewportWidth;

    qreal m_pageStartTime;
    int m_playheadXInPage;

    const qreal m_basePixelsPerSecond = 100.0;
    const qreal m_minPixelsPerSecond = 1.0;
    const qreal m_maxPixelsPerSecond = 10000.0;

    bool m_showPerformance;
    QElapsedTimer m_paintTimer;
    qint64 m_lastPaintTime;
    int m_frameCount;

    bool m_followPlayback;
    int m_currentLevelIndex;

    QVector<SentenceSegment> m_sentences;
    int m_currentSentenceIndex;
    int m_hoveredSentenceIndex;
    bool m_showSentenceHighlight;
    qint64 m_hoveredTimeMs;

    bool m_enableBoundaryEdit;
    DragMode m_dragMode;
    int m_dragSentenceIndex;
    qint64 m_dragOriginalTime;
    int m_hoveredBoundaryIndex;
    bool m_hoveredBoundaryIsStart;
    const qreal m_boundaryHandleRadius = 8.0;
    const qreal m_boundaryHitRadius = 12.0;

    void updateCurrentLevel();
    void variantListToCache(const QVariantList& data, QVector<MinMaxPair>& cache);

    void paintWaveform(QPainter* painter, const QSizeF& size = QSizeF());
    void paintSentenceHighlights(QPainter* painter);
    void paintSentenceBoundaries(QPainter* painter);
    void paintPlayhead(QPainter* painter);
    void paintCenterLine(QPainter* painter, const QSizeF& size = QSizeF());
    void paintTimeAxis(QPainter* painter);
    void paintPerformanceInfo(QPainter* painter);
    void paintHoverInfo(QPainter* painter);
    void paintBoundaryHandle(QPainter* painter, qreal x, bool isStart, bool isHovered);

    void paintWaveformSampleLevel(QPainter* painter, qreal viewW, qreal viewH,
        qreal centerY, qreal amp, qreal pixelsPerDataPoint);
    void paintWaveformPeakLines(QPainter* painter, qreal viewW, qreal viewH,
        qreal centerY, qreal amp, qreal pixelsPerDataPoint);
    void paintWaveformDense(QPainter* painter, qreal viewW, qreal viewH,
        qreal centerY, qreal amp, qreal pixelsPerDataPoint);

    void updateContentWidth();
    void updateCurrentSentence();
    qreal timeToPixel(qint64 timeMs) const;
    qint64 pixelToTime(qreal pixel) const;
    qreal secondsToPixels(qreal seconds) const;
    qreal pixelsToSeconds(qreal pixels) const;

    void updatePlayheadPosition();
    qreal getPageWidthInSeconds() const;
    void updatePlayheadPositionWithoutScroll();

    bool checkBoundaryHit(const QPointF& pos, int& outSentenceIndex, bool& outIsStart);
    void updateCursor();
};

#endif // WAVEFORMVIEW_H