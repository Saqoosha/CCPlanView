import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    fileprivate static let titlebarHeight: CGFloat = 52
    fileprivate static let windowButtonsWidth: CGFloat = 70
    fileprivate static let toolbarButtonsWidth: CGFloat = 100
    static let windowFrameKey = "CCPlanViewWindowFrame"

    private static let dontAskHookSetupKey = "dontAskHookSetup"

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

        // Check hook setup on launch
        checkHookSetup()
    }

    private func checkHookSetup() {
        guard HookManager.isClaudeCodeInstalled() else { return }

        // Check for settings validation errors
        if let error = HookManager.validateSettings() {
            showSettingsWarning(error)
            return
        }

        // Check if hook needs update (cleanup)
        if HookManager.needsHookUpdate() {
            promptHookCleanup()
            return
        }

        // Check if hook needs to be installed
        guard !UserDefaults.standard.bool(forKey: Self.dontAskHookSetupKey) else { return }
        guard !HookManager.isHookConfigured() else { return }

        let alert = NSAlert()
        alert.messageText = "Setup Claude Code Hooks?"
        alert.informativeText =
            "CCPlanView can automatically open plan files when Claude exits plan mode. Would you like to install the hook?"
        alert.addButton(withTitle: "Install")
        alert.addButton(withTitle: "Later")
        alert.addButton(withTitle: "Don't Ask Again")

        switch alert.runModal() {
        case .alertFirstButtonReturn:  // Install
            do {
                try HookManager.installHook()
                NotificationCenter.default.post(name: .hookConfigurationChanged, object: nil)
                showSuccessAlert()
            } catch {
                showErrorAlert(error)
            }
        case .alertThirdButtonReturn:  // Don't Ask Again
            UserDefaults.standard.set(true, forKey: Self.dontAskHookSetupKey)
        default:
            break
        }
    }

    private func showSettingsWarning(_ error: HookManagerError) {
        let alert = NSAlert()
        alert.messageText = "Claude Code Settings Warning"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func promptHookCleanup() {
        let alert = NSAlert()
        alert.messageText = "Update Hook Configuration?"
        alert.informativeText =
            "CCPlanView detected outdated or duplicate hooks. Would you like to clean up and update the hook configuration?"
        alert.addButton(withTitle: "Update")
        alert.addButton(withTitle: "Later")

        if alert.runModal() == .alertFirstButtonReturn {
            do {
                try HookManager.cleanupAndInstallHook()
                NotificationCenter.default.post(name: .hookConfigurationChanged, object: nil)
                showSuccessAlert()
            } catch {
                showErrorAlert(error)
            }
        }
    }

    private func showSuccessAlert() {
        let alert = NSAlert()
        alert.messageText = "Hooks Installed"
        alert.informativeText =
            "Claude Code hooks have been configured. CCPlanView will open plan files when Claude exits plan mode."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func showErrorAlert(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Failed to Configure Hooks"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .critical
        alert.addButton(withTitle: "OK")
        alert.runModal()
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

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            if url.scheme == "ccplanview" && url.host == "refresh" {
                var targetFileURL: URL?
                if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                   let filePath = components.queryItems?.first(where: { $0.name == "file" })?.value {
                    targetFileURL = URL(fileURLWithPath: filePath)
                }
                NotificationCenter.default.post(name: .ccplanviewRefresh, object: targetFileURL)
            } else {
                NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
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

        window.identifier = NSUserInterfaceItemIdentifier(Constants.mainWindowIdentifier)
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
        // Leave space for window buttons (left) and toolbar buttons (right)
        if local.x < AppDelegate.windowButtonsWidth { return nil }
        if local.x > bounds.width - AppDelegate.toolbarButtonsWidth { return nil }
        return self
    }
}
