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
│  startWatching(url:) ──▶ syncs content + starts watcher │
│  open(url:) ──▶ reloadContent() + restarts watcher      │
│                      │              │                   │
│                      ▼              ▼                   │
│              String(contentsOf:)  FileWatcher           │
│                                   │ onChange ──▶ reloadContent()
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

## FileWatcher

```
DispatchSource.makeFileSystemObjectSource
  eventMask: [.write, .rename, .delete]

  .write ──▶ debouncedOnChange() (100ms)

  .delete / .rename ──▶ stopWatching()
                        wait 100ms
                        startWatching() on new fd
                        debouncedOnChange()
```

Editors save files differently:
- **VS Code**: writes directly to the file → `.write` event
- **vim / TextMate**: deletes the file, creates a new one → `.delete` + `.rename`

The watcher handles both patterns by detecting delete/rename events, waiting for the
new file to appear, then re-opening a fresh file descriptor.

All operations happen on a dedicated serial `DispatchQueue` to avoid race conditions.

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
  │       └─ FileWatcher
  ├─ AppDelegate (via @NSApplicationDelegateAdaptor)
  │   └─ TitlebarDragView
  └─ ContentView
      └─ MarkdownWebView
          ├─ DropContainerView
          │   └─ DropOverlayView
          └─ WKWebView + Coordinator
              └─ index.html (Resources)
```

No external Swift dependencies. All JS/CSS libraries are vendored in `Resources/`.
