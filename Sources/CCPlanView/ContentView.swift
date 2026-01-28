import SwiftUI

struct ContentView: View {
    @ObservedObject var document: MarkdownDocument

    var body: some View {
        MarkdownWebView(markdown: document.markdownContent) { url in
            document.open(url: url)
        }
        .navigationTitle(document.windowTitle)
    }
}
