import SwiftUI

@main
struct CCPlanViewApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate

    var body: some Scene {
        DocumentGroup(viewing: MarkdownFileDocument.self) { configuration in
            ContentView(document: configuration.document)
                .task {
                    if let url = configuration.fileURL {
                        configuration.document.startWatching(url: url)
                    }
                }
        }
        .windowStyle(.automatic)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
