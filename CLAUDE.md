# omarchy-ai-usage

AI usage monitoring for Omarchy — track Claude, Codex, Gemini, and Antigravity rate limits in Waybar.

## Architecture

```
XDG-compliant layout:

~/.local/libexec/ai-usage/          ← All scripts installed here
  ├── lib.sh                        ← Shared library (logging, cache, errors, atomic writes)
  ├── ai-usage.sh                   ← Main waybar module, outputs JSON for waybar
  │     ├── ai-usage-claude.sh      ← Claude provider (OAuth token refresh)
  │     ├── ai-usage-codex.sh       ← Codex provider (JSON-RPC + OAuth fallback)
  │     ├── ai-usage-gemini.sh      ← Gemini provider (Google quota API)
  │     └── ai-usage-antigravity.sh ← Antigravity provider (local LSP probe)
  ├── ai-usage-tui.sh               ← Interactive dashboard (gum + custom prompt_choice)
  └── ai-usage-check.sh             ← Diagnostic tool (validates deps, creds, network)

~/.config/waybar/scripts/            ← Thin wrappers that delegate to libexec
  ├── ai-usage.sh
  └── ai-usage-tui.sh

Config: ~/.config/ai-usage/config.json
Cache:  ~/.cache/ai-usage/cache/ai-usage-cache-{claude,codex,gemini,antigravity}.json (55s TTL)
Log:    ~/.cache/ai-usage/ai-usage.log (auto-rotated, max 1000 lines)
```

## File Inventory

### Scripts (`scripts/`)

| File | Description |
|------|-------------|
| `lib.sh` | Shared library. Functions: `log_info/warn/error`, `error_json`, `check_cache`, `atomic_write`, `cache_output`, `rotate_log`, `resolve_libexec_dir`. All providers source this. |
| `ai-usage.sh` | Main waybar module. Reads config, calls provider scripts, outputs `{"text","tooltip","class"}` JSON. Supports 3 display modes (icon/compact/full). |
| `ai-usage-claude.sh` | Claude provider. OAuth token from `~/.claude/.credentials.json` (field `claudeAiOauth`). Auto-refreshes expired tokens via `POST https://platform.claude.com/v1/oauth/token`. Calls `GET https://api.anthropic.com/api/oauth/usage`. |
| `ai-usage-codex.sh` | Codex provider. Primary: JSON-RPC via FIFOs to `codex app-server` (method `account/rateLimits/read`). Fallback: OAuth API from `~/.codex/auth.json`. 15s timeout on RPC. |
| `ai-usage-gemini.sh` | Gemini provider. OAuth from `~/.gemini/oauth_creds.json`. Extracts client_id/secret from Gemini CLI, auto-refreshes tokens via Google OAuth. Fetches quota via `POST https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota`. |
| `ai-usage-antigravity.sh` | Antigravity provider (experimental). Detects local language server process via `ps`, discovers ports via `ss`/`lsof`, probes Connect protocol endpoints for quota data. No external auth needed. |
| `ai-usage-tui.sh` | Interactive TUI. Uses `gum style` for headers. Custom `prompt_choice()` function for menus with both hotkey and arrow navigation. Dashboard + settings screens. |
| `ai-usage-check.sh` | Diagnostic tool. Validates dependencies, credentials, network connectivity, and provider reachability. Color-coded pass/fail/warn output. |

### Distribution

| File | Description |
|------|-------------|
| `install.sh` | Main installer. Copies scripts to `~/.local/libexec/ai-usage/`, creates waybar wrappers, registers module, adds CSS. |
| `uninstall.sh` | Removes libexec dir, wrappers, waybar module, CSS, cache, logs. Prompts for config removal. |
| `Makefile` | Standard targets: `install`, `uninstall`, `lint`, `check`. |
| `PKGBUILD` | AUR package definition. |
| `.install` | Pacman post-install hook. Runs `omarchy-ai-usage-setup` for user-level waybar integration. |
| `VERSION` | Single-line version string (e.g. `1.0.0`). |
| `CHANGELOG.md` | Documents all changes per version. |

## API Details

### Claude API

- Credentials: `~/.claude/.credentials.json` → `.claudeAiOauth.accessToken`
- Token refresh: `POST https://platform.claude.com/v1/oauth/token` with client_id `9d1c250a-...`
- Usage: `GET https://api.anthropic.com/api/oauth/usage` → `{ five_hour: { utilization, resets_at }, seven_day: { ... } }`

### Codex API

- Primary: JSON-RPC via `codex -s read-only -a untrusted app-server`, method `account/rateLimits/read`
- Fallback: `GET https://chatgpt.com/backend-api/wham/usage` with Bearer token from `~/.codex/auth.json`

### Gemini API

- Credentials: `~/.gemini/oauth_creds.json` (access_token, refresh_token, expiry_date)
- Client ID/Secret: Extracted from Gemini CLI's `oauth2.js` at runtime
- Token refresh: `POST https://oauth2.googleapis.com/token`
- Project discovery: `POST https://cloudcode-pa.googleapis.com/v1internal:loadCodeAssist`
- Quota: `POST https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota`
- Maps Pro model quotas → primary (seven_day), Flash model quotas → secondary (five_hour)
- Plan detection via tier in loadCodeAssist response: standard-tier → Paid, free-tier → Free/Workspace

### Antigravity API (experimental)

- Process detection: `ps -ax -o pid=,command=` → match `language_server` + `antigravity`
- Extract: `--csrf_token` and `--extension_server_port` from process command line
- Port discovery: `ss -tlnp` (Linux) or `lsof -nP -iTCP -sTCP:LISTEN` (fallback)
- Connect probe: `POST https://127.0.0.1:<port>/exa.language_server_pb.LanguageServerService/GetUnleashData`
- Quota: `POST https://127.0.0.1:<port>/exa.language_server_pb.LanguageServerService/GetUserStatus`
- **Pro Plan Detection:** Prioritizes `availablePromptCredits` / `monthlyPromptCredits` (primary) and `availableFlowCredits` / `monthlyFlowCredits` (secondary).
- **Free Plan Detection:** Fallback to `remainingFraction` within `clientModelConfigs` for Claude and Gemini/Pro/Flash models.
- Self-signed TLS (--insecure), HTTP fallback on extension_server_port

### TUI prompt_choice()

Custom menu function supporting both hotkeys and arrow navigation simultaneously. Renders to `/dev/tty` (not stdout) so it works inside `$(...)` command substitution. Reads input from `/dev/tty`. Only the selected hotkey character goes to stdout.

## Shared Library (`lib.sh`)

All provider scripts source `lib.sh` for shared functionality:

| Function | Purpose |
|----------|---------|
| `log_info/warn/error MSG` | Timestamped log to `~/.cache/ai-usage/ai-usage.log` |
| `error_json MSG` | Print `{"error","provider"}` JSON and exit 1 |
| `check_cache FILE` | If cache is fresh (< 55s), print and exit |
| `atomic_write FILE CONTENT` | Write via temp file + `mv` (crash-safe) |
| `cache_output FILE CONTENT` | `atomic_write` + print |
| `rotate_log` | Trim log to last 1000 lines |
| `resolve_libexec_dir` | Returns `~/.local/libexec/ai-usage` or `scripts/` in dev |

## Config Format

```json
{
  "display_mode": "icon",        // "icon" | "compact" | "full"
  "refresh_interval": 60,        // seconds (for waybar)
  "providers": {
    "claude": { "enabled": true },
    "codex": { "enabled": true },
    "gemini": { "enabled": true },
    "antigravity": { "enabled": true }
  }
}
```

## Provider JSON Contract

Every provider outputs this shape (or `{"error":"..."}` on failure):

```json
{
  "provider": "claude",
  "five_hour": 42.5,
  "five_hour_reset": "2025-01-01T12:00:00Z",
  "seven_day": 65.0,
  "seven_day_reset": "2025-01-03T00:00:00Z",
  "plan": "pro"
}
```

## Waybar Output

The main script outputs:

```json
{"text": "󰧑", "tooltip": "AI Usage\n─────────────────\nClaude  ▰▰▰▱▱▱  45%  ↻ 2h 30m", "class": "ai-ok"}
```

CSS classes: `ai-ok` (< 60%), `ai-warn` (60–84%), `ai-crit` (≥ 85%).

## Development Guide

### Adding a new provider

1. Create `scripts/ai-usage-<provider>.sh` following the pattern of `ai-usage-claude.sh`
   - Source `lib.sh`, set `AI_USAGE_PROVIDER`, use `check_cache`, `error_json`, `cache_output`
   - Output JSON: `{"provider","five_hour","five_hour_reset","seven_day","seven_day_reset","plan"}`
2. Add provider to `ai-usage.sh` (fetch + tooltip + max_pct logic)
3. Add provider toggle to `ai-usage-tui.sh` (settings screen + fetch_all + dashboard)
4. Add provider to default config in `install.sh`
5. Add checks to `ai-usage-check.sh`
6. Add `optdepends` to `PKGBUILD` if there's a CLI dependency
7. Update this file with API details and file inventory

### Publishing a new version to AUR

The AUR repo is **separate** from the GitHub repo. It lives at `/tmp/omarchy-ai-usage-git` (clone as needed) and only contains `PKGBUILD`, `.SRCINFO`, `.install`, and `.gitignore`.

```bash
# 1. Push changes to GitHub first
cd ~/dev/projects/omarchy-ai-usage
git add -A && git commit -m "description" && git push

# 2. Clone AUR repo (if not already)
cd /tmp
git -c init.defaultBranch=master clone ssh://aur@aur.archlinux.org/omarchy-ai-usage-git.git
cd /tmp/omarchy-ai-usage-git

# 3. If only scripts changed (no PKGBUILD/.install changes needed):
#    For -git packages, pkgver auto-updates from git commits.
#    Just bump pkgrel if you need to force yay to rebuild:
#    Edit PKGBUILD → increment pkgrel (e.g. 3 → 4)

# 4. If PKGBUILD or .install changed:
#    Edit the files directly in /tmp/omarchy-ai-usage-git/

# 5. Clean previous build artifacts and rebuild
rm -rf src/ pkg/ omarchy-ai-usage-git/ *.pkg.tar.zst
makepkg -si   # builds and installs locally for testing

# 6. Test the package works (check waybar, click icon, etc.)

# 7. Regenerate .SRCINFO and publish
makepkg --printsrcinfo > .SRCINFO
git add PKGBUILD .SRCINFO omarchy-ai-usage.install
git commit -m "description of change"
git push
```

**Key gotchas:**
- `yay` caches builds in `~/.cache/yay/omarchy-ai-usage-git/` — bump `pkgrel` to force rebuild
- `.gitignore` must exclude `omarchy-ai-usage-git/` (makepkg clone cache) — AUR rejects subdirectories
- Always regenerate `.SRCINFO` before pushing (`makepkg --printsrcinfo > .SRCINFO`)
- To test a clean install cycle: `sudo pacman -R omarchy-ai-usage-git --noconfirm && rm -rf ~/.cache/yay/omarchy-ai-usage-git && yay -S omarchy-ai-usage-git --noconfirm`

### AUR repos

- **GitHub** (source): https://github.com/rodrigo-sntg/omarchy-ai-usage
- **AUR** (package): https://aur.archlinux.org/packages/omarchy-ai-usage-git
- **AUR git**: `ssh://aur@aur.archlinux.org/omarchy-ai-usage-git.git`
