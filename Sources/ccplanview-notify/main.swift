import Foundation

/// ccplanview-notify - CLI tool for notifying CCPlanView to refresh
///
/// Usage:
///   ccplanview-notify [file]     Open file in CCPlanView and refresh
///   ccplanview-notify --latest   Find and open the latest plan file from ~/.claude/plans/
///   ccplanview-notify --help     Show this help message
///
/// If no argument is provided, behaves like --latest
///
/// This tool is designed to be used in Claude Code hooks for automatic plan file viewing.

let appName = "CCPlanView"
let urlScheme = "ccplanview"

func printUsage() {
    print("""
    ccplanview-notify - Notify CCPlanView to open and refresh a file

    Usage:
      ccplanview-notify [file]     Open file in CCPlanView and refresh
      ccplanview-notify --latest   Find and open the latest plan file
      ccplanview-notify --help     Show this help message

    If no argument is provided, behaves like --latest (finds latest plan in ~/.claude/plans/)

    Examples:
      ccplanview-notify ~/docs/plan.md    # Open specific file
      ccplanview-notify --latest          # Open latest plan file
      ccplanview-notify                   # Same as --latest
    """)
}

func findLatestPlanFile() -> URL? {
    let homeDir = FileManager.default.homeDirectoryForCurrentUser
    let plansDir = homeDir.appendingPathComponent(".claude/plans")

    guard FileManager.default.fileExists(atPath: plansDir.path) else {
        return nil
    }

    do {
        let files = try FileManager.default.contentsOfDirectory(
            at: plansDir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )

        let mdFiles = files.filter { $0.pathExtension == "md" }

        let sorted = try mdFiles.sorted { file1, file2 in
            let date1 =
                try file1.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate ?? .distantPast
            let date2 =
                try file2.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate ?? .distantPast
            return date1 > date2
        }

        return sorted.first
    } catch {
        return nil
    }
}

func openFile(_ fileURL: URL) -> Bool {
    // Resolve symlinks to get the real path
    let resolvedPath = fileURL.resolvingSymlinksInPath().path

    // Open the file with CCPlanView
    let openProcess = Process()
    openProcess.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    openProcess.arguments = ["-a", appName, resolvedPath]

    do {
        try openProcess.run()
        openProcess.waitUntilExit()

        if openProcess.terminationStatus != 0 {
            fputs("Error: Failed to open \(appName)\n", stderr)
            return false
        }
    } catch {
        fputs("Error: \(error.localizedDescription)\n", stderr)
        return false
    }

    return true
}

func sendRefreshURL(_ fileURL: URL) -> Bool {
    // Resolve symlinks and URL-encode the path
    let resolvedPath = fileURL.resolvingSymlinksInPath().path

    guard
        let encodedPath = resolvedPath.addingPercentEncoding(
            withAllowedCharacters: .urlQueryAllowed)
    else {
        fputs("Error: Failed to encode file path\n", stderr)
        return false
    }

    let refreshURLString = "\(urlScheme)://refresh?file=\(encodedPath)"

    guard let refreshURL = URL(string: refreshURLString) else {
        fputs("Error: Failed to create refresh URL\n", stderr)
        return false
    }

    // Small delay to ensure app is ready
    Thread.sleep(forTimeInterval: 0.3)

    // Open the URL scheme
    let urlProcess = Process()
    urlProcess.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    urlProcess.arguments = [refreshURL.absoluteString]

    do {
        try urlProcess.run()
        urlProcess.waitUntilExit()

        if urlProcess.terminationStatus != 0 {
            fputs("Error: Failed to send refresh notification\n", stderr)
            return false
        }
    } catch {
        fputs("Error: \(error.localizedDescription)\n", stderr)
        return false
    }

    return true
}

func notify(fileURL: URL) -> Bool {
    guard FileManager.default.fileExists(atPath: fileURL.path) else {
        fputs("Error: File not found: \(fileURL.path)\n", stderr)
        return false
    }

    guard openFile(fileURL) else {
        return false
    }

    guard sendRefreshURL(fileURL) else {
        return false
    }

    return true
}

// MARK: - Main

let args = CommandLine.arguments.dropFirst()

if args.contains("--help") || args.contains("-h") {
    printUsage()
    exit(0)
}

let fileURL: URL

if args.isEmpty || args.first == "--latest" {
    // Find latest plan file
    guard let latestFile = findLatestPlanFile() else {
        fputs("No plan files found in ~/.claude/plans/\n", stderr)
        exit(1)
    }
    fileURL = latestFile
} else {
    // Use provided file path
    let filePath = args.first!
    if filePath.hasPrefix("/") {
        fileURL = URL(fileURLWithPath: filePath)
    } else if filePath.hasPrefix("~") {
        let expandedPath =
            (filePath as NSString).expandingTildeInPath
        fileURL = URL(fileURLWithPath: expandedPath)
    } else {
        // Relative path - resolve from current directory
        let currentDir = FileManager.default.currentDirectoryPath
        fileURL = URL(fileURLWithPath: currentDir).appendingPathComponent(filePath)
    }
}

if notify(fileURL: fileURL) {
    exit(0)
} else {
    exit(1)
}
