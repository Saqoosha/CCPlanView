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
- **AppDelegate.swift** - Sets up TitlebarDragView, handles URL Scheme (`ccplanview://refresh?file=...`), manages hook setup
- **HookManager.swift** - Manages Claude Code hook installation, cleanup, and validation
- **MarkdownWebView.swift** - `NSViewRepresentable` wrapping WKWebView + DropContainerView/DropOverlayView for drag & drop
- **MarkdownFileDocument.swift** - `ReferenceFileDocument` conforming document
- **Resources/index.html** - HTML template with marked.js + highlight.js, called via `evaluateJavaScript`
- **notifier/** - Standalone CLI tool called by Claude Code hooks to open latest plan file

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

## Dependencies

- **CCHookInstaller** - Shared library for Claude Code hook management (GitHub: `Saqoosha/CCHookInstaller`)

### Local Development with CCHookInstaller

When making changes to CCHookInstaller alongside this project:

```bash
# 1. Ignore local project.yml changes
git update-index --assume-unchanged project.yml

# 2. Edit project.yml to use local path:
# packages:
#   CCHookInstaller:
#     path: ../CCHookInstaller

# 3. Develop and build - CCHookInstaller changes reflect immediately

# 4. When done: push CCHookInstaller, create new tag (e.g., v1.1.0)

# 5. Revert project.yml to GitHub URL with new version

# 6. Stop ignoring and commit
git update-index --no-assume-unchanged project.yml
```

**Note:** Keep project.yml pointing to GitHub URL in commits so this public repo remains buildable by others.

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
