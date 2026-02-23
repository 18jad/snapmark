import SwiftUI

/// Custom menu commands for the app.
struct AppCommands: Commands {
    var body: some Commands {
        // Replace default New Document behavior
        CommandGroup(replacing: .newItem) { }

        CommandGroup(replacing: .help) {
            Button("Snapmark Help") {
                if let url = URL(string: "https://github.com/snapmark/snapmark") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }
}
