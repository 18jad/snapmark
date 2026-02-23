import AppKit
import CoreImage
import UniformTypeIdentifiers

// MARK: - Drag State

private enum DragState {
    case idle
    case drawingShape(startImagePoint: CGPoint)
    case drawingCrop(startImagePoint: CGPoint)
    case movingOverlay(
        overlayID: UUID,
        startImagePoint: CGPoint,
        originalFrame: CGRect,
        originalStart: CGPoint?,
        originalEnd: CGPoint?
    )
    case resizingOverlay(
        overlayID: UUID,
        handle: SelectionHandle,
        startImagePoint: CGPoint,
        originalFrame: CGRect
    )
    case panning(startViewPoint: CGPoint, originalOffset: CGPoint)
}

// MARK: - CanvasNSView

/// Custom AppKit view that handles all canvas rendering and pointer/keyboard input.
final class CanvasNSView: NSView {
    // MARK: Properties

    var viewModel: CanvasViewModel?

    private var dragState: DragState = .idle
    private var temporaryOverlay: Overlay?

    /// True while space is held for temporary grab mode.
    private var isSpaceGrabbing: Bool = false

    /// Cached blur patches keyed by overlay ID.
    private var blurCache: [UUID: NSImage] = [:]
    private var blurCacheKeys: [UUID: String] = [:]

    /// Tracks base image identity for cache invalidation.
    var lastBaseImageHash: Int = 0

    /// Active in-place text field.
    private var activeTextField: NSTextField?
    private var editingTextImagePoint: CGPoint?

    // MARK: View Config

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        wantsLayer = true
        layer?.backgroundColor = NSColor(white: 0.91, alpha: 1).cgColor
        layer?.masksToBounds = true  // Clip canvas content to bounds

        // Register for drag-and-drop
        registerForDraggedTypes([.fileURL, .tiff, .png])
    }

    // MARK: - Coordinate Conversion

    /// The scale factor that fits the image within the view, before user zoom.
    private var fitScale: CGFloat {
        guard let img = viewModel?.baseImage else { return 1 }
        let s = img.size
        guard s.width > 0, s.height > 0 else { return 1 }
        return min(bounds.width / s.width, bounds.height / s.height)
    }

    /// Total scale = fitScale * userZoom.
    private var totalScale: CGFloat {
        fitScale * (viewModel?.zoomScale ?? 1)
    }

    /// The affine transform from image coordinates to view coordinates.
    private var imageToViewTransform: CGAffineTransform {
        guard let img = viewModel?.baseImage else { return .identity }
        let s = img.size
        let ts = totalScale
        let pan = viewModel?.panOffset ?? .zero
        let tx = (bounds.width - s.width * ts) / 2 + pan.x
        let ty = (bounds.height - s.height * ts) / 2 + pan.y
        return CGAffineTransform(a: ts, b: 0, c: 0, d: ts, tx: tx, ty: ty)
    }

    private func viewToImage(_ viewPt: CGPoint) -> CGPoint {
        viewPt.applying(imageToViewTransform.inverted())
    }

    private func imageToView(_ imgPt: CGPoint) -> CGPoint {
        imgPt.applying(imageToViewTransform)
    }

    /// Converts a rect from image coords to view coords.
    private func imageRectToView(_ r: CGRect) -> CGRect {
        let origin = imageToView(r.origin)
        return CGRect(
            x: origin.x,
            y: origin.y,
            width: r.width * totalScale,
            height: r.height * totalScale
        )
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current else { return }

        drawCanvasBackground()

        guard let vm = viewModel, let baseImage = vm.baseImage else {
            drawEmptyState()
            return
        }

        ctx.saveGraphicsState()

        // Apply image→view transform
        let xform = NSAffineTransform()
        let t = imageToViewTransform
        xform.transformStruct = NSAffineTransformStruct(
            m11: t.a, m12: t.b, m21: t.c, m22: t.d, tX: t.tx, tY: t.ty
        )
        xform.concat()

        // Shadow under the image to lift it off the background
        if let shadow = NSShadow() as NSShadow? {
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
            shadow.shadowOffset = NSSize(width: 0, height: -2)
            shadow.shadowBlurRadius = 12
            shadow.set()
        }

        // Base image (respectFlipped needed in a flipped NSView)
        baseImage.draw(
            in: CGRect(origin: .zero, size: baseImage.size),
            from: .zero,
            operation: .sourceOver,
            fraction: 1.0,
            respectFlipped: true,
            hints: [.interpolation: NSNumber(value: NSImageInterpolation.high.rawValue)]
        )

        // Reset shadow so overlays don't inherit it
        NSShadow().set()

        // Blur overlays (draw blurred patches over base image)
        for overlay in vm.overlays where overlay.type == .blur {
            drawBlurOverlay(overlay)
        }

        // Vector overlays
        for overlay in vm.overlays where overlay.type != .blur {
            drawSingleOverlay(overlay)
        }

        // Temporary overlay being drawn
        if let temp = temporaryOverlay {
            if temp.type == .blur {
                drawTemporaryBlurPreview(temp)
            } else {
                drawSingleOverlay(temp)
            }
        }

        ctx.restoreGraphicsState()

        // Crop dimming (in view coords)
        if vm.selectedTool == .crop || vm.isCropActive, let cropRect = vm.cropRect {
            drawCropDimming(cropRect)
        }

        // Selection handles (in view coords) — show for any tool that places overlays
        if let selID = vm.selectedOverlayID,
           let overlay = vm.overlays.first(where: { $0.id == selID }),
           vm.selectedTool != .grab && vm.selectedTool != .crop {
            drawSelectionHandles(for: overlay)
        }
    }

    // MARK: Canvas Background

    private func drawCanvasBackground() {
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua

        // Solid neutral surface
        let bg = isDark ? NSColor(white: 0.13, alpha: 1) : NSColor(white: 0.91, alpha: 1)
        bg.setFill()
        bounds.fill()

        // Thin grid lines (only when an image is loaded)
        guard viewModel?.baseImage != nil else { return }

        let gridColor = isDark
            ? NSColor.white.withAlphaComponent(0.04)
            : NSColor.black.withAlphaComponent(0.045)
        gridColor.setStroke()

        let spacing: CGFloat = 28
        let path = NSBezierPath()
        path.lineWidth = 0.5

        // Vertical lines
        var x = bounds.minX.truncatingRemainder(dividingBy: spacing)
        if x < 0 { x += spacing }
        while x <= bounds.maxX {
            path.move(to: NSPoint(x: x, y: bounds.minY))
            path.line(to: NSPoint(x: x, y: bounds.maxY))
            x += spacing
        }

        // Horizontal lines
        var y = bounds.minY.truncatingRemainder(dividingBy: spacing)
        if y < 0 { y += spacing }
        while y <= bounds.maxY {
            path.move(to: NSPoint(x: bounds.minX, y: y))
            path.line(to: NSPoint(x: bounds.maxX, y: y))
            y += spacing
        }

        path.stroke()
    }

    // MARK: Empty State

    private func drawEmptyState() {
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua

        // Dashed drop-zone rounded rect
        let zoneSize = CGSize(width: min(380, bounds.width - 80), height: min(220, bounds.height - 60))
        let zoneRect = CGRect(
            x: (bounds.width - zoneSize.width) / 2,
            y: (bounds.height - zoneSize.height) / 2,
            width: zoneSize.width,
            height: zoneSize.height
        )

        let borderColor = isDark
            ? NSColor.white.withAlphaComponent(0.12)
            : NSColor.black.withAlphaComponent(0.10)
        borderColor.setStroke()

        let zonePath = NSBezierPath(roundedRect: zoneRect, xRadius: 16, yRadius: 16)
        zonePath.lineWidth = 1.5
        let pattern: [CGFloat] = [7, 5]
        zonePath.setLineDash(pattern, count: 2, phase: 0)
        zonePath.stroke()

        // Measure all content first so we can center the group
        let iconSize: CGFloat = 36
        let titleFont = NSFont.systemFont(ofSize: 16, weight: .medium)
        let subFont = NSFont.systemFont(ofSize: 12, weight: .regular)
        let title = "Drop an image here"
        let sub = "or press \u{2318}V to paste  \u{00B7}  \u{2318}O to open"

        let titleColor = isDark
            ? NSColor.white.withAlphaComponent(0.55)
            : NSColor.black.withAlphaComponent(0.50)
        let subColor = isDark
            ? NSColor.white.withAlphaComponent(0.30)
            : NSColor.black.withAlphaComponent(0.30)
        let iconColor = isDark
            ? NSColor.white.withAlphaComponent(0.25)
            : NSColor.black.withAlphaComponent(0.22)

        let titleAttrs: [NSAttributedString.Key: Any] = [.font: titleFont, .foregroundColor: titleColor]
        let subAttrs: [NSAttributedString.Key: Any] = [.font: subFont, .foregroundColor: subColor]
        let titleSize = (title as NSString).size(withAttributes: titleAttrs)
        let subSize = (sub as NSString).size(withAttributes: subAttrs)

        // Total content height: icon + gap + title + gap + subtitle
        let iconH = iconSize * 0.9
        let gap1: CGFloat = 12
        let gap2: CGFloat = 6
        let totalHeight = iconH + gap1 + titleSize.height + gap2 + subSize.height

        // Center the group vertically in the zone
        let contentTop = zoneRect.midY - totalHeight / 2

        // Icon — plain SF Symbol, no background
        if let iconImage = NSImage(systemSymbolName: "photo.on.rectangle.angled",
                                   accessibilityDescription: "Drop image") {
            let config = NSImage.SymbolConfiguration(pointSize: iconSize, weight: .ultraLight)
                .applying(.init(paletteColors: [iconColor]))
            let configured = iconImage.withSymbolConfiguration(config) ?? iconImage
            let iconW = iconSize * 1.2
            let iconRect = CGRect(
                x: zoneRect.midX - iconW / 2,
                y: contentTop,
                width: iconW,
                height: iconH
            )
            configured.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 1.0,
                            respectFlipped: true, hints: nil)
        }

        // Title
        let titleY = contentTop + iconH + gap1
        let titleOrigin = NSPoint(x: zoneRect.midX - titleSize.width / 2, y: titleY)
        (title as NSString).draw(at: titleOrigin, withAttributes: titleAttrs)

        // Subtitle
        let subY = titleY + titleSize.height + gap2
        let subOrigin = NSPoint(x: zoneRect.midX - subSize.width / 2, y: subY)
        (sub as NSString).draw(at: subOrigin, withAttributes: subAttrs)
    }

    // MARK: Overlay Drawing

    private func drawSingleOverlay(_ overlay: Overlay) {
        switch overlay.type {
        case .rectangle:
            drawRectangleOverlay(overlay)
        case .ellipse:
            drawEllipseOverlay(overlay)
        case .line:
            drawLineOverlay(overlay)
        case .arrow:
            drawArrowOverlay(overlay)
        case .text:
            drawTextOverlay(overlay)
        case .blur:
            break // handled separately
        }
    }

    private func drawRectangleOverlay(_ overlay: Overlay) {
        let path = NSBezierPath(
            roundedRect: overlay.frame,
            xRadius: overlay.style.cornerRadius,
            yRadius: overlay.style.cornerRadius
        )
        if overlay.style.fillColor.alphaComponent > 0 {
            overlay.style.fillColor.setFill()
            path.fill()
        }
        overlay.style.strokeColor.setStroke()
        path.lineWidth = overlay.style.strokeWidth
        path.stroke()
    }

    private func drawEllipseOverlay(_ overlay: Overlay) {
        let path = NSBezierPath(ovalIn: overlay.frame)
        if overlay.style.fillColor.alphaComponent > 0 {
            overlay.style.fillColor.setFill()
            path.fill()
        }
        overlay.style.strokeColor.setStroke()
        path.lineWidth = overlay.style.strokeWidth
        path.stroke()
    }

    private func drawLineOverlay(_ overlay: Overlay) {
        guard let start = overlay.startPoint, let end = overlay.endPoint else { return }
        let path = NSBezierPath()
        path.move(to: start)
        path.line(to: end)
        overlay.style.strokeColor.setStroke()
        path.lineWidth = overlay.style.strokeWidth
        path.lineCapStyle = .round
        path.stroke()
    }

    private func drawArrowOverlay(_ overlay: Overlay) {
        guard let start = overlay.startPoint, let end = overlay.endPoint else { return }

        // Shaft
        let path = NSBezierPath()
        path.move(to: start)
        path.line(to: end)
        overlay.style.strokeColor.setStroke()
        path.lineWidth = overlay.style.strokeWidth
        path.lineCapStyle = .round
        path.stroke()

        // Arrowhead
        let angle = angleBetween(from: start, to: end)
        let headLen = overlay.style.strokeWidth * 3.5 + 8
        let spread: CGFloat = .pi / 6

        let tip1 = CGPoint(
            x: end.x - headLen * cos(angle - spread),
            y: end.y - headLen * sin(angle - spread)
        )
        let tip2 = CGPoint(
            x: end.x - headLen * cos(angle + spread),
            y: end.y - headLen * sin(angle + spread)
        )

        let head = NSBezierPath()
        head.move(to: end)
        head.line(to: tip1)
        head.line(to: tip2)
        head.close()
        overlay.style.strokeColor.setFill()
        head.fill()
    }

    private func drawTextOverlay(_ overlay: Overlay) {
        guard let text = overlay.text, !text.isEmpty else { return }

        let font = NSFont(name: overlay.style.fontName, size: overlay.style.fontSize)
            ?? NSFont.systemFont(ofSize: overlay.style.fontSize)

        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: overlay.style.strokeColor,
        ]
        (text as NSString).draw(at: overlay.frame.origin, withAttributes: attrs)
    }

    // MARK: Blur Overlay

    private func drawBlurOverlay(_ overlay: Overlay) {
        guard let baseImage = viewModel?.baseImage else { return }
        let rect = overlay.frame
        let radius = overlay.style.blurRadius
        let cacheKey = "\(rect)|\(radius)"

        if let cached = blurCache[overlay.id], blurCacheKeys[overlay.id] == cacheKey {
            cached.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0,
                        respectFlipped: true, hints: nil)
        } else if let blurred = BlurRenderer.renderBlur(
            baseImage: baseImage,
            rect: rect,
            radius: radius
        ) {
            blurCache[overlay.id] = blurred
            blurCacheKeys[overlay.id] = cacheKey
            blurred.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0,
                         respectFlipped: true, hints: nil)
        }

        // Only show border when selected
        if overlay.id == viewModel?.selectedOverlayID {
            NSColor.controlAccentColor.setStroke()
            let border = NSBezierPath(rect: rect)
            border.lineWidth = 1.5
            let pattern: [CGFloat] = [4, 3]
            border.setLineDash(pattern, count: 2, phase: 0)
            border.stroke()
        }
    }

    /// Draws a visible preview rectangle while the user drags to define a blur region.
    private func drawTemporaryBlurPreview(_ overlay: Overlay) {
        let rect = overlay.frame

        // Semi-transparent fill so the user can see the area they're selecting
        NSColor.white.withAlphaComponent(0.15).setFill()
        rect.fill()

        // Solid border
        NSColor.controlAccentColor.withAlphaComponent(0.8).setStroke()
        let path = NSBezierPath(rect: rect)
        path.lineWidth = 1.5
        path.stroke()
    }

    // MARK: Crop Dimming

    private func drawCropDimming(_ cropRect: CGRect) {
        let viewCropRect = imageRectToView(cropRect)

        NSColor.black.withAlphaComponent(0.5).setFill()

        // Fill areas outside crop rect
        // Top
        NSRect(x: 0, y: 0, width: bounds.width, height: viewCropRect.minY).fill()
        // Bottom
        let bottomY = viewCropRect.maxY
        NSRect(x: 0, y: bottomY, width: bounds.width, height: bounds.height - bottomY).fill()
        // Left
        NSRect(x: 0, y: viewCropRect.minY, width: viewCropRect.minX, height: viewCropRect.height).fill()
        // Right
        let rightX = viewCropRect.maxX
        NSRect(x: rightX, y: viewCropRect.minY, width: bounds.width - rightX, height: viewCropRect.height).fill()

        // Crop border
        NSColor.white.setStroke()
        let border = NSBezierPath(rect: viewCropRect)
        border.lineWidth = 1.5
        let pattern: [CGFloat] = [6, 3]
        border.setLineDash(pattern, count: 2, phase: 0)
        border.stroke()
    }

    // MARK: Selection Handles

    private func drawSelectionHandles(for overlay: Overlay) {
        let rect: CGRect
        if overlay.type == .line || overlay.type == .arrow,
           let s = overlay.startPoint, let e = overlay.endPoint {
            rect = rectFromDrag(start: s, end: e)
        } else {
            rect = overlay.frame
        }

        let viewRect = imageRectToView(rect)

        // Bounding box
        NSColor.controlAccentColor.setStroke()
        let box = NSBezierPath(rect: viewRect)
        box.lineWidth = 1
        box.stroke()

        // Handles
        for handle in SelectionHandle.allCases {
            let center = handleCenter(for: handle, in: viewRect)
            let handleRect = CGRect(
                x: center.x - handleSize / 2,
                y: center.y - handleSize / 2,
                width: handleSize,
                height: handleSize
            )
            NSColor.white.setFill()
            let path = NSBezierPath(ovalIn: handleRect)
            path.fill()
            NSColor.controlAccentColor.setStroke()
            path.lineWidth = 1.5
            path.stroke()
        }
    }

    // MARK: - Mouse Events

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        finishTextEditing()

        // Double-click → zoom to fit
        if event.clickCount == 2 {
            viewModel?.zoomToFit()
            needsDisplay = true
            return
        }

        let viewPt = convert(event.locationInWindow, from: nil)
        let imagePt = viewToImage(viewPt)

        guard let vm = viewModel else { return }

        // Space-grab or Grab tool → start panning
        if isSpaceGrabbing || vm.selectedTool == .grab {
            dragState = .panning(
                startViewPoint: viewPt,
                originalOffset: vm.panOffset
            )
            refreshCursor()
            return
        }

        switch vm.selectedTool {
        case .select:
            handleSelectMouseDown(viewPt: viewPt, imagePt: imagePt)
        case .grab:
            break // handled above
        case .crop:
            guard vm.baseImage != nil else { return }
            dragState = .drawingCrop(startImagePoint: imagePt)
            vm.isCropActive = true
        case .text:
            guard vm.baseImage != nil else { return }
            handleTextMouseDown(imagePt: imagePt)
        case .blur, .rectangle, .ellipse, .line, .arrow:
            guard vm.baseImage != nil else { return }
            // Check resize handles on already-selected overlay first
            if let selID = vm.selectedOverlayID,
               let selOverlay = vm.overlays.first(where: { $0.id == selID }) {
                let selRect = selOverlay.type == .line || selOverlay.type == .arrow
                    ? selOverlay.hitRect : selOverlay.frame
                let viewRect = imageRectToView(selRect)
                if let handle = hitTestHandles(point: viewPt, rect: viewRect, viewScale: 1) {
                    dragState = .resizingOverlay(
                        overlayID: selID,
                        handle: handle,
                        startImagePoint: imagePt,
                        originalFrame: selOverlay.frame
                    )
                    needsDisplay = true
                    return
                }
            }
            // Then check for hit on existing overlays to select/move
            let tolerance = max(5.0 / totalScale, 3)
            if let hitID = hitTestOverlays(vm.overlays, at: imagePt, tolerance: tolerance) {
                vm.selectedOverlayID = hitID
                vm.syncStyleFromSelectedOverlay()
                let overlay = vm.overlays.first { $0.id == hitID }!
                dragState = .movingOverlay(
                    overlayID: hitID,
                    startImagePoint: imagePt,
                    originalFrame: overlay.frame,
                    originalStart: overlay.startPoint,
                    originalEnd: overlay.endPoint
                )
            } else {
                vm.selectedOverlayID = nil
                dragState = .drawingShape(startImagePoint: imagePt)
            }
            needsDisplay = true
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let viewPt = convert(event.locationInWindow, from: nil)
        let imagePt = viewToImage(viewPt)

        guard let vm = viewModel else { return }

        switch dragState {
        case .idle:
            break

        case .panning(let startView, let origOffset):
            let delta = viewPt - startView
            vm.panOffset = CGPoint(x: origOffset.x + delta.x, y: origOffset.y + delta.y)
            needsDisplay = true

        case .drawingShape(let start):
            updateTemporaryOverlay(from: start, to: imagePt, tool: vm.selectedTool)
            needsDisplay = true

        case .drawingCrop(let start):
            vm.cropRect = rectFromDrag(start: start, end: imagePt)
            needsDisplay = true

        case .movingOverlay(let id, let startImg, let origFrame, let origStart, let origEnd):
            let delta = imagePt - startImg
            vm.updateOverlayLive(id: id) { overlay in
                overlay.frame = CGRect(
                    x: origFrame.origin.x + delta.x,
                    y: origFrame.origin.y + delta.y,
                    width: origFrame.width,
                    height: origFrame.height
                )
                if let os = origStart {
                    overlay.startPoint = CGPoint(x: os.x + delta.x, y: os.y + delta.y)
                }
                if let oe = origEnd {
                    overlay.endPoint = CGPoint(x: oe.x + delta.x, y: oe.y + delta.y)
                }
            }
            // Invalidate blur cache when moving blur overlays
            blurCache.removeValue(forKey: id)
            blurCacheKeys.removeValue(forKey: id)
            needsDisplay = true

        case .resizingOverlay(let id, let handle, let startImg, let origFrame):
            let delta = imagePt - startImg
            let newFrame = applyHandleResize(handle: handle, delta: delta, to: origFrame)
            vm.updateOverlayLive(id: id) { overlay in
                overlay.frame = newFrame
            }
            // Invalidate blur cache so it re-renders at the new size
            blurCache.removeValue(forKey: id)
            blurCacheKeys.removeValue(forKey: id)
            needsDisplay = true
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard let vm = viewModel else {
            dragState = .idle
            return
        }

        switch dragState {
        case .idle:
            break

        case .panning:
            break // cursor updated below via refreshCursor()

        case .drawingShape:
            if let temp = temporaryOverlay {
                // Only add if it has meaningful size
                let minDim: CGFloat = 3
                if temp.frame.width >= minDim || temp.frame.height >= minDim
                    || temp.type == .line || temp.type == .arrow {
                    vm.addOverlay(temp)
                    // Invalidate blur cache if needed
                    if temp.type == .blur {
                        blurCache.removeValue(forKey: temp.id)
                    }
                }
            }
            temporaryOverlay = nil

        case .drawingCrop:
            vm.isCropActive = true

        case .movingOverlay(let id, _, let origFrame, let origStart, let origEnd):
            // Register undo for the entire move
            if let overlay = vm.overlays.first(where: { $0.id == id }) {
                var original = overlay
                original.frame = origFrame
                original.startPoint = origStart
                original.endPoint = origEnd
                vm.registerOverlayUndo(id: id, previousState: original)
            }

        case .resizingOverlay(let id, _, _, let origFrame):
            if let overlay = vm.overlays.first(where: { $0.id == id }) {
                var original = overlay
                original.frame = origFrame
                vm.registerOverlayUndo(id: id, previousState: original)
            }
        }

        dragState = .idle
        refreshCursor()
        needsDisplay = true
    }

    // MARK: Select Tool

    private func handleSelectMouseDown(viewPt: CGPoint, imagePt: CGPoint) {
        guard let vm = viewModel else { return }

        // Check handles on selected overlay first
        if let selID = vm.selectedOverlayID,
           let selOverlay = vm.overlays.first(where: { $0.id == selID }) {
            let selRect = selOverlay.type == .line || selOverlay.type == .arrow
                ? selOverlay.hitRect : selOverlay.frame
            let viewRect = imageRectToView(selRect)
            if let handle = hitTestHandles(point: viewPt, rect: viewRect, viewScale: 1) {
                dragState = .resizingOverlay(
                    overlayID: selID,
                    handle: handle,
                    startImagePoint: imagePt,
                    originalFrame: selOverlay.frame
                )
                return
            }
        }

        // Hit test overlays
        let tolerance = max(5.0 / totalScale, 3)
        if let hitID = hitTestOverlays(vm.overlays, at: imagePt, tolerance: tolerance) {
            vm.selectedOverlayID = hitID
            vm.syncStyleFromSelectedOverlay()
            let overlay = vm.overlays.first { $0.id == hitID }!
            dragState = .movingOverlay(
                overlayID: hitID,
                startImagePoint: imagePt,
                originalFrame: overlay.frame,
                originalStart: overlay.startPoint,
                originalEnd: overlay.endPoint
            )
        } else {
            vm.selectedOverlayID = nil
        }
        needsDisplay = true
    }

    // MARK: Text Tool

    private func handleTextMouseDown(imagePt: CGPoint) {
        guard let vm = viewModel else { return }
        let viewPt = imageToView(imagePt)

        let field = NSTextField()
        field.stringValue = "Text"
        field.font = NSFont.systemFont(ofSize: vm.currentStyle.fontSize * totalScale)
        field.textColor = vm.currentStyle.strokeColor
        field.backgroundColor = NSColor.white.withAlphaComponent(0.85)
        field.isBordered = false
        field.isEditable = true
        field.isBezeled = false
        field.drawsBackground = true
        field.focusRingType = .none
        field.sizeToFit()
        field.frame.origin = viewPt
        field.frame.size.width = max(field.frame.width, 80)
        field.target = self
        field.action = #selector(textFieldAction(_:))
        field.delegate = self

        addSubview(field)
        window?.makeFirstResponder(field)
        field.selectText(nil)

        activeTextField = field
        editingTextImagePoint = imagePt
    }

    @objc private func textFieldAction(_ sender: NSTextField) {
        finishTextEditing()
    }

    func finishTextEditing() {
        guard let field = activeTextField, let imgPt = editingTextImagePoint else { return }
        let text = field.stringValue

        if !text.isEmpty, let vm = viewModel {
            let font = NSFont(name: vm.currentStyle.fontName, size: vm.currentStyle.fontSize)
                ?? NSFont.systemFont(ofSize: vm.currentStyle.fontSize)
            let attrs: [NSAttributedString.Key: Any] = [.font: font]
            let textSize = (text as NSString).size(withAttributes: attrs)

            let overlay = Overlay(
                type: .text,
                frame: CGRect(origin: imgPt, size: textSize),
                style: vm.currentStyle,
                text: text
            )
            vm.addOverlay(overlay)
        }

        field.removeFromSuperview()
        activeTextField = nil
        editingTextImagePoint = nil
        needsDisplay = true
    }

    // MARK: Temporary Shape

    private func updateTemporaryOverlay(from start: CGPoint, to current: CGPoint, tool: Tool) {
        guard let vm = viewModel else { return }
        let style = vm.currentStyle

        switch tool {
        case .rectangle:
            temporaryOverlay = Overlay(
                type: .rectangle,
                frame: rectFromDrag(start: start, end: current),
                style: style
            )
        case .ellipse:
            temporaryOverlay = Overlay(
                type: .ellipse,
                frame: rectFromDrag(start: start, end: current),
                style: style
            )
        case .blur:
            var blurStyle = style
            blurStyle.blurRadius = style.blurRadius
            temporaryOverlay = Overlay(
                type: .blur,
                frame: rectFromDrag(start: start, end: current),
                style: blurStyle
            )
        case .line:
            temporaryOverlay = Overlay.lineOverlay(
                type: .line, from: start, to: current, style: style
            )
        case .arrow:
            temporaryOverlay = Overlay.lineOverlay(
                type: .arrow, from: start, to: current, style: style
            )
        default:
            break
        }
    }

    // MARK: - Keyboard Events

    override func keyDown(with event: NSEvent) {
        guard let vm = viewModel else {
            super.keyDown(with: event)
            return
        }

        switch event.keyCode {
        case 51, 117: // Delete, Forward Delete
            vm.deleteSelectedOverlay()
            needsDisplay = true
        case 36, 76: // Return, Enter — apply crop if active
            if vm.isCropActive, vm.cropRect != nil {
                vm.commitCrop()
                needsDisplay = true
                return
            }
        case 53: // Escape
            if vm.isCropActive {
                vm.cancelCrop()
            }
            vm.selectedOverlayID = nil
            temporaryOverlay = nil
            needsDisplay = true
        default:
            // Tool shortcuts (only when not editing text)
            if activeTextField == nil, let chars = event.charactersIgnoringModifiers?.lowercased() {
                let newTool: Tool?
                switch chars {
                case "v": newTool = .select
                case "h": newTool = .grab
                case "c": newTool = .crop
                case "b": newTool = .blur
                case "t": newTool = .text
                case "a": newTool = .arrow
                case "r": newTool = .rectangle
                case "e": newTool = .ellipse
                case "l": newTool = .line
                default: newTool = nil; super.keyDown(with: event)
                }
                if let tool = newTool {
                    // Cancel active crop when switching away from crop tool
                    if vm.isCropActive && tool != .crop {
                        vm.cancelCrop()
                    }
                    vm.selectedTool = tool
                }
            } else {
                super.keyDown(with: event)
            }
        }
    }

    override func flagsChanged(with event: NSEvent) {
        // No modifier flags needed for space; space is handled differently.
        super.flagsChanged(with: event)
    }

    // Space bar for temporary grab — use a monitor since keyDown doesn't fire reliably for space.
    private var spaceMonitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        if window != nil, spaceMonitor == nil {
            spaceMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) {
                [weak self] event in
                guard let self = self, self.window?.firstResponder === self else { return event }
                guard event.keyCode == 49 else { return event } // Space

                if event.type == .keyDown {
                    if !self.isSpaceGrabbing {
                        self.isSpaceGrabbing = true
                        self.refreshCursor()
                    }
                } else {
                    self.isSpaceGrabbing = false
                    self.refreshCursor()
                }
                return nil // consume space so it doesn't type into fields
            }
        } else if window == nil, let monitor = spaceMonitor {
            NSEvent.removeMonitor(monitor)
            spaceMonitor = nil
            isSpaceGrabbing = false
        }
    }

    deinit {
        if let monitor = spaceMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    // MARK: - Scroll / Zoom (Figma-like)

    override func scrollWheel(with event: NSEvent) {
        guard let vm = viewModel else { return }
        let viewPt = convert(event.locationInWindow, from: nil)

        if event.modifierFlags.contains(.command) || event.modifierFlags.contains(.control) {
            // Cmd+scroll / Ctrl+scroll → zoom toward cursor
            let delta = event.scrollingDeltaY
            let factor: CGFloat = delta > 0 ? 1.03 : 0.97
            let steps = abs(delta) / 2
            let totalFactor = pow(factor, min(steps, 10))
            zoomAtPoint(by: totalFactor, viewPoint: viewPt)
        } else if event.hasPreciseScrollingDeltas {
            // Trackpad two-finger scroll → pan (Figma behavior)
            vm.panOffset = CGPoint(
                x: vm.panOffset.x + event.scrollingDeltaX,
                y: vm.panOffset.y + event.scrollingDeltaY
            )
        } else {
            // Mouse scroll wheel (discrete) → zoom toward cursor
            let delta = event.scrollingDeltaY
            let factor: CGFloat = delta > 0 ? 1.15 : (1 / 1.15)
            zoomAtPoint(by: factor, viewPoint: viewPt)
        }
        needsDisplay = true
    }

    override func magnify(with event: NSEvent) {
        // Trackpad pinch → zoom centered on gesture midpoint
        let viewPt = convert(event.locationInWindow, from: nil)
        let factor = 1 + event.magnification
        zoomAtPoint(by: factor, viewPoint: viewPt)
        needsDisplay = true
    }

    /// Zoom by `factor` keeping the point under `viewPoint` fixed on screen.
    /// This is what makes zoom feel like Figma — the content under your cursor doesn't drift.
    private func zoomAtPoint(by factor: CGFloat, viewPoint: CGPoint) {
        guard let vm = viewModel else { return }
        let oldZoom = vm.zoomScale
        let newZoom = max(0.05, min(20.0, oldZoom * factor))
        guard newZoom != oldZoom else { return }

        // The math: we want the image point under the cursor to stay at the same
        // view position before and after the zoom change.
        //
        // viewPt = imageCenter_in_view + panOffset + (imagePt - imageSize/2) * fitScale * zoom
        //
        // Keeping viewPt constant while changing zoom requires adjusting panOffset:
        let viewCenter = CGPoint(x: bounds.midX, y: bounds.midY)
        let ratio = 1 - newZoom / oldZoom
        let dx = (viewPoint.x - viewCenter.x - vm.panOffset.x) * ratio
        let dy = (viewPoint.y - viewCenter.y - vm.panOffset.y) * ratio

        vm.zoomScale = newZoom
        vm.panOffset = CGPoint(x: vm.panOffset.x + dx, y: vm.panOffset.y + dy)
    }

    // MARK: - Cursor (centralized — no push/pop)

    /// Single source of truth: what cursor should be showing right now?
    private var desiredCursor: NSCursor {
        // 1. Active pan drag always wins
        if case .panning = dragState {
            return .closedHand
        }
        // 2. Space held OR grab tool selected → open hand
        if isSpaceGrabbing || viewModel?.selectedTool == .grab {
            return .openHand
        }
        // 3. Default
        return .arrow
    }

    override func resetCursorRects() {
        discardCursorRects()
        addCursorRect(bounds, cursor: desiredCursor)
    }

    /// Call whenever any state that affects the cursor changes.
    private func refreshCursor() {
        window?.invalidateCursorRects(for: self)
        desiredCursor.set()  // immediate update (cursor rects only apply on mouse move)
    }

    /// Called by the NSViewRepresentable bridge on every SwiftUI update.
    func updateCursorForTool() {
        refreshCursor()
    }

    // MARK: - Drag & Drop

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: [
            .urlReadingContentsConformToTypes: [UTType.image.identifier]
        ]) {
            return .copy
        }
        return []
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingContentsConformToTypes: [UTType.image.identifier]
        ]) as? [URL] else {
            return false
        }
        viewModel?.loadDroppedImage(from: urls)
        needsDisplay = true
        return true
    }

    // MARK: - Accessibility

    override func accessibilityRole() -> NSAccessibility.Role? {
        .group
    }

    override func accessibilityLabel() -> String? {
        "Image editing canvas"
    }

    // MARK: - Cache Invalidation

    func invalidateBlurCache() {
        blurCache.removeAll()
        blurCacheKeys.removeAll()
    }
}

// MARK: - NSTextFieldDelegate

extension CanvasNSView: NSTextFieldDelegate {
    func controlTextDidEndEditing(_ obj: Notification) {
        finishTextEditing()
    }
}
