import Foundation

@MainActor
final class MarkdownDocument: ObservableObject {
    @Published var fileURL: URL?
    @Published var markdownContent: String = ""
    @Published var windowTitle: String = "CCPlanView"

    private var fileWatcher: FileWatcher?

    func open(url: URL) {
        guard url != fileURL else { return }
        fileURL = url
        windowTitle = url.lastPathComponent
        loadContent()
        startWatching()
    }

    private func loadContent() {
        guard let url = fileURL else { return }
        do {
            markdownContent = try String(contentsOf: url, encoding: .utf8)
        } catch {
            markdownContent = "**Error reading file:** \(error.localizedDescription)"
        }
    }

    private func startWatching() {
        fileWatcher?.stop()
        guard let url = fileURL else { return }
        fileWatcher = FileWatcher(url: url) { [weak self] in
            Task { @MainActor in
                self?.loadContent()
            }
        }
        fileWatcher?.start()
    }
}
