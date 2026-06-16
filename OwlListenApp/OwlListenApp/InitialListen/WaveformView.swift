import AppKit
import OwlListenKit
import SwiftUI

struct WaveformView: View {
    let envelope: WaveformEnvelope
    let duration: TimeInterval
    let viewStart: TimeInterval
    let viewEnd: TimeInterval
    let currentTime: TimeInterval
    let playheadAnchorDate: Date
    let canInterpolatePlayhead: Bool
    let isPlaying: Bool
    let playbackRate: Float
    let labels: [AudioLabel]
    let selectedLabelID: UUID?
    let onSeek: (TimeInterval) -> Void
    let onCreateLabel: (TimeInterval, TimeInterval) -> Void
    let onSelectLabel: (UUID) -> Void
    let onAdjustLabel: (UUID, TimeInterval?, TimeInterval?) -> Void
    let onWidthChanged: (CGFloat) -> Void
    let onZoom: (Double, TimeInterval) -> Void
    let onScroll: (Double) -> Void

    @State private var dragStart: CGFloat?
    @State private var dragCurrent: CGFloat?
    @State private var edgeDrag: EdgeDrag?
    @State private var hoverEdge: EdgeDrag?
    @State private var isPanning = false
    @State private var previousPanX: CGFloat?
    @State private var previousMagnification: CGFloat = 1

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.972, green: 0.975, blue: 0.962),
                        Color(red: 0.944, green: 0.952, blue: 0.938),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                Canvas { context, canvasSize in
                    drawStudyPaper(context: &context, size: canvasSize)
                    drawWaveform(context: &context, size: canvasSize)
                    drawLabels(context: &context, size: canvasSize)
                    drawDragPreview(context: &context, size: canvasSize)
                }

                TimelineView(.animation(minimumInterval: 1 / 60, paused: !shouldInterpolatePlayhead)) { timeline in
                    Canvas { context, canvasSize in
                        drawPlayhead(
                            context: &context,
                            size: canvasSize,
                            time: playheadTime(at: timeline.date)
                        )
                    }
                }
                .allowsHitTesting(false)

                WaveformScrollMonitor(
                    viewStart: viewStart,
                    viewEnd: viewEnd,
                    onZoom: onZoom,
                    onScroll: onScroll
                )

                Color.clear
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            hoverEdge = hitTestEdge(x: location.x, width: size.width)
                        default:
                            hoverEdge = nil
                        }
                    }
                    .gesture(dragGesture(width: size.width))
                    .simultaneousGesture(magnificationGesture)
            }
            .modifier(HoverCursor(cursor: waveformCursor))
            .onAppear {
                onWidthChanged(size.width)
            }
            .onChange(of: size.width) { width in
                onWidthChanged(width)
            }
        }
    }

    private var waveformCursor: NSCursor {
        edgeDrag != nil || hoverEdge != nil ? .resizeLeftRight : .crosshair
    }

    private func dragGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let x = min(max(0, value.location.x), width)
                if dragStart == nil {
                    dragStart = x
                    dragCurrent = x
                    isPanning = NSEvent.modifierFlags.contains(.shift)
                    previousPanX = x
                    if isPanning {
                        return
                    }
                    edgeDrag = hitTestEdge(x: x, width: width)
                } else {
                    dragCurrent = x
                }

                if isPanning, let previousPanX, width > 0 {
                    onScroll(-Double(x - previousPanX) / Double(width))
                    self.previousPanX = x
                    return
                }

                if let edgeDrag {
                    let second = seconds(for: x, width: width)
                    switch edgeDrag.edge {
                    case .start:
                        onAdjustLabel(edgeDrag.id, second, nil)
                    case .end:
                        onAdjustLabel(edgeDrag.id, nil, second)
                    }
                }
            }
            .onEnded { value in
                defer {
                    dragStart = nil
                    dragCurrent = nil
                    edgeDrag = nil
                    isPanning = false
                    previousPanX = nil
                }
                guard let startX = dragStart else {
                    return
                }
                let endX = min(max(0, value.location.x), width)
                if isPanning {
                    return
                }
                if edgeDrag != nil {
                    return
                }

                if abs(endX - startX) < 6 {
                    if let label = hitTestLabel(x: endX, width: width) {
                        onSelectLabel(label.id)
                    } else {
                        onSeek(seconds(for: endX, width: width))
                    }
                } else {
                    onCreateLabel(
                        seconds(for: min(startX, endX), width: width),
                        seconds(for: max(startX, endX), width: width)
                    )
                }
            }
    }

    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { magnification in
                guard magnification > 0 else {
                    return
                }
                onZoom(
                    Double(previousMagnification / magnification),
                    viewStart + (viewEnd - viewStart) / 2
                )
                previousMagnification = magnification
            }
            .onEnded { _ in
                previousMagnification = 1
            }
    }

    private func drawWaveform(context: inout GraphicsContext, size: CGSize) {
        guard !envelope.samples.isEmpty, viewEnd > viewStart else {
            return
        }
        let centerY = size.height / 2
        let step = size.width / CGFloat(max(envelope.samples.count - 1, 1))
        var centerLine = Path()
        centerLine.move(to: CGPoint(x: 0, y: centerY))
        centerLine.addLine(to: CGPoint(x: size.width, y: centerY))
        context.stroke(
            centerLine,
            with: .color(Color(red: 0.173, green: 0.290, blue: 0.549).opacity(0.26)),
            style: StrokeStyle(lineWidth: 1, dash: [5, 5])
        )

        var path = Path()
        for (index, amplitude) in envelope.samples.enumerated() {
            let x = CGFloat(index) * step
            let height = max(1, CGFloat(amplitude) * size.height * 0.40)
            path.move(to: CGPoint(x: x, y: centerY - height))
            path.addLine(to: CGPoint(x: x, y: centerY + height))
        }
        context.stroke(path, with: .color(Color(red: 0.148, green: 0.255, blue: 0.492)), lineWidth: 1)
    }

    private func drawStudyPaper(context: inout GraphicsContext, size: CGSize) {
        let gridColor = Color(red: 0.102, green: 0.153, blue: 0.267).opacity(0.055)
        let majorColor = Color(red: 0.102, green: 0.153, blue: 0.267).opacity(0.085)

        var horizontal = Path()
        let rowHeight: CGFloat = 42
        var y = rowHeight
        while y < size.height {
            horizontal.move(to: CGPoint(x: 0, y: y))
            horizontal.addLine(to: CGPoint(x: size.width, y: y))
            y += rowHeight
        }
        context.stroke(horizontal, with: .color(gridColor), lineWidth: 1)

        guard viewEnd > viewStart else {
            return
        }
        let visibleDuration = viewEnd - viewStart
        let options: [TimeInterval] = [0.25, 0.5, 1, 2, 5, 10, 15, 30, 60, 120]
        let interval = options.min { abs($0 - visibleDuration / 12) < abs($1 - visibleDuration / 12) } ?? 1
        var tick = ceil(viewStart / interval) * interval
        var vertical = Path()
        while tick <= viewEnd + 0.000_001 {
            let x = self.x(for: tick, width: size.width)
            vertical.move(to: CGPoint(x: x, y: 0))
            vertical.addLine(to: CGPoint(x: x, y: size.height))
            tick += interval
        }
        context.stroke(vertical, with: .color(majorColor), lineWidth: 1)
    }

    private func drawLabels(context: inout GraphicsContext, size: CGSize) {
        guard duration > 0 else {
            return
        }
        for label in labels {
            guard label.end >= viewStart, label.start <= viewEnd else {
                continue
            }
            let startX = x(for: label.start, width: size.width)
            let endX = x(for: label.end, width: size.width)
            let rect = CGRect(
                x: startX,
                y: 14,
                width: max(1, endX - startX),
                height: max(1, size.height - 28)
            )
            let selected = label.id == selectedLabelID
            context.fill(
                Path(roundedRect: rect, cornerRadius: 8),
                with: .color(
                    selected
                        ? Color(red: 0.729, green: 0.831, blue: 0.980).opacity(0.54)
                        : Color(red: 0.729, green: 0.831, blue: 0.980).opacity(0.30)
                )
            )
            context.stroke(
                Path(roundedRect: rect, cornerRadius: 8),
                with: .color(
                    selected
                        ? Color(red: 0.102, green: 0.306, blue: 0.847).opacity(0.88)
                        : Color(red: 0.231, green: 0.510, blue: 0.965).opacity(0.7)
                ),
                lineWidth: selected ? 1.5 : 0.8
            )

            if selected, rect.width > 42 {
                let labelText = Text("\(waveformTimeString(label.start))")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(Color(red: 0.102, green: 0.306, blue: 0.847))
                context.draw(labelText, at: CGPoint(x: rect.minX + 8, y: rect.minY + 11), anchor: .leading)
            }
        }
    }

    private func drawDragPreview(context: inout GraphicsContext, size: CGSize) {
        guard edgeDrag == nil, let dragStart, let dragCurrent, abs(dragCurrent - dragStart) >= 6 else {
            return
        }
        let rect = CGRect(
            x: min(dragStart, dragCurrent),
            y: 0,
            width: abs(dragCurrent - dragStart),
            height: size.height
        )
        context.fill(
            Path(roundedRect: rect.insetBy(dx: 0, dy: 14), cornerRadius: 8),
            with: .color(Color(red: 0.102, green: 0.306, blue: 0.847).opacity(0.20))
        )
        context.stroke(
            Path(roundedRect: rect.insetBy(dx: 0, dy: 14), cornerRadius: 8),
            with: .color(Color(red: 0.102, green: 0.306, blue: 0.847).opacity(0.75)),
            style: StrokeStyle(lineWidth: 1, dash: [5, 3])
        )
    }

    private func drawPlayhead(
        context: inout GraphicsContext,
        size: CGSize,
        time: TimeInterval
    ) {
        guard duration > 0, time >= viewStart, time <= viewEnd else {
            return
        }
        let playheadX = x(for: time, width: size.width)
        let markerSide: CGFloat = 11
        let markerHeight = markerSide * 0.866
        var marker = Path()
        marker.move(to: CGPoint(x: playheadX, y: 14 + markerHeight))
        marker.addLine(to: CGPoint(x: playheadX - markerSide / 2, y: 14))
        marker.addLine(to: CGPoint(x: playheadX + markerSide / 2, y: 14))
        marker.closeSubpath()
        context.fill(marker, with: .color(Color(red: 0.086, green: 0.502, blue: 0.286)))
        var path = Path()
        path.move(to: CGPoint(x: playheadX, y: 0))
        path.addLine(to: CGPoint(x: playheadX, y: size.height))
        context.stroke(path, with: .color(Color(red: 0.086, green: 0.502, blue: 0.286)), lineWidth: 1.5)
    }

    private var shouldInterpolatePlayhead: Bool {
        isPlaying && canInterpolatePlayhead
    }

    private func playheadTime(at date: Date) -> TimeInterval {
        guard shouldInterpolatePlayhead else {
            return currentTime
        }
        let elapsed = min(max(0, date.timeIntervalSince(playheadAnchorDate)), 0.12)
        return min(duration, currentTime + elapsed * Double(playbackRate))
    }

    private func hitTestEdge(x: CGFloat, width: CGFloat) -> EdgeDrag? {
        let tolerance: CGFloat = 7
        for label in labels {
            if abs(x - self.x(for: label.start, width: width)) <= tolerance {
                return EdgeDrag(id: label.id, edge: .start)
            }
            if abs(x - self.x(for: label.end, width: width)) <= tolerance {
                return EdgeDrag(id: label.id, edge: .end)
            }
        }
        return nil
    }

    private func hitTestLabel(x: CGFloat, width: CGFloat) -> AudioLabel? {
        labels.first {
            x >= self.x(for: $0.start, width: width)
                && x <= self.x(for: $0.end, width: width)
        }
    }

    private func x(for second: TimeInterval, width: CGFloat) -> CGFloat {
        let visibleDuration = viewEnd - viewStart
        guard visibleDuration > 0 else {
            return 0
        }
        return CGFloat((second - viewStart) / visibleDuration) * width
    }

    private func seconds(for x: CGFloat, width: CGFloat) -> TimeInterval {
        guard width > 0 else {
            return 0
        }
        return viewStart + TimeInterval(x / width) * (viewEnd - viewStart)
    }

    private struct EdgeDrag {
        enum Edge {
            case start
            case end
        }

        let id: UUID
        let edge: Edge
    }
}

private struct WaveformScrollMonitor: NSViewRepresentable {
    let viewStart: TimeInterval
    let viewEnd: TimeInterval
    let onZoom: (Double, TimeInterval) -> Void
    let onScroll: (Double) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.install(for: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.viewStart = viewStart
        context.coordinator.viewEnd = viewEnd
        context.coordinator.onZoom = onZoom
        context.coordinator.onScroll = onScroll
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    final class Coordinator {
        weak var view: NSView?
        var monitor: Any?
        var viewStart: TimeInterval = 0
        var viewEnd: TimeInterval = 0
        var onZoom: ((Double, TimeInterval) -> Void)?
        var onScroll: ((Double) -> Void)?

        func install(for view: NSView) {
            self.view = view
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self,
                      let view = self.view,
                      let window = view.window,
                      event.window === window
                else {
                    return event
                }

                let point = view.convert(event.locationInWindow, from: nil)
                guard view.bounds.contains(point), view.bounds.width > 0 else {
                    return event
                }

                let delta = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY)
                    ? event.scrollingDeltaX
                    : event.scrollingDeltaY
                let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                if modifiers.contains(.command) || modifiers.contains(.control) {
                    let ratio = min(max(0, point.x / view.bounds.width), 1)
                    let center = self.viewStart + TimeInterval(ratio) * (self.viewEnd - self.viewStart)
                    self.onZoom?(delta > 0 ? 0.8 : 1.25, center)
                } else {
                    self.onScroll?(delta / 200)
                }
                return nil
            }
        }

        func uninstall() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
            monitor = nil
        }

        deinit {
            uninstall()
        }
    }
}

private func waveformTimeString(_ seconds: TimeInterval) -> String {
    guard seconds.isFinite, seconds >= 0 else {
        return "0:00.00"
    }
    let minutes = Int(seconds) / 60
    let remainder = seconds - Double(minutes * 60)
    return String(format: "%d:%05.2f", minutes, remainder)
}
