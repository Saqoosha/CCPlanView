import Foundation

enum HookManagerError: LocalizedError, Equatable {
    case settingsCorrupted
    case settingsUnreadable
    case unexpectedStructure
    case notifierNotFound

    var errorDescription: String? {
        switch self {
        case .settingsCorrupted:
            return "Claude Code settings.json is corrupted or not valid JSON."
        case .settingsUnreadable:
            return "Could not read Claude Code settings.json. Check file permissions."
        case .unexpectedStructure:
            return "Claude Code settings.json has unexpected structure."
        case .notifierNotFound:
            return "The notifier CLI tool was not found in the app bundle."
        }
    }
}

enum HookManager {
    /// Claude Code settings directory (can be overridden for testing)
    nonisolated(unsafe) static var claudeDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude")
    static var settingsPath: URL { claudeDir.appendingPathComponent("settings.json") }

    /// Unique identifier for CCPlanView hook command (used for detection and removal)
    private static let hookIdentifier = "CCPlanView.app/Contents/MacOS/notifier"

    /// Legacy hook identifier for migration from old command format
    private static let legacyHookIdentifier = "open -a 'CCPlanView'"

    /// The matcher for CCPlanView hook - must match BOTH matcher AND command identifier
    private static let hookMatcher = "ExitPlanMode"

    /// Get the path to the notifier CLI tool in the current app bundle
    /// Returns nil if the notifier doesn't exist
    private static func getNotifierPath() -> String? {
        let bundlePath = Bundle.main.bundlePath
        let notifierPath = "\(bundlePath)/Contents/MacOS/notifier"
        return FileManager.default.fileExists(atPath: notifierPath) ? notifierPath : nil
    }

    /// Check if Claude Code is installed (.claude directory exists)
    static func isClaudeCodeInstalled() -> Bool {
        FileManager.default.fileExists(atPath: claudeDir.path)
    }

    /// Validate settings.json and return any error
    /// Returns nil if settings are valid or don't exist yet
    static func validateSettings() -> HookManagerError? {
        guard FileManager.default.fileExists(atPath: settingsPath.path) else {
            return nil  // No settings file is fine
        }

        do {
            _ = try readSettings()
            return nil
        } catch let error as HookManagerError {
            return error
        } catch {
            return .settingsUnreadable
        }
    }

    /// Check if CCPlanView hook is configured
    /// Uses both matcher AND command identifier to avoid false positives
    /// Returns false if settings can't be read (file doesn't exist or errors)
    static func isHookConfigured() -> Bool {
        guard let settings = try? readSettings() else { return false }
        return findCCPlanViewHookIndex(in: settings) != nil
    }

    /// Check if hook needs update (cleanup required)
    /// Returns true if any of:
    /// - Legacy hook exists
    /// - Hook path doesn't match current app bundle
    /// - Multiple CCPlanView hooks exist
    static func needsHookUpdate() -> Bool {
        guard let settings = try? readSettings(),
              let hooks = settings["hooks"] as? [String: Any],
              let preToolUse = hooks["PreToolUse"] as? [Any]
        else {
            return false
        }

        guard let currentNotifierPath = getNotifierPath() else {
            return false  // Can't update if notifier doesn't exist
        }

        var ccplanviewHookCount = 0
        var hasCorrectPath = false

        for item in preToolUse {
            guard let hookEntry = item as? [String: Any],
                  let matcher = hookEntry["matcher"] as? String,
                  matcher == hookMatcher,
                  let hooksList = hookEntry["hooks"] as? [[String: Any]]
            else {
                continue
            }

            for hook in hooksList {
                guard let command = hook["command"] as? String else { continue }

                // Check for legacy or new format
                if command.contains(hookIdentifier) || command.contains(legacyHookIdentifier) {
                    ccplanviewHookCount += 1

                    // Check if this is the correct path
                    if command == currentNotifierPath {
                        hasCorrectPath = true
                    }
                }
            }
        }

        // Needs update if: multiple hooks, or no correct path hook exists
        return ccplanviewHookCount > 1 || (ccplanviewHookCount > 0 && !hasCorrectPath)
    }

    /// Clean up and reinstall hook
    /// Removes ALL CCPlanView hooks (legacy and new format) and installs fresh one
    /// All operations are performed in a single file coordination block to prevent race conditions
    static func cleanupAndInstallHook() throws {
        guard let notifierPath = getNotifierPath() else {
            throw HookManagerError.notifierNotFound
        }

        try withFileCoordination(writing: true) {
            var settings = try readSettingsOrEmpty()

            // Validate and get hooks object
            if let existing = settings["hooks"], !(existing is [String: Any]) {
                throw HookManagerError.unexpectedStructure
            }
            var hooks = settings["hooks"] as? [String: Any] ?? [:]

            // Get PreToolUse array
            if let existing = hooks["PreToolUse"], !(existing is [Any]) {
                throw HookManagerError.unexpectedStructure
            }
            var preToolUse = hooks["PreToolUse"] as? [Any] ?? []

            // Remove all existing CCPlanView hooks
            let indicesToRemove = findAllCCPlanViewHookIndices(preToolUse: preToolUse)
            for index in indicesToRemove.reversed() {
                preToolUse.remove(at: index)
            }

            // Add fresh hook
            let ccplanviewHook: [String: Any] = [
                "hooks": [
                    [
                        "command": notifierPath,
                        "timeout": 10,
                        "type": "command",
                    ] as [String: Any],
                ],
                "matcher": hookMatcher,
            ]
            preToolUse.append(ccplanviewHook)
            hooks["PreToolUse"] = preToolUse
            settings["hooks"] = hooks

            try writeSettings(settings)
        }
    }

    /// Install the CCPlanView hook into settings.json
    /// Uses merge strategy to preserve existing settings
    /// Thread-safe via file coordination
    static func installHook() throws {
        guard let notifierPath = getNotifierPath() else {
            throw HookManagerError.notifierNotFound
        }

        try withFileCoordination(writing: true) {
            // Skip if already installed
            if isHookConfigured() { return }

            var settings = try readSettingsOrEmpty()

            // Validate and get hooks object
            if let existing = settings["hooks"], !(existing is [String: Any]) {
                throw HookManagerError.unexpectedStructure
            }
            var hooks = settings["hooks"] as? [String: Any] ?? [:]

            // Get PreToolUse array - support mixed arrays by working with [Any]
            // Only reject if PreToolUse exists but is not an array at all
            if let existing = hooks["PreToolUse"], !(existing is [Any]) {
                throw HookManagerError.unexpectedStructure
            }
            var preToolUse = hooks["PreToolUse"] as? [Any] ?? []

            // Create the CCPlanView hook entry
            let ccplanviewHook: [String: Any] = [
                "hooks": [
                    [
                        "command": notifierPath,
                        "timeout": 10,
                        "type": "command",
                    ] as [String: Any],
                ],
                "matcher": hookMatcher,
            ]

            // Add to PreToolUse array
            preToolUse.append(ccplanviewHook)
            hooks["PreToolUse"] = preToolUse
            settings["hooks"] = hooks

            // Write settings back
            try writeSettings(settings)
        }
    }

    /// Remove the CCPlanView hook from settings.json
    /// Only removes hooks matching BOTH ExitPlanMode matcher AND CCPlanView command
    /// Thread-safe via file coordination
    /// Handles mixed arrays (containing both dictionaries and other types)
    static func removeHook() throws {
        try withFileCoordination(writing: true) {
            guard var settings = try readSettings() else { return }

            guard var hooks = settings["hooks"] as? [String: Any],
                  var preToolUse = hooks["PreToolUse"] as? [Any]
            else {
                return
            }

            // Find CCPlanView hook index in mixed array
            if let index = findCCPlanViewHookIndexInMixedArray(preToolUse: preToolUse) {
                preToolUse.remove(at: index)
                hooks["PreToolUse"] = preToolUse
                settings["hooks"] = hooks
                try writeSettings(settings)
            }
        }
    }

    // MARK: - Private

    /// Find CCPlanView hook index checking BOTH matcher AND command identifier
    /// Handles mixed arrays where some elements may not be dictionaries
    private static func findCCPlanViewHookIndex(in settings: [String: Any]) -> Int? {
        guard let hooks = settings["hooks"] as? [String: Any],
              let preToolUse = hooks["PreToolUse"] as? [Any]
        else {
            return nil
        }
        return findCCPlanViewHookIndexInMixedArray(preToolUse: preToolUse)
    }

    /// Internal helper to find CCPlanView hook index in potentially mixed PreToolUse array
    /// Skips non-dictionary entries and searches only valid hook entries
    /// Detects both new CLI tool format and legacy bash command format
    private static func findCCPlanViewHookIndexInMixedArray(preToolUse: [Any]) -> Int? {
        findAllCCPlanViewHookIndices(preToolUse: preToolUse).first
    }

    /// Find ALL CCPlanView hook indices in PreToolUse array
    /// Returns indices of all hooks matching either new or legacy format
    private static func findAllCCPlanViewHookIndices(preToolUse: [Any]) -> [Int] {
        var indices: [Int] = []

        for (index, item) in preToolUse.enumerated() {
            // Skip non-dictionary entries
            guard let hookEntry = item as? [String: Any] else { continue }

            // Must have ExitPlanMode matcher
            guard let matcher = hookEntry["matcher"] as? String,
                  matcher == hookMatcher
            else {
                continue
            }

            // Must have command containing our identifier (new or legacy)
            guard let hooksList = hookEntry["hooks"] as? [[String: Any]] else { continue }
            let hasOurCommand = hooksList.contains { hook in
                guard let command = hook["command"] as? String else { return false }
                return command.contains(hookIdentifier) || command.contains(legacyHookIdentifier)
            }

            if hasOurCommand {
                indices.append(index)
            }
        }
        return indices
    }

    /// Read settings, returning nil only if file doesn't exist
    /// Throws error if file exists but can't be read or parsed
    private static func readSettings() throws -> [String: Any]? {
        guard FileManager.default.fileExists(atPath: settingsPath.path) else {
            return nil
        }

        let data: Data
        do {
            data = try Data(contentsOf: settingsPath)
        } catch {
            throw HookManagerError.settingsUnreadable
        }

        guard let json = try? JSONSerialization.jsonObject(with: data),
              let settings = json as? [String: Any]
        else {
            throw HookManagerError.settingsCorrupted
        }

        return settings
    }

    /// Read settings, returning empty dict if file doesn't exist
    /// Throws error if file exists but can't be read or parsed
    private static func readSettingsOrEmpty() throws -> [String: Any] {
        try readSettings() ?? [:]
    }

    private static func writeSettings(_ settings: [String: Any]) throws {
        // Create .claude directory if it doesn't exist
        if !FileManager.default.fileExists(atPath: claudeDir.path) {
            try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)
        }

        let data = try JSONSerialization.data(
            withJSONObject: settings,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )

        try data.write(to: settingsPath, options: .atomic)
    }

    /// Execute a block with file coordination for thread safety
    /// This prevents concurrent read-modify-write issues
    private static func withFileCoordination(writing: Bool, block: () throws -> Void) throws {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinatorError: NSError?
        var blockError: Error?

        let intent: NSFileCoordinator.WritingOptions = writing ? .forMerging : []

        coordinator.coordinate(
            writingItemAt: settingsPath,
            options: intent,
            error: &coordinatorError
        ) { _ in
            do {
                try block()
            } catch {
                blockError = error
            }
        }

        if let error = coordinatorError {
            throw error
        }
        if let error = blockError {
            throw error
        }
    }
}
