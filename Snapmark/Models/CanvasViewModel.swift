import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

/// Central view model holding all canvas/document state.
/// SwiftUI views observe this; the AppKit canvas reads/writes it directly.
final class CanvasViewModel: ObservableObject {
    // MARK: - Document State

    @Published var baseImage: NSImage?
    @Published var overlays: [Overlay] = []
    @Published var cropRect: CGRect?
    @Published var isCropActive: Bool = false

    // MARK: - Tool State

    @Published var selectedTool: Tool = .select
    @Published var selectedOverlayID: UUID?

    /// Style template applied to newly created overlays.
    @Published var currentStyle: OverlayStyle = .default

    // MARK: - View State

    @Published var zoomScale: CGFloat = 1.0
    @Published var panOffset: CGPoint = .zero

    // MARK: - Panel Visibility

    @Published var showInspector: Bool = true
    @Published var showToolbar: Bool = true

    // MARK: - Canvas Refresh Trigger

    /// Incremented to force the NSView to redraw.
    @Published var canvasRevision: UInt = 0

    // MARK: - Undo

    let undoManager = UndoManager()

    // MARK: - Computed Properties

    var imageSize: CGSize {
        baseImage?.size ?? CGSize(width: 800, height: 600)
    }

    var selectedOverlay: Overlay? {
        guard let id = selectedOverlayID else { return nil }
        return overlays.first { $0.id == id }
    }

    var canUndo: Bool { undoManager.canUndo }
    var canRedo: Bool { undoManager.canRedo }

    // MARK: - Image Import

    func importImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, .png, .jpeg, .tiff, .bmp, .gif]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let image = NSImage(contentsOf: url) else { return }
        setBaseImage(image)
    }

    func setBaseImage(_ image: NSImage) {
        let oldImage = baseImage
        let oldOverlays = overlays
        let oldCrop = cropRect

        baseImage = image
        overlays = []
        cropRect = nil
        isCropActive = false
        selectedOverlayID = nil
        zoomScale = 1.0
        panOffset = .zero
        bumpRevision()

        undoManager.registerUndo(withTarget: self) { target in
            target.restoreDocumentState(image: oldImage, overlays: oldOverlays, crop: oldCrop)
        }
    }

    /// Restores full document state and registers reverse undo for redo support.
    private func restoreDocumentState(image: NSImage?, overlays newOverlays: [Overlay], crop: CGRect?) {
        let prevImage = baseImage
        let prevOverlays = overlays
        let prevCrop = cropRect

        baseImage = image
        overlays = newOverlays
        cropRect = crop
        isCropActive = false
        selectedOverlayID = nil
        bumpRevision()

        undoManager.registerUndo(withTarget: self) { target in
            target.restoreDocumentState(image: prevImage, overlays: prevOverlays, crop: prevCrop)
        }
    }

    func pasteImage() {
        let pb = NSPasteboard.general
        // Try common image types
        if let tiff = pb.data(forType: .tiff), let img = NSImage(data: tiff) {
            setBaseImage(img)
            return
        }
        if let png = pb.data(forType: .png), let img = NSImage(data: png) {
            setBaseImage(img)
            return
        }
        // Try file URLs
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingContentsConformToTypes: [UTType.image.identifier]
        ]) as? [URL], let url = urls.first, let img = NSImage(contentsOf: url) {
            setBaseImage(img)
        }
    }

    func loadDroppedImage(from urls: [URL]) {
        guard let url = urls.first, let image = NSImage(contentsOf: url) else { return }
        setBaseImage(image)
    }

    // MARK: - Overlay Management

    func addOverlay(_ overlay: Overlay) {
        performInsertOverlay(overlay)
    }

    func removeOverlay(id: UUID) {
        guard let overlay = overlays.first(where: { $0.id == id }) else { return }
        performRemoveOverlay(overlay)
    }

    /// Insert overlay and register undo (remove). Redo calls insert again.
    private func performInsertOverlay(_ overlay: Overlay) {
        overlays.append(overlay)
        selectedOverlayID = overlay.id
        bumpRevision()

        undoManager.registerUndo(withTarget: self) { target in
            target.performRemoveOverlay(overlay)
        }
    }

    /// Remove overlay and register undo (re-insert). Redo calls remove again.
    private func performRemoveOverlay(_ overlay: Overlay) {
        overlays.removeAll { $0.id == overlay.id }
        if selectedOverlayID == overlay.id { selectedOverlayID = nil }
        bumpRevision()

        undoManager.registerUndo(withTarget: self) { target in
            target.performInsertOverlay(overlay)
        }
    }

    /// Update an overlay and register an undo action with the previous state.
    func updateOverlay(id: UUID, transform: (inout Overlay) -> Void) {
        guard let index = overlays.firstIndex(where: { $0.id == id }) else { return }
        let old = overlays[index]
        transform(&overlays[index])
        bumpRevision()

        undoManager.registerUndo(withTarget: self) { target in
            target.setOverlayState(id: id, state: old)
        }
    }

    /// Set an overlay to a specific state and register the reverse for redo.
    private func setOverlayState(id: UUID, state: Overlay) {
        guard let index = overlays.firstIndex(where: { $0.id == id }) else { return }
        let previous = overlays[index]
        overlays[index] = state
        bumpRevision()

        undoManager.registerUndo(withTarget: self) { target in
            target.setOverlayState(id: id, state: previous)
        }
    }

    /// Lightweight update during live drag (no undo registration).
    func updateOverlayLive(id: UUID, transform: (inout Overlay) -> Void) {
        guard let index = overlays.firstIndex(where: { $0.id == id }) else { return }
        transform(&overlays[index])
        bumpRevision()
    }

    /// Register undo for an overlay that was modified via `updateOverlayLive`.
    func registerOverlayUndo(id: UUID, previousState: Overlay) {
        let current = overlays.first { $0.id == id }
        undoManager.registerUndo(withTarget: self) { target in
            target.setOverlayState(id: id, state: previousState)
        }
    }

    func deleteSelectedOverlay() {
        guard let id = selectedOverlayID else { return }
        removeOverlay(id: id)
    }

    // MARK: - Crop

    func commitCrop() {
        guard let image = baseImage, let crop = cropRect,
              crop.width > 1, crop.height > 1 else {
            cancelCrop()
            return
        }

        // Render a flattened composite of image + all overlays within the crop rect.
        // This handles overlays that extend outside the base image bounds.
        let croppedImage = NSImage(size: crop.size, flipped: true) { _ in
            guard let ctx = NSGraphicsContext.current else { return false }
            ctx.imageInterpolation = .high

            // Translate so crop origin maps to (0,0)
            let xform = NSAffineTransform()
            xform.translateX(by: -crop.origin.x, yBy: -crop.origin.y)
            xform.concat()

            // Draw base image
            image.draw(
                in: CGRect(origin: .zero, size: image.size),
                from: .zero,
                operation: .sourceOver,
                fraction: 1.0,
                respectFlipped: true,
                hints: nil
            )

            // Draw blur overlays
            for overlay in self.overlays where overlay.type == .blur {
                if let blurred = BlurRenderer.renderBlur(
                    baseImage: image,
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

            // Draw vector overlays
            for overlay in self.overlays where overlay.type != .blur {
                ExportRenderer.drawOverlayPublic(overlay)
            }

            return true
        }

        // Snapshot for undo
        let oldImage = image
        let oldOverlays = overlays

        // Apply — the crop flattens everything into a new base image, overlays are baked in
        baseImage = croppedImage
        overlays = []
        cropRect = nil
        isCropActive = false
        selectedOverlayID = nil
        selectedTool = .select
        zoomScale = 1.0
        panOffset = .zero
        bumpRevision()

        // Register undo
        undoManager.registerUndo(withTarget: self) { target in
            target.restoreDocumentState(image: oldImage, overlays: oldOverlays, crop: nil)
        }
    }

    func cancelCrop() {
        let oldCrop = cropRect
        cropRect = nil
        isCropActive = false
        bumpRevision()

        if oldCrop != nil {
            undoManager.registerUndo(withTarget: self) { target in
                target.cropRect = oldCrop
                target.bumpRevision()
            }
        }
    }

    // MARK: - Zoom

    func zoomIn() {
        zoomScale = min(zoomScale * 1.25, 10.0)
    }

    func zoomOut() {
        zoomScale = max(zoomScale / 1.25, 0.1)
    }

    func zoomToFit() {
        zoomScale = 1.0
        panOffset = .zero
    }

    // MARK: - Export

    func copyToClipboard() {
        guard let image = renderFinalImage() else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([image])
    }

    func saveToFile() {
        guard let image = renderFinalImage() else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png, .jpeg]
        panel.nameFieldStringValue = "Snapmark Export.png"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        guard let tiffData = image.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData)
        else { return }

        let isPNG = url.pathExtension.lowercased() != "jpg"
            && url.pathExtension.lowercased() != "jpeg"

        let data: Data?
        if isPNG {
            data = bitmapRep.representation(using: .png, properties: [:])
        } else {
            data = bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: 0.9])
        }

        try? data?.write(to: url)
    }

    func renderFinalImage() -> NSImage? {
        ExportRenderer.render(viewModel: self)
    }

    // MARK: - Undo / Redo

    func undo() { undoManager.undo(); bumpRevision() }
    func redo() { undoManager.redo(); bumpRevision() }

    // MARK: - Style Sync

    /// When a style property changes in the inspector, push it to the selected overlay.
    func syncStyleToSelectedOverlay() {
        guard let id = selectedOverlayID else { return }
        updateOverlay(id: id) { overlay in
            overlay.style = self.currentStyle
        }
    }

    /// When an overlay is selected, pull its style into currentStyle for the inspector.
    func syncStyleFromSelectedOverlay() {
        guard let overlay = selectedOverlay else { return }
        currentStyle = overlay.style
    }

    // MARK: - Helpers

    func bumpRevision() {
        canvasRevision &+= 1
    }

}
