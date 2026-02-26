# omarchy-ai-usage

AI usage monitoring for [Omarchy](https://omarchy.org/) — track your Claude, Codex, Gemini, and Antigravity rate limits directly from Waybar.

Inspired by [CodexBar](https://github.com/steipete/CodexBar) (macOS).

## Features

- **Waybar icon** that changes color based on usage (green/yellow/red)
- **Tooltip** with compact overview of all providers on hover
- **Interactive TUI** (click) with detailed usage bars, reset countdowns, and settings
- **Configurable** display modes: icon-only, compact, or full bars
- **Keyboard shortcuts** throughout the TUI
- **Centralized logging** to `~/.cache/ai-usage/ai-usage.log`
- **Diagnostic command** (`make check`) to validate setup
- Automatic token refresh for Claude OAuth and Gemini OAuth
- Codex support via JSON-RPC (app-server) with OAuth API fallback
- Gemini support via Gemini CLI OAuth credentials and Google quota API
- Antigravity support via local language server probe (experimental)
- 55-second cache to minimize API calls
- Atomic file writes to prevent corruption

## Supported Providers

| Provider | Auth Method | Data Source |
|----------|------------|-------------|
| Claude | OAuth (`~/.claude/.credentials.json`) | Anthropic Usage API |
| Codex | RPC / OAuth (`~/.codex/auth.json`) | `codex app-server` or ChatGPT API |
| Gemini | OAuth (`~/.gemini/oauth_creds.json`) | Google Cloud Quota API |
| Antigravity | Local LSP (auto-detected) | Antigravity Language Server (experimental) |

## Install

### AUR (recommended for Arch/Omarchy)

```bash
yay -S omarchy-ai-usage-git
```

Waybar is configured automatically during install.

### From source

```bash
git clone https://github.com/rodrigo-sntg/omarchy-ai-usage.git
cd omarchy-ai-usage
make install
```

## Uninstall

### AUR

```bash
sudo pacman -R omarchy-ai-usage-git
```

### From source

```bash
make uninstall
```

## Architecture

```
~/.local/libexec/ai-usage/          ← All scripts (XDG compliant)
  ├── lib.sh                        ← Shared library (logging, cache, errors)
  ├── ai-usage.sh                   ← Main waybar module
  ├── ai-usage-claude.sh            ← Claude provider
  ├── ai-usage-codex.sh             ← Codex provider
  ├── ai-usage-gemini.sh            ← Gemini provider
  ├── ai-usage-antigravity.sh       ← Antigravity provider
  ├── ai-usage-tui.sh               ← Interactive TUI
  └── ai-usage-check.sh             ← Diagnostic tool

~/.config/waybar/scripts/            ← Thin wrappers only
  ├── ai-usage.sh                   ← Delegates to libexec
  └── ai-usage-tui.sh               ← Delegates to libexec

~/.config/ai-usage/config.json       ← User configuration
~/.cache/ai-usage/ai-usage.log       ← Centralized log file
```

## Configuration

Edit `~/.config/ai-usage/config.json` or use the TUI settings (click the icon → `s`):

```json
{
  "display_mode": "icon",
  "refresh_interval": 60,
  "providers": {
    "claude": { "enabled": true },
    "codex": { "enabled": true },
    "gemini": { "enabled": true },
    "antigravity": { "enabled": true }
  }
}
```

### Display Modes

| Mode | Description |
|------|-------------|
| `icon` | Single icon, color indicates worst status |
| `compact` | Icon + progress bar of worst provider |
| `full` | Icon + progress bars for all providers |

## TUI Shortcuts

### Dashboard
| Key | Action |
|-----|--------|
| `r` | Refresh data |
| `s` | Open settings |
| `q` | Quit |

### Settings
| Key | Action |
|-----|--------|
| `d` | Change display mode |
| `i` | Change refresh interval |
| `c` | Toggle Claude |
| `x` | Toggle Codex |
| `g` | Toggle Gemini |
| `a` | Toggle Antigravity |
| `b` | Back to dashboard |

## Diagnostics

Run `make check` to validate your setup:

```bash
make check
# or directly:
bash scripts/ai-usage-check.sh
```

This checks dependencies, credential files, network connectivity, and running services.

Logs are written to `~/.cache/ai-usage/ai-usage.log` (auto-rotated, max 1000 lines).

## Development

```bash
make lint     # Run shellcheck on all scripts
make check    # Run diagnostic checks
make install  # Install locally
```

## Prerequisites

- [Omarchy](https://omarchy.org/) (Arch Linux + Hyprland + Waybar)
- `jq`, `curl`, `gum` (auto-installed by install script)
- Claude CLI logged in (`claude auth`)
- Codex CLI logged in (`codex login`)
- Gemini CLI logged in (`gemini auth`) — for Gemini provider
- Antigravity app running — for Antigravity provider (experimental)

## About

**omarchy-ai-usage** brings AI rate limit visibility to the Linux desktop. The idea is simple: if you use AI coding assistants daily, you should always know how much quota you have left — without opening a browser or running CLI commands.

This project was born from the need to have [CodexBar](https://github.com/steipete/CodexBar)-like functionality on Arch Linux with Hyprland/Waybar, bringing the same concept of a unified AI usage dashboard to the Omarchy ecosystem.

Built by [Rodrigo Santiago](https://github.com/rodrigo-sntg).

## License

MIT
