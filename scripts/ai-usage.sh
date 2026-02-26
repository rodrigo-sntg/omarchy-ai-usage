#!/bin/bash
# AI Usage Bar — Waybar module
# Reads config from ~/.config/ai-usage/config.json
# Supports display modes: icon, compact, full

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"
# shellcheck source=ai-usage-history.sh
source "$SCRIPT_DIR/ai-usage-history.sh"
LIB_DIR=$(resolve_libexec_dir)

AI_USAGE_PROVIDER="main"
CONFIG_FILE="$AI_USAGE_CONFIG"

# Rotate log on each waybar refresh cycle
rotate_log

# ── Read config ───────────────────────────────────────────────────────────────

DISPLAY_MODE="icon"
HISTORY_ENABLED="true"
if [ -f "$CONFIG_FILE" ]; then
    DISPLAY_MODE=$(jq -r '.display_mode // "icon"' "$CONFIG_FILE")
    HISTORY_ENABLED=$(jq -r '.history_enabled // true' "$CONFIG_FILE")
fi
export AI_USAGE_HISTORY_RETENTION
AI_USAGE_HISTORY_RETENTION=$(jq -r '.history_retention_days // 7' "$CONFIG_FILE" 2>/dev/null || echo 7)

# Export cache TTL so provider subprocesses inherit it
export AI_USAGE_CACHE_TTL
AI_USAGE_CACHE_TTL=$(get_config_value "cache_ttl_seconds" "$CACHE_MAX_AGE_DEFAULT")

# ── Helpers ───────────────────────────────────────────────────────────────────

# countdown_from_iso removed — now using format_countdown from lib.sh

progress_bar_6() {
    local pct="$1"
    [ "$pct" -lt 0 ] 2>/dev/null && pct=0
    [ "$pct" -gt 100 ] 2>/dev/null && pct=100
    local filled=$(( (pct * 6 + 50) / 100 ))
    [ "$filled" -gt 6 ] && filled=6
    [ "$filled" -lt 0 ] && filled=0
    local empty=$(( 6 - filled )) bar="" i
    for (( i=0; i<filled; i++ )); do bar+="▰"; done
    for (( i=0; i<empty; i++ )); do bar+="▱"; done
    echo "$bar"
}

round_float() { printf "%.0f" "$1" 2>/dev/null || echo "0"; }

# ── Check which providers are enabled ─────────────────────────────────────────

claude_enabled=true
codex_enabled=true
gemini_enabled=true
antigravity_enabled=true
if [ -f "$CONFIG_FILE" ]; then
    claude_enabled=$(jq -r 'if .providers.claude.enabled == null then true else .providers.claude.enabled end' "$CONFIG_FILE")
    codex_enabled=$(jq -r 'if .providers.codex.enabled == null then true else .providers.codex.enabled end' "$CONFIG_FILE")
    gemini_enabled=$(jq -r 'if .providers.gemini.enabled == null then true else .providers.gemini.enabled end' "$CONFIG_FILE")
    antigravity_enabled=$(jq -r 'if .providers.antigravity.enabled == null then true else .providers.antigravity.enabled end' "$CONFIG_FILE")
fi

# ── Fetch provider data ──────────────────────────────────────────────────────

claude_json=""
codex_json=""
gemini_json=""
antigravity_json=""
claude_ok=false
codex_ok=false
gemini_ok=false
antigravity_ok=false

fetch_provider() {
    local name="$1" script="$2"
    local json
    json=$("$LIB_DIR/$script" 2>/dev/null)
    if [ -n "$json" ] && ! echo "$json" | jq -e '.error' &>/dev/null; then
        echo "$json"
        return 0
    fi
    return 1
}

if [ "$claude_enabled" = "true" ]; then
    claude_json=$(fetch_provider claude ai-usage-claude.sh) && claude_ok=true
fi
if [ "$codex_enabled" = "true" ]; then
    codex_json=$(fetch_provider codex ai-usage-codex.sh) && codex_ok=true
fi
if [ "$gemini_enabled" = "true" ]; then
    gemini_json=$(fetch_provider gemini ai-usage-gemini.sh) && gemini_ok=true
fi
if [ "$antigravity_enabled" = "true" ]; then
    antigravity_json=$(fetch_provider antigravity ai-usage-antigravity.sh) && antigravity_ok=true
fi

# Record history snapshots
if [ "$HISTORY_ENABLED" = "true" ]; then
    _record() {
        local ok="$1" json="$2" name="$3"
        if $ok; then
            local fh sd
            fh=$(echo "$json" | jq -r '.five_hour // 0')
            sd=$(echo "$json" | jq -r '.seven_day // 0')
            record_snapshot "$name" "$fh" "$sd"
        fi
    }
    _record "$claude_ok" "$claude_json" "claude"
    _record "$codex_ok" "$codex_json" "codex"
    _record "$gemini_ok" "$gemini_json" "gemini"
    _record "$antigravity_ok" "$antigravity_json" "antigravity"
fi

# ── Compute max usage across all providers ────────────────────────────────────

max_pct=0
tooltip_lines=()

if $claude_ok; then
    c7=$(round_float "$(echo "$claude_json" | jq -r 'if .seven_day == null then 0 else .seven_day end')")
    c5=$(round_float "$(echo "$claude_json" | jq -r 'if .five_hour == null then 0 else .five_hour end')")
    c5r=$(echo "$claude_json" | jq -r '.five_hour_reset // ""')
    c7r=$(echo "$claude_json" | jq -r '.seven_day_reset // ""')
    c_bar=$(progress_bar_6 "$c5")
    tooltip_lines+=("Claude  ${c_bar}  ${c5}%  5h↻$(format_countdown "$c5r")  7d↻$(format_countdown "$c7r")")
    [ "$c7" -gt "$max_pct" ] 2>/dev/null && max_pct=$c7
    [ "$c5" -gt "$max_pct" ] 2>/dev/null && max_pct=$c5
fi

if $codex_ok; then
    x7=$(round_float "$(echo "$codex_json" | jq -r 'if .seven_day == null then 0 else .seven_day end')")
    x5=$(round_float "$(echo "$codex_json" | jq -r 'if .five_hour == null then 0 else .five_hour end')")
    x5r=$(echo "$codex_json" | jq -r '.five_hour_reset // ""')
    x7r=$(echo "$codex_json" | jq -r '.seven_day_reset // ""')
    x_bar=$(progress_bar_6 "$x5")
    tooltip_lines+=("Codex   ${x_bar}  ${x5}%  5h↻$(format_countdown "$x5r")  7d↻$(format_countdown "$x7r")")
    [ "$x7" -gt "$max_pct" ] 2>/dev/null && max_pct=$x7
    [ "$x5" -gt "$max_pct" ] 2>/dev/null && max_pct=$x5
fi

if $gemini_ok; then
    g7=$(round_float "$(echo "$gemini_json" | jq -r 'if .seven_day == null then 0 else .seven_day end')")
    g5=$(round_float "$(echo "$gemini_json" | jq -r 'if .five_hour == null then 0 else .five_hour end')")
    g5r=$(echo "$gemini_json" | jq -r '.five_hour_reset // ""')
    g7r=$(echo "$gemini_json" | jq -r '.seven_day_reset // ""')
    g_bar=$(progress_bar_6 "$g5")
    tooltip_lines+=("Gemini  ${g_bar}  ${g5}%  5h↻$(format_countdown "$g5r")  7d↻$(format_countdown "$g7r")")
    [ "$g7" -gt "$max_pct" ] 2>/dev/null && max_pct=$g7
    [ "$g5" -gt "$max_pct" ] 2>/dev/null && max_pct=$g5
fi

if $antigravity_ok; then
    a7=$(round_float "$(echo "$antigravity_json" | jq -r 'if .seven_day == null then 0 else .seven_day end')")
    a5=$(round_float "$(echo "$antigravity_json" | jq -r 'if .five_hour == null then 0 else .five_hour end')")
    a5r=$(echo "$antigravity_json" | jq -r '.five_hour_reset // ""')
    a7r=$(echo "$antigravity_json" | jq -r '.seven_day_reset // ""')
    a_bar=$(progress_bar_6 "$a5")
    tooltip_lines+=("Antigr  ${a_bar}  ${a5}%  5h↻$(format_countdown "$a5r")  7d↻$(format_countdown "$a7r")")
    [ "$a7" -gt "$max_pct" ] 2>/dev/null && max_pct=$a7
    [ "$a5" -gt "$max_pct" ] 2>/dev/null && max_pct=$a5
fi

# ── Notifications ────────────────────────────────────────────────────────────

NOTIFY_STATE_FILE="$AI_USAGE_CACHE_DIR/notify-state.json"

NOTIFY_ENABLED="true"
NOTIFY_WARN_THRESH=80
NOTIFY_CRIT_THRESH=95
NOTIFY_COOLDOWN_MIN=15
if [ -f "$CONFIG_FILE" ]; then
    NOTIFY_ENABLED=$(jq -r '.notifications_enabled // true' "$CONFIG_FILE" 2>/dev/null)
    NOTIFY_WARN_THRESH=$(jq -r '.notify_warn_threshold // 80' "$CONFIG_FILE" 2>/dev/null)
    NOTIFY_CRIT_THRESH=$(jq -r '.notify_critical_threshold // 95' "$CONFIG_FILE" 2>/dev/null)
    NOTIFY_COOLDOWN_MIN=$(jq -r '.notify_cooldown_minutes // 15' "$CONFIG_FILE" 2>/dev/null)
fi

_send_notification() {
    local provider="$1" pct="$2" reset_info="$3"

    [ "$pct" -lt "$NOTIFY_WARN_THRESH" ] 2>/dev/null && return

    local now last_time cooldown_s
    now=$(date +%s)
    cooldown_s=$((NOTIFY_COOLDOWN_MIN * 60))
    if [ -f "$NOTIFY_STATE_FILE" ]; then
        last_time=$(jq -r ".${provider}_last // 0" "$NOTIFY_STATE_FILE" 2>/dev/null)
        if [ $((now - last_time)) -lt "$cooldown_s" ]; then
            return
        fi
    fi

    local urgency="normal"
    [ "$pct" -ge "$NOTIFY_CRIT_THRESH" ] 2>/dev/null && urgency="critical"

    notify-send -u "$urgency" -a "AI Usage" \
        "AI Usage Alert" \
        "${provider^} usage at ${pct}% — resets in ${reset_info}" 2>/dev/null

    local state="{}"
    [ -f "$NOTIFY_STATE_FILE" ] && state=$(cat "$NOTIFY_STATE_FILE" 2>/dev/null)
    state=$(echo "$state" | jq --argjson t "$now" ".${provider}_last = \$t" 2>/dev/null)
    if [ -n "$state" ]; then
        atomic_write "$NOTIFY_STATE_FILE" "$state"
    else
        log_warn "failed to update notification state for $provider"
    fi
}

if [ "$NOTIFY_ENABLED" = "true" ] && command -v notify-send &>/dev/null; then
    $claude_ok && _send_notification "claude" "$c5" "$(format_countdown "$c5r")"
    $codex_ok && _send_notification "codex" "$x5" "$(format_countdown "$x5r")"
    $gemini_ok && _send_notification "gemini" "$g5" "$(format_countdown "$g5r")"
    $antigravity_ok && _send_notification "antigravity" "$a5" "$(format_countdown "$a5r")"
fi

# ── CSS class ─────────────────────────────────────────────────────────────────

if [ "$max_pct" -ge 85 ]; then class="ai-crit"
elif [ "$max_pct" -ge 60 ]; then class="ai-warn"
else class="ai-ok"; fi

# Append light theme class if system is in light mode
_is_light_theme() {
    local theme_pref
    theme_pref=$(jq -r '.theme // "auto"' "$CONFIG_FILE" 2>/dev/null)
    if [ "$theme_pref" = "dark" ]; then return 1; fi
    if [ "$theme_pref" = "light" ]; then return 0; fi
    local gtk_theme
    gtk_theme=$(gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null | tr -d "'")
    case "$gtk_theme" in *dark*) return 1 ;; *light*) return 0 ;; esac
    gtk_theme=$(gsettings get org.gnome.desktop.interface gtk-theme 2>/dev/null | tr -d "'")
    case "$gtk_theme" in *[Ll]ight*) return 0 ;; esac
    return 1
}
_is_light_theme && class="$class ai-usage-light"

# ── Build output based on display mode ────────────────────────────────────────

if ! $claude_ok && ! $codex_ok && ! $gemini_ok && ! $antigravity_ok; then
    jq -n -c '{"text":"󰧑 ?","tooltip":"AI Usage: No data available\nCheck credentials","class":"ai-warn"}'
    exit 0
fi

# Build tooltip (use real newlines, jq will escape them properly)
tooltip="AI Usage"
tooltip+=$'\n'"─────────────────"
for line in "${tooltip_lines[@]}"; do
    tooltip+=$'\n'"$line"
done

case "$DISPLAY_MODE" in
    icon)
        text="󰧑"
        ;;
    compact)
        worst_bar=$(progress_bar_6 "$max_pct")
        text="󰧑 ${worst_bar}"
        ;;
    full)
        text_parts=()
        $claude_ok && text_parts+=("󰧑 $c_bar")
        $codex_ok && text_parts+=("󰧑 $x_bar")
        $gemini_ok && text_parts+=("󰧑 $g_bar")
        $antigravity_ok && text_parts+=("󰧑 $a_bar")
        text=""
        for (( i=0; i<${#text_parts[@]}; i++ )); do
            [ $i -gt 0 ] && text+="  "
            text+="${text_parts[$i]}"
        done
        ;;
    *)
        text="󰧑"
        ;;
esac

jq -n -c --arg text "$text" --arg tooltip "$tooltip" --arg class "$class" \
    '{"text": $text, "tooltip": $tooltip, "class": $class}'
