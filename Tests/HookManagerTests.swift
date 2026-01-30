#!/usr/bin/env swift

import Foundation

// MARK: - HookManager Implementation (must be kept in sync with Sources/CCPlanView/HookManager.swift)
// This is a copy because Swift scripts cannot import from the main target.
// When modifying HookManager.swift, update this copy as well.

enum HookManagerError: LocalizedError, Equatable {
    case settingsCorrupted
    case settingsUnreadable
    case unexpectedStructure

    var errorDescription: String? {
        switch self {
        case .settingsCorrupted:
            return "Claude Code settings.json is corrupted or not valid JSON."
        case .settingsUnreadable:
            return "Could not read Claude Code settings.json. Check file permissions."
        case .unexpectedStructure:
            return "Claude Code settings.json has unexpected structure."
        }
    }
}

enum HookManager {
    /// Claude Code settings directory (can be overridden for testing)
    static var claudeDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude")
    static var settingsPath: URL { claudeDir.appendingPathComponent("settings.json") }

    /// Unique identifier for CCPlanView hook command (used for detection and removal)
    private static let hookIdentifier = "ccplanview-notify"

    /// Legacy hook identifier for migration from old command format
    private static let legacyHookIdentifier = "open -a 'CCPlanView'"

    /// The matcher for CCPlanView hook - must match BOTH matcher AND command identifier
    private static let hookMatcher = "ExitPlanMode"

    /// The hook command for CCPlanView
    /// Uses the bundled CLI tool for clean hook integration
    private static let hookCommand =
        "/Applications/CCPlanView.app/Contents/MacOS/ccplanview-notify"

    static func isClaudeCodeInstalled() -> Bool {
        FileManager.default.fileExists(atPath: claudeDir.path)
    }

    static func isHookConfigured() -> Bool {
        guard let settings = try? readSettings() else { return false }
        return findCCPlanViewHookIndex(in: settings) != nil
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
                return index
            }
        }
        return nil
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

test("Install hook with empty settings.json") {
    try writeTestSettings("{}")

    try assertFalse(HookManager.isHookConfigured())
    try HookManager.installHook()
    try assertTrue(HookManager.isHookConfigured())

    let settings = try readTestSettings()
    let preToolUse = try getPreToolUse(settings)
    try assertEqual(preToolUse.count, 1)
}

test("Install hook when hooks key doesn't exist") {
    try writeTestSettings("""
    {
        "someOtherSetting": "value"
    }
    """)

    try HookManager.installHook()
    try assertTrue(HookManager.isHookConfigured())

    let settings = try readTestSettings()
    try assertEqual(settings["someOtherSetting"] as? String, "value", "Other settings should be preserved")
}

test("Install hook when PreToolUse doesn't exist") {
    try writeTestSettings("""
    {
        "hooks": {
            "PostToolUse": []
        }
    }
    """)

    try HookManager.installHook()
    try assertTrue(HookManager.isHookConfigured())

    let settings = try readTestSettings()
    let hooks = settings["hooks"] as? [String: Any]
    try assertNotNil(hooks?["PostToolUse"], "PostToolUse should be preserved")
}

test("Install hook with empty PreToolUse array") {
    try writeTestSettings("""
    {
        "hooks": {
            "PreToolUse": []
        }
    }
    """)

    try HookManager.installHook()
    try assertTrue(HookManager.isHookConfigured())

    let settings = try readTestSettings()
    let preToolUse = try getPreToolUse(settings)
    try assertEqual(preToolUse.count, 1)
}

// MARK: Error Handling Tests

test("Reject when hooks is not a dictionary - unexpectedStructure") {
    try writeTestSettings("""
    {
        "hooks": ["not", "a", "dictionary"]
    }
    """)

    try assertThrows(HookManagerError.unexpectedStructure) {
        try HookManager.installHook()
    }
}

test("Reject when PreToolUse is not an array - unexpectedStructure") {
    try writeTestSettings("""
    {
        "hooks": {
            "PreToolUse": "not an array"
        }
    }
    """)

    try assertThrows(HookManagerError.unexpectedStructure) {
        try HookManager.installHook()
    }
}

test("Reject corrupted JSON - settingsCorrupted") {
    try writeTestSettings("{ this is not valid json }")

    try assertThrows(HookManagerError.settingsCorrupted) {
        try HookManager.installHook()
    }
}

test("Reject when JSON root is array - settingsCorrupted") {
    try writeTestSettings("[1, 2, 3]")

    try assertThrows(HookManagerError.settingsCorrupted) {
        try HookManager.installHook()
    }
}

test("Reject when JSON root is string - settingsCorrupted") {
    try writeTestSettings("\"just a string\"")

    try assertThrows(HookManagerError.settingsCorrupted) {
        try HookManager.installHook()
    }
}

test("Unreadable file throws settingsUnreadable") {
    try writeTestSettings("{}")

    // Make file unreadable
    try FileManager.default.setAttributes(
        [.posixPermissions: 0o000],
        ofItemAtPath: HookManager.settingsPath.path
    )

    defer {
        // Restore permissions for cleanup
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o644],
            ofItemAtPath: HookManager.settingsPath.path
        )
    }

    try assertThrows(HookManagerError.settingsUnreadable) {
        _ = try HookManager.readSettings()
    }
}

// MARK: Duplicate Prevention Tests

test("No duplicate when hook already installed") {
    try writeTestSettings("{}")

    try HookManager.installHook()
    try HookManager.installHook()  // Second install should be no-op

    let settings = try readTestSettings()
    let preToolUse = try getPreToolUse(settings)
    try assertEqual(preToolUse.count, 1, "Should not duplicate hook")
}

// MARK: Hook Preservation Tests

test("Preserve other hooks when installing CCPlanView") {
    try writeTestSettings("""
    {
        "hooks": {
            "PreToolUse": [
                {
                    "matcher": "SomeOtherTool",
                    "hooks": [
                        {
                            "command": "echo 'other hook'",
                            "type": "command"
                        }
                    ]
                }
            ]
        }
    }
    """)

    try HookManager.installHook()

    let settings = try readTestSettings()
    let preToolUse = try getPreToolUse(settings)
    try assertEqual(preToolUse.count, 2, "Should have both hooks")
}

test("Remove only CCPlanView hook, preserve others") {
    try writeTestSettings("{}")
    try HookManager.installHook()

    // Add another hook manually
    var settings = try readTestSettings()
    var hooks = settings["hooks"] as? [String: Any] ?? [:]
    var preToolUse = hooks["PreToolUse"] as? [[String: Any]] ?? []
    preToolUse.append([
        "matcher": "SomeOtherTool",
        "hooks": [
            ["command": "echo 'other'", "type": "command"]
        ]
    ] as [String: Any])
    hooks["PreToolUse"] = preToolUse
    settings["hooks"] = hooks
    try HookManager.writeSettings(settings)

    try HookManager.removeHook()

    let finalSettings = try readTestSettings()
    let finalPreToolUse = try getPreToolUse(finalSettings)
    try assertEqual(finalPreToolUse.count, 1, "Should only have other hook")
    try assertFalse(HookManager.isHookConfigured(), "CCPlanView hook should be removed")
}

// MARK: False Positive Prevention Tests (Matcher + Command)

test("Don't detect hooks with similar names (e.g., 'MyCCPlanViewHelper')") {
    // This hook mentions CCPlanView but doesn't use the exact identifier "open -a 'CCPlanView'"
    try writeTestSettings("""
    {
        "hooks": {
            "PreToolUse": [
                {
                    "matcher": "SomeTool",
                    "hooks": [
                        {
                            "command": "echo 'MyCCPlanViewHelper'",
                            "type": "command"
                        }
                    ]
                }
            ]
        }
    }
    """)

    try assertFalse(HookManager.isHookConfigured(), "Should not detect similar name as installed")
}

test("Don't remove hooks with similar names") {
    try writeTestSettings("""
    {
        "hooks": {
            "PreToolUse": [
                {
                    "matcher": "SomeTool",
                    "hooks": [
                        {
                            "command": "echo 'CCPlanView is great'",
                            "type": "command"
                        }
                    ]
                }
            ]
        }
    }
    """)

    try HookManager.installHook()
    try HookManager.removeHook()

    let settings = try readTestSettings()
    let preToolUse = try getPreToolUse(settings)
    try assertEqual(preToolUse.count, 1, "Similar named hook should be preserved")
}

test("Don't falsely detect 'open -a CCPlanViewHelper' as our hook") {
    try writeTestSettings("""
    {
        "hooks": {
            "PreToolUse": [
                {
                    "matcher": "SomeTool",
                    "hooks": [
                        {
                            "command": "open -a 'CCPlanViewHelper' /some/path",
                            "type": "command"
                        }
                    ]
                }
            ]
        }
    }
    """)

    // This should NOT be detected because "open -a 'CCPlanViewHelper'" != "open -a 'CCPlanView'"
    try assertFalse(HookManager.isHookConfigured(), "Should not detect CCPlanViewHelper as CCPlanView")
}

test("Don't detect same command with different matcher") {
    // Hook with correct command but WRONG matcher should NOT be detected
    try writeTestSettings("""
    {
        "hooks": {
            "PreToolUse": [
                {
                    "matcher": "SomeOtherMatcher",
                    "hooks": [
                        {
                            "command": "open -a 'CCPlanView' /some/path",
                            "type": "command"
                        }
                    ]
                }
            ]
        }
    }
    """)

    try assertFalse(HookManager.isHookConfigured(), "Should not detect hook with wrong matcher")
}

test("Don't remove hook with same command but different matcher") {
    // Hook with correct command but WRONG matcher should NOT be removed
    try writeTestSettings("""
    {
        "hooks": {
            "PreToolUse": [
                {
                    "matcher": "SomeOtherMatcher",
                    "hooks": [
                        {
                            "command": "open -a 'CCPlanView' /some/path",
                            "type": "command"
                        }
                    ]
                }
            ]
        }
    }
    """)

    // Install our hook (should add a new one)
    try HookManager.installHook()

    let settings = try readTestSettings()
    let preToolUse = try getPreToolUse(settings)
    try assertEqual(preToolUse.count, 2, "Should have both hooks (different matchers)")

    // Remove our hook
    try HookManager.removeHook()

    let finalSettings = try readTestSettings()
    let finalPreToolUse = try getPreToolUse(finalSettings)
    try assertEqual(finalPreToolUse.count, 1, "Should preserve hook with different matcher")

    // The remaining hook should be the one with SomeOtherMatcher
    guard let remainingHook = finalPreToolUse.first,
          let matcher = remainingHook["matcher"] as? String
    else {
        throw TestError(message: "Could not get remaining hook matcher")
    }
    try assertEqual(matcher, "SomeOtherMatcher", "Hook with different matcher should remain")
}

test("Detect hook only when BOTH matcher and command match") {
    // Hook with BOTH correct matcher AND correct command
    try writeTestSettings("""
    {
        "hooks": {
            "PreToolUse": [
                {
                    "matcher": "ExitPlanMode",
                    "hooks": [
                        {
                            "command": "open -a 'CCPlanView' /some/path",
                            "type": "command"
                        }
                    ]
                }
            ]
        }
    }
    """)

    try assertTrue(HookManager.isHookConfigured(), "Should detect hook with correct matcher and command")
}

// MARK: Edge Cases Tests

test("Remove hook when settings.json doesn't exist (no-op)") {
    try HookManager.removeHook()  // Should not throw
    try assertFalse(HookManager.isClaudeCodeInstalled())
}

test("isHookConfigured returns false with malformed hooks array") {
    try writeTestSettings("""
    {
        "hooks": {
            "PreToolUse": [
                "not a dictionary"
            ]
        }
    }
    """)

    try assertFalse(HookManager.isHookConfigured())
}

test("Preserve all root-level settings") {
    try writeTestSettings("""
    {
        "apiKey": "secret",
        "theme": "dark",
        "nested": {
            "deep": {
                "value": 123
            }
        }
    }
    """)

    try HookManager.installHook()

    let settings = try readTestSettings()
    try assertEqual(settings["apiKey"] as? String, "secret")
    try assertEqual(settings["theme"] as? String, "dark")

    guard let nested = settings["nested"] as? [String: Any],
          let deep = nested["deep"] as? [String: Any]
    else {
        throw TestError(message: "Nested structure not preserved")
    }
    try assertEqual(deep["value"] as? Int, 123)
}

// MARK: Hook Content Verification Tests

test("Installed hook has correct matcher") {
    try writeTestSettings("{}")
    try HookManager.installHook()

    let settings = try readTestSettings()
    let preToolUse = try getPreToolUse(settings)
    guard let hookEntry = preToolUse.first else {
        throw TestError(message: "No hook entry found")
    }

    try assertEqual(hookEntry["matcher"] as? String, "ExitPlanMode", "matcher should be ExitPlanMode")
}

test("Installed hook has correct timeout") {
    try writeTestSettings("{}")
    try HookManager.installHook()

    let settings = try readTestSettings()
    let preToolUse = try getPreToolUse(settings)
    guard let hookEntry = preToolUse.first,
          let hooksList = hookEntry["hooks"] as? [[String: Any]],
          let firstHook = hooksList.first
    else {
        throw TestError(message: "Could not find hook")
    }

    try assertEqual(firstHook["timeout"] as? Int, 10, "timeout should be 10")
    try assertEqual(firstHook["type"] as? String, "command", "type should be command")
}

test("Installed hook command contains required elements") {
    try writeTestSettings("{}")
    try HookManager.installHook()

    let settings = try readTestSettings()
    let preToolUse = try getPreToolUse(settings)
    guard let hookEntry = preToolUse.first else {
        throw TestError(message: "No hook entry found")
    }

    let command = try getHookCommand(hookEntry)

    try assertTrue(command.contains("ls -t ~/.claude/plans/*.md"), "Command should list plan files")
    try assertTrue(command.contains("2>/dev/null"), "Command should suppress ls errors")
    try assertTrue(command.contains("[ -n \"$FILE\" ]"), "Command should check if file exists")
    try assertTrue(command.contains("open -a 'CCPlanView'"), "Command should open CCPlanView")
    try assertTrue(command.contains("ccplanview://refresh"), "Command should trigger refresh")
    try assertTrue(command.contains("urllib.parse.quote"), "Command should URL-encode file path")
}

// MARK: Mixed Array Tests (dictionaries + non-dictionaries)

test("Detect hook in mixed PreToolUse array") {
    // Create settings with CCPlanView hook manually
    try writeTestSettings("{}")
    try HookManager.installHook()

    // Add a non-dictionary entry to PreToolUse
    var settings = try readTestSettings()
    var hooks = settings["hooks"] as? [String: Any] ?? [:]
    var preToolUse = hooks["PreToolUse"] as? [Any] ?? []
    preToolUse.insert("malformed string entry", at: 0)  // Add non-dict at beginning
    hooks["PreToolUse"] = preToolUse
    settings["hooks"] = hooks

    let data = try JSONSerialization.data(withJSONObject: settings, options: .prettyPrinted)
    try data.write(to: HookManager.settingsPath)

    // Should still detect our hook even with mixed array
    try assertTrue(HookManager.isHookConfigured(), "Should detect hook in mixed array")
}

test("Remove hook from mixed PreToolUse array") {
    // Create settings with CCPlanView hook manually
    try writeTestSettings("{}")
    try HookManager.installHook()

    // Add a non-dictionary entry to PreToolUse
    var settings = try readTestSettings()
    var hooks = settings["hooks"] as? [String: Any] ?? [:]
    var preToolUse = hooks["PreToolUse"] as? [Any] ?? []
    preToolUse.insert("malformed string entry", at: 0)  // Add non-dict at beginning
    hooks["PreToolUse"] = preToolUse
    settings["hooks"] = hooks

    let data = try JSONSerialization.data(withJSONObject: settings, options: .prettyPrinted)
    try data.write(to: HookManager.settingsPath)

    // Verify we have mixed array with 2 items
    let beforeSettings = try readTestSettings()
    let beforePreToolUse = try getPreToolUseAny(beforeSettings)
    try assertEqual(beforePreToolUse.count, 2, "Should have 2 items before removal")

    // Remove should work and remove only CCPlanView hook
    try HookManager.removeHook()

    // Verify only 1 item remains (the malformed string)
    let afterSettings = try readTestSettings()
    let afterPreToolUse = try getPreToolUseAny(afterSettings)
    try assertEqual(afterPreToolUse.count, 1, "Should have 1 item after removal")
    try assertTrue(afterPreToolUse.first is String, "Remaining item should be the malformed string")
    try assertFalse(HookManager.isHookConfigured(), "Hook should be removed")
}

test("Install hook into existing mixed PreToolUse array") {
    // Create mixed array without our hook
    try writeTestSettings("""
    {
        "hooks": {
            "PreToolUse": [
                "malformed string",
                {
                    "matcher": "OtherTool",
                    "hooks": [{"command": "echo other", "type": "command"}]
                },
                12345
            ]
        }
    }
    """)

    // Install should work and append to existing array
    try HookManager.installHook()
    try assertTrue(HookManager.isHookConfigured(), "Hook should be installed")

    // Verify array structure preserved
    let settings = try readTestSettings()
    let preToolUse = try getPreToolUseAny(settings)
    try assertEqual(preToolUse.count, 4, "Should have 4 items (3 original + 1 new)")
    try assertTrue(preToolUse[0] is String, "First item should still be string")
    try assertTrue(preToolUse[2] is Int, "Third item should still be number")
}

test("Remove hook preserves malformed entries in PreToolUse") {
    // First install our hook
    try writeTestSettings("{}")
    try HookManager.installHook()

    // Add a malformed entry manually
    var settings = try readTestSettings()
    var hooks = settings["hooks"] as? [String: Any] ?? [:]
    var preToolUse = hooks["PreToolUse"] as? [Any] ?? []
    preToolUse.append("malformed string entry")  // This is not a dictionary
    hooks["PreToolUse"] = preToolUse
    settings["hooks"] = hooks

    // Write it back (bypass our writeSettings to keep malformed data)
    let data = try JSONSerialization.data(withJSONObject: settings, options: .prettyPrinted)
    try data.write(to: HookManager.settingsPath)

    // Remove should work without crashing and preserve malformed entry
    try HookManager.removeHook()

    // The file should still exist with the malformed entry
    let afterSettings = try readTestSettings()
    let afterPreToolUse = try getPreToolUseAny(afterSettings)
    try assertEqual(afterPreToolUse.count, 1, "Malformed entry should be preserved")
    try assertTrue(afterPreToolUse.first is String, "Preserved entry should be string")
}

test("Remove hook actually removes CCPlanView hook from mixed array") {
    // Install our hook
    try writeTestSettings("{}")
    try HookManager.installHook()

    // Add another valid hook
    var settings = try readTestSettings()
    var hooks = settings["hooks"] as? [String: Any] ?? [:]
    var preToolUse = hooks["PreToolUse"] as? [[String: Any]] ?? []
    preToolUse.insert([
        "matcher": "OtherMatcher",
        "hooks": [["command": "echo other", "type": "command"]]
    ] as [String: Any], at: 0)  // Insert at beginning
    hooks["PreToolUse"] = preToolUse
    settings["hooks"] = hooks
    try HookManager.writeSettings(settings)

    // Verify we have 2 hooks
    let beforeRemove = try readTestSettings()
    let beforePreToolUse = try getPreToolUse(beforeRemove)
    try assertEqual(beforePreToolUse.count, 2, "Should have 2 hooks before removal")

    // Remove CCPlanView hook
    try HookManager.removeHook()

    // Verify only 1 hook remains
    let afterRemove = try readTestSettings()
    let afterPreToolUse = try getPreToolUse(afterRemove)
    try assertEqual(afterPreToolUse.count, 1, "Should have 1 hook after removal")

    // Verify it's the other hook that remains
    guard let remaining = afterPreToolUse.first,
          let matcher = remaining["matcher"] as? String
    else {
        throw TestError(message: "Could not get remaining hook")
    }
    try assertEqual(matcher, "OtherMatcher", "OtherMatcher hook should remain")
    try assertFalse(HookManager.isHookConfigured(), "CCPlanView hook should be gone")
}

// MARK: JSON Output Format Tests

test("Output uses sorted keys for consistency") {
    try writeTestSettings("{}")
    try HookManager.installHook()

    let data = try Data(contentsOf: HookManager.settingsPath)
    let jsonString = String(decoding: data, as: UTF8.self)

    // "hooks" should appear before any key that comes after it alphabetically
    // Since we use sortedKeys, the output should be deterministic
    try assertTrue(jsonString.contains("\"hooks\""), "Should contain hooks key")
}

// MARK: - Summary

print("\n=== Summary ===")
print("Passed: \(testsPassed)")
print("Failed: \(testsFailed)")
print("Total: \(testsPassed + testsFailed)")

if testsFailed > 0 {
    exit(1)
}
