# CCPlanView - Project Guide

## Overview

Lightweight macOS markdown viewer. Swift 6.0 + SwiftUI + WKWebView + vanilla JS.

## Build & Run

```bash
./scripts/build.sh        # Debug build (xcodegen + xcodebuild)
./scripts/build.sh Release
```

App output: `build/DerivedData/Build/Products/{Config}/CCPlanView.app`

## Architecture

- **CCPlanViewApp.swift** - `@main` entry with `DocumentGroup(viewing:)` for multi-window support
- **AppDelegate.swift** - Sets up TitlebarDragView, handles URL Scheme (`ccplanview://refresh?file=...`)
- **MarkdownWebView.swift** - `NSViewRepresentable` wrapping WKWebView + DropContainerView/DropOverlayView for drag & drop
- **MarkdownFileDocument.swift** - `ReferenceFileDocument` conforming document
- **Resources/index.html** - HTML template with marked.js + highlight.js, called via `evaluateJavaScript`

## URL Scheme

- `ccplanview://refresh` - Refresh all open documents
- `ccplanview://refresh?file=/path/to/file.md` - Refresh specific file (symlinks resolved for comparison)

## Key Design Decisions

- **`loadFileURL` over `loadHTMLString`** - Load index.html once, update content via JS. Avoids re-creating HTML on each update, preserves scroll position.
- **DropOverlayView** - Transparent NSView on top of WKWebView to capture drag & drop. WKWebView's internal views consume drag events, so overlay with `hitTest` passthrough is needed.
- **File opening via `open -a`** - Standard macOS procedure. CLI args (`ProcessInfo.arguments`) are not used; `application(_:open:)` is the correct path.

## Project Config

- **Bundle ID**: `sh.saqoo.ccplanview`
- **Deployment target**: macOS 14.0
- **XcodeGen**: `project.yml` generates `.xcodeproj`
- **Version control**: jj (Jujutsu)

## Scripts

- `scripts/build.sh` - xcodegen + xcodebuild
- `scripts/notarize.sh` - codesign + notarytool
- `scripts/package_dmg.sh` - DMG creation + notarization
- `scripts/release.sh` - version bump + jj + gh release

## Debugging macOS Swift App

Use `Logger` from `os` framework for debug logging:

```swift
import os
private let logger = Logger(subsystem: "sh.saqoo.ccplanview", category: "MyCategory")

// Use privacy: .public to see actual values in logs
logger.info("My value: \(someValue, privacy: .public)")
```

View logs with:
```bash
/usr/bin/log stream --predicate 'subsystem == "sh.saqoo.ccplanview"' --level debug
```

**Note**: Default log output shows `<private>` for interpolated values. Use `privacy: .public` to reveal actual values during debugging.
