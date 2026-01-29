import AppKit
import SwiftUI
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    fileprivate static let titlebarHeight: CGFloat = 52
    fileprivate static let windowButtonsWidth: CGFloat = 70
    static let windowFrameKey = "CCPlanViewWindowFrame"
    private var fileMenu: NSMenu!

    func applicationDidFinishLaunching(_ notification: Notification) {
        refreshFileMenuReference()
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

    private func refreshFileMenuReference() {
        let currentFileMenu = NSApp.mainMenu!.items.first { $0.title == "File" }!.submenu!
        if fileMenu !== currentFileMenu {
            fileMenu = currentFileMenu
            fileMenu.delegate = self
        }
        rebuildFileMenu()
    }

    private func rebuildFileMenu() {
        fileMenu.removeAllItems()

        let newItem = NSMenuItem(title: "New", action: #selector(NSDocumentController.newDocument(_:)), keyEquivalent: "n")
        newItem.keyEquivalentModifierMask = [.command]
        fileMenu.addItem(newItem)
        fileMenu.addItem(.separator())

        let openItem = NSMenuItem(title: "Open…", action: #selector(NSDocumentController.openDocument(_:)), keyEquivalent: "o")
        openItem.keyEquivalentModifierMask = [.command]
        fileMenu.addItem(openItem)

        let openRecentItem = NSMenuItem(title: "Open Recent", action: nil, keyEquivalent: "")
        let openRecentMenu = NSMenu(title: "Open Recent")
        let recentURLs = NSDocumentController.shared.recentDocumentURLs
        if recentURLs.isEmpty {
            let emptyItem = NSMenuItem(title: "No Recent Documents", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            openRecentMenu.addItem(emptyItem)
        } else {
            for url in recentURLs {
                let item = NSMenuItem(title: url.lastPathComponent, action: #selector(openRecentDocument(_:)), keyEquivalent: "")
                item.representedObject = url
                openRecentMenu.addItem(item)
            }
        }
        openRecentMenu.addItem(.separator())
        let clearItem = NSMenuItem(title: "Clear Menu", action: #selector(NSDocumentController.clearRecentDocuments(_:)), keyEquivalent: "")
        openRecentMenu.addItem(clearItem)
        openRecentItem.submenu = openRecentMenu
        fileMenu.addItem(openRecentItem)

        fileMenu.addItem(.separator())
        let closeItem = NSMenuItem(title: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        closeItem.keyEquivalentModifierMask = [.command]
        fileMenu.addItem(closeItem)
        let closeAllItem = NSMenuItem(title: "Close All", action: Selector(("closeAll:")), keyEquivalent: "")
        fileMenu.addItem(closeAllItem)
    }

    @objc private func openRecentDocument(_ sender: NSMenuItem) {
        let url = sender.representedObject as! URL
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in
            DispatchQueue.main.async {
                self.refreshFileMenuReference()
            }
        }
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        if menu === fileMenu { refreshFileMenuReference() }
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
