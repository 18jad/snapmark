import AppKit

/// Notification posted when the menu bar icon is clicked to open & paste.
extension Notification.Name {
    static let snapmarkOpenAndPaste = Notification.Name("snapmarkOpenAndPaste")
}

/// App delegate that manages the menu bar status item and keeps the app alive in background.
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem?
    /// Strong reference to the main window so it survives closing.
    private var mainWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()

        // Capture the main window once SwiftUI has created it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.captureMainWindow()
        }
    }

    /// Keep the app running when the last window is closed — it lives in the menu bar.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Reopen the window when the dock icon is clicked and no window is visible.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            showWindow()
        }
        return true
    }

    // MARK: - NSWindowDelegate

    /// Intercept close → hide the window instead of destroying it.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)  // Hide instead of close
        return false          // Prevent actual close
    }

    // MARK: - Status Item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        guard let button = statusItem?.button else { return }

        if let image = NSImage(named: "MenuBarIcon") {
            image.isTemplate = true
            image.size = NSSize(width: 18, height: 18)
            button.image = image
        }

        button.action = #selector(statusItemClicked)
        button.target = self
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @objc private func statusItemClicked() {
        guard let event = NSApp.currentEvent else {
            activateAndPaste()
            return
        }

        if event.type == .rightMouseUp {
            let menu = NSMenu()
            menu.addItem(NSMenuItem(title: "Open Snapmark", action: #selector(openOnly), keyEquivalent: ""))
            menu.addItem(NSMenuItem.separator())
            menu.addItem(NSMenuItem(title: "Quit Snapmark", action: #selector(quitApp), keyEquivalent: "q"))
            statusItem?.menu = menu
            statusItem?.button?.performClick(nil)
            DispatchQueue.main.async { self.statusItem?.menu = nil }
        } else {
            activateAndPaste()
        }
    }

    // MARK: - Window Management

    /// Find and retain the main SwiftUI window, become its delegate.
    private func captureMainWindow() {
        guard mainWindow == nil else { return }
        for window in NSApp.windows where window.canBecomeKey {
            mainWindow = window
            window.delegate = self
            window.isReleasedWhenClosed = false
            break
        }
    }

    /// Show the main window (it's always alive, just hidden).
    private func showWindow() {
        // Make sure we have captured the window
        if mainWindow == nil { captureMainWindow() }

        if let window = mainWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func activateAndPaste() {
        showWindow()

        // Check if clipboard has an image
        let pb = NSPasteboard.general
        let hasImage = pb.data(forType: .tiff) != nil
            || pb.data(forType: .png) != nil
            || (pb.readObjects(forClasses: [NSURL.self], options: [
                .urlReadingContentsConformToTypes: ["public.image"]
            ]) as? [URL])?.isEmpty == false

        if hasImage {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                NotificationCenter.default.post(name: .snapmarkOpenAndPaste, object: nil)
            }
        }
    }

    @objc private func openOnly() {
        showWindow()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
