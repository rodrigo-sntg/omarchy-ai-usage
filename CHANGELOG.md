# Changelog

All notable changes to this project will be documented in this file.

## [1.1.0] — 2026-02-26

### Added
- **Reset countdown** — Shared `format_countdown` function in `lib.sh` for human-readable reset times (e.g. "2h 30m")
- **Configurable cache TTL** — `cache_ttl_seconds` in config, exported to provider subprocesses via `get_config_value`
- **Better error messages** — `error_json` now accepts an optional hint parameter; uses `jq` for JSON-safe output
- **Retry with exponential backoff** — `retry_curl` in `lib.sh` with configurable `--retries N` and jittered backoff
- **TUI log viewer** — View all logs, filter by errors, or filter by provider with `gum pager`
- **Clipboard export** — Copy usage report to clipboard from TUI via `wl-copy`, `xclip`, or `xsel`
- **Desktop notifications** — `notify-send` alerts when usage exceeds configurable thresholds (80%/95%) with cooldown
- **Gemini credentials fix** — Multi-strategy client ID/secret extraction with fallback chain
- **Usage history** — JSONL-based tracking with sparkline visualization (▁▂▃▄▅▆▇█) in TUI and tooltips
- **Auto dark/light theme** — GTK theme detection via `gsettings`; Catppuccin Latte (light) / Mocha (dark) palettes in TUI; `.ai-usage-light` CSS class for Waybar
- **Automated tests** — 70-test bash framework covering `lib.sh`, config handling, provider JSON contract, and waybar output

### Changed
- Provider scripts now use `retry_curl` instead of raw `curl` for resilient API calls
- Antigravity provider uses `--retries 1` to avoid excessive latency on localhost
- Codex provider removed `-f` flag from curl to avoid conflict with `retry_curl` HTTP code handling
- Notification config is read once upfront instead of per-provider to reduce `jq` calls
- Install.sh default config now includes all new settings (`cache_ttl_seconds`, `notifications_enabled`, `history_enabled`, `history_retention_days`, `theme`)

### Fixed
- JSON injection vulnerability in `error_json` — switched from `printf` to `jq -n -c --arg`
- Unnecessary `eval` in clipboard pipe replaced with direct command execution
- `@media (prefers-color-scheme)` CSS replaced with class-based approach (GTK/Waybar doesn't support media queries)

## [1.0.0] — 2026-02-26

### Added
- **Gemini provider** — OAuth via `~/.gemini/oauth_creds.json`, Google Cloud quota API
- **Antigravity provider** — Local language server probe (experimental)
- **Shared library** (`lib.sh`) — Centralized logging, caching, atomic writes, error handling
- **Diagnostic command** (`ai-usage-check.sh`) — Validates dependencies, credentials, and network
- **Centralized logging** to `~/.cache/ai-usage/ai-usage.log` with auto-rotation
- **Makefile** — `install`, `uninstall`, `lint`, `check` targets
- **XDG directory layout** — Scripts in `~/.local/libexec/ai-usage/`, config in `~/.config/ai-usage/`
- TUI settings toggles for Gemini (`g`) and Antigravity (`a`)
- About section in README with link to author's GitHub

### Changed
- All file writes are now atomic (tmp + mv) to prevent corruption
- Provider scripts replaced `2>/dev/null` with structured log messages
- `install.sh` positions AI usage module at the start of Waybar's modules-right

### Fixed
- Duplicate CSS class comment in `ai-usage.sh`
- Missing base CSS rule for `#custom-ai-usage`

### Initial Features (from pre-1.0)
- Claude provider with OAuth token refresh
- Codex provider with JSON-RPC primary and OAuth API fallback
- Waybar module with icon/compact/full display modes
- Interactive TUI with `gum`-based dashboard and settings
- 55-second cache TTL for all providers
