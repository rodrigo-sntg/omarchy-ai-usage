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
    jq -n -c --arg e "$full_msg" --arg p "$provider" '{"error":$e,"provider":$p}'
    exit 1
}

# ── Cache ─────────────────────────────────────────────────────────────────────

CACHE_MAX_AGE_DEFAULT=55  # seconds

# Read a value from the config file. Usage: get_config_value "key" "default"
get_config_value() {
    local key="$1" default="$2"
    if [ -f "$AI_USAGE_CONFIG" ]; then
        local val
        val=$(jq -r ".$key // empty" "$AI_USAGE_CONFIG" 2>/dev/null)
        [ -n "$val" ] && echo "$val" && return
    fi
    echo "$default"
}

# Check cache freshness. Usage: check_cache "/path/to/cache.json" [ttl_seconds]
# TTL resolution: explicit param > AI_USAGE_CACHE_TTL env > config > 55s default
check_cache() {
    local cache_file="$1"
    local ttl="${2:-${AI_USAGE_CACHE_TTL:-}}"
    [ -z "$ttl" ] && ttl=$(get_config_value "cache_ttl_seconds" "$CACHE_MAX_AGE_DEFAULT")
    _ensure_dirs
    if [ -f "$cache_file" ]; then
        local cache_age
        cache_age=$(( $(date +%s) - $(stat -c %Y "$cache_file") ))
        if [ "$cache_age" -lt "$ttl" ]; then
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

# ── Countdown formatting ─────────────────────────────────────────────────────

# Format an ISO 8601 timestamp as a human-friendly countdown.
# Returns: "< 1m", "42m", "2h 30m", "1d 5h", "expired", or "—"
format_countdown() {
    local iso="$1"
    [ -z "$iso" ] || [ "$iso" = "null" ] || [ "$iso" = "" ] && echo "—" && return
    local reset_epoch now_epoch diff_s
    reset_epoch=$(date -d "$iso" +%s 2>/dev/null) || { echo "—"; return; }
    now_epoch=$(date +%s)
    diff_s=$(( reset_epoch - now_epoch ))
    if [ "$diff_s" -le 0 ]; then echo "expired"; return; fi
    local d=$(( diff_s / 86400 )) h=$(( (diff_s % 86400) / 3600 )) m=$(( (diff_s % 3600) / 60 ))
    if [ "$d" -gt 0 ]; then printf '%dd %dh' "$d" "$h"
    elif [ "$h" -gt 0 ]; then printf '%dh %dm' "$h" "$m"
    elif [ "$m" -gt 0 ]; then printf '%dm' "$m"
    else echo "< 1m"; fi
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
