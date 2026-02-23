import Foundation

/// Identifies one of eight resize handles around a selection.
enum SelectionHandle: Int, CaseIterable {
    case topLeft, topCenter, topRight
    case middleLeft, middleRight
    case bottomLeft, bottomCenter, bottomRight
}

/// Hit-test radius for handles.
let handleSize: CGFloat = 8
let handleHitRadius: CGFloat = 10

/// Returns the center point of a handle relative to a bounding rect (in image coordinates).
func handleCenter(for handle: SelectionHandle, in rect: CGRect) -> CGPoint {
    switch handle {
    case .topLeft:      return CGPoint(x: rect.minX, y: rect.minY)
    case .topCenter:    return CGPoint(x: rect.midX, y: rect.minY)
    case .topRight:     return CGPoint(x: rect.maxX, y: rect.minY)
    case .middleLeft:   return CGPoint(x: rect.minX, y: rect.midY)
    case .middleRight:  return CGPoint(x: rect.maxX, y: rect.midY)
    case .bottomLeft:   return CGPoint(x: rect.minX, y: rect.maxY)
    case .bottomCenter: return CGPoint(x: rect.midX, y: rect.maxY)
    case .bottomRight:  return CGPoint(x: rect.maxX, y: rect.maxY)
    }
}

/// Test whether `point` is near a handle. Returns the handle if hit.
func hitTestHandles(point: CGPoint, rect: CGRect, viewScale: CGFloat) -> SelectionHandle? {
    let radius = handleHitRadius / viewScale
    for handle in SelectionHandle.allCases {
        let center = handleCenter(for: handle, in: rect)
        if point.distance(to: center) <= radius {
            return handle
        }
    }
    return nil
}

/// Apply a handle drag delta to a rect.
func applyHandleResize(
    handle: SelectionHandle,
    delta: CGPoint,
    to rect: CGRect,
    minSize: CGFloat = 4
) -> CGRect {
    var r = rect
    switch handle {
    case .topLeft:
        r.origin.x += delta.x
        r.origin.y += delta.y
        r.size.width -= delta.x
        r.size.height -= delta.y
    case .topCenter:
        r.origin.y += delta.y
        r.size.height -= delta.y
    case .topRight:
        r.size.width += delta.x
        r.origin.y += delta.y
        r.size.height -= delta.y
    case .middleLeft:
        r.origin.x += delta.x
        r.size.width -= delta.x
    case .middleRight:
        r.size.width += delta.x
    case .bottomLeft:
        r.origin.x += delta.x
        r.size.width -= delta.x
        r.size.height += delta.y
    case .bottomCenter:
        r.size.height += delta.y
    case .bottomRight:
        r.size.width += delta.x
        r.size.height += delta.y
    }
    // Enforce minimum size
    if r.size.width < minSize {
        r.size.width = minSize
    }
    if r.size.height < minSize {
        r.size.height = minSize
    }
    return r
}

/// Hit-test overlays back-to-front, returning the ID of the topmost overlay whose
/// bounding rect contains `imagePoint`.
func hitTestOverlays(_ overlays: [Overlay], at imagePoint: CGPoint, tolerance: CGFloat) -> UUID? {
    for overlay in overlays.reversed() {
        switch overlay.type {
        case .line, .arrow:
            if let s = overlay.startPoint, let e = overlay.endPoint {
                let dist = distanceFromPointToSegment(point: imagePoint, segStart: s, segEnd: e)
                if dist <= tolerance {
                    return overlay.id
                }
            }
        default:
            let expandedRect = overlay.frame.insetBy(dx: -tolerance, dy: -tolerance)
            if expandedRect.contains(imagePoint) {
                return overlay.id
            }
        }
    }
    return nil
}

/// Distance from a point to a line segment.
func distanceFromPointToSegment(point: CGPoint, segStart: CGPoint, segEnd: CGPoint) -> CGFloat {
    let dx = segEnd.x - segStart.x
    let dy = segEnd.y - segStart.y
    let lenSq = dx * dx + dy * dy
    guard lenSq > 0 else { return point.distance(to: segStart) }

    var t = ((point.x - segStart.x) * dx + (point.y - segStart.y) * dy) / lenSq
    t = max(0, min(1, t))

    let proj = CGPoint(x: segStart.x + t * dx, y: segStart.y + t * dy)
    return point.distance(to: proj)
}
