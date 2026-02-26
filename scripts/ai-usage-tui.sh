#!/bin/bash
# AI Usage TUI — Interactive dashboard with gum
# Launched via waybar click: omarchy-launch-floating-terminal-with-presentation

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$HOME/.config/ai-usage/config.json"

# ── Ensure config exists ──────────────────────────────────────────────────────

ensure_config() {
    mkdir -p "$(dirname "$CONFIG_FILE")"
    if [ ! -f "$CONFIG_FILE" ]; then
        cat > "$CONFIG_FILE" << 'EOF'
{
  "display_mode": "icon",
  "refresh_interval": 60,
  "providers": {
    "claude": { "enabled": true },
    "codex": { "enabled": true }
  }
}
EOF
    fi
}

# ── Colors and styles ─────────────────────────────────────────────────────────

BOLD='\033[1m'
DIM='\033[2m'
UNDERLINE='\033[4m'
RESET='\033[0m'
CYAN='\033[36m'
GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
WHITE='\033[37m'

# ── Helpers ───────────────────────────────────────────────────────────────────

color_for_pct() {
    local pct=${1:-0}
    if [ "$pct" -ge 85 ]; then printf '%b' "$RED"
    elif [ "$pct" -ge 60 ]; then printf '%b' "$YELLOW"
    else printf '%b' "$GREEN"; fi
}

progress_bar() {
    local pct=${1:-0} width=${2:-25}
    [ "$pct" -lt 0 ] 2>/dev/null && pct=0
    [ "$pct" -gt 100 ] 2>/dev/null && pct=100
    local filled=$(( pct * width / 100 ))
    [ "$filled" -gt "$width" ] && filled=$width
    local empty=$(( width - filled ))
    local color
    color=$(color_for_pct "$pct")
    local bar="${color}"
    for (( i=0; i<filled; i++ )); do bar+="━"; done
    printf '%b' "$RESET"
    bar+="${DIM}"
    for (( i=0; i<empty; i++ )); do bar+="╌"; done
    bar+="${RESET}"
    echo -e "$bar"
}

time_until() {
    local iso="$1"
    [ -z "$iso" ] || [ "$iso" = "null" ] && echo "—" && return
    local target now diff
    target=$(date -d "$iso" +%s 2>/dev/null) || { echo "—"; return; }
    now=$(date +%s)
    diff=$(( target - now ))
    [ "$diff" -le 0 ] && echo "now" && return
    local d=$(( diff / 86400 )) h=$(( (diff % 86400) / 3600 )) m=$(( (diff % 3600) / 60 ))
    if [ "$d" -gt 0 ]; then printf '%dd %dh' "$d" "$h"
    elif [ "$h" -gt 0 ]; then printf '%dh %dm' "$h" "$m"
    elif [ "$m" -gt 0 ]; then printf '%dm' "$m"
    else echo "<1m"; fi
}

format_plan() {
    local plan="$1"
    plan="${plan#default_claude_}"
    echo "$plan"
}

# ── Fetch data ────────────────────────────────────────────────────────────────

fetch_all() {
    CLAUDE_JSON=""
    CODEX_JSON=""
    CLAUDE_OK=false
    CODEX_OK=false

    local claude_enabled codex_enabled
    claude_enabled=$(jq -r '.providers.claude.enabled // true' "$CONFIG_FILE" 2>/dev/null)
    codex_enabled=$(jq -r '.providers.codex.enabled // true' "$CONFIG_FILE" 2>/dev/null)

    if [ "$claude_enabled" = "true" ]; then
        CLAUDE_JSON=$("$SCRIPT_DIR/ai-usage-claude.sh" 2>/dev/null)
        if [ -n "$CLAUDE_JSON" ] && ! echo "$CLAUDE_JSON" | jq -e '.error' &>/dev/null; then
            CLAUDE_OK=true
        fi
    fi

    if [ "$codex_enabled" = "true" ]; then
        CODEX_JSON=$("$SCRIPT_DIR/ai-usage-codex.sh" 2>/dev/null)
        if [ -n "$CODEX_JSON" ] && ! echo "$CODEX_JSON" | jq -e '.error' &>/dev/null; then
            CODEX_OK=true
        fi
    fi
}

# ── Render provider block ────────────────────────────────────────────────────

render_provider() {
    local json="$1" name="$2"

    local err
    err=$(echo "$json" | jq -r '.error // empty' 2>/dev/null)
    if [ -n "$err" ]; then
        printf '  %b%b%s%b  %b— unavailable (%s)%b\n\n' "$BOLD" "$CYAN" "$name" "$RESET" "$DIM" "$err" "$RESET"
        return
    fi

    local plan five_hour seven_day five_hour_reset seven_day_reset
    plan=$(echo "$json" | jq -r '.plan // "?"')
    five_hour=$(echo "$json" | jq -r '.five_hour // 0' | cut -d. -f1)
    seven_day=$(echo "$json" | jq -r '.seven_day // 0' | cut -d. -f1)
    five_hour_reset=$(echo "$json" | jq -r '.five_hour_reset // ""')
    seven_day_reset=$(echo "$json" | jq -r '.seven_day_reset // ""')

    local display_plan
    display_plan=$(format_plan "$plan")

    local source
    source=$(echo "$json" | jq -r '.source // empty' 2>/dev/null)
    local suffix=""
    [ -n "$source" ] && [ "$source" != "null" ] && suffix=" via $source"

    printf '  %b%b%s%b  %b%s%s%b\n' "$BOLD" "$CYAN" "$name" "$RESET" "$DIM" "$display_plan" "$suffix" "$RESET"

    # Weekly bar
    local w_color w_bar w_reset
    w_color=$(color_for_pct "$seven_day")
    w_bar=$(progress_bar "$seven_day" 25)
    w_reset=$(time_until "$seven_day_reset")
    printf '  Weekly   %b %b%3d%%%b  %b↻ %s%b\n' "$w_bar" "$w_color" "$seven_day" "$RESET" "$DIM" "$w_reset" "$RESET"

    # Session bar
    local s_color s_bar s_reset
    s_color=$(color_for_pct "$five_hour")
    s_bar=$(progress_bar "$five_hour" 25)
    s_reset=$(time_until "$five_hour_reset")
    printf '  Session  %b %b%3d%%%b  %b↻ %s%b\n' "$s_bar" "$s_color" "$five_hour" "$RESET" "$DIM" "$s_reset" "$RESET"

    # Extra usage for Claude
    if [ "$name" = "Claude" ]; then
        local raw extra_enabled
        raw=$(echo "$json" | jq -r '.raw // ""')
        if [ -n "$raw" ]; then
            extra_enabled=$(echo "$raw" | jq -r '.extra_usage.is_enabled // false' 2>/dev/null)
            if [ "$extra_enabled" = "true" ]; then
                local used limit
                used=$(echo "$raw" | jq -r '.extra_usage.used_credits // 0' 2>/dev/null)
                limit=$(echo "$raw" | jq -r '.extra_usage.monthly_limit // 0' 2>/dev/null)
                local used_d limit_d
                used_d=$(awk "BEGIN { printf \"%.2f\", $used / 100 }")
                limit_d=$(awk "BEGIN { printf \"%.2f\", $limit / 100 }")
                printf '  %bExtra credits: $%s / $%s%b\n' "$DIM" "$used_d" "$limit_d" "$RESET"
            fi
        fi
    fi
    echo ""
}

# ── Menu helper: hotkeys + arrow navigation ───────────────────────────────────

# Interactive menu supporting BOTH single-key hotkeys AND arrow navigation.
# Usage: prompt_choice "hotkey:Label" "hotkey:Label" ...
# Example: prompt_choice "r:Refresh" "s:Settings" "q:Quit"
# Returns the hotkey character of the selected item.
prompt_choice() {
    local -a hotkeys=()
    local -a labels=()
    for arg in "$@"; do
        hotkeys+=("${arg%%:*}")
        labels+=("${arg#*:}")
    done

    local count=${#labels[@]}
    local selected=0
    local menu_drawn=0

    # Hide cursor — write to tty, not stdout
    tput civis 2>/dev/null > /dev/tty

    draw_menu() {
        {
            # Move cursor up to overwrite previous menu render
            if [ "$menu_drawn" -eq 1 ]; then
                printf '\033[%dA' "$count"
            fi
            for i in "${!labels[@]}"; do
                if [ "$i" -eq "$selected" ]; then
                    printf '\r\033[K  \033[36m❯ [%s] %s\033[0m\n' "${hotkeys[$i]}" "${labels[$i]}"
                else
                    printf '\r\033[K    [%s] %s\n' "${hotkeys[$i]}" "${labels[$i]}"
                fi
            done
        } > /dev/tty
        menu_drawn=1
    }

    draw_menu

    while true; do
        local key
        IFS= read -r -s -n 1 key < /dev/tty

        if [ "$key" = $'\x1b' ]; then
            local seq
            read -r -s -n 2 -t 0.1 seq < /dev/tty
            case "$seq" in
                '[A') (( selected = selected > 0 ? selected - 1 : count - 1 )); draw_menu ;;
                '[B') (( selected = selected < count - 1 ? selected + 1 : 0 )); draw_menu ;;
            esac
        elif [ "$key" = "" ]; then
            tput cnorm 2>/dev/null > /dev/tty
            echo "${hotkeys[$selected]}"
            return
        else
            local lower_key
            lower_key=$(printf '%s' "$key" | tr '[:upper:]' '[:lower:]')
            for i in "${!hotkeys[@]}"; do
                if [ "$lower_key" = "${hotkeys[$i]}" ]; then
                    tput cnorm 2>/dev/null > /dev/tty
                    echo "${hotkeys[$i]}"
                    return
                fi
            done
        fi
    done
}

# ── Waybar signal ─────────────────────────────────────────────────────────────

# Signal 9 in waybar config = SIGRTMIN+9 to the waybar process
refresh_waybar() {
    pkill -RTMIN+9 waybar 2>/dev/null
}

# ── Screens ───────────────────────────────────────────────────────────────────

show_dashboard() {
    clear
    echo ""
    gum style \
        --border rounded \
        --border-foreground 39 \
        --padding "0 2" \
        --margin "0 1" \
        --bold \
        "󰧑  AI Usage Dashboard"
    echo ""

    if $CLAUDE_OK; then
        render_provider "$CLAUDE_JSON" "Claude"
    elif [ "$(jq -r '.providers.claude.enabled // true' "$CONFIG_FILE" 2>/dev/null)" = "true" ]; then
        render_provider '{"error":"fetch failed"}' "Claude"
    fi

    if $CODEX_OK; then
        render_provider "$CODEX_JSON" "Codex"
    elif [ "$(jq -r '.providers.codex.enabled // true' "$CONFIG_FILE" 2>/dev/null)" = "true" ]; then
        render_provider '{"error":"fetch failed"}' "Codex"
    fi

    printf '  %bUpdated %s%b\n\n' "$DIM" "$(date '+%H:%M:%S')" "$RESET"
}

show_settings() {
    while true; do
        clear
        echo ""
        gum style \
            --border rounded \
            --border-foreground 39 \
            --padding "0 2" \
            --margin "0 1" \
            --bold \
            "⚙  Settings"
        echo ""

        local current_mode current_interval
        current_mode=$(jq -r '.display_mode // "icon"' "$CONFIG_FILE")
        current_interval=$(jq -r '.refresh_interval // 60' "$CONFIG_FILE")
        local claude_on codex_on
        claude_on=$(jq -r '.providers.claude.enabled // true' "$CONFIG_FILE")
        codex_on=$(jq -r '.providers.codex.enabled // true' "$CONFIG_FILE")

        local claude_mark codex_mark
        [ "$claude_on" = "true" ] && claude_mark="${GREEN}✓${RESET}" || claude_mark="${RED}✗${RESET}"
        [ "$codex_on" = "true" ] && codex_mark="${GREEN}✓${RESET}" || codex_mark="${RED}✗${RESET}"

        printf "  ${BOLD}${UNDERLINE}d${RESET}${BOLD}isplay mode:${RESET}  %s\n" "$current_mode"
        printf "  ${BOLD}${UNDERLINE}i${RESET}${BOLD}nterval:${RESET}      %ss\n" "$current_interval"
        echo ""
        printf "  ${BOLD}Providers:${RESET}\n"
        printf "  [%b] ${UNDERLINE}c${RESET}laude\n" "$claude_mark"
        printf "  [%b] code${UNDERLINE}x${RESET}\n" "$codex_mark"
        echo ""
        local choice
        choice=$(prompt_choice "d:Display mode" "i:Refresh interval" "c:Toggle Claude" "x:Toggle Codex" "b:Back")

        case "$choice" in
            d)
                local new_mode
                new_mode=$(gum choose "icon" "compact" "full" \
                    --cursor.foreground 39 \
                    --item.foreground 255 \
                    --header "Select display mode:" \
                    --selected "$current_mode")
                if [ -n "$new_mode" ]; then
                    local tmp
                    tmp=$(mktemp)
                    jq --arg m "$new_mode" '.display_mode = $m' "$CONFIG_FILE" > "$tmp" && mv "$tmp" "$CONFIG_FILE"
                    refresh_waybar
                fi
                ;;
            i)
                local new_interval
                new_interval=$(gum choose "30" "60" "120" "300" \
                    --cursor.foreground 39 \
                    --item.foreground 255 \
                    --header "Refresh interval (seconds):")
                if [ -n "$new_interval" ]; then
                    local tmp
                    tmp=$(mktemp)
                    jq --argjson i "$new_interval" '.refresh_interval = $i' "$CONFIG_FILE" > "$tmp" && mv "$tmp" "$CONFIG_FILE"
                    refresh_waybar
                fi
                ;;
            c)
                local new_val
                [ "$claude_on" = "true" ] && new_val=false || new_val=true
                local tmp
                tmp=$(mktemp)
                jq --argjson v "$new_val" '.providers.claude.enabled = $v' "$CONFIG_FILE" > "$tmp" && mv "$tmp" "$CONFIG_FILE"
                refresh_waybar
                ;;
            x)
                local new_val
                [ "$codex_on" = "true" ] && new_val=false || new_val=true
                local tmp
                tmp=$(mktemp)
                jq --argjson v "$new_val" '.providers.codex.enabled = $v' "$CONFIG_FILE" > "$tmp" && mv "$tmp" "$CONFIG_FILE"
                refresh_waybar
                ;;
            b)
                return
                ;;
        esac
    done
}

# ── Main loop ─────────────────────────────────────────────────────────────────

main() {
    ensure_config

    # Initial fetch
    fetch_all

    while true; do
        show_dashboard

        local choice
        choice=$(prompt_choice "r:Refresh" "s:Settings" "q:Quit")

        case "$choice" in
            r)
                rm -f /tmp/ai-usage-cache-claude.json /tmp/ai-usage-cache-codex.json
                fetch_all
                ;;
            s)
                show_settings
                rm -f /tmp/ai-usage-cache-claude.json /tmp/ai-usage-cache-codex.json
                fetch_all
                ;;
            q)
                clear
                exit 0
                ;;
        esac
    done
}

main "$@"
