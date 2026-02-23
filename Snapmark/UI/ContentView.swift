import SwiftUI

/// Main application layout: command bar + canvas (with floating toolbar) + inspector.
struct ContentView: View {
    @StateObject private var viewModel = CanvasViewModel()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            CommandBarView(viewModel: viewModel)
            Divider()

            HStack(spacing: 0) {
                // Canvas with floating toolbar overlay
                ZStack(alignment: .bottom) {
                    CanvasRepresentable(viewModel: viewModel)
                        .frame(minWidth: 300, minHeight: 200)
                        .clipped()
                        .accessibilityElement(children: .contain)
                        .accessibilityLabel("Canvas")

                    if viewModel.showToolbar && viewModel.baseImage != nil {
                        ToolbarView(viewModel: viewModel)
                            .padding(.bottom, 16)
                    }
                }

                // Right inspector
                if viewModel.showInspector {
                    Divider()
                    InspectorView(viewModel: viewModel)
                }
            }
        }
        .frame(minWidth: 700, minHeight: 450)
        .onReceive(NotificationCenter.default.publisher(for: .snapmarkOpenAndPaste)) { _ in
            // Auto-paste clipboard image when opened via menu bar icon
            viewModel.pasteImage()
        }
        .background(
            Group {
                Button("") { viewModel.pasteImage() }
                    .keyboardShortcut("v", modifiers: .command)
                    .hidden()
                    .frame(width: 0, height: 0)
                Button("") { viewModel.copyToClipboard() }
                    .keyboardShortcut("c", modifiers: .command)
                    .hidden()
                    .frame(width: 0, height: 0)
                Button("") { viewModel.saveToFile() }
                    .keyboardShortcut("s", modifiers: .command)
                    .hidden()
                    .frame(width: 0, height: 0)
                Button("") { viewModel.undo() }
                    .keyboardShortcut("z", modifiers: .command)
                    .hidden()
                    .frame(width: 0, height: 0)
                Button("") { viewModel.redo() }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                    .hidden()
                    .frame(width: 0, height: 0)
                Button("") { viewModel.importImage() }
                    .keyboardShortcut("o", modifiers: .command)
                    .hidden()
                    .frame(width: 0, height: 0)
            }
        )
    }
}
