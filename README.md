# omarchy-ai-usage

AI usage monitoring for [Omarchy](https://omarchy.org/) — track your Claude, Codex, Gemini, and Antigravity rate limits directly from Waybar.

Inspired by [CodexBar](https://github.com/steipete/CodexBar) (macOS).

## Features

- **Waybar icon** that changes color based on usage (green/yellow/red)
- **Tooltip** with compact overview of all providers on hover
- **Interactive TUI** (click) with detailed usage bars, reset countdowns, and settings
- **Usage history** with sparkline visualization (▁▂▃▄▅▆▇█) — tracks usage over time
- **Desktop notifications** when usage exceeds thresholds (80%/95%) with cooldown
- **Clipboard export** — copy usage report via `wl-copy`, `xclip`, or `xsel`
- **Auto dark/light theme** — detects GTK theme, supports Catppuccin Latte/Mocha palettes
- **Log viewer** in TUI — filter by provider or severity
- **Configurable** display modes: icon-only, compact, or full bars
- **Configurable cache TTL** — adjust how long provider data is cached
- **Keyboard shortcuts** throughout the TUI (hotkeys + arrow navigation)
- **Retry with exponential backoff** for transient API failures
- **Better error messages** with actionable hints
- **Centralized logging** to `~/.cache/ai-usage/ai-usage.log`
- **Diagnostic command** (`make check`) to validate setup
- **Automated tests** — 70 tests covering lib, config, and providers
- Automatic token refresh for Claude OAuth and Gemini OAuth
- Codex support via JSON-RPC (app-server) with OAuth API fallback
- Gemini support via Gemini CLI OAuth credentials and Google quota API
- Antigravity support via local language server probe (experimental)
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
  ├── lib.sh                        ← Shared library (logging, cache, errors, retry, countdown)
  ├── ai-usage.sh                   ← Main waybar module
  ├── ai-usage-claude.sh            ← Claude provider
  ├── ai-usage-codex.sh             ← Codex provider
  ├── ai-usage-gemini.sh            ← Gemini provider
  ├── ai-usage-antigravity.sh       ← Antigravity provider
  ├── ai-usage-history.sh           ← Usage history tracking & sparklines
  ├── ai-usage-tui.sh               ← Interactive TUI
  └── ai-usage-check.sh             ← Diagnostic tool

~/.config/waybar/scripts/            ← Thin wrappers only
  ├── ai-usage.sh                   ← Delegates to libexec
  └── ai-usage-tui.sh               ← Delegates to libexec

~/.config/ai-usage/config.json       ← User configuration
~/.cache/ai-usage/ai-usage.log       ← Centralized log file
~/.cache/ai-usage/history/           ← Usage history (JSONL per provider)
```

## Configuration

Edit `~/.config/ai-usage/config.json` or use the TUI settings (click the icon → `s`):

```json
{
  "display_mode": "icon",
  "refresh_interval": 60,
  "cache_ttl_seconds": 55,
  "notifications_enabled": true,
  "notify_warn_threshold": 80,
  "notify_critical_threshold": 95,
  "notify_cooldown_minutes": 15,
  "history_enabled": true,
  "history_retention_days": 7,
  "theme": "auto",
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

### Theme

| Value | Description |
|-------|-------------|
| `auto` | Detect from GTK settings (default) |
| `dark` | Force dark theme (Catppuccin Mocha) |
| `light` | Force light theme (Catppuccin Latte) |

### Notifications

Desktop notifications via `notify-send` when any provider's 5-hour usage crosses the warning or critical thresholds. A cooldown prevents repeated alerts.

| Setting | Default | Description |
|---------|---------|-------------|
| `notifications_enabled` | `true` | Enable/disable notifications |
| `notify_warn_threshold` | `80` | Warning notification at this % |
| `notify_critical_threshold` | `95` | Critical notification at this % |
| `notify_cooldown_minutes` | `15` | Minimum minutes between alerts per provider |

## TUI Shortcuts

### Dashboard
| Key | Action |
|-----|--------|
| `r` | Refresh data |
| `h` | View usage history (sparklines) |
| `c` | Copy usage report to clipboard |
| `s` | Open settings |
| `l` | View logs |
| `q` | Quit |

### Settings
| Key | Action |
|-----|--------|
| `d` | Change display mode |
| `i` | Change refresh interval |
| `t` | Change cache TTL |
| `e` | Change theme (auto/dark/light) |
| `n` | Toggle notifications |
| `c` | Toggle Claude |
| `x` | Toggle Codex |
| `g` | Toggle Gemini |
| `a` | Toggle Antigravity |
| `b` | Back to dashboard |

### Log Viewer
| Key | Action |
|-----|--------|
| `a` | All logs |
| `e` | Errors only |
| `p` | Filter by provider |
| `b` | Back |

## Diagnostics

Run `make check` to validate your setup:

```bash
make check
# or directly:
bash scripts/ai-usage-check.sh
```

This checks dependencies, credential files, network connectivity, and running services.

Logs are written to `~/.cache/ai-usage/ai-usage.log` (auto-rotated, max 1000 lines).

## Testing

```bash
make test
# or directly:
bash tests/run-all.sh
```

Runs 70 automated tests covering the shared library, config handling, provider JSON contract, and waybar output formatting.

## Development

```bash
make lint     # Run shellcheck on all scripts
make test     # Run automated tests
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

### Optional

- `libnotify` — for desktop notifications (`notify-send`)
- `wl-clipboard` — for clipboard export on Wayland (`wl-copy`)
- `xclip` / `xsel` — for clipboard export on X11

## About

**omarchy-ai-usage** brings AI rate limit visibility to the Linux desktop. The idea is simple: if you use AI coding assistants daily, you should always know how much quota you have left — without opening a browser or running CLI commands.

This project was born from the need to have [CodexBar](https://github.com/steipete/CodexBar)-like functionality on Arch Linux with Hyprland/Waybar, bringing the same concept of a unified AI usage dashboard to the Omarchy ecosystem.

Built by [Rodrigo Santiago](https://github.com/rodrigo-sntg).

## License

MIT
