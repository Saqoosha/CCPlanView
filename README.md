English | [日本語](README.ja.md)

# CCPlanView

<p align="center">
  <img src="images/appicon.png" width="128" height="128" alt="CCPlanView icon">
  <br>
  A lightweight macOS markdown viewer for Claude Code plans.
</p>

<p align="center">
  <img src="images/screenshot.png" alt="CCPlanView screenshot showing diff visualization">
</p>

## Features

- **GitHub-Flavored Markdown** - Render `.md` files with beautiful GitHub-style formatting
- **Syntax Highlighting** - Code blocks with highlight.js support for all major languages
- **Diff Visualization** - Green for added lines, red for deleted lines
- **Dark/Light Mode** - Automatically switches based on system appearance
- **URL Scheme Refresh** - Trigger on-demand refresh via `ccplanview://refresh?file=...`
- **Multiple Open Methods** - File > Open, drag & drop, Finder "Open With", or terminal command

## Installation

1. Download the latest `.dmg` from [Releases](https://github.com/Saqoosha/CCPlanView/releases)
2. Open the DMG and drag `CCPlanView.app` to Applications
3. Launch the app and open a markdown file

## Usage

### Opening Files

```bash
# Open a file from terminal
open -a "CCPlanView" /path/to/file.md

# Or drag & drop a .md file onto the window
```

### Use with Claude Code Hooks

CCPlanView works great as a plan viewer for [Claude Code](https://docs.anthropic.com/en/docs/claude-code). When Claude generates a plan file (via `ExitPlanMode`), a hook automatically opens it in CCPlanView with diff highlighting.

**Just launch the app** — if Claude Code is installed, CCPlanView will offer to configure the hook automatically.

The following hook is added to `~/.claude/settings.json`:

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

> **Note**: The path reflects the actual app location at install time.

#### Custom Plans Directory

By default, the notifier looks for plan files in `~/.claude/plans/`. To use a project-local directory, add a [`plansDirectory`](https://docs.anthropic.com/en/docs/claude-code/settings#available-settings) setting to your Claude Code configuration:

```json
// .claude/settings.json (project-level, shared with team)
{
  "plansDirectory": "./.plans"
}
```

The notifier checks settings in this order:
1. `.claude/settings.local.json` (project, personal)
2. `.claude/settings.json` (project, shared)
3. `~/.claude/settings.json` (global)

---

## Development

### Requirements

- macOS 14.0+
- Xcode 16.0+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

### Build from Source

```bash
git clone https://github.com/Saqoosha/CCPlanView.git
cd CCPlanView
./scripts/build.sh Release

# The app is located at:
# build/DerivedData/Build/Products/Release/CCPlanView.app
```

### Build Commands

```bash
./scripts/build.sh          # Debug build
./scripts/build.sh Release  # Release build
./scripts/package_dmg.sh    # Package DMG (includes notarization)
./scripts/release.sh 1.0.0  # Release new version
```

### Tech Stack

- Swift 6.0 + SwiftUI + WKWebView
- [marked.js](https://github.com/markedjs/marked) (markdown parsing)
- [highlight.js](https://highlightjs.org/) (syntax highlighting)
- [github-markdown-css](https://github.com/sindresorhus/github-markdown-css) (styling)

### Project Structure

```
Sources/
├── CCPlanView/          # Main app (SwiftUI + WKWebView)
│   └── Resources/       # HTML/CSS/JS for markdown rendering
└── notifier/            # CLI tool for Claude Code hooks
```

## License

MIT
