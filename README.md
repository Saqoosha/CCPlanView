# CCPlanView

<p align="center">
  <img src="images/appicon.png" width="128" height="128" alt="CCPlanView icon">
  <br>
  Lightweight macOS markdown viewer for Claude Code plans.
</p>

## Features

- Render `.md` files with GitHub-flavored markdown styling
- Code syntax highlighting (highlight.js)
- Diff visualization (green for added, red for deleted)
- Dark/light mode auto-switch
- URL scheme for on-demand refresh (`ccplanview://refresh?file=...`)
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

CCPlanView works great as a plan viewer for [Claude Code](https://docs.anthropic.com/en/docs/claude-code). When Claude generates a plan file (via `ExitPlanMode`), a hook can automatically open it in CCPlanView and trigger a refresh to show the latest content with diff highlighting.

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
            "command": "FILE=$(ls -t ~/.claude/plans/*.md | head -1) && open -a 'CCPlanView' \"$FILE\" && sleep 0.5 && open \"ccplanview://refresh?file=$FILE\"",
            "timeout": 10
          }
        ]
      }
    ]
  }
}
```

This hook triggers right before Claude presents a plan for approval. It opens the latest plan file in CCPlanView and sends a refresh command via URL scheme, highlighting any changes since the last view.

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
