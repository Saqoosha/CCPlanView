#!/usr/bin/env swift

import Foundation

// MARK: - HookManager Implementation (must be kept in sync with Sources/CCPlanView/HookManager.swift)
// This is a copy because Swift scripts cannot import from the main target.
// When modifying HookManager.swift, update this copy as well.

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
    static var claudeDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude")
    static var settingsPath: URL { claudeDir.appendingPathComponent("settings.json") }

    /// Unique identifier for CCPlanView hook command (used for detection and removal)
    private static let hookIdentifier = "CCPlanView.app/Contents/MacOS/notifier"

    /// Legacy hook identifier for migration from old command format
    private static let legacyHookIdentifier = "open -a 'CCPlanView'"

    /// The matcher for CCPlanView hook - must match BOTH matcher AND command identifier
    private static let hookMatcher = "ExitPlanMode"

    /// The hook command for CCPlanView (used in tests only)
    private static let hookCommand = "/Applications/CCPlanView.app/Contents/MacOS/notifier"

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

        // For testing, we use the hardcoded path
        let currentNotifierPath = hookCommand

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
    static func cleanupAndInstallHook() throws {
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
                        "command": hookCommand,
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

    static func installHook() throws {
        try withFileCoordination(writing: true) {
            if isHookConfigured() { return }

            var settings = try readSettingsOrEmpty()

            if let existing = settings["hooks"], !(existing is [String: Any]) {
                throw HookManagerError.unexpectedStructure
            }
            var hooks = settings["hooks"] as? [String: Any] ?? [:]

            // Get PreToolUse array - support mixed arrays by working with [Any]
            if let existing = hooks["PreToolUse"], !(existing is [Any]) {
                throw HookManagerError.unexpectedStructure
            }
            var preToolUse = hooks["PreToolUse"] as? [Any] ?? []

            let ccplanviewHook: [String: Any] = [
                "hooks": [
                    [
                        "command": hookCommand,
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

    static func removeHook() throws {
        try withFileCoordination(writing: true) {
            guard var settings = try readSettings() else { return }

            guard var hooks = settings["hooks"] as? [String: Any],
                  var preToolUse = hooks["PreToolUse"] as? [Any]
            else {
                return
            }

            if let index = findCCPlanViewHookIndexInMixedArray(preToolUse: preToolUse) {
                preToolUse.remove(at: index)
                hooks["PreToolUse"] = preToolUse
                settings["hooks"] = hooks
                try writeSettings(settings)
            }
        }
    }

    private static func findCCPlanViewHookIndex(in settings: [String: Any]) -> Int? {
        guard let hooks = settings["hooks"] as? [String: Any],
              let preToolUse = hooks["PreToolUse"] as? [Any]
        else {
            return nil
        }
        return findCCPlanViewHookIndexInMixedArray(preToolUse: preToolUse)
    }

    private static func findCCPlanViewHookIndexInMixedArray(preToolUse: [Any]) -> Int? {
        findAllCCPlanViewHookIndices(preToolUse: preToolUse).first
    }

    /// Find ALL CCPlanView hook indices in PreToolUse array
    /// Returns indices of all hooks matching either new or legacy format
    private static func findAllCCPlanViewHookIndices(preToolUse: [Any]) -> [Int] {
        var indices: [Int] = []

        for (index, item) in preToolUse.enumerated() {
            guard let hookEntry = item as? [String: Any] else { continue }

            guard let matcher = hookEntry["matcher"] as? String,
                  matcher == hookMatcher
            else {
                continue
            }

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

    static func readSettings() throws -> [String: Any]? {
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

    static func readSettingsOrEmpty() throws -> [String: Any] {
        try readSettings() ?? [:]
    }

    static func writeSettings(_ settings: [String: Any]) throws {
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

// MARK: - Test Framework

struct TestError: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}

var testsPassed = 0
var testsFailed = 0

func test(_ name: String, _ block: () throws -> Void) {
    // Reset test directory for each test
    HookManager.claudeDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("HookManagerTest-\(UUID().uuidString)")

    do {
        try block()
        print("✅ \(name)")
        testsPassed += 1
    } catch {
        print("❌ \(name): \(error)")
        testsFailed += 1
    }

    // Cleanup
    try? FileManager.default.removeItem(at: HookManager.claudeDir)
}

func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String = "") throws {
    guard actual == expected else {
        throw TestError(message: "Expected \(expected), got \(actual). \(message)")
    }
}

func assertTrue(_ condition: Bool, _ message: String = "") throws {
    guard condition else {
        throw TestError(message: "Expected true. \(message)")
    }
}

func assertFalse(_ condition: Bool, _ message: String = "") throws {
    guard !condition else {
        throw TestError(message: "Expected false. \(message)")
    }
}

func assertThrows<E: Error & Equatable>(_ expectedError: E, _ block: () throws -> Void) throws {
    do {
        try block()
        throw TestError(message: "Expected error \(expectedError) but no error was thrown")
    } catch let error as E {
        guard error == expectedError else {
            throw TestError(message: "Expected error \(expectedError) but got \(error)")
        }
    } catch {
        throw TestError(message: "Expected error \(expectedError) but got \(type(of: error)): \(error)")
    }
}

func assertNil<T>(_ value: T?, _ message: String = "") throws {
    guard value == nil else {
        throw TestError(message: "Expected nil, got \(value!). \(message)")
    }
}

func assertNotNil<T>(_ value: T?, _ message: String = "") throws {
    guard value != nil else {
        throw TestError(message: "Expected non-nil value. \(message)")
    }
}

func writeTestSettings(_ content: String) throws {
    try FileManager.default.createDirectory(at: HookManager.claudeDir, withIntermediateDirectories: true)
    try content.write(to: HookManager.settingsPath, atomically: true, encoding: .utf8)
}

func readTestSettings() throws -> [String: Any] {
    let data = try Data(contentsOf: HookManager.settingsPath)
    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw TestError(message: "Failed to parse settings.json as dictionary")
    }
    return json
}

func getPreToolUse(_ settings: [String: Any]) throws -> [[String: Any]] {
    guard let hooks = settings["hooks"] as? [String: Any] else {
        throw TestError(message: "hooks key not found or not a dictionary")
    }
    guard let preToolUse = hooks["PreToolUse"] as? [[String: Any]] else {
        throw TestError(message: "PreToolUse key not found or not an array of dictionaries")
    }
    return preToolUse
}

func getPreToolUseAny(_ settings: [String: Any]) throws -> [Any] {
    guard let hooks = settings["hooks"] as? [String: Any] else {
        throw TestError(message: "hooks key not found or not a dictionary")
    }
    guard let preToolUse = hooks["PreToolUse"] as? [Any] else {
        throw TestError(message: "PreToolUse key not found or not an array")
    }
    return preToolUse
}

func getHookCommand(_ hookEntry: [String: Any]) throws -> String {
    guard let hooksList = hookEntry["hooks"] as? [[String: Any]],
          let firstHook = hooksList.first,
          let command = firstHook["command"] as? String
    else {
        throw TestError(message: "Could not extract command from hook entry")
    }
    return command
}

// MARK: - Tests

print("=== HookManager Tests ===\n")

// MARK: Basic Installation Tests

test("Install hook when settings.json doesn't exist") {
    try assertFalse(HookManager.isClaudeCodeInstalled())
    try assertFalse(HookManager.isHookConfigured())

    try HookManager.installHook()

    try assertTrue(HookManager.isClaudeCodeInstalled())
    try assertTrue(HookManager.isHookConfigured())
}

test("Install hook when empty settings.json exists") {
    try writeTestSettings("{}")

    try HookManager.installHook()

    try assertTrue(HookManager.isHookConfigured())
    let settings = try readTestSettings()
    let preToolUse = try getPreToolUse(settings)
    try assertEqual(preToolUse.count, 1)
}

test("Install hook preserves existing hooks") {
    try writeTestSettings("""
    {
        "hooks": {
            "PreToolUse": [
                {
                    "matcher": "SomeOtherTool",
                    "hooks": [{"command": "echo test", "type": "command"}]
                }
            ]
        }
    }
    """)

    try HookManager.installHook()

    let settings = try readTestSettings()
    let preToolUse = try getPreToolUse(settings)
    try assertEqual(preToolUse.count, 2)
}

test("Install hook is idempotent") {
    try HookManager.installHook()
    try HookManager.installHook()
    try HookManager.installHook()

    let settings = try readTestSettings()
    let preToolUse = try getPreToolUse(settings)
    try assertEqual(preToolUse.count, 1)
}

// MARK: Remove Hook Tests

test("Remove hook when configured") {
    try HookManager.installHook()
    try assertTrue(HookManager.isHookConfigured())

    try HookManager.removeHook()

    try assertFalse(HookManager.isHookConfigured())
}

test("Remove hook preserves other hooks") {
    try writeTestSettings("""
    {
        "hooks": {
            "PreToolUse": [
                {
                    "matcher": "SomeOtherTool",
                    "hooks": [{"command": "echo test", "type": "command"}]
                }
            ]
        }
    }
    """)
    try HookManager.installHook()

    let settingsBefore = try readTestSettings()
    let preToolUseBefore = try getPreToolUse(settingsBefore)
    try assertEqual(preToolUseBefore.count, 2)

    try HookManager.removeHook()

    let settingsAfter = try readTestSettings()
    let preToolUseAfter = try getPreToolUse(settingsAfter)
    try assertEqual(preToolUseAfter.count, 1)
    try assertEqual(preToolUseAfter[0]["matcher"] as? String, "SomeOtherTool")
}

test("Remove hook when not configured does nothing") {
    try writeTestSettings("{}")

    try HookManager.removeHook()

    try assertFalse(HookManager.isHookConfigured())
}

// MARK: Error Handling Tests

test("validateSettings returns nil for valid settings") {
    try writeTestSettings("{}")
    try assertNil(HookManager.validateSettings())
}

test("validateSettings returns nil when file doesn't exist") {
    try assertNil(HookManager.validateSettings())
}

test("validateSettings returns settingsCorrupted for invalid JSON") {
    try writeTestSettings("not valid json")
    try assertEqual(HookManager.validateSettings(), HookManagerError.settingsCorrupted)
}

test("validateSettings returns settingsCorrupted for non-object JSON") {
    try writeTestSettings("[1, 2, 3]")
    try assertEqual(HookManager.validateSettings(), HookManagerError.settingsCorrupted)
}

test("installHook throws unexpectedStructure when hooks is not object") {
    try writeTestSettings("""
    {"hooks": "not an object"}
    """)

    try assertThrows(HookManagerError.unexpectedStructure) {
        try HookManager.installHook()
    }
}

test("installHook throws unexpectedStructure when PreToolUse is not array") {
    try writeTestSettings("""
    {"hooks": {"PreToolUse": "not an array"}}
    """)

    try assertThrows(HookManagerError.unexpectedStructure) {
        try HookManager.installHook()
    }
}

// MARK: Mixed Array Support Tests

test("isHookConfigured works with mixed PreToolUse array") {
    try writeTestSettings("""
    {
        "hooks": {
            "PreToolUse": [
                "string entry",
                123,
                null,
                {
                    "matcher": "ExitPlanMode",
                    "hooks": [{"command": "/Applications/CCPlanView.app/Contents/MacOS/notifier", "type": "command"}]
                }
            ]
        }
    }
    """)

    try assertTrue(HookManager.isHookConfigured())
}

test("removeHook works with mixed PreToolUse array") {
    try writeTestSettings("""
    {
        "hooks": {
            "PreToolUse": [
                "string entry",
                {
                    "matcher": "ExitPlanMode",
                    "hooks": [{"command": "/Applications/CCPlanView.app/Contents/MacOS/notifier", "type": "command"}]
                },
                123
            ]
        }
    }
    """)

    try HookManager.removeHook()

    try assertFalse(HookManager.isHookConfigured())
    let settings = try readTestSettings()
    let preToolUse = try getPreToolUseAny(settings)
    try assertEqual(preToolUse.count, 2)
}

// MARK: Hook Detection Tests

test("isHookConfigured requires both matcher and command") {
    // Wrong matcher with right command
    try writeTestSettings("""
    {
        "hooks": {
            "PreToolUse": [
                {
                    "matcher": "WrongMatcher",
                    "hooks": [{"command": "/Applications/CCPlanView.app/Contents/MacOS/notifier", "type": "command"}]
                }
            ]
        }
    }
    """)
    try assertFalse(HookManager.isHookConfigured())
}

test("isHookConfigured detects hook with correct matcher and command") {
    try writeTestSettings("""
    {
        "hooks": {
            "PreToolUse": [
                {
                    "matcher": "ExitPlanMode",
                    "hooks": [{"command": "/Applications/CCPlanView.app/Contents/MacOS/notifier", "type": "command"}]
                }
            ]
        }
    }
    """)
    try assertTrue(HookManager.isHookConfigured())
}

// MARK: Cleanup Tests

test("needsHookUpdate returns false when no hooks") {
    try writeTestSettings("{}")
    try assertFalse(HookManager.needsHookUpdate())
}

test("needsHookUpdate returns true for legacy hook") {
    try writeTestSettings("""
    {
        "hooks": {
            "PreToolUse": [
                {
                    "matcher": "ExitPlanMode",
                    "hooks": [{"command": "open -a 'CCPlanView' test.md", "type": "command"}]
                }
            ]
        }
    }
    """)
    try assertTrue(HookManager.needsHookUpdate())
}

test("needsHookUpdate returns true for wrong path") {
    try writeTestSettings("""
    {
        "hooks": {
            "PreToolUse": [
                {
                    "matcher": "ExitPlanMode",
                    "hooks": [{"command": "/Wrong/Path/CCPlanView.app/Contents/MacOS/notifier", "type": "command"}]
                }
            ]
        }
    }
    """)
    try assertTrue(HookManager.needsHookUpdate())
}

test("needsHookUpdate returns true for multiple hooks") {
    try writeTestSettings("""
    {
        "hooks": {
            "PreToolUse": [
                {
                    "matcher": "ExitPlanMode",
                    "hooks": [{"command": "/Applications/CCPlanView.app/Contents/MacOS/notifier", "type": "command"}]
                },
                {
                    "matcher": "ExitPlanMode",
                    "hooks": [{"command": "open -a 'CCPlanView' test.md", "type": "command"}]
                }
            ]
        }
    }
    """)
    try assertTrue(HookManager.needsHookUpdate())
}

test("cleanupAndInstallHook removes all old hooks and installs fresh") {
    try writeTestSettings("""
    {
        "hooks": {
            "PreToolUse": [
                {
                    "matcher": "ExitPlanMode",
                    "hooks": [{"command": "/Wrong/Path/CCPlanView.app/Contents/MacOS/notifier", "type": "command"}]
                },
                {
                    "matcher": "ExitPlanMode",
                    "hooks": [{"command": "open -a 'CCPlanView' test.md", "type": "command"}]
                },
                {
                    "matcher": "OtherMatcher",
                    "hooks": [{"command": "echo other", "type": "command"}]
                }
            ]
        }
    }
    """)

    try HookManager.cleanupAndInstallHook()

    let settings = try readTestSettings()
    let preToolUse = try getPreToolUse(settings)
    try assertEqual(preToolUse.count, 2)

    // Check that other hook is preserved
    let otherHook = preToolUse.first { ($0["matcher"] as? String) == "OtherMatcher" }
    try assertNotNil(otherHook)

    // Check that CCPlanView hook has correct path
    let ccplanviewHook = preToolUse.first { ($0["matcher"] as? String) == "ExitPlanMode" }
    try assertNotNil(ccplanviewHook)
    let command = try getHookCommand(ccplanviewHook!)
    try assertEqual(command, "/Applications/CCPlanView.app/Contents/MacOS/notifier")
}

// MARK: - Summary

print("\n=== Results ===")
print("Passed: \(testsPassed)")
print("Failed: \(testsFailed)")

if testsFailed > 0 {
    exit(1)
}
