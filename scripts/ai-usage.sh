#!/bin/bash
# AI Usage Bar — Waybar module
# Reads config from ~/.config/ai-usage/config.json
# Supports display modes: icon, compact, full

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$HOME/.config/ai-usage/config.json"

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
if [ -f "$CONFIG_FILE" ]; then
    claude_enabled=$(jq -r '.providers.claude.enabled // true' "$CONFIG_FILE")
    codex_enabled=$(jq -r '.providers.codex.enabled // true' "$CONFIG_FILE")
fi

# ── Fetch provider data ──────────────────────────────────────────────────────

claude_json=""
codex_json=""
claude_ok=false
codex_ok=false

if [ "$claude_enabled" = "true" ]; then
    claude_json=$("$SCRIPT_DIR/ai-usage-claude.sh" 2>/dev/null)
    if [ -n "$claude_json" ] && ! echo "$claude_json" | jq -e '.error' &>/dev/null; then
        claude_ok=true
    fi
fi

if [ "$codex_enabled" = "true" ]; then
    codex_json=$("$SCRIPT_DIR/ai-usage-codex.sh" 2>/dev/null)
    if [ -n "$codex_json" ] && ! echo "$codex_json" | jq -e '.error' &>/dev/null; then
        codex_ok=true
    fi
fi

# ── Compute max usage across all providers ────────────────────────────────────

max_pct=0
tooltip_lines=()

if $claude_ok; then
    c7=$(round_float "$(echo "$claude_json" | jq -r '.seven_day // 0')")
    c5=$(round_float "$(echo "$claude_json" | jq -r '.five_hour // 0')")
    cr=$(echo "$claude_json" | jq -r '.seven_day_reset // ""')
    c_bar=$(progress_bar_6 "$c7")
    tooltip_lines+=("Claude  ${c_bar}  ${c7}%  ↻ $(countdown_from_iso "$cr")")
    [ "$c7" -gt "$max_pct" ] 2>/dev/null && max_pct=$c7
    [ "$c5" -gt "$max_pct" ] 2>/dev/null && max_pct=$c5
fi

if $codex_ok; then
    x7=$(round_float "$(echo "$codex_json" | jq -r '.seven_day // 0')")
    x5=$(round_float "$(echo "$codex_json" | jq -r '.five_hour // 0')")
    xr=$(echo "$codex_json" | jq -r '.seven_day_reset // ""')
    x_bar=$(progress_bar_6 "$x7")
    tooltip_lines+=("Codex   ${x_bar}  ${x7}%  ↻ $(countdown_from_iso "$xr")")
    [ "$x7" -gt "$max_pct" ] 2>/dev/null && max_pct=$x7
    [ "$x5" -gt "$max_pct" ] 2>/dev/null && max_pct=$x5
fi

# ── CSS class ─────────────────────────────────────────────────────────────────

if [ "$max_pct" -ge 85 ]; then class="ai-crit"
elif [ "$max_pct" -ge 60 ]; then class="ai-warn"
else class="ai-ok"; fi

# ── Build output based on display mode ────────────────────────────────────────

if ! $claude_ok && ! $codex_ok; then
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
        # Show icon + bar of the worst provider
        worst_bar=$(progress_bar_6 "$max_pct")
        text="󰧑 ${worst_bar}"
        ;;
    full)
        # Show icon + bars for all providers
        text_parts=()
        $claude_ok && text_parts+=("󰧑 $c_bar")
        $codex_ok && text_parts+=("󰧑 $x_bar")
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
