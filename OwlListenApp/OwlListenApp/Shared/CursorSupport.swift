import AppKit
import SwiftUI

struct HoverCursor: ViewModifier {
    let cursor: NSCursor

    func body(content: Content) -> some View {
        content.overlay {
            CursorRectView(cursor: cursor)
        }
    }
}

private struct CursorRectView: NSViewRepresentable {
    let cursor: NSCursor

    func makeNSView(context: Context) -> CursorNSView {
        CursorNSView(cursor: cursor)
    }

    func updateNSView(_ nsView: CursorNSView, context: Context) {
        nsView.cursor = cursor
    }
}

private final class CursorNSView: NSView {
    var cursor: NSCursor {
        didSet {
            guard oldValue !== cursor else {
                return
            }
            invalidateWindowCursorRects()
        }
    }

    init(cursor: NSCursor) {
        self.cursor = cursor
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        invalidateWindowCursorRects()
    }

    override func layout() {
        super.layout()
        invalidateWindowCursorRects()
    }

    override func resetCursorRects() {
        guard let contentView = window?.contentView else {
            return
        }
        contentView.addCursorRect(convert(bounds, to: contentView), cursor: cursor)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    private func invalidateWindowCursorRects() {
        guard let contentView = window?.contentView else {
            return
        }
        window?.invalidateCursorRects(for: contentView)
        window?.invalidateCursorRects(for: self)
    }
}
