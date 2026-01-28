import SwiftUI

@MainActor
final class WindowManager: ObservableObject {
    static let shared = WindowManager()

    @Published var pendingURLs: [URL] = []

    private init() {}

    func openFile(_ url: URL) {
        pendingURLs.append(url)
    }

    func consumeURL() -> URL? {
        pendingURLs.isEmpty ? nil : pendingURLs.removeFirst()
    }
}
