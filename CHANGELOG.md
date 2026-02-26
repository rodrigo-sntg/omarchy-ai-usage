# Changelog

All notable changes to this project will be documented in this file.

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
