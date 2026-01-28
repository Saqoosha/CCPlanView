import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    fileprivate static let titlebarHeight: CGFloat = 52
    fileprivate static let windowButtonsWidth: CGFloat = 70
    static let windowFrameKey = "CCPlanViewWindowFrame"

    private var hasOpenedInitialFile = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidBecomeKey(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidResize(_:)),
            name: NSWindow.didResizeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidMove(_:)),
            name: NSWindow.didMoveNotification,
            object: nil
        )
    }

    @objc private func windowDidResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        saveWindowFrame(window)
    }

    @objc private func windowDidMove(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        saveWindowFrame(window)
    }

    private func saveWindowFrame(_ window: NSWindow) {
        // Only save frames for our main windows (ones with TitlebarDragView)
        guard let themeFrame = window.contentView?.superview,
              themeFrame.subviews.contains(where: { $0 is TitlebarDragView })
        else { return }

        let frameString = window.frameDescriptor
        UserDefaults.standard.set(frameString, forKey: AppDelegate.windowFrameKey)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for (index, url) in urls.enumerated() {
            if index == 0 && !hasOpenedInitialFile {
                // First file goes to the existing empty window
                hasOpenedInitialFile = true
                WindowManager.shared.openFile(url)
                NotificationCenter.default.post(
                    name: .openFileInWindow,
                    object: nil,
                    userInfo: ["url": url]
                )
            } else {
                // Subsequent files open new windows
                WindowManager.shared.openFile(url)
                // SwiftUI WindowGroup will create new window when we post this
                // But we need a way to open a new window...
                // For now, open in current window (will be fixed with proper multi-window support)
                NotificationCenter.default.post(
                    name: .openFileInWindow,
                    object: nil,
                    userInfo: ["url": url]
                )
            }
        }
    }

    @objc private func windowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        setupTitlebarDragView(for: window)
    }

    private func setupTitlebarDragView(for window: NSWindow) {
        guard let themeFrame = window.contentView?.superview,
              !themeFrame.subviews.contains(where: { $0 is TitlebarDragView })
        else { return }

        window.titlebarAppearsTransparent = true

        let dragView = TitlebarDragView()
        dragView.translatesAutoresizingMaskIntoConstraints = false
        themeFrame.addSubview(dragView)
        NSLayoutConstraint.activate([
            dragView.topAnchor.constraint(equalTo: themeFrame.topAnchor),
            dragView.leadingAnchor.constraint(equalTo: themeFrame.leadingAnchor),
            dragView.trailingAnchor.constraint(equalTo: themeFrame.trailingAnchor),
            dragView.heightAnchor.constraint(equalToConstant: Self.titlebarHeight),
        ])
    }
}

// Transparent view that enables window dragging over the titlebar area.
final class TitlebarDragView: NSView {
    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard bounds.contains(local) else { return nil }
        if local.x < AppDelegate.windowButtonsWidth { return nil }
        return self
    }
}
