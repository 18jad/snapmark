import SwiftUI

/// Top command bar with import, export, zoom, and undo/redo controls.
struct CommandBarView: View {
    @ObservedObject var viewModel: CanvasViewModel
    @State private var hoveredButton: String?

    var body: some View {
        HStack(spacing: 0) {
            // Left: Import actions
            HStack(spacing: 2) {
                headerButton("Open", icon: "folder", shortcut: "O") {
                    viewModel.importImage()
                }
                headerButton("Paste", icon: "clipboard", shortcut: "V") {
                    viewModel.pasteImage()
                }
            }

            thinDivider()

            // Export actions
            HStack(spacing: 2) {
                headerButton("Copy", icon: "doc.on.doc", shortcut: "C") {
                    viewModel.copyToClipboard()
                }
                .disabled(viewModel.baseImage == nil)

                headerButton("Export", icon: "square.and.arrow.up", shortcut: "S") {
                    viewModel.saveToFile()
                }
                .disabled(viewModel.baseImage == nil)
            }

            thinDivider()

            // Undo / Redo
            HStack(spacing: 2) {
                headerButton("Undo", icon: "arrow.uturn.backward", shortcut: "Z", showLabel: false) {
                    viewModel.undo()
                }
                .disabled(!viewModel.canUndo)

                headerButton("Redo", icon: "arrow.uturn.forward", shortcut: "\u{21E7}Z", showLabel: false) {
                    viewModel.redo()
                }
                .disabled(!viewModel.canRedo)
            }

            Spacer()

            if viewModel.baseImage != nil {
                // Zoom controls — only visible when an image is loaded
                HStack(spacing: 2) {
                    headerButton("Zoom Out", icon: "minus.magnifyingglass", showLabel: false) {
                        viewModel.zoomOut()
                    }

                    Text("\(Int(viewModel.zoomScale * 100))%")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 40)

                    headerButton("Zoom In", icon: "plus.magnifyingglass", showLabel: false) {
                        viewModel.zoomIn()
                    }

                    headerButton("Fit", icon: "arrow.down.right.and.arrow.up.left", showLabel: false) {
                        viewModel.zoomToFit()
                    }
                }

                thinDivider()
            }

            // Panel toggles
            HStack(spacing: 2) {
                if viewModel.baseImage != nil {
                    headerToggle("Toolbar", icon: "rectangle.bottomhalf.inset.filled",
                                 isOn: $viewModel.showToolbar)
                }
                headerToggle("Inspector", icon: "sidebar.trailing",
                             isOn: $viewModel.showInspector)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial)
    }

    // MARK: - Components

    @ViewBuilder
    private func headerButton(_ label: String, icon: String,
                              shortcut: String? = nil,
                              showLabel: Bool = true,
                              action: @escaping () -> Void) -> some View {
        let isHovered = hoveredButton == label

        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                if showLabel {
                    Text(label)
                        .font(.system(size: 11, weight: .medium))
                }
            }
            .foregroundColor(isHovered ? .primary : .secondary)
            .padding(.horizontal, showLabel ? 8 : 0)
            .frame(minWidth: 30, minHeight: 26, maxHeight: 26)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(isHovered ? Color.primary.opacity(0.08) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredButton = hovering ? label : nil
        }
        .help(shortcut != nil ? "\(label)  \u{2318}\(shortcut!)" : label)
        .accessibilityLabel(label)
    }

    @ViewBuilder
    private func headerToggle(_ label: String, icon: String,
                              isOn: Binding<Bool>) -> some View {
        let isHovered = hoveredButton == label

        Button {
            isOn.wrappedValue.toggle()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(isOn.wrappedValue ? .accentColor : (isHovered ? .primary : .secondary))
                .frame(width: 30, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(isOn.wrappedValue
                              ? Color.accentColor.opacity(0.12)
                              : (isHovered ? Color.primary.opacity(0.08) : Color.clear))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredButton = hovering ? label : nil
        }
        .help("Toggle \(label)")
        .accessibilityLabel("Toggle \(label)")
    }

    private func thinDivider() -> some View {
        Divider()
            .frame(height: 16)
            .padding(.horizontal, 6)
    }
}
