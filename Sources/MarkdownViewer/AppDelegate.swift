import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    var document: MarkdownDocument?
    var pendingURL: URL?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        if let document {
            Task { @MainActor in
                document.open(url: url)
            }
        } else {
            pendingURL = url
        }
    }
}
