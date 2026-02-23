import SwiftUI

/// Floating bottom toolbar with tool selection buttons, Figma-style.
struct ToolbarView: View {
    @ObservedObject var viewModel: CanvasViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hoveredTool: Tool?

    var body: some View {
        VStack(spacing: 6) {
            // Tooltip appears above the bar
            if let tool = hoveredTool {
                Text("\(tool.displayName)  \(tool.shortcutHint)")
                    .font(.caption2)
                    .foregroundColor(.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
                    )
                    .transition(.opacity.combined(with: .offset(y: 4)))
            }

            HStack(spacing: 2) {
                ForEach(Tool.allCases) { tool in
                    toolButton(tool)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
                    )
            }
        }
        .animation(.easeInOut(duration: 0.12), value: hoveredTool)
    }

    @ViewBuilder
    private func toolButton(_ tool: Tool) -> some View {
        Button {
            withAnimation(reduceMotion ? .none : .easeInOut(duration: 0.15)) {
                viewModel.selectedTool = tool
            }
        } label: {
            Image(systemName: tool.sfSymbol)
                .font(.system(size: 15, weight: .medium))
                .frame(width: 34, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(viewModel.selectedTool == tool
                              ? Color.accentColor.opacity(0.2)
                              : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering in
            hoveredTool = isHovering ? tool : nil
        }
        .accessibilityLabel("\(tool.displayName) tool")
        .accessibilityHint("Shortcut: \(tool.shortcutHint)")
        .accessibilityAddTraits(viewModel.selectedTool == tool ? .isSelected : [])
    }
}
