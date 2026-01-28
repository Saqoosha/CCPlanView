import SwiftUI

struct ContentView: View {
    @ObservedObject var document: MarkdownDocument
    @Environment(\.colorScheme) private var colorScheme

    private var backgroundColor: Color {
        colorScheme == .dark
            ? Color(nsColor: NSColor(red: 0.051, green: 0.067, blue: 0.09, alpha: 1))
            : Color.white
    }

    var body: some View {
        ZStack(alignment: .top) {
            backgroundColor
            MarkdownWebView(markdown: document.markdownContent) { url in
                document.open(url: url)
            }
            LinearGradient(
                colors: [
                    backgroundColor.opacity(1.0),
                    backgroundColor.opacity(0.8),
                    backgroundColor.opacity(0.0),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 52)
            .allowsHitTesting(false)
        }
        .ignoresSafeArea()
        .navigationTitle(document.windowTitle)
    }
}
