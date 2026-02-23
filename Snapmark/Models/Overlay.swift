import AppKit
import Foundation

// MARK: - Overlay Type

enum OverlayType: String {
    case rectangle
    case ellipse
    case line
    case arrow
    case text
    case blur
}

// MARK: - Overlay Style

struct OverlayStyle {
    var strokeColor: NSColor = .systemRed
    var fillColor: NSColor = .clear
    var strokeWidth: CGFloat = 2
    var fontSize: CGFloat = 24
    var fontName: String = ".AppleSystemUIFont"
    var blurRadius: CGFloat = 15
    var cornerRadius: CGFloat = 0

    static let `default` = OverlayStyle()
}

// MARK: - Overlay

/// A single annotation overlay on the canvas (shape, text, blur region, etc.)
struct Overlay: Identifiable {
    let id: UUID
    var type: OverlayType
    var frame: CGRect
    var style: OverlayStyle
    var text: String?

    /// For line/arrow overlays, the start and end points.
    var startPoint: CGPoint?
    var endPoint: CGPoint?

    init(
        id: UUID = UUID(),
        type: OverlayType,
        frame: CGRect,
        style: OverlayStyle = .default,
        text: String? = nil
    ) {
        self.id = id
        self.type = type
        self.frame = frame
        self.style = style
        self.text = text
    }

    /// Create a line or arrow overlay from two points.
    static func lineOverlay(
        type: OverlayType,
        from start: CGPoint,
        to end: CGPoint,
        style: OverlayStyle = .default
    ) -> Overlay {
        let frame = CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
        var overlay = Overlay(type: type, frame: frame, style: style)
        overlay.startPoint = start
        overlay.endPoint = end
        return overlay
    }

    /// Bounding rect for hit testing (accounts for line/arrow endpoints).
    var hitRect: CGRect {
        if let s = startPoint, let e = endPoint {
            let minX = min(s.x, e.x) - style.strokeWidth
            let minY = min(s.y, e.y) - style.strokeWidth
            let maxX = max(s.x, e.x) + style.strokeWidth
            let maxY = max(s.y, e.y) + style.strokeWidth
            return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        }
        return frame.insetBy(dx: -style.strokeWidth, dy: -style.strokeWidth)
    }
}
