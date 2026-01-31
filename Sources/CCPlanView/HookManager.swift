import CCHookInstaller
import Foundation

/// Hook manager configuration for CCPlanView
enum HookManager {
    /// Shared hook manager instance
    static let shared = CCHookInstaller.HookManager(
        configuration: .preToolUse(
            appName: "CCPlanView",
            hookIdentifiers: [
                "CCPlanView.app/Contents/MacOS/notifier",
            ],
            matcher: "ExitPlanMode",
            timeout: 10
        )
    )

    /// Messages for hook setup dialogs
    static let messages = HookSetupMessages(
        installPromptMessage:
            "CCPlanView can automatically open plan files when Claude exits plan mode. Would you like to install the hook?",
        updatePromptMessage:
            "The CCPlanView hook path has changed. Would you like to update it to use the current app location?",
        successMessage:
            "Claude Code hooks have been configured. CCPlanView will open plan files when Claude exits plan mode.",
        updateSuccessMessage:
            "Claude Code hook has been updated to use the current app location."
    )

    /// UserDefaults key for "Don't Ask Again" preference
    static let dontAskAgainKey = "dontAskHookSetup"

    // MARK: - Pass-through methods for Settings UI

    static func isClaudeCodeInstalled() -> Bool {
        shared.isClaudeCodeInstalled()
    }

    static func isHookConfigured() -> Bool {
        shared.isHookConfigured()
    }

    static func installHook() throws {
        try shared.installHook()
    }

    static func removeHook() throws {
        try shared.removeHook()
    }
}
