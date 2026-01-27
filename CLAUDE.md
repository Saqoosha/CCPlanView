# Markdown Viewer - Project Guide

## Overview

Lightweight macOS markdown viewer. Swift 6.0 + SwiftUI + WKWebView + vanilla JS.

## Build & Run

```bash
./scripts/build.sh        # Debug build (xcodegen + xcodebuild)
./scripts/build.sh Release
```

App output: `build/DerivedData/Build/Products/{Config}/Markdown Viewer.app`

## Architecture

- **MarkdownViewerApp.swift** - `@main` entry, WindowGroup, File > Open menu
- **AppDelegate.swift** - `application(_:open:)` for Finder/`open -a` file opening, passes to MarkdownDocument
- **ContentView.swift** - Hosts MarkdownWebView
- **MarkdownWebView.swift** - `NSViewRepresentable` wrapping WKWebView + DropContainerView/DropOverlayView for drag & drop
- **MarkdownDocument.swift** - `ObservableObject` managing file URL, content, and FileWatcher
- **FileWatcher.swift** - `DispatchSource` file monitoring with debounce, handles vim-style delete+create saves
- **Resources/index.html** - HTML template with marked.js + highlight.js, called via `evaluateJavaScript`

## Key Design Decisions

- **`loadFileURL` over `loadHTMLString`** - Load index.html once, update content via JS. Avoids re-creating HTML on each update, preserves scroll position.
- **DropOverlayView** - Transparent NSView on top of WKWebView to capture drag & drop. WKWebView's internal views consume drag events, so overlay with `hitTest` passthrough is needed.
- **File opening via `open -a`** - Standard macOS procedure. CLI args (`ProcessInfo.arguments`) are not used; `application(_:open:)` is the correct path.

## Project Config

- **Bundle ID**: `sh.saqoo.markdown-viewer`
- **Deployment target**: macOS 14.0
- **XcodeGen**: `project.yml` generates `.xcodeproj`
- **Version control**: jj (Jujutsu)

## Scripts

- `scripts/build.sh` - xcodegen + xcodebuild
- `scripts/notarize.sh` - codesign + notarytool
- `scripts/package_dmg.sh` - DMG creation + notarization
- `scripts/release.sh` - version bump + jj + gh release
