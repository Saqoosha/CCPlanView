import SwiftUI
import WebKit

struct MarkdownWebView: NSViewRepresentable {
    let markdown: String
    let onFileDrop: (URL) -> Void
    @Environment(\.colorScheme) private var colorScheme

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> DropContainerView {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")

        let container = DropContainerView(webView: webView)
        container.onFileDrop = onFileDrop

        // Load index.html from bundle
        if let resourceURL = Bundle.main.resourceURL,
           let htmlURL = Bundle.main.url(forResource: "index", withExtension: "html")
        {
            webView.loadFileURL(htmlURL, allowingReadAccessTo: resourceURL)
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
            return
        }

        let themeChanged = context.coordinator.lastIsDarkMode != isDarkMode
        let contentChanged = context.coordinator.lastMarkdown != markdown

        if themeChanged {
            context.coordinator.lastIsDarkMode = isDarkMode
            let js = "setTheme(\(isDarkMode));"
            webView.evaluateJavaScript(js)
        }

        if contentChanged {
            context.coordinator.lastMarkdown = markdown
            if markdown.isEmpty {
                webView.evaluateJavaScript("showEmpty();")
            } else {
                let escaped = escapeForJS(markdown)
                webView.evaluateJavaScript("renderMarkdown(`\(escaped)`);") { _, _ in
                    // Debug: dump rendered HTML structure after diff is applied
                    webView.evaluateJavaScript("""
                        (function() {
                            const el = document.getElementById('content');
                            if (!el) return '';
                            const lines = [];
                            function walk(node, indent) {
                                for (const child of node.children) {
                                    const tag = child.tagName.toLowerCase();
                                    const cls = child.className ? '.' + child.className.split(' ').join('.') : '';
                                    const text = child.textContent.substring(0, 60).replace(/\\n/g, ' ');
                                    lines.push(indent + '<' + tag + cls + '> ' + text);
                                    if (['ul','ol','table','thead','tbody','tr'].includes(tag)) walk(child, indent + '  ');
                                }
                            }
                            walk(el, '');
                            return lines.join('\\n');
                        })()
                    """) { result, _ in
                        if let html = result as? String, !html.isEmpty {
                            let path = "/tmp/ccplanview-debug.txt"
                            try? html.write(toFile: path, atomically: true, encoding: .utf8)
                        }
                    }
                }
            }
        }
    }

    private func escapeForJS(_ string: String) -> String {
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
        var isPageLoaded = false
        var pendingMarkdown: String?
        var pendingIsDarkMode: Bool?

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isPageLoaded = true

            if let isDark = pendingIsDarkMode {
                lastIsDarkMode = isDark
                webView.evaluateJavaScript("setTheme(\(isDark));")
            }
            if let markdown = pendingMarkdown, !markdown.isEmpty {
                lastMarkdown = markdown
                let escaped = markdown
                    .replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "`", with: "\\`")
                    .replacingOccurrences(of: "$", with: "\\$")
                    .replacingOccurrences(of: "</script>", with: "<\\/script>")
                webView.evaluateJavaScript("renderMarkdown(`\(escaped)`);")
            }
            pendingMarkdown = nil
            pendingIsDarkMode = nil
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
}

// Transparent view that sits on top and only activates during drag operations
final class DropOverlayView: NSView {
    var dropHandler: ((URL) -> Void)?
    private var isDragging = false

    private static let markdownExtensions: Set<String> = ["md", "markdown", "mdown", "mkd"]

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
              Self.markdownExtensions.contains(url.pathExtension.lowercased())
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
        return Self.markdownExtensions.contains(url.pathExtension.lowercased())
    }

    private func extractFileURL(_ info: NSDraggingInfo) -> URL? {
        info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true,
        ])?.first as? URL
    }
}
