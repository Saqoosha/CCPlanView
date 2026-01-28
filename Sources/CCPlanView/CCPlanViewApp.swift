import SwiftUI

@MainActor
@Observable
final class RecentFilesManager {
    static let shared = RecentFilesManager()

    var recentFiles: [URL] = NSDocumentController.shared.recentDocumentURLs

    private init() {
        NotificationCenter.default.addObserver(
            forName: .recentFilesDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.recentFiles = NSDocumentController.shared.recentDocumentURLs
            }
        }
    }

    func openFile(_ url: URL, openWindow: OpenWindowAction) {
        WindowManager.shared.openFile(url)
        openWindow(id: "main")
    }

    func clearRecents() {
        NSDocumentController.shared.clearRecentDocuments(nil)
        recentFiles = []
    }
}

@main
struct CCPlanViewApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @Environment(\.openWindow) private var openWindow
    @State private var recentFilesManager = RecentFilesManager.shared

    var body: some Scene {
        WindowGroup(id: "main") {
            MainContentView()
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
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open...") {
                    openFileWithPanel()
                }
                .keyboardShortcut("o", modifiers: .command)

                Menu("Open Recent") {
                    ForEach(recentFilesManager.recentFiles, id: \.self) { url in
                        Button(url.lastPathComponent) {
                            recentFilesManager.openFile(url, openWindow: openWindow)
                        }
                    }

                    if !recentFilesManager.recentFiles.isEmpty {
                        Divider()
                    }

                    Button("Clear Menu") {
                        recentFilesManager.clearRecents()
                    }
                    .disabled(recentFilesManager.recentFiles.isEmpty)
                }
            }
        }
    }

    private func openFileWithPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        if panel.runModal() == .OK, let url = panel.url {
            // If no windows exist, store URL and create window
            if NSApp.windows.filter({ $0.isVisible }).isEmpty {
                WindowManager.shared.openFile(url)
                openWindow(id: "main")
            } else {
                NotificationCenter.default.post(
                    name: .openFileInWindow,
                    object: nil,
                    userInfo: ["url": url]
                )
            }
        }
    }
}

struct MainContentView: View {
    @StateObject private var document = MarkdownDocument()
    @State private var fileURL: URL?
    @Environment(\.colorScheme) private var colorScheme

    private var backgroundColor: Color {
        colorScheme == .dark
            ? Color(nsColor: NSColor(red: 0.051, green: 0.067, blue: 0.09, alpha: 1))
            : Color.white
    }

    var body: some View {
        ZStack(alignment: .top) {
            backgroundColor

            if document.fileURL != nil {
                MarkdownWebView(
                    markdown: document.markdownContent,
                    fileURL: document.fileURL,
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
        .navigationTitle(document.fileURL?.lastPathComponent ?? "CCPlanView")
        .onAppear {
            // Check if there's a pending URL from AppDelegate
            if let url = WindowManager.shared.consumeURL() {
                openFile(url)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openFileInWindow)) { notification in
            if let url = notification.userInfo?["url"] as? URL {
                openFile(url)
            }
        }
    }

    private func openFile(_ url: URL) {
        fileURL = url
        document.open(url: url)
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
        NotificationCenter.default.post(name: .recentFilesDidChange, object: nil)
    }

    private func showOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        if panel.runModal() == .OK, let url = panel.url {
            openFile(url)
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

extension Notification.Name {
    static let openFileInWindow = Notification.Name("openFileInWindow")
    static let recentFilesDidChange = Notification.Name("recentFilesDidChange")
}
