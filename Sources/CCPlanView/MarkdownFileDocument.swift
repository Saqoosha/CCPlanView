import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let markdown = UTType(filenameExtension: "md")!
}

final class MarkdownFileDocument: ReferenceFileDocument, ObservableObject {
    static var readableContentTypes: [UTType] { [.markdown, .plainText] }

    @Published var markdown: String

    init(markdown: String = "") {
        self.markdown = markdown
    }

    required init(configuration: ReadConfiguration) throws {
        let data = configuration.file.regularFileContents!
        markdown = String(decoding: data, as: UTF8.self)
    }

    func snapshot(contentType: UTType) throws -> String {
        markdown
    }

    func fileWrapper(snapshot: String, configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(snapshot.utf8))
    }
}
