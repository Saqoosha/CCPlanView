import Foundation

/// CCPlanView Hook Notifier
/// This CLI tool is called by Claude Code hooks to notify CCPlanView
/// when plan mode is exited, opening the latest plan file.

/// Resolve plans directory from Claude Code settings
/// Priority: .claude/settings.local.json > .claude/settings.json > ~/.claude/settings.json > default
func resolvePlansDirectory() -> URL {
    let fm = FileManager.default
    let homeDir = fm.homeDirectoryForCurrentUser
    let defaultDir = homeDir.appendingPathComponent(".claude/plans")

    // Settings files to check (in priority order)
    let settingsFiles = [
        URL(fileURLWithPath: ".claude/settings.local.json"),
        URL(fileURLWithPath: ".claude/settings.json"),
        homeDir.appendingPathComponent(".claude/settings.json")
    ]

    for settingsURL in settingsFiles {
        guard fm.fileExists(atPath: settingsURL.path),
              let data = try? Data(contentsOf: settingsURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let plansDir = json["plansDirectory"] as? String else {
            continue
        }

        // Expand ~ and resolve relative paths
        let expandedPath = NSString(string: plansDir).expandingTildeInPath
        if expandedPath.hasPrefix("/") {
            return URL(fileURLWithPath: expandedPath)
        } else {
            // Relative path - resolve from current directory
            return URL(fileURLWithPath: expandedPath).standardizedFileURL
        }
    }

    return defaultDir
}

// Find the latest plan file
let plansDir = resolvePlansDirectory()

guard FileManager.default.fileExists(atPath: plansDir.path) else {
    // No plans directory, exit silently
    exit(0)
}

let contents: [URL]
do {
    contents = try FileManager.default.contentsOfDirectory(
        at: plansDir,
        includingPropertiesForKeys: [.contentModificationDateKey],
        options: [.skipsHiddenFiles]
    )
} catch {
    exit(0)
}

// Filter for markdown files and sort by modification date
let mdFiles = contents.filter { url in
    let ext = url.pathExtension.lowercased()
    return ["md", "markdown", "mdown", "mkd"].contains(ext)
}

guard !mdFiles.isEmpty else {
    exit(0)
}

let sortedFiles = mdFiles.sorted { url1, url2 in
    let date1 = (try? url1.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
    let date2 = (try? url2.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
    return date1 > date2
}

guard let latestFile = sortedFiles.first else {
    exit(0)
}

// Resolve symlinks to get the real path
let resolvedPath = latestFile.resolvingSymlinksInPath().path

// URL encode the path using a safe character set (RFC 3986 unreserved characters)
let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
guard let encodedPath = resolvedPath.addingPercentEncoding(withAllowedCharacters: allowedCharacters) else {
    exit(1)
}

// Open the file in CCPlanView
let openProcess = Process()
openProcess.executableURL = URL(fileURLWithPath: "/usr/bin/open")
openProcess.arguments = ["-a", "CCPlanView", resolvedPath]
try? openProcess.run()
openProcess.waitUntilExit()

// Small delay to let the app open
Thread.sleep(forTimeInterval: 0.5)

// Send refresh notification via URL scheme
let refreshURL = URL(string: "ccplanview://refresh?file=\(encodedPath)")!
let urlProcess = Process()
urlProcess.executableURL = URL(fileURLWithPath: "/usr/bin/open")
urlProcess.arguments = [refreshURL.absoluteString]
try? urlProcess.run()
urlProcess.waitUntilExit()
