import SwiftUI
import WebKit

struct MarkdownWebView: NSViewRepresentable {
    let markdown: String
    let fileURL: URL?
    let onFileDrop: (URL) -> Void
    @Environment(\.colorScheme) private var colorScheme

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> DropContainerView {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.underPageBackgroundColor = .white
        let container = DropContainerView(webView: webView)
        container.onFileDrop = onFileDrop

        // Load index.html from bundle
        // Allow read access to root so images relative to markdown file can load
        if let htmlURL = Bundle.main.url(forResource: "index", withExtension: "html") {
            webView.loadFileURL(htmlURL, allowingReadAccessTo: URL(fileURLWithPath: "/"))
        }

        context.coordinator.webView = webView
        return container
    }

    func updateNSView(_ container: DropContainerView, context: Context) {
        guard let webView = context.coordinator.webView else { return }
        let isDarkMode = colorScheme == .dark

        // Wait for initial page load before evaluating JS
        if !context.coordinator.isPageLoaded {
            context.coordinator.pendingMarkdown = markdown
            context.coordinator.pendingIsDarkMode = isDarkMode
            context.coordinator.pendingFileURL = fileURL
            return
        }

        let fileChanged = context.coordinator.lastFileURL != fileURL
        let themeChanged = context.coordinator.lastIsDarkMode != isDarkMode
        let contentChanged = context.coordinator.lastMarkdown != markdown

        if fileChanged {
            context.coordinator.lastFileURL = fileURL
            webView.evaluateJavaScript("resetDiff();")
            // Set base URL for resolving relative image paths
            if let fileURL = fileURL {
                let baseURL = fileURL.deletingLastPathComponent().path
                let escapedBase = Self.escapeForJS(baseURL)
                webView.evaluateJavaScript("setBaseURL(`\(escapedBase)`);")
            } else {
                webView.evaluateJavaScript("setBaseURL(null);")
            }
        }

        if themeChanged {
            context.coordinator.lastIsDarkMode = isDarkMode
            // GitHub dark theme background (#0d1117)
            webView.underPageBackgroundColor = isDarkMode ? NSColor(red: 0.051, green: 0.067, blue: 0.09, alpha: 1) : .white
            let js = "setTheme(\(isDarkMode));"
            webView.evaluateJavaScript(js)
        }

        if contentChanged {
            context.coordinator.lastMarkdown = markdown
            let escaped = Self.escapeForJS(markdown)
            webView.evaluateJavaScript("renderMarkdown(`\(escaped)`);")
        }
    }

    private static func escapeForJS(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "$", with: "\\$")
            .replacingOccurrences(of: "</script>", with: "<\\/script>")
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var webView: WKWebView? {
            didSet {
                webView?.navigationDelegate = self
            }
        }
        var lastMarkdown: String?
        var lastIsDarkMode: Bool?
        var lastFileURL: URL?
        var isPageLoaded = false
        var pendingMarkdown: String?
        var pendingIsDarkMode: Bool?
        var pendingFileURL: URL?

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isPageLoaded = true

            if let isDark = pendingIsDarkMode {
                lastIsDarkMode = isDark
                webView.evaluateJavaScript("setTheme(\(isDark));")
            }
            // Set base URL before rendering markdown so images resolve correctly
            if let fileURL = pendingFileURL {
                lastFileURL = fileURL
                let baseURL = fileURL.deletingLastPathComponent().path
                let escapedBase = MarkdownWebView.escapeForJS(baseURL)
                webView.evaluateJavaScript("setBaseURL(`\(escapedBase)`);")
            }
            if let markdown = pendingMarkdown, !markdown.isEmpty {
                lastMarkdown = markdown
                let escaped = MarkdownWebView.escapeForJS(markdown)
                webView.evaluateJavaScript("renderMarkdown(`\(escaped)`);")
            }
            pendingMarkdown = nil
            pendingIsDarkMode = nil
            pendingFileURL = nil
        }
    }
}

// Container that places a transparent drop overlay ON TOP of WKWebView
final class DropContainerView: NSView {
    let webView: WKWebView
    var onFileDrop: ((URL) -> Void)?

    init(webView: WKWebView) {
        self.webView = webView
        super.init(frame: .zero)

        // Add WKWebView as the bottom layer
        webView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(webView)

        // Add transparent drop overlay on top
        let overlay = DropOverlayView()
        overlay.translatesAutoresizingMaskIntoConstraints = false
        overlay.dropHandler = { [weak self] url in
            self?.onFileDrop?(url)
        }
        addSubview(overlay, positioned: .above, relativeTo: webView)

        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: topAnchor),
            webView.bottomAnchor.constraint(equalTo: bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: trailingAnchor),
            overlay.topAnchor.constraint(equalTo: topAnchor),
            overlay.bottomAnchor.constraint(equalTo: bottomAnchor),
            overlay.leadingAnchor.constraint(equalTo: leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }

    override var isOpaque: Bool { true }
    override var preservesContentDuringLiveResize: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill()
        dirtyRect.fill()
    }
}

// Transparent view that sits on top and only activates during drag operations
final class DropOverlayView: NSView {
    var dropHandler: ((URL) -> Void)?
    private var isDragging = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }

    // Allow mouse events to pass through to WebView when not dragging
    override func hitTest(_ point: NSPoint) -> NSView? {
        isDragging ? super.hitTest(point) : nil
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        if hasMarkdownFile(sender) {
            isDragging = true
            return .copy
        }
        return []
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        hasMarkdownFile(sender) ? .copy : []
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        isDragging = false
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        isDragging = false
        guard let url = extractFileURL(sender),
              Constants.markdownExtensions.contains(url.pathExtension.lowercased())
        else {
            return false
        }
        dropHandler?(url)
        return true
    }

    override func draggingEnded(_ sender: any NSDraggingInfo) {
        isDragging = false
    }

    private func hasMarkdownFile(_ info: NSDraggingInfo) -> Bool {
        guard let url = extractFileURL(info) else { return false }
        return Constants.markdownExtensions.contains(url.pathExtension.lowercased())
    }

    private func extractFileURL(_ info: NSDraggingInfo) -> URL? {
        info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true,
        ])?.first as? URL
    }
}
