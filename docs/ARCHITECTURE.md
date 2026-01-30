# Architecture

## Data Flow

```
┌─────────────────────────────────────────────────────────┐
│ File Open Triggers                                      │
│                                                         │
│  Finder / open -a ──▶ DocumentGroup creates new window  │
│  File > Open ────────▶ DocumentGroup creates new window │
│  Drag & Drop ────────▶ MarkdownFileDocument.open(url:)  │
│                        (opens in same window)           │
└─────────────────────────┬───────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────┐
│ MarkdownFileDocument (ReferenceFileDocument)            │
│                                                         │
│  @Published fileURL ──────────────────────────────────  │
│  @Published markdownContent ──▶ triggers SwiftUI update │
│                                                         │
│  init(configuration:) ──▶ loads content from FileWrapper│
│  @Published markdown ──▶ content as String              │
└─────────────────────────┬───────────────────────────────┘
                          │ @Published markdownContent
                          ▼
┌─────────────────────────────────────────────────────────┐
│ MarkdownWebView (NSViewRepresentable)                   │
│                                                         │
│  updateNSView() ──▶ evaluateJavaScript()                │
│    • setTheme(isDark) ──▶ switches highlight.js CSS     │
│    • renderMarkdown(src) ──▶ marked.parse + hljs        │
│                                                         │
│  Coordinator (WKNavigationDelegate)                     │
│    • Tracks isPageLoaded                                │
│    • Buffers pending content until page ready           │
│    • Prevents duplicate renders via lastMarkdown check  │
└─────────────────────────────────────────────────────────┘
```

## View Hierarchy (AppKit Layer)

```
DocumentGroup (manages multiple windows)
 └─ NSWindow (titlebarAppearsTransparent, fullSizeContentView)
     ├─ themeFrame
     │   └─ TitlebarDragView      ← transparent, intercepts mouse drags
     │                              (added via didBecomeKeyNotification)
     └─ NSHostingController
         └─ ContentView (SwiftUI)
             └─ ZStack
                 ├─ backgroundColor
                 ├─ MarkdownWebView (NSViewRepresentable)
                 │   └─ DropContainerView (NSView)
                 │       ├─ WKWebView          ← renders markdown
                 │       └─ DropOverlayView    ← transparent, on top
                 │           • registerForDraggedTypes([.fileURL])
                 │           • hitTest() returns nil unless dragging
                 │           • draggingEntered/performDragOperation
                 └─ LinearGradient             ← fades titlebar into content
                     • allowsHitTesting(false)
```

### Why TitlebarDragView?

With `fullSizeContentView` and `titlebarAppearsTransparent`, WKWebView extends under
the titlebar. WKWebView's internal views consume all mouse events, preventing window
dragging. `TitlebarDragView` is a transparent NSView added to the themeFrame (the
superview of the window's contentView) that:

1. Sits **above** all other views in the window chrome
2. Calls `window?.performDrag(with:)` on `mouseDown`
3. Returns `self` from `hitTest` for points within bounds (captures all titlebar clicks)

### Why DropOverlayView?

WKWebView's internal subviews (WKContentView) consume drag events before they reach
any parent or sibling view. Neither `unregisterDraggedTypes()` on WKWebView nor
subclassing WKWebView resolves this. The solution is a transparent overlay view that:

1. Sits **above** WKWebView in the z-order
2. Returns `nil` from `hitTest(_:)` when not dragging (mouse events pass through to WebView)
3. Accepts drag events via `registerForDraggedTypes`
4. Sets `isDragging = true` on `draggingEntered` to temporarily become the hit-test target

### Why LinearGradient over the titlebar?

The titlebar is transparent and content scrolls underneath it. The gradient provides a
smooth fade from the background color to transparent, so content doesn't abruptly
appear behind the window controls. `allowsHitTesting(false)` ensures it doesn't
interfere with the titlebar buttons or drag view.

## AppDelegate Lifecycle

```
applicationDidFinishLaunching
  └─ Register for NSWindow.didBecomeKeyNotification

windowDidBecomeKey (notification)
  └─ setupTitlebarDragView(for: window)
      ├─ Check if TitlebarDragView already added
      ├─ Set window.titlebarAppearsTransparent = true
      └─ Add TitlebarDragView to themeFrame

applicationShouldTerminateAfterLastWindowClosed ──▶ true
```

Note: File opening and menu setup are now handled by SwiftUI's DocumentGroup.
Each file opens in a new window automatically.

## URL Scheme Refresh

```
ccplanview://refresh              ──▶ Refresh all open documents
ccplanview://refresh?file=/path  ──▶ Refresh specific file only
```

### Flow

```
open "ccplanview://refresh?file=/path/to/file.md"
  │
  ▼
AppDelegate.application(_:open:)
  ├─ Parse URL scheme and query params
  ├─ Create targetFileURL from file param
  └─ NotificationCenter.post(.ccplanviewRefresh, object: targetFileURL)
      │
      ▼
MainContentView.onReceive(.ccplanviewRefresh)
  ├─ Compare paths using resolvingSymlinksInPath()
  │   (handles ~/.claude → ~/.config/claude symlinks)
  ├─ If targetURL matches or is nil, call refreshContent()
  └─ refreshContent() reads file and updates renderedMarkdown
```

### Usage with Claude Code Hooks

CCPlanView automatically offers to install the hook on first launch (via `HookManager`).
The installed hook calls the bundled `notifier` CLI:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "ExitPlanMode",
        "hooks": [
          {
            "type": "command",
            "command": "/Applications/CCPlanView.app/Contents/MacOS/notifier",
            "timeout": 10
          }
        ]
      }
    ]
  }
}
```

### Why URL Scheme Instead of FileWatcher?

The previous implementation used `DispatchSource.makeFileSystemObjectSource` to watch
for file changes. This was replaced with URL scheme refresh for several reasons:

1. **Use case mismatch** — CCPlanView is primarily used to view Claude Code plan files.
   Plans are written once by Claude, then reviewed by the user. Continuous file watching
   is unnecessary; refresh only needs to happen when Claude updates the plan.

2. **Hook integration** — Claude Code hooks (`PreToolUse`) trigger at the exact moment
   when the plan is ready for review. URL scheme allows the hook to explicitly refresh
   the view, giving precise control over timing.

3. **Simpler implementation** — FileWatcher required handling edge cases like vim-style
   saves (delete + create), debouncing rapid changes, and managing file descriptors.
   URL scheme is stateless and trivial to implement.

4. **Resource efficiency** — No background file descriptor or dispatch source running
   continuously. The app only does work when explicitly requested.

## WebView Rendering Pipeline

```
index.html (loaded once via loadFileURL)
  ├─ marked.min.js      ← markdown → HTML
  ├─ highlight.min.js   ← syntax highlighting
  ├─ github-markdown.css
  └─ highlight-github[-dark].min.css

Swift calls evaluateJavaScript:
  1. setTheme(isDark)      ← switches <link> href for highlight CSS
  2. renderMarkdown(src)   ← marked.parse() + hljs.highlightAll()
                             diff algorithm highlights changes
                             (green for added, red for deleted)
```

### Why loadFileURL instead of loadHTMLString?

`loadHTMLString` inlines all JS/CSS and re-creates the entire HTML
on every content change. `loadFileURL`:
- Loads the page once; subsequent updates via `evaluateJavaScript`
- Naturally preserves scroll position (no page reload)
- No flicker on live reload
- JS/CSS loaded as separate files (easier to debug)

### Diff Visualization

The `renderMarkdown` JS function uses a token-based diff algorithm (LCS) to detect
changes between the previous and current render. Changed content is highlighted:
- `.changed-block` — green highlight for added/modified content
- `.deleted-block` — red strikethrough for removed content
- `.code-line-changed` / `.code-line-deleted` — per-line diffs in code blocks

Granular diff functions handle nested structures: `diffListItems()`, `diffTableRows()`,
`diffCodeLines()`.

## Module Dependency Graph

```
CCPlanViewApp (@main)
  ├─ DocumentGroup(viewing: MarkdownFileDocument)
  │   └─ MarkdownFileDocument (ReferenceFileDocument)
  ├─ AppDelegate (via @NSApplicationDelegateAdaptor)
  │   ├─ TitlebarDragView
  │   ├─ URL Scheme handler (ccplanview://refresh)
  │   └─ HookManager (hook setup/cleanup on launch)
  └─ MainContentView
      ├─ .onReceive(.ccplanviewRefresh) ──▶ refreshContent()
      └─ MarkdownWebView
          ├─ DropContainerView
          │   └─ DropOverlayView
          └─ WKWebView + Coordinator
              └─ index.html (Resources)

notifier (standalone CLI, bundled in app)
  └─ Called by Claude Code hooks to open latest plan file
```

No external Swift dependencies. All JS/CSS libraries are vendored in `Resources/`.
