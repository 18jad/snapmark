import SwiftUI

/// Right panel showing properties for the selected tool/overlay.
struct InspectorView: View {
    @ObservedObject var viewModel: CanvasViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header pinned outside scroll, divider edge-to-edge
            inspectorHeader
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            Divider()

            // Scrollable content
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    inspectorContent
                    Spacer()
                }
                .padding(12)
            }
        }
        .frame(width: 220)
        .background(.ultraThinMaterial)
    }

    // MARK: - Header

    @ViewBuilder
    private var inspectorHeader: some View {
        if let overlay = viewModel.selectedOverlay {
            Label(overlay.type.rawValue.capitalized, systemImage: iconForType(overlay.type))
                .font(.subheadline.weight(.medium))
                .foregroundColor(.primary)
        } else {
            Label(viewModel.selectedTool.displayName, systemImage: viewModel.selectedTool.sfSymbol)
                .font(.subheadline.weight(.medium))
                .foregroundColor(.primary)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var inspectorContent: some View {
        if viewModel.selectedOverlay != nil,
           viewModel.selectedTool != .crop && viewModel.selectedTool != .grab {
            selectedOverlayInspector
        } else {
            switch viewModel.selectedTool {
            case .grab:
                imageInfoInspector
            case .crop:
                cropInspector
            case .text:
                textStyleInspector
            case .blur:
                blurInspector
            case .select:
                imageInfoInspector
            default:
                shapeStyleInspector
            }
        }
    }

    // MARK: - Image Info

    @ViewBuilder
    private var imageInfoInspector: some View {
        if let img = viewModel.baseImage {
            propertyRow("Width", "\(Int(img.size.width)) px")
            propertyRow("Height", "\(Int(img.size.height)) px")
            propertyRow("Zoom", "\(Int(viewModel.zoomScale * 100))%")
        } else {
            Text("No image loaded")
                .foregroundColor(.secondary)
                .font(.caption)
        }
    }

    // MARK: - Crop Inspector

    @ViewBuilder
    private var cropInspector: some View {
        if let crop = viewModel.cropRect {
            HStack(spacing: 8) {
                compactValue("X", "\(Int(crop.origin.x))")
                compactValue("Y", "\(Int(crop.origin.y))")
            }
            HStack(spacing: 8) {
                compactValue("W", "\(Int(crop.width))")
                compactValue("H", "\(Int(crop.height))")
            }

            VStack(spacing: 6) {
                Button(action: { viewModel.commitCrop() }) {
                    Text("Apply Crop")
                        .font(.caption.weight(.medium))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button(action: { viewModel.cancelCrop() }) {
                    Text("Cancel")
                        .font(.caption)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.top, 4)

            Text("\u{21A9} Enter to apply \u{00B7} Esc to cancel")
                .font(.caption2)
                .foregroundColor(.secondary.opacity(0.6))
        } else {
            hintText("Drag on the canvas to define a crop region.")
        }
    }

    // MARK: - Shape Style Inspector

    @ViewBuilder
    private var shapeStyleInspector: some View {
        styleSection
    }

    // MARK: - Text Style Inspector

    @ViewBuilder
    private var textStyleInspector: some View {
        sliderRow("Size", value: $viewModel.currentStyle.fontSize, range: 8...200, step: 1)
        colorRow("Color", binding: strokeColorBinding)
    }

    // MARK: - Blur Inspector

    @ViewBuilder
    private var blurInspector: some View {
        sliderRow("Radius", value: $viewModel.currentStyle.blurRadius, range: 1...20, step: 1)
        hintText("Drag on canvas to blur a region.")
    }

    // MARK: - Selected Overlay Inspector

    @ViewBuilder
    private var selectedOverlayInspector: some View {
        if let overlay = viewModel.selectedOverlay {
            switch overlay.type {
            case .text:
                textOverlayInspector
            case .blur:
                blurOverlayInspector
            default:
                styleSection
            }

            Divider()

            Button(role: .destructive) {
                viewModel.deleteSelectedOverlay()
            } label: {
                Label("Delete", systemImage: "trash")
                    .font(.caption)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    @ViewBuilder
    private var textOverlayInspector: some View {
        if let selID = viewModel.selectedOverlayID,
           let index = viewModel.overlays.firstIndex(where: { $0.id == selID }) {
            VStack(alignment: .leading, spacing: 4) {
                sectionLabel("Text")
                TextField("Text", text: Binding(
                    get: { viewModel.overlays[index].text ?? "" },
                    set: { newVal in
                        viewModel.updateOverlay(id: selID) { overlay in
                            overlay.text = newVal
                            let font = NSFont(name: overlay.style.fontName, size: overlay.style.fontSize)
                                ?? NSFont.systemFont(ofSize: overlay.style.fontSize)
                            let size = (newVal as NSString).size(withAttributes: [.font: font])
                            overlay.frame.size = size
                        }
                    }
                ))
                .textFieldStyle(.roundedBorder)
                .font(.caption)
            }
        }

        sliderRow("Size", value: fontSizeBinding, range: 8...200, step: 1)
        colorRow("Color", binding: strokeColorBinding)
    }

    @ViewBuilder
    private var blurOverlayInspector: some View {
        sliderRow("Radius", value: blurRadiusBinding, range: 1...20, step: 1)
    }

    // MARK: - Shared Style Section

    @ViewBuilder
    private var styleSection: some View {
        colorRow("Stroke", binding: strokeColorBinding)
        sliderRow("Width", value: strokeWidthBinding, range: 1...20, step: 0.5)
        colorRow("Fill", binding: fillColorBinding, supportsOpacity: true)

        if viewModel.selectedTool == .rectangle ||
            (viewModel.selectedOverlay?.type == .rectangle) {
            sliderRow("Corners", value: cornerRadiusBinding, range: 0...50, step: 1)
        }
    }

    // MARK: - Reusable Row Components

    /// A labeled slider with a value readout.
    private func sliderRow(_ label: String, value: Binding<CGFloat>,
                           range: ClosedRange<CGFloat>, step: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                sectionLabel(label)
                Spacer()
                Text(step >= 1 ? "\(Int(value.wrappedValue))" :
                        String(format: "%.1f", value.wrappedValue))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundColor(.secondary)
            }
            Slider(value: value, in: range, step: step)
                .controlSize(.small)
        }
    }

    /// A labeled color picker row.
    private func colorRow(_ label: String, binding: Binding<Color>,
                          supportsOpacity: Bool = false) -> some View {
        HStack {
            sectionLabel(label)
            Spacer()
            ColorPicker("", selection: binding, supportsOpacity: supportsOpacity)
                .labelsHidden()
        }
    }

    /// A key-value property row.
    private func propertyRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
                .monospacedDigit()
        }
    }

    /// Compact value for crop dimensions (side by side).
    private func compactValue(_ label: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary.opacity(0.6))
            Text(value)
                .font(.caption)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Bindings (sync style to selected overlay)

    private var strokeColorBinding: Binding<Color> {
        Binding(
            get: { Color(nsColor: viewModel.currentStyle.strokeColor) },
            set: { newColor in
                viewModel.currentStyle.strokeColor = NSColor(newColor)
                viewModel.syncStyleToSelectedOverlay()
            }
        )
    }

    private var fillColorBinding: Binding<Color> {
        Binding(
            get: { Color(nsColor: viewModel.currentStyle.fillColor) },
            set: { newColor in
                viewModel.currentStyle.fillColor = NSColor(newColor)
                viewModel.syncStyleToSelectedOverlay()
            }
        )
    }

    private var strokeWidthBinding: Binding<CGFloat> {
        Binding(
            get: { viewModel.currentStyle.strokeWidth },
            set: { newVal in
                viewModel.currentStyle.strokeWidth = newVal
                viewModel.syncStyleToSelectedOverlay()
            }
        )
    }

    private var fontSizeBinding: Binding<CGFloat> {
        Binding(
            get: { viewModel.currentStyle.fontSize },
            set: { newVal in
                viewModel.currentStyle.fontSize = newVal
                viewModel.syncStyleToSelectedOverlay()
            }
        )
    }

    private var blurRadiusBinding: Binding<CGFloat> {
        Binding(
            get: { viewModel.currentStyle.blurRadius },
            set: { newVal in
                viewModel.currentStyle.blurRadius = newVal
                viewModel.syncStyleToSelectedOverlay()
            }
        )
    }

    private var cornerRadiusBinding: Binding<CGFloat> {
        Binding(
            get: { viewModel.currentStyle.cornerRadius },
            set: { newVal in
                viewModel.currentStyle.cornerRadius = newVal
                viewModel.syncStyleToSelectedOverlay()
            }
        )
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .foregroundColor(.secondary)
            .textCase(.uppercase)
    }

    private func hintText(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func iconForType(_ type: OverlayType) -> String {
        switch type {
        case .rectangle: return "rectangle"
        case .ellipse:   return "circle"
        case .line:      return "line.diagonal"
        case .arrow:     return "arrow.up.right"
        case .text:      return "textformat"
        case .blur:      return "aqi.medium"
        }
    }
}
