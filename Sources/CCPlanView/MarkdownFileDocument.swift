import SwiftUI
import UniformTypeIdentifiers

final class MarkdownFileDocument: ReferenceFileDocument, ObservableObject, @unchecked Sendable {
    nonisolated(unsafe) static var readableContentTypes: [UTType] = [
        UTType(filenameExtension: "md")!,
        UTType(filenameExtension: "markdown")!,
        UTType(filenameExtension: "mdown")!,
        UTType(filenameExtension: "mkd")!,
        .plainText,
    ]

    @MainActor @Published var markdownContent: String = ""
    @MainActor @Published var fileURL: URL?

    @MainActor private var fileWatcher: FileWatcher?

    /// Content loaded from file, accessed from any isolation context.
    /// Used for snapshot/fileWrapper which are nonisolated protocol requirements.
    private let contentLock = NSLock()
    nonisolated(unsafe) private var _storedContent: String = ""
    private var storedContent: String {
        get {
            contentLock.lock()
            defer { contentLock.unlock() }
            return _storedContent
        }
        set {
            contentLock.lock()
            defer { contentLock.unlock() }
            _storedContent = newValue
        }
    }

    init() {}

    required init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let content = String(data: data, encoding: .utf8)
        else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self._storedContent = content
        // MainActor property will be synced in startWatching
    }

    nonisolated func snapshot(contentType: UTType) throws -> String {
        storedContent
    }

    nonisolated func fileWrapper(snapshot: String, configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: snapshot.data(using: .utf8) ?? Data())
    }

    @MainActor
    func startWatching(url: URL) {
        fileURL = url
        // Sync stored content to published property
        markdownContent = storedContent
        fileWatcher?.stop()
        fileWatcher = FileWatcher(url: url) { [weak self] in
            Task { @MainActor in
                self?.reloadContent()
            }
        }
        fileWatcher?.start()
    }

    @MainActor
    func open(url: URL) {
        // D&D で別ファイルを開く用
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

    @MainActor
    private func reloadContent() {
        guard let url = fileURL else { return }
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            storedContent = content
            markdownContent = content
        } catch {
            let errorMessage = "**Error:** \(error.localizedDescription)"
            storedContent = errorMessage
            markdownContent = errorMessage
        }
    }
}
