import AppKit
import SwiftUI

@main
struct CCPlanViewApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate

    var body: some Scene {
        DocumentGroup(viewing: MarkdownFileDocument.self) { file in
            MainContentView(document: file.document, fileURL: file.fileURL)
        }
        .defaultWindowPlacement { _, _ in
            let defaultSize = CGSize(width: 800, height: 900)
            if let frameString = UserDefaults.standard.string(forKey: AppDelegate.windowFrameKey) {
                // Parse saved frame: "x y width height screenX screenY screenWidth screenHeight"
                let components = frameString.split(separator: " ").compactMap { Double($0) }
                if components.count >= 4 {
                    let size = CGSize(width: components[2], height: components[3])
                    let position = CGPoint(x: components[0], y: components[1])
                    return WindowPlacement(position, size: size)
                }
            }
            return WindowPlacement(size: defaultSize)
        }
        .windowStyle(.automatic)
        .windowToolbarStyle(.unified(showsTitle: true))
    }
}

struct MainContentView: View {
    @ObservedObject var document: MarkdownFileDocument
    let fileURL: URL?
    @Environment(\.colorScheme) private var colorScheme
    @State private var renderedMarkdown: String = ""

    private var backgroundColor: Color {
        colorScheme == .dark
            ? Color(nsColor: NSColor(red: 0.051, green: 0.067, blue: 0.09, alpha: 1))
            : Color.white
    }

    var body: some View {
        ZStack(alignment: .top) {
            backgroundColor

            if fileURL != nil {
                MarkdownWebView(
                    markdown: renderedMarkdown,
                    fileURL: fileURL,
                    onFileDrop: { url in
                        openFile(url)
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
            } else {
                EmptyStateView(onOpen: showOpenPanel, onDrop: openFile)
            }
        }
        .ignoresSafeArea()
        .navigationTitle(fileURL?.lastPathComponent ?? "CCPlanView")
        .onAppear {
            loadContent()
        }
        .onChange(of: fileURL) { _, _ in
            loadContent()
        }
        .onReceive(NotificationCenter.default.publisher(for: .ccplanviewRefresh)) { notification in
            if let targetURL = notification.object as? URL {
                let myPath = fileURL?.resolvingSymlinksInPath().path
                let targetPath = targetURL.resolvingSymlinksInPath().path
                guard targetPath == myPath else { return }
            }
            refreshContent()
        }
    }

    private func openFile(_ url: URL) {
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
    }

    private func showOpenPanel() {
        NSDocumentController.shared.openDocument(nil)
    }

    private func loadContent() {
        renderedMarkdown = document.markdown
    }

    private func refreshContent() {
        guard let fileURL else { return }
        if let data = try? Data(contentsOf: fileURL) {
            renderedMarkdown = String(decoding: data, as: UTF8.self)
        }
    }
}

struct EmptyStateView: View {
    let onOpen: () -> Void
    let onDrop: (URL) -> Void

    @State private var isTargeted = false

    private static let markdownExtensions: Set<String> = ["md", "markdown", "mdown", "mkd"]

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
                if let url, Self.markdownExtensions.contains(url.pathExtension.lowercased()) {
                    DispatchQueue.main.async {
                        onDrop(url)
                    }
                }
            }
            return true
        }
    }
}
