import AppKit
import CoreGraphics

/// Composites the final image: base + blur + overlays + crop.
enum ExportRenderer {
    static func render(viewModel: CanvasViewModel) -> NSImage? {
        guard let baseImage = viewModel.baseImage else { return nil }
        let imageSize = baseImage.size

        // Compute a canvas that covers the base image AND all overlays
        var canvasRect = CGRect(origin: .zero, size: imageSize)
        for overlay in viewModel.overlays {
            let overlayRect: CGRect
            if overlay.type == .line || overlay.type == .arrow,
               let s = overlay.startPoint, let e = overlay.endPoint {
                // Lines/arrows: use endpoints + stroke padding
                let pad = overlay.style.strokeWidth * 3 + 10
                let minX = min(s.x, e.x) - pad
                let minY = min(s.y, e.y) - pad
                let maxX = max(s.x, e.x) + pad
                let maxY = max(s.y, e.y) + pad
                overlayRect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
            } else {
                // Shapes, text, blur: use frame + stroke padding
                let pad = overlay.style.strokeWidth / 2
                overlayRect = overlay.frame.insetBy(dx: -pad, dy: -pad)
            }
            canvasRect = canvasRect.union(overlayRect)
        }

        // If there's a crop, use that instead (crop already clips to intent)
        let exportRect: CGRect
        let outputSize: CGSize
        if let cropRect = viewModel.cropRect, cropRect.width > 0, cropRect.height > 0 {
            exportRect = cropRect
            outputSize = cropRect.size
        } else {
            exportRect = canvasRect
            outputSize = canvasRect.size
        }

        guard outputSize.width > 0, outputSize.height > 0 else { return nil }

        let result = NSImage(size: outputSize, flipped: true) { _ in
            let ctx = NSGraphicsContext.current!
            ctx.imageInterpolation = .high

            // Translate so export region maps to output origin
            let xform = NSAffineTransform()
            xform.translateX(by: -exportRect.origin.x, yBy: -exportRect.origin.y)
            xform.concat()

            // 1. Draw base image
            baseImage.draw(
                in: CGRect(origin: .zero, size: imageSize),
                from: .zero,
                operation: .sourceOver,
                fraction: 1.0,
                respectFlipped: true,
                hints: nil
            )

            // 2. Draw blur overlays
            for overlay in viewModel.overlays where overlay.type == .blur {
                if let blurred = BlurRenderer.renderBlur(
                    baseImage: baseImage,
                    rect: overlay.frame,
                    radius: overlay.style.blurRadius
                ) {
                    blurred.draw(
                        in: overlay.frame,
                        from: .zero,
                        operation: .sourceOver,
                        fraction: 1.0,
                        respectFlipped: true,
                        hints: nil
                    )
                }
            }

            // 3. Draw vector overlays
            for overlay in viewModel.overlays where overlay.type != .blur {
                ExportRenderer.drawOverlay(overlay)
            }

            return true
        }

        return result
    }

    // MARK: - Overlay Drawing (for export)

    /// Public entry point so commitCrop can reuse overlay drawing.
    static func drawOverlayPublic(_ overlay: Overlay) {
        drawOverlay(overlay)
    }

    private static func drawOverlay(_ overlay: Overlay) {
        switch overlay.type {
        case .rectangle:
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

        case .ellipse:
            let path = NSBezierPath(ovalIn: overlay.frame)
            if overlay.style.fillColor.alphaComponent > 0 {
                overlay.style.fillColor.setFill()
                path.fill()
            }
            overlay.style.strokeColor.setStroke()
            path.lineWidth = overlay.style.strokeWidth
            path.stroke()

        case .line:
            guard let start = overlay.startPoint, let end = overlay.endPoint else { return }
            let path = NSBezierPath()
            path.move(to: start)
            path.line(to: end)
            overlay.style.strokeColor.setStroke()
            path.lineWidth = overlay.style.strokeWidth
            path.lineCapStyle = .round
            path.stroke()

        case .arrow:
            guard let start = overlay.startPoint, let end = overlay.endPoint else { return }
            let path = NSBezierPath()
            path.move(to: start)
            path.line(to: end)
            overlay.style.strokeColor.setStroke()
            path.lineWidth = overlay.style.strokeWidth
            path.lineCapStyle = .round
            path.stroke()

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

        case .text:
            guard let text = overlay.text, !text.isEmpty else { return }
            let font = NSFont(name: overlay.style.fontName, size: overlay.style.fontSize)
                ?? NSFont.systemFont(ofSize: overlay.style.fontSize)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: overlay.style.strokeColor,
            ]
            (text as NSString).draw(at: overlay.frame.origin, withAttributes: attrs)

        case .blur:
            break
        }
    }
}
