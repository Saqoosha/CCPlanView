import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let markdown = UTType(filenameExtension: "md")!
}

struct MarkdownFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.markdown, .plainText] }
    static var writableContentTypes: [UTType] { [] }

    var markdown: String

    init(markdown: String = "") {
        self.markdown = markdown
    }

    init(configuration: ReadConfiguration) throws {
        let data = try configuration.file.regularFileContents!
        markdown = String(decoding: data, as: UTF8.self)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = Data(markdown.utf8)
        return FileWrapper(regularFileWithContents: data)
    }
}
