import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    fileprivate static let titlebarHeight: CGFloat = 52
    fileprivate static let windowButtonsWidth: CGFloat = 70

    let document = MarkdownDocument()
    private var window: NSWindow?
    /// Holds URL received before window is ready.
    /// `application(_:open:)` can be called before `applicationDidFinishLaunching`.
    private var pendingURL: URL?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let contentView = ContentView(document: document)
            .frame(minWidth: 500, minHeight: 400)
        let hostingController = NSHostingController(rootView: contentView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.titlebarAppearsTransparent = true
        window.backgroundColor = .white
        window.contentViewController = hostingController
        window.title = "CCPlanView"
        window.setFrameAutosaveName("MainWindow")
        window.makeKeyAndOrderFront(nil)

        // Add invisible draggable view over titlebar area so window can be moved.
        // Must be added to themeFrame (contentView's superview) to sit above WKWebView.
        if let themeFrame = window.contentView?.superview {
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
        self.window = window

        setupMenu()

        if let url = pendingURL {
            pendingURL = nil
            document.open(url: url)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            window?.makeKeyAndOrderFront(nil)
        }
        sender.activate()
        return false
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        if window != nil {
            document.open(url: url)
            window?.makeKeyAndOrderFront(nil)
            application.activate()
        } else {
            pendingURL = url
        }
    }

    private func setupMenu() {
        let mainMenu = NSMenu()

        // App menu
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About CCPlanView", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit CCPlanView", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // File menu
        let fileMenuItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        let openItem = NSMenuItem(title: "Open...", action: #selector(openFile), keyEquivalent: "o")
        openItem.target = self
        fileMenu.addItem(openItem)
        fileMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        // Edit menu
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        // View menu
        let viewMenuItem = NSMenuItem()
        let viewMenu = NSMenu(title: "View")
        viewMenu.addItem(withTitle: "Enter Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)

        // Window menu
        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)

        NSApp.mainMenu = mainMenu
        NSApp.windowsMenu = windowMenu
    }

    @objc private func openFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [
            UTType(filenameExtension: "md"),
            UTType(filenameExtension: "markdown"),
            .plainText,
        ].compactMap { $0 }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        if panel.runModal() == .OK, let url = panel.url {
            document.open(url: url)
        }
    }
}

// Transparent view that enables window dragging over the titlebar area.
// WKWebView consumes all mouse events, so this sits on top to intercept drags.
final class TitlebarDragView: NSView {
    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Only intercept in the titlebar region, excluding window control buttons
        let local = convert(point, from: superview)
        guard bounds.contains(local) else { return nil }
        // Skip left area where close/minimize/zoom buttons are
        if local.x < AppDelegate.windowButtonsWidth { return nil }
        return self
    }
}
