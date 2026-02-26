#!/bin/bash
# lib.sh — Shared functions for omarchy-ai-usage
# Sourced by all provider scripts, main module, and TUI.

# ── Paths ─────────────────────────────────────────────────────────────────────

AI_USAGE_VERSION="1.0.0"
AI_USAGE_CONFIG="$HOME/.config/ai-usage/config.json"
AI_USAGE_CACHE_DIR="$HOME/.cache/ai-usage/cache"
AI_USAGE_LOG_DIR="$HOME/.cache/ai-usage"
AI_USAGE_LOG_FILE="$AI_USAGE_LOG_DIR/ai-usage.log"
AI_USAGE_LOG_MAX_LINES=1000

# ── Logging ───────────────────────────────────────────────────────────────────

_ensure_dirs() {
    [ -d "$AI_USAGE_LOG_DIR" ] || mkdir -p "$AI_USAGE_LOG_DIR" 2>/dev/null
    [ -d "$AI_USAGE_CACHE_DIR" ] || mkdir -p "$AI_USAGE_CACHE_DIR" 2>/dev/null
}

_log() {
    local level="$1"; shift
    _ensure_dirs
    local ts
    ts=$(date '+%Y-%m-%d %H:%M:%S')
    local caller="${AI_USAGE_PROVIDER:-main}"
    printf '[%s] [%-5s] [%s] %s\n' "$ts" "$level" "$caller" "$*" >> "$AI_USAGE_LOG_FILE" 2>/dev/null
}

log_info()  { _log INFO  "$@"; }
log_warn()  { _log WARN  "$@"; }
log_error() { _log ERROR "$@"; }

# Rotate log if it gets too big (keep last N lines)
rotate_log() {
    if [ -f "$AI_USAGE_LOG_FILE" ]; then
        local lines
        lines=$(wc -l < "$AI_USAGE_LOG_FILE" 2>/dev/null || echo 0)
        if [ "$lines" -gt "$AI_USAGE_LOG_MAX_LINES" ]; then
            local tmp
            tmp=$(mktemp "${AI_USAGE_LOG_FILE}.XXXXXX")
            tail -n "$AI_USAGE_LOG_MAX_LINES" "$AI_USAGE_LOG_FILE" > "$tmp" && mv "$tmp" "$AI_USAGE_LOG_FILE"
        fi
    fi
}

# ── Error output ──────────────────────────────────────────────────────────────

# Print error JSON and exit. Usage: error_json "message" ["hint"]
# Automatically includes provider name from AI_USAGE_PROVIDER.
error_json() {
    local msg="$1"
    local hint="${2:-}"
    local provider="${AI_USAGE_PROVIDER:-unknown}"
    local full_msg="$msg"
    [ -n "$hint" ] && full_msg="$msg. Hint: $hint"
    log_error "$full_msg"
    printf '{"error":"%s","provider":"%s"}\n' "$full_msg" "$provider"
    exit 1
}

# ── Cache ─────────────────────────────────────────────────────────────────────

CACHE_MAX_AGE=55  # seconds

# Check cache freshness. Usage: check_cache "/path/to/cache.json"
# If fresh, prints cached content and exits the script.
check_cache() {
    local cache_file="$1"
    _ensure_dirs
    if [ -f "$cache_file" ]; then
        local cache_age
        cache_age=$(( $(date +%s) - $(stat -c %Y "$cache_file") ))
        if [ "$cache_age" -lt "$CACHE_MAX_AGE" ]; then
            cat "$cache_file"
            exit 0
        fi
    fi
}

# ── Atomic write ──────────────────────────────────────────────────────────────

# Write content to file atomically (tmp + mv). Usage: atomic_write "/path/to/file" "content"
atomic_write() {
    local target="$1"
    local content="$2"
    local dir
    dir=$(dirname "$target")
    [ -d "$dir" ] || mkdir -p "$dir" 2>/dev/null
    local tmp
    tmp=$(mktemp "${dir}/.tmp.XXXXXX") || { log_error "mktemp failed for $target"; return 1; }
    printf '%s\n' "$content" > "$tmp" || { rm -f "$tmp"; log_error "write failed for $target"; return 1; }
    mv "$tmp" "$target" || { rm -f "$tmp"; log_error "mv failed for $target"; return 1; }
}

# Write output to cache and print it. Usage: cache_output "/path/to/cache.json" "json_string"
cache_output() {
    local cache_file="$1"
    local content="$2"
    atomic_write "$cache_file" "$content"
    printf '%s\n' "$content"
}

# ── Resolve script directory ──────────────────────────────────────────────────

# Returns the directory where ai-usage scripts live.
# Order: 1. Local libexec, 2. AUR system path, 3. Development fallback.
resolve_libexec_dir() {
    local xdg_dir="$HOME/.local/libexec/ai-usage"
    local aur_dir="/usr/share/omarchy-ai-usage/scripts"

    if [ -d "$xdg_dir" ]; then
        echo "$xdg_dir"
    elif [ -d "$aur_dir" ]; then
        echo "$aur_dir"
    else
        # Development fallback: use the directory of the calling script
        # BASH_SOURCE[1] refers to the script that sourced lib.sh
        cd "$(dirname "${BASH_SOURCE[1]}")" && pwd
    fi
}
