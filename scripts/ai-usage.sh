#!/bin/bash
# AI Usage Bar — Waybar module
# Reads config from ~/.config/ai-usage/config.json
# Supports display modes: icon, compact, full

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"
LIB_DIR=$(resolve_libexec_dir)

AI_USAGE_PROVIDER="main"
CONFIG_FILE="$AI_USAGE_CONFIG"

# Rotate log on each waybar refresh cycle
rotate_log

# ── Read config ───────────────────────────────────────────────────────────────

DISPLAY_MODE="icon"
if [ -f "$CONFIG_FILE" ]; then
    DISPLAY_MODE=$(jq -r '.display_mode // "icon"' "$CONFIG_FILE")
fi

# ── Helpers ───────────────────────────────────────────────────────────────────

countdown_from_iso() {
    local iso="$1"
    if [ -z "$iso" ] || [ "$iso" = "null" ]; then echo "?"; return; fi
    local reset_epoch now_epoch diff_s
    reset_epoch=$(date -d "$iso" +%s 2>/dev/null) || { echo "?"; return; }
    now_epoch=$(date +%s)
    diff_s=$(( reset_epoch - now_epoch ))
    [ "$diff_s" -le 0 ] && echo "now" && return
    local d=$(( diff_s / 86400 )) h=$(( (diff_s % 86400) / 3600 )) m=$(( (diff_s % 3600) / 60 ))
    if [ "$d" -gt 0 ]; then echo "${d}d ${h}h"
    elif [ "$h" -gt 0 ]; then echo "${h}h ${m}m"
    elif [ "$m" -eq 0 ]; then echo "<1m"
    else echo "${m}m"; fi
}

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

# ── Compute max usage across all providers ────────────────────────────────────

max_pct=0
tooltip_lines=()

if $claude_ok; then
    c7=$(round_float "$(echo "$claude_json" | jq -r 'if .seven_day == null then 0 else .seven_day end')")
    c5=$(round_float "$(echo "$claude_json" | jq -r 'if .five_hour == null then 0 else .five_hour end')")
    cr=$(echo "$claude_json" | jq -r '.five_hour_reset // ""')
    c_bar=$(progress_bar_6 "$c5")
    tooltip_lines+=("Claude  ${c_bar}  ${c5}%  ↻ $(countdown_from_iso "$cr")")
    [ "$c7" -gt "$max_pct" ] 2>/dev/null && max_pct=$c7
    [ "$c5" -gt "$max_pct" ] 2>/dev/null && max_pct=$c5
fi

if $codex_ok; then
    x7=$(round_float "$(echo "$codex_json" | jq -r 'if .seven_day == null then 0 else .seven_day end')")
    x5=$(round_float "$(echo "$codex_json" | jq -r 'if .five_hour == null then 0 else .five_hour end')")
    xr=$(echo "$codex_json" | jq -r '.five_hour_reset // ""')
    x_bar=$(progress_bar_6 "$x5")
    tooltip_lines+=("Codex   ${x_bar}  ${x5}%  ↻ $(countdown_from_iso "$xr")")
    [ "$x7" -gt "$max_pct" ] 2>/dev/null && max_pct=$x7
    [ "$x5" -gt "$max_pct" ] 2>/dev/null && max_pct=$x5
fi

if $gemini_ok; then
    g7=$(round_float "$(echo "$gemini_json" | jq -r 'if .seven_day == null then 0 else .seven_day end')")
    g5=$(round_float "$(echo "$gemini_json" | jq -r 'if .five_hour == null then 0 else .five_hour end')")
    gr=$(echo "$gemini_json" | jq -r '.five_hour_reset // ""')
    g_bar=$(progress_bar_6 "$g5")
    tooltip_lines+=("Gemini  ${g_bar}  ${g5}%  ↻ $(countdown_from_iso "$gr")")
    [ "$g7" -gt "$max_pct" ] 2>/dev/null && max_pct=$g7
    [ "$g5" -gt "$max_pct" ] 2>/dev/null && max_pct=$g5
fi

if $antigravity_ok; then
    a7=$(round_float "$(echo "$antigravity_json" | jq -r 'if .seven_day == null then 0 else .seven_day end')")
    a5=$(round_float "$(echo "$antigravity_json" | jq -r 'if .five_hour == null then 0 else .five_hour end')")
    ar=$(echo "$antigravity_json" | jq -r '.five_hour_reset // ""')
    a_bar=$(progress_bar_6 "$a5")
    tooltip_lines+=("Antigr  ${a_bar}  ${a5}%  ↻ $(countdown_from_iso "$ar")")
    [ "$a7" -gt "$max_pct" ] 2>/dev/null && max_pct=$a7
    [ "$a5" -gt "$max_pct" ] 2>/dev/null && max_pct=$a5
fi

# ── Notifications ────────────────────────────────────────────────────────────

NOTIFY_STATE_FILE="$AI_USAGE_CACHE_DIR/notify-state.json"

_read_notify_config() {
    local key="$1" default="$2"
    if [ -f "$CONFIG_FILE" ]; then
        local val
        val=$(jq -r ".$key // empty" "$CONFIG_FILE" 2>/dev/null)
        [ -n "$val" ] && echo "$val" && return
    fi
    echo "$default"
}

check_and_notify() {
    local provider="$1" pct="$2" reset_info="$3"
    local notify_enabled warn_thresh crit_thresh cooldown_min

    notify_enabled=$(_read_notify_config "notifications_enabled" "true")
    [ "$notify_enabled" != "true" ] && return

    command -v notify-send &>/dev/null || return

    warn_thresh=$(_read_notify_config "notify_warn_threshold" "80")
    crit_thresh=$(_read_notify_config "notify_critical_threshold" "95")
    cooldown_min=$(_read_notify_config "notify_cooldown_minutes" "15")

    [ "$pct" -lt "$warn_thresh" ] 2>/dev/null && return

    # Check cooldown
    local now last_time cooldown_s
    now=$(date +%s)
    cooldown_s=$((cooldown_min * 60))
    if [ -f "$NOTIFY_STATE_FILE" ]; then
        last_time=$(jq -r ".${provider}_last // 0" "$NOTIFY_STATE_FILE" 2>/dev/null)
        if [ $((now - last_time)) -lt "$cooldown_s" ]; then
            return
        fi
    fi

    local urgency="normal"
    [ "$pct" -ge "$crit_thresh" ] 2>/dev/null && urgency="critical"

    notify-send -u "$urgency" -a "AI Usage" \
        "AI Usage Alert" \
        "${provider^} usage at ${pct}% — resets in ${reset_info}" 2>/dev/null

    # Update cooldown state
    local state="{}"
    [ -f "$NOTIFY_STATE_FILE" ] && state=$(cat "$NOTIFY_STATE_FILE" 2>/dev/null)
    state=$(echo "$state" | jq --argjson t "$now" ".${provider}_last = \$t" 2>/dev/null)
    [ -n "$state" ] && atomic_write "$NOTIFY_STATE_FILE" "$state"
}

# Check notifications for each provider
if $claude_ok; then
    check_and_notify "claude" "$c5" "$(countdown_from_iso "$cr")"
fi
if $codex_ok; then
    check_and_notify "codex" "$x5" "$(countdown_from_iso "$xr")"
fi
if $gemini_ok; then
    check_and_notify "gemini" "$g5" "$(countdown_from_iso "$gr")"
fi
if $antigravity_ok; then
    check_and_notify "antigravity" "$a5" "$(countdown_from_iso "$ar")"
fi

# ── CSS class ─────────────────────────────────────────────────────────────────

if [ "$max_pct" -ge 85 ]; then class="ai-crit"
elif [ "$max_pct" -ge 60 ]; then class="ai-warn"
else class="ai-ok"; fi

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
