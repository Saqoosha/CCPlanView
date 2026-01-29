import Foundation

enum Constants {
    static let markdownExtensions: Set<String> = ["md", "markdown", "mdown", "mkd"]
    static let mainWindowIdentifier = "CCPlanViewMainWindow"
}

extension Notification.Name {
    static let ccplanviewRefresh = Notification.Name("CCPlanViewRefresh")
    static let ccplanviewFileChanged = Notification.Name("CCPlanViewFileChanged")
    static let ccplanviewDiffStatusChanged = Notification.Name("CCPlanViewDiffStatusChanged")
    static let hookConfigurationChanged = Notification.Name("HookConfigurationChanged")
}
