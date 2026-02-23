import Foundation

// MARK: - CGPoint helpers

extension CGPoint {
    func distance(to other: CGPoint) -> CGFloat {
        let dx = x - other.x
        let dy = y - other.y
        return sqrt(dx * dx + dy * dy)
    }

    func midpoint(to other: CGPoint) -> CGPoint {
        CGPoint(x: (x + other.x) / 2, y: (y + other.y) / 2)
    }

    static func + (lhs: CGPoint, rhs: CGPoint) -> CGPoint {
        CGPoint(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
    }

    static func - (lhs: CGPoint, rhs: CGPoint) -> CGPoint {
        CGPoint(x: lhs.x - rhs.x, y: lhs.y - rhs.y)
    }
}

// MARK: - CGSize helpers

extension CGSize {
    var aspectRatio: CGFloat {
        guard height > 0 else { return 1 }
        return width / height
    }
}

// MARK: - CGRect helpers

extension CGRect {
    /// Returns a rect normalized so width and height are positive.
    var normalized: CGRect {
        CGRect(
            x: width < 0 ? origin.x + width : origin.x,
            y: height < 0 ? origin.y + height : origin.y,
            width: abs(width),
            height: abs(height)
        )
    }

    var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }

    /// Clamps rect to lie within `bounds`.
    func clamped(to bounds: CGRect) -> CGRect {
        let x = max(bounds.minX, min(origin.x, bounds.maxX - width))
        let y = max(bounds.minY, min(origin.y, bounds.maxY - height))
        let w = min(width, bounds.width)
        let h = min(height, bounds.height)
        return CGRect(x: x, y: y, width: w, height: h)
    }
}

// MARK: - Angle helper

func angleBetween(from: CGPoint, to: CGPoint) -> CGFloat {
    atan2(to.y - from.y, to.x - from.x)
}

/// Build a rect from two arbitrary corner points (handles any drag direction).
func rectFromDrag(start: CGPoint, end: CGPoint) -> CGRect {
    CGRect(
        x: min(start.x, end.x),
        y: min(start.y, end.y),
        width: abs(end.x - start.x),
        height: abs(end.y - start.y)
    )
}
