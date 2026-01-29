import Foundation

enum Constants {
    static let markdownExtensions: Set<String> = ["md", "markdown", "mdown", "mkd"]
    static let mainWindowIdentifier = "CCPlanViewMainWindow"
}

extension Notification.Name {
    static let ccplanviewRefresh = Notification.Name("CCPlanViewRefresh")
}
