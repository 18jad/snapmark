import SwiftUI

/// Bridges the AppKit CanvasNSView into SwiftUI.
struct CanvasRepresentable: NSViewRepresentable {
    @ObservedObject var viewModel: CanvasViewModel

    func makeNSView(context: Context) -> CanvasNSView {
        let view = CanvasNSView(frame: .zero)
        view.viewModel = viewModel
        return view
    }

    func updateNSView(_ nsView: CanvasNSView, context: Context) {
        nsView.viewModel = viewModel

        // Invalidate blur cache when base image changes
        let currentHash = viewModel.baseImage?.hashValue ?? 0
        if nsView.lastBaseImageHash != currentHash {
            nsView.invalidateBlurCache()
            nsView.lastBaseImageHash = currentHash
        }

        // Update cursor when tool changes (e.g. grab tool shows open hand)
        nsView.updateCursorForTool()

        nsView.needsDisplay = true
    }
}
