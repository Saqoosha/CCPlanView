# Markdown Viewer

Lightweight macOS markdown viewer with live reload.

## Features

- Render `.md` files with GitHub-flavored markdown styling
- Code syntax highlighting (highlight.js)
- Live reload on file changes (works with vim, VS Code, etc.)
- Dark/light mode auto-switch
- Open files via File > Open, drag & drop, or Finder "Open With"

## Requirements

- macOS 14.0 (Sonoma) or later
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

## Build

```bash
./scripts/build.sh          # Debug build
./scripts/build.sh Release  # Release build
```

## Usage

```bash
# Open a file from terminal
open -a "Markdown Viewer" /path/to/file.md

# Or drag & drop a .md file onto the window
```

## Release

```bash
./scripts/release.sh 1.0.0
```

## Tech Stack

- Swift 6.0 + SwiftUI + WKWebView
- [marked.js](https://github.com/markedjs/marked) (markdown parsing)
- [highlight.js](https://highlightjs.org/) (syntax highlighting)
- [github-markdown-css](https://github.com/sindresorhus/github-markdown-css) (styling)

## License

MIT
