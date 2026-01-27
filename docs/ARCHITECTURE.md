# Architecture

## Data Flow

```
┌─────────────────────────────────────────────────────────┐
│ File Open Triggers                                      │
│                                                         │
│  Finder / open -a ──▶ AppDelegate.application(_:open:)  │
│  Drag & Drop ────────▶ DropOverlayView.performDrag...   │
│  File > Open ────────▶ MarkdownViewerApp.openFile()     │
│                                                         │
│  All paths call ──────▶ MarkdownDocument.open(url:)     │
└─────────────────────────┬───────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────┐
│ MarkdownDocument (ObservableObject)                     │
│                                                         │
│  @Published fileURL ──────────────────────────────────  │
│  @Published markdownContent ──▶ triggers SwiftUI update │
│  @Published windowTitle                                 │
│                                                         │
│  open(url:) ──▶ loadContent() + startWatching()         │
│                      │              │                   │
│                      ▼              ▼                   │
│              String(contentsOf:)  FileWatcher            │
│                                   │ onChange ──▶ loadContent()
└─────────────────────────┬───────────────────────────────┘
                          │ @Published markdownContent
                          ▼
┌─────────────────────────────────────────────────────────┐
│ MarkdownWebView (NSViewRepresentable)                   │
│                                                         │
│  updateNSView() ──▶ evaluateJavaScript()                │
│    • setTheme(isDark) ──▶ switches highlight.js CSS     │
│    • renderMarkdown(src) ──▶ marked.parse + hljs        │
│    • showEmpty()                                        │
│                                                         │
│  Coordinator (WKNavigationDelegate)                     │
│    • Tracks isPageLoaded                                │
│    • Buffers pending content until page ready            │
│    • Prevents duplicate renders via lastMarkdown check  │
└─────────────────────────────────────────────────────────┘
```

## View Hierarchy (AppKit Layer)

```
NSWindow
 └─ SwiftUI HostingView
     └─ ContentView
         └─ MarkdownWebView (NSViewRepresentable)
             └─ DropContainerView (NSView)
                 ├─ WKWebView          ← renders markdown
                 └─ DropOverlayView    ← transparent, on top
                     • registerForDraggedTypes([.fileURL])
                     • hitTest() returns nil unless dragging
                     • draggingEntered/performDragOperation
```

### Why DropOverlayView?

WKWebView's internal subviews (WKContentView) consume drag events before they reach
any parent or sibling view. Neither `unregisterDraggedTypes()` on WKWebView nor
subclassing WKWebView resolves this. The solution is a transparent overlay view that:

1. Sits **above** WKWebView in the z-order
2. Returns `nil` from `hitTest(_:)` when not dragging (mouse events pass through to WebView)
3. Accepts drag events via `registerForDraggedTypes`
4. Sets `isDragging = true` on `draggingEntered` to temporarily become the hit-test target

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
                             preserves scroll ratio across re-renders
```

### Why loadFileURL instead of loadHTMLString?

`loadHTMLString` (used by ccdiary) inlines all JS/CSS and re-creates the entire HTML
on every content change. `loadFileURL`:
- Loads the page once; subsequent updates via `evaluateJavaScript`
- Naturally preserves scroll position (no page reload)
- No flicker on live reload
- JS/CSS loaded as separate files (easier to debug)

## Module Dependency Graph

```
MarkdownViewerApp (@main)
  ├─ AppDelegate
  │   └─ MarkdownDocument
  └─ ContentView
      ├─ MarkdownDocument
      └─ MarkdownWebView
          ├─ DropContainerView
          │   └─ DropOverlayView
          └─ WKWebView + Coordinator
              └─ index.html (Resources)

FileWatcher ← owned by MarkdownDocument
```

No external Swift dependencies. All JS/CSS libraries are vendored in `Resources/`.
