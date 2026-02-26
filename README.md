# omarchy-ai-usage

AI usage monitoring for [Omarchy](https://omarchy.org/) — track your Claude and Codex rate limits directly from Waybar.

Inspired by [CodexBar](https://github.com/steipete/CodexBar) (macOS).

## Features

- **Waybar icon** that changes color based on usage (green/yellow/red)
- **Tooltip** with compact overview of all providers on hover
- **Interactive TUI** (click) with detailed usage bars, reset countdowns, and settings
- **Configurable** display modes: icon-only, compact, or full bars
- **Keyboard shortcuts** throughout the TUI
- Automatic token refresh for Claude OAuth
- Codex support via JSON-RPC (app-server) with OAuth API fallback
- 55-second cache to minimize API calls

## Supported Providers

| Provider | Auth Method | Data Source |
|----------|------------|-------------|
| Claude | OAuth (`~/.claude/.credentials.json`) | Anthropic Usage API |
| Codex | RPC / OAuth (`~/.codex/auth.json`) | `codex app-server` or ChatGPT API |

## Install

```bash
git clone https://github.com/YOUR_USER/omarchy-ai-usage.git
cd omarchy-ai-usage
./install.sh
```

## Uninstall

```bash
cd omarchy-ai-usage
./uninstall.sh
```

## Configuration

Edit `~/.config/ai-usage/config.json` or use the TUI settings (click the icon → `s`):

```json
{
  "display_mode": "icon",
  "refresh_interval": 60,
  "providers": {
    "claude": { "enabled": true },
    "codex": { "enabled": true }
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
| `b` | Back to dashboard |

## Prerequisites

- [Omarchy](https://omarchy.org/) (Arch Linux + Hyprland + Waybar)
- `jq`, `curl`, `gum` (auto-installed by install script)
- Claude CLI logged in (`claude auth`)
- Codex CLI logged in (`codex login`)

## License

MIT
