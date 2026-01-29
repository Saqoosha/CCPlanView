# macOS Multi-Document Architecture for Viewer Apps

## Current State

CCPlanView correctly uses `DocumentGroup(viewing:)` mode and sets `CFBundleTypeRole` to `Viewer` in Info.plist. However, macOS and SwiftUI still show editor-specific menu items (Save, Duplicate, Rename, Move To..., Revert To...) even in viewing-only mode.

## The Problem

When using SwiftUI's `DocumentGroup(viewing:)`:
- macOS still displays the full File menu with editor commands
- Pressing ⌘S or using File > Save shows save functionality
- "Duplicate" menu item appears (despite being a viewer)
- This is a known limitation in SwiftUI's document architecture

## Solutions

### Solution 1: Use `CommandGroup(replacing: .saveItem)` (Recommended)

Add the `.commands` modifier to remove the Save item and related commands:

```swift
@main
struct CCPlanViewApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate

    var body: some Scene {
        DocumentGroup(viewing: MarkdownFileDocument.self) { file in
            MainContentView(document: file.document, fileURL: file.fileURL)
        }
        .commands {
            // Remove Save/Save As menu items
            CommandGroup(replacing: .saveItem) { }
        }
        // ... rest of configuration
    }
}
```

**Limitations:**
- `CommandGroupPlacement` only covers certain menu items (`.saveItem`, `.newItem`, `.printItem`, etc.)
- Does NOT have a built-in placement for "Duplicate", "Rename", "Move To..."
- These items require AppKit-level manipulation

### Solution 2: Remove Menu Items via AppDelegate (For Duplicate, Rename, etc.)

Add menu manipulation in `applicationDidFinishLaunching`:

```swift
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Existing setup...

        // Remove editor-only menu items after a brief delay
        // (menu may not be fully populated immediately)
        DispatchQueue.main.async {
            self.removeEditorMenuItems()
        }
    }

    private func removeEditorMenuItems() {
        guard let mainMenu = NSApplication.shared.mainMenu,
              let fileMenuItem = mainMenu.item(withTitle: "File"),
              let fileMenu = fileMenuItem.submenu else { return }

        // Items to remove for a viewer app
        let itemsToRemove = ["Save", "Save As...", "Duplicate", "Rename...",
                            "Move To...", "Revert To"]

        for title in itemsToRemove {
            if let item = fileMenu.item(withTitle: title) {
                fileMenu.removeItem(item)
            }
        }

        // Also remove separators that become orphaned
        // (be careful with this - may affect other menu items)
    }
}
```

**Issues with this approach:**
- Menu item titles are localized (different in each language)
- Menu may be rebuilt by the system when windows open/close
- Need to use `NSWindow.didBecomeMainNotification` to re-apply removals

### Solution 3: Override in NSDocument Subclass (AppKit Hybrid)

For more robust control, create an NSDocument subclass that explicitly declares it's not editable:

```swift
class MarkdownNSDocument: NSDocument {
    override var isDocumentEdited: Bool { false }
    override var hasUndoManager: Bool { false }
    override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(save(_:)),
             #selector(saveAs(_:)),
             #selector(duplicate(_:)),
             #selector(rename(_:)),
             #selector(move(_:)):
            return false
        default:
            return super.validateMenuItem(menuItem)
        }
    }
}
```

**Note:** This requires bridging between SwiftUI's `ReferenceFileDocument` and AppKit's `NSDocument`, which is complex.

### Solution 4: Use `applicationWillUpdate` for Continuous Cleanup

For persistent menu removal across the app lifecycle:

```swift
func applicationWillUpdate(_ notification: Notification) {
    // This is called frequently - ensure idempotent operations
    if !menusCleaned {
        removeEditorMenuItems()
        menusCleaned = true
    }
}
```

**Caveat:** `applicationWillUpdate` is called very frequently; be careful about performance.

## SwiftUI CommandGroupPlacements Available

| Placement | Description |
|-----------|-------------|
| `.appInfo` | About menu item |
| `.appSettings` | Preferences/Settings |
| `.appTermination` | Quit menu item |
| `.appVisibility` | Hide, Hide Others, Show All |
| `.systemServices` | Services menu |
| `.newItem` | New, New Window |
| `.saveItem` | Save, Save As |
| `.importExport` | Import, Export |
| `.printItem` | Print, Page Setup |
| `.undoRedo` | Undo, Redo |
| `.pasteboard` | Cut, Copy, Paste |
| `.textEditing` | Select All, Find |
| `.textFormatting` | Font, Text styles |
| `.toolbar` | Toolbar visibility |
| `.sidebar` | Sidebar visibility |
| `.windowArrangement` | Window arrangement |
| `.windowList` | Window list |
| `.windowSize` | Zoom, Minimize |
| `.singleWindowList` | Single window list |
| `.help` | Help menu |

**Missing:** No built-in placement for Duplicate, Rename, Move To, Revert To.

## Recommended Implementation for CCPlanView

### Step 1: Add `.commands` modifier

```swift
var body: some Scene {
    DocumentGroup(viewing: MarkdownFileDocument.self) { file in
        MainContentView(document: file.document, fileURL: file.fileURL)
    }
    .commands {
        CommandGroup(replacing: .saveItem) { }
        CommandGroup(replacing: .newItem) { }  // Optional: remove New menu if not needed
    }
    // existing modifiers...
}
```

### Step 2: Remove remaining items in AppDelegate

```swift
func applicationDidFinishLaunching(_ notification: Notification) {
    // Existing notification observers...

    // Clean up menus when windows become main
    NotificationCenter.default.addObserver(
        self,
        selector: #selector(cleanupMenus),
        name: NSWindow.didBecomeMainNotification,
        object: nil
    )
}

@objc private func cleanupMenus() {
    guard let mainMenu = NSApplication.shared.mainMenu,
          let fileMenuItem = mainMenu.item(withTitle: "File"),
          let fileMenu = fileMenuItem.submenu else { return }

    // Use action selectors instead of titles (language-independent)
    for item in fileMenu.items {
        if let action = item.action,
           [#selector(NSDocument.duplicate(_:)),
            #selector(NSDocument.rename(_:)),
            #selector(NSDocument.move(_:)),
            NSSelectorFromString("revertDocumentToSaved:")].contains(action) {
            fileMenu.removeItem(item)
        }
    }
}
```

## Alternative: Full AppKit Document Architecture

If SwiftUI's limitations become too problematic, consider:

1. **Use NSDocumentController directly** - More control over document lifecycle
2. **Custom WindowGroup instead of DocumentGroup** - Handle file opening manually
3. **Hybrid approach** - Use NSDocument with SwiftUI views

## References

- [Apple Developer Forums - Preventing Save in DocumentGroup](https://developer.apple.com/forums/thread/667288)
- [Apple Developer Forums - Removing Default Menus](https://developer.apple.com/forums/thread/740591)
- [SwiftUI DocumentGroup Documentation](https://developer.apple.com/documentation/swiftui/documentgroup)
- [NSDocument isLocked Documentation](https://developer.apple.com/documentation/appkit/nsdocument/1515212-islocked)
- [Hacking with Swift - DocumentGroup](https://www.hackingwithswift.com/quick-start/swiftui/how-to-create-a-document-based-app-using-filedocument-and-documentgroup)
- [Swift Dev Journal - Document Types](https://www.swiftdevjournal.com/document-types-in-swiftui-apps/)

## Conclusion

SwiftUI's document architecture is still maturing. For a viewer-only app:

1. **Required:** Use `DocumentGroup(viewing:)` + `CFBundleTypeRole: Viewer`
2. **Recommended:** Add `CommandGroup(replacing: .saveItem) { }`
3. **For complete cleanup:** Use AppDelegate to remove Duplicate/Rename/Move items by action selector

The hybrid SwiftUI + AppKit approach provides the most control for macOS document-based apps.
