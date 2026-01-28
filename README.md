# CCPlanView

Lightweight macOS markdown viewer with live reload.

## Features

- Render `.md` files with GitHub-flavored markdown styling
- Code syntax highlighting (highlight.js)
- Live reload on file changes (works with vim, VS Code, etc.)
- Dark/light mode auto-switch
- Open files via File > Open, drag & drop, or Finder "Open With"

## Installation

1. Go to [Releases](https://github.com/Saqoosha/CCPlanView/releases)
2. Download the latest `.dmg` file
3. Open the `.dmg` and drag **CCPlanView** to `/Applications`

## Usage

```bash
# Open a file from terminal
open -a "CCPlanView" /path/to/file.md

# Or drag & drop a .md file onto the window
```

### Use with Claude Code Hooks

CCPlanView works great as a plan viewer for [Claude Code](https://docs.anthropic.com/en/docs/claude-code). When Claude generates a plan file (via `ExitPlanMode`), a hook can automatically open it in CCPlanView with live reload — so you can review the plan in real-time as Claude writes it.

Add the following to your `~/.config/claude/settings.json`:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "ExitPlanMode",
        "hooks": [
          {
            "type": "command",
            "command": "open -a 'CCPlanView' \"$(ls -t ~/.claude/plans/*.md | head -1)\"",
            "timeout": 5
          }
        ]
      }
    ]
  }
}
```

This hook triggers right before Claude presents a plan for approval, opening the latest plan file in CCPlanView. Thanks to live reload, the content updates automatically as the plan is finalized.

---

## Development

### Build

Requires macOS 14.0+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
./scripts/build.sh          # Debug build
./scripts/build.sh Release  # Release build
```

### Release

```bash
./scripts/release.sh 1.0.0
```

### Tech Stack

- Swift 6.0 + SwiftUI + WKWebView
- [marked.js](https://github.com/markedjs/marked) (markdown parsing)
- [highlight.js](https://highlightjs.org/) (syntax highlighting)
- [github-markdown-css](https://github.com/sindresorhus/github-markdown-css) (styling)

## License

MIT
