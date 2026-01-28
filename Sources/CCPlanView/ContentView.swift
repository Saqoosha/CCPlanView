import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var document: MarkdownDocument
    @Environment(\.colorScheme) private var colorScheme

    private var backgroundColor: Color {
        colorScheme == .dark
            // GitHub dark theme background (#0d1117)
            ? Color(nsColor: NSColor(red: 0.051, green: 0.067, blue: 0.09, alpha: 1))
            : Color.white
    }

    var body: some View {
        ZStack(alignment: .top) {
            backgroundColor
            if document.markdownContent.isEmpty {
                EmptyStateView(onOpen: openFilePanel, onDrop: document.open)
            } else {
                MarkdownWebView(
                    markdown: document.markdownContent,
                    fileURL: document.fileURL,
                    onFileDrop: { url in
                        document.open(url: url)
                    }
                )
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
        }
        .ignoresSafeArea()
        .navigationTitle(document.windowTitle)
    }

    private func openFilePanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [
            UTType(filenameExtension: "md"),
            UTType(filenameExtension: "markdown"),
            .plainText,
        ].compactMap { $0 }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = "Select a Markdown file"

        if panel.runModal() == .OK, let url = panel.url {
            document.open(url: url)
        }
    }
}

struct EmptyStateView: View {
    let onOpen: () -> Void
    let onDrop: (URL) -> Void

    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Document icon
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: "doc.text")
                    .font(.system(size: 64, weight: .thin))
                    .foregroundStyle(.secondary)

                // Markdown badge
                Image(systemName: "m.square.fill")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(.tint)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(.background)
                            .frame(width: 22, height: 22)
                    )
                    .offset(x: 6, y: 6)
            }
            .padding(.bottom, 20)

            Text("Drop a Markdown file here")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.primary)
                .padding(.bottom, 6)

            HStack(spacing: 4) {
                Text("or press")
                    .foregroundStyle(.secondary)
                Text("⌘O")
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(nsColor: .separatorColor).opacity(0.5))
                    )
                    .foregroundStyle(.secondary)
                Text("to open")
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 13))

            Button("Open File...") {
                onOpen()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.top, 24)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    isTargeted ? Color.accentColor : Color.clear,
                    style: StrokeStyle(lineWidth: 3, dash: [8, 4])
                )
                .padding(20)
        )
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url, Constants.markdownExtensions.contains(url.pathExtension.lowercased()) {
                    DispatchQueue.main.async {
                        onDrop(url)
                    }
                }
            }
            return true
        }
    }
}
