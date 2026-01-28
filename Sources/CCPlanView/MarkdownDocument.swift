import SwiftUI

@MainActor
final class MarkdownDocument: ObservableObject {
    @Published var markdownContent: String = ""
    @Published var fileURL: URL?

    private var fileWatcher: FileWatcher?

    func open(url: URL) {
        fileURL = url
        reloadContent()
        fileWatcher?.stop()
        fileWatcher = FileWatcher(url: url) { [weak self] in
            Task { @MainActor in
                self?.reloadContent()
            }
        }
        fileWatcher?.start()
    }

    private func reloadContent() {
        guard let url = fileURL else { return }
        do {
            markdownContent = try String(contentsOf: url, encoding: .utf8)
        } catch {
            markdownContent = "**Error:** \(error.localizedDescription)"
        }
    }
}
