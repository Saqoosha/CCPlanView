import SwiftUI
import UniformTypeIdentifiers

@main
struct MarkdownViewerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var document = MarkdownDocument()

    var body: some Scene {
        WindowGroup {
            ContentView(document: document)
                .frame(minWidth: 500, minHeight: 400)
                .onAppear {
                    // Wire up document to AppDelegate
                    appDelegate.document = document
                    // Handle any pending URL from CLI args or Finder open
                    if let url = appDelegate.pendingURL {
                        appDelegate.pendingURL = nil
                        document.open(url: url)
                    }
                }
        }
        .defaultSize(width: 800, height: 600)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open...") {
                    openFile()
                }
                .keyboardShortcut("o", modifiers: .command)
            }
        }
    }

    private func openFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [
            UTType(filenameExtension: "md")!,
            UTType(filenameExtension: "markdown")!,
            .plainText,
        ]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        if panel.runModal() == .OK, let url = panel.url {
            document.open(url: url)
        }
    }
}
