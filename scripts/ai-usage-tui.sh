#!/bin/bash
# AI Usage TUI — Interactive dashboard with gum
# Launched via waybar click: omarchy-launch-floating-terminal-with-presentation

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"
# shellcheck source=ai-usage-history.sh
source "$SCRIPT_DIR/ai-usage-history.sh"

AI_USAGE_PROVIDER="tui"

# ── Ensure config exists ──────────────────────────────────────────────────────

ensure_config() {
    mkdir -p "$(dirname "$AI_USAGE_CONFIG")"
    if [ ! -f "$AI_USAGE_CONFIG" ]; then
        cat > "$AI_USAGE_CONFIG" << 'EOF'
{
  "display_mode": "icon",
  "refresh_interval": 60,
  "cache_ttl_seconds": 55,
  "notifications_enabled": true,
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
EOF
    fi
}

# ── Theme detection ──────────────────────────────────────────────────────────

detect_system_theme() {
    local theme_pref
    theme_pref=$(jq -r '.theme // "auto"' "$AI_USAGE_CONFIG" 2>/dev/null)
    if [ "$theme_pref" = "dark" ] || [ "$theme_pref" = "light" ]; then
        echo "$theme_pref"
        return
    fi
    local gtk_theme
    gtk_theme=$(gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null | tr -d "'")
    case "$gtk_theme" in
        *dark*) echo "dark"; return ;;
        *light*) echo "light"; return ;;
    esac
    gtk_theme=$(gsettings get org.gnome.desktop.interface gtk-theme 2>/dev/null | tr -d "'")
    case "$gtk_theme" in
        *[Ll]ight*) echo "light"; return ;;
    esac
    echo "dark"
}

# ── Colors and styles ─────────────────────────────────────────────────────────

BOLD='\033[1m'
DIM='\033[2m'
UNDERLINE='\033[4m'
RESET='\033[0m'

apply_theme() {
    local theme="${1:-dark}"
    if [ "$theme" = "light" ]; then
        CYAN='\033[38;2;30;102;245m'
        GREEN='\033[38;2;64;160;43m'
        YELLOW='\033[38;2;223;142;29m'
        RED='\033[38;2;210;15;57m'
        WHITE='\033[38;2;76;79;105m'
        DIM='\033[38;2;140;143;161m'
    else
        CYAN='\033[36m'
        GREEN='\033[32m'
        YELLOW='\033[33m'
        RED='\033[31m'
        WHITE='\033[37m'
        DIM='\033[2m'
    fi
}

CURRENT_THEME=$(detect_system_theme)
apply_theme "$CURRENT_THEME"

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

# time_until removed — now using format_countdown from lib.sh
time_until() { format_countdown "$1"; }

format_plan() {
    local plan="$1"
    plan="${plan#default_claude_}"
    echo "$plan"
}

# ── Fetch data ────────────────────────────────────────────────────────────────

fetch_all() {
    # Visual feedback
    clear
    echo ""
    gum style --foreground 39 --bold "  󰧑  Refreshing AI usage data..."
    echo "     Please wait while we connect to providers..."
    echo ""

    CLAUDE_JSON=""
    CODEX_JSON=""
    GEMINI_JSON=""
    ANTIGRAVITY_JSON=""
    CLAUDE_OK=false
    CODEX_OK=false
    GEMINI_OK=false
    ANTIGRAVITY_OK=false

    local claude_enabled codex_enabled gemini_enabled antigravity_enabled
    claude_enabled=$(jq -r 'if .providers.claude.enabled == null then true else .providers.claude.enabled end' "$AI_USAGE_CONFIG" 2>/dev/null)
    codex_enabled=$(jq -r 'if .providers.codex.enabled == null then true else .providers.codex.enabled end' "$AI_USAGE_CONFIG" 2>/dev/null)
    gemini_enabled=$(jq -r 'if .providers.gemini.enabled == null then true else .providers.gemini.enabled end' "$AI_USAGE_CONFIG" 2>/dev/null)
    antigravity_enabled=$(jq -r 'if .providers.antigravity.enabled == null then true else .providers.antigravity.enabled end' "$AI_USAGE_CONFIG" 2>/dev/null)

    LIBEXEC_DIR=$(resolve_libexec_dir)

    if [ "$claude_enabled" = "true" ]; then
        CLAUDE_JSON=$("$LIBEXEC_DIR/ai-usage-claude.sh" 2>/dev/null)
        if [ -n "$CLAUDE_JSON" ] && ! echo "$CLAUDE_JSON" | jq -e '.error' &>/dev/null; then
            CLAUDE_OK=true
        fi
    fi

    if [ "$codex_enabled" = "true" ]; then
        CODEX_JSON=$("$LIBEXEC_DIR/ai-usage-codex.sh" 2>/dev/null)
        if [ -n "$CODEX_JSON" ] && ! echo "$CODEX_JSON" | jq -e '.error' &>/dev/null; then
            CODEX_OK=true
        fi
    fi

    if [ "$gemini_enabled" = "true" ]; then
        GEMINI_JSON=$("$LIBEXEC_DIR/ai-usage-gemini.sh" 2>/dev/null)
        if [ -n "$GEMINI_JSON" ] && ! echo "$GEMINI_JSON" | jq -e '.error' &>/dev/null; then
            GEMINI_OK=true
        fi
    fi

    if [ "$antigravity_enabled" = "true" ]; then
        ANTIGRAVITY_JSON=$("$LIBEXEC_DIR/ai-usage-antigravity.sh" 2>/dev/null)
        if [ -n "$ANTIGRAVITY_JSON" ] && ! echo "$ANTIGRAVITY_JSON" | jq -e '.error' &>/dev/null; then
            ANTIGRAVITY_OK=true
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

    # Sparklines (history)
    local provider_key
    provider_key=$(echo "$name" | tr '[:upper:]' '[:lower:]')
    local spark_5h spark_7d
    spark_5h=$(get_sparkline "$provider_key" "five_hour" 20)
    spark_7d=$(get_sparkline "$provider_key" "seven_day" 20)
    if [ -n "$spark_5h" ] || [ -n "$spark_7d" ]; then
        printf '  %bHistory   %s  %s%b\n' "$DIM" "${spark_7d:-—}" "${spark_5h:-—}" "$RESET"
    fi

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

    tput civis 2>/dev/null > /dev/tty

    draw_menu() {
        {
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

    local c_on x_on g_on a_on
    c_on=$(jq -r 'if .providers.claude.enabled == null then true else .providers.claude.enabled end' "$AI_USAGE_CONFIG" 2>/dev/null)
    x_on=$(jq -r 'if .providers.codex.enabled == null then true else .providers.codex.enabled end' "$AI_USAGE_CONFIG" 2>/dev/null)
    g_on=$(jq -r 'if .providers.gemini.enabled == null then true else .providers.gemini.enabled end' "$AI_USAGE_CONFIG" 2>/dev/null)
    a_on=$(jq -r 'if .providers.antigravity.enabled == null then true else .providers.antigravity.enabled end' "$AI_USAGE_CONFIG" 2>/dev/null)

    if $CLAUDE_OK; then
        render_provider "$CLAUDE_JSON" "Claude"
    elif [ "$c_on" = "true" ]; then
        render_provider '{"error":"fetch failed"}' "Claude"
    fi

    if $CODEX_OK; then
        render_provider "$CODEX_JSON" "Codex"
    elif [ "$x_on" = "true" ]; then
        render_provider '{"error":"fetch failed"}' "Codex"
    fi

    if $GEMINI_OK; then
        render_provider "$GEMINI_JSON" "Gemini"
    elif [ "$g_on" = "true" ]; then
        render_provider '{"error":"fetch failed"}' "Gemini"
    fi

    if $ANTIGRAVITY_OK; then
        render_provider "$ANTIGRAVITY_JSON" "Antigravity"
    elif [ "$a_on" = "true" ]; then
        render_provider '{"error":"fetch failed"}' "Antigravity"
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

        local current_mode current_interval current_cache_ttl
        current_mode=$(jq -r '.display_mode // "icon"' "$AI_USAGE_CONFIG")
        current_interval=$(jq -r '.refresh_interval // 60' "$AI_USAGE_CONFIG")
        current_cache_ttl=$(jq -r '.cache_ttl_seconds // 55' "$AI_USAGE_CONFIG")

        local claude_on codex_on gemini_on antigravity_on
        claude_on=$(jq -r 'if .providers.claude.enabled == null then true else .providers.claude.enabled end' "$AI_USAGE_CONFIG")
        codex_on=$(jq -r 'if .providers.codex.enabled == null then true else .providers.codex.enabled end' "$AI_USAGE_CONFIG")
        gemini_on=$(jq -r 'if .providers.gemini.enabled == null then true else .providers.gemini.enabled end' "$AI_USAGE_CONFIG")
        antigravity_on=$(jq -r 'if .providers.antigravity.enabled == null then true else .providers.antigravity.enabled end' "$AI_USAGE_CONFIG")

        local claude_mark codex_mark gemini_mark antigravity_mark
        [ "$claude_on" = "true" ] && claude_mark="${GREEN}✓${RESET}" || claude_mark="${RED}✗${RESET}"
        [ "$codex_on" = "true" ] && codex_mark="${GREEN}✓${RESET}" || codex_mark="${RED}✗${RESET}"
        [ "$gemini_on" = "true" ] && gemini_mark="${GREEN}✓${RESET}" || gemini_mark="${RED}✗${RESET}"
        [ "$antigravity_on" = "true" ] && antigravity_mark="${GREEN}✓${RESET}" || antigravity_mark="${RED}✗${RESET}"

        local current_theme
        current_theme=$(jq -r '.theme // "auto"' "$AI_USAGE_CONFIG")

        printf "  ${BOLD}${UNDERLINE}d${RESET}${BOLD}isplay mode:${RESET}  %s\n" "$current_mode"
        printf "  ${BOLD}${UNDERLINE}i${RESET}${BOLD}nterval:${RESET}      %ss\n" "$current_interval"
        printf "  cache ${BOLD}${UNDERLINE}t${RESET}${BOLD}tl:${RESET}      %ss\n" "$current_cache_ttl"
        printf "  th${BOLD}${UNDERLINE}e${RESET}${BOLD}me:${RESET}         %s\n" "$current_theme"
        echo ""
        printf "  ${BOLD}Providers:${RESET}\n"
        printf "  [%b] ${UNDERLINE}c${RESET}laude\n" "$claude_mark"
        printf "  [%b] code${UNDERLINE}x${RESET}\n" "$codex_mark"
        printf "  [%b] ${UNDERLINE}g${RESET}emini\n" "$gemini_mark"
        printf "  [%b] ${UNDERLINE}a${RESET}ntigravity\n" "$antigravity_mark"
        echo ""
        local choice
        local notify_on
        notify_on=$(jq -r '.notifications_enabled // true' "$AI_USAGE_CONFIG")
        local notify_mark
        [ "$notify_on" = "true" ] && notify_mark="${GREEN}✓${RESET}" || notify_mark="${RED}✗${RESET}"
        printf "  [%b] ${UNDERLINE}n${RESET}otifications\n" "$notify_mark"
        echo ""

        choice=$(prompt_choice "d:Display mode" "i:Refresh interval" "t:Cache TTL" "e:Theme" "n:Toggle notifications" "c:Toggle Claude" "x:Toggle Codex" "g:Toggle Gemini" "a:Toggle Antigravity" "b:Back")

        case "$choice" in
            d)
                local new_mode
                new_mode=$(gum choose "icon" "compact" "full" \
                    --cursor.foreground 39 \
                    --item.foreground 255 \
                    --header "Select display mode:" \
                    --selected "$current_mode")
                if [ -n "$new_mode" ]; then
                    local updated
                    updated=$(jq --arg m "$new_mode" '.display_mode = $m' "$AI_USAGE_CONFIG")
                    atomic_write "$AI_USAGE_CONFIG" "$updated"
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
                    local updated
                    updated=$(jq --argjson i "$new_interval" '.refresh_interval = $i' "$AI_USAGE_CONFIG")
                    atomic_write "$AI_USAGE_CONFIG" "$updated"
                    refresh_waybar
                fi
                ;;
            t)
                local new_ttl
                new_ttl=$(gum choose "30" "45" "55" "90" "120" \
                    --cursor.foreground 39 \
                    --item.foreground 255 \
                    --header "Cache TTL (seconds):" \
                    --selected "$current_cache_ttl")
                if [ -n "$new_ttl" ]; then
                    local updated
                    updated=$(jq --argjson t "$new_ttl" '.cache_ttl_seconds = $t' "$AI_USAGE_CONFIG")
                    atomic_write "$AI_USAGE_CONFIG" "$updated"
                    refresh_waybar
                fi
                ;;
            e)
                local new_theme
                new_theme=$(gum choose "auto" "dark" "light" \
                    --cursor.foreground 39 \
                    --item.foreground 255 \
                    --header "Select theme:" \
                    --selected "$current_theme")
                if [ -n "$new_theme" ]; then
                    local updated
                    updated=$(jq --arg t "$new_theme" '.theme = $t' "$AI_USAGE_CONFIG")
                    atomic_write "$AI_USAGE_CONFIG" "$updated"
                    CURRENT_THEME=$(detect_system_theme)
                    apply_theme "$CURRENT_THEME"
                    refresh_waybar
                fi
                ;;
            n)
                local new_val
                [ "$notify_on" = "true" ] && new_val=false || new_val=true
                local updated
                updated=$(jq --argjson v "$new_val" '.notifications_enabled = $v' "$AI_USAGE_CONFIG")
                atomic_write "$AI_USAGE_CONFIG" "$updated"
                ;;
            c)
                local new_val
                [ "$claude_on" = "true" ] && new_val=false || new_val=true
                local updated
                updated=$(jq --argjson v "$new_val" '.providers.claude.enabled = $v' "$AI_USAGE_CONFIG")
                atomic_write "$AI_USAGE_CONFIG" "$updated"
                refresh_waybar
                ;;
            x)
                local new_val
                [ "$codex_on" = "true" ] && new_val=false || new_val=true
                local updated
                updated=$(jq --argjson v "$new_val" '.providers.codex.enabled = $v' "$AI_USAGE_CONFIG")
                atomic_write "$AI_USAGE_CONFIG" "$updated"
                refresh_waybar
                ;;
            g)
                local new_val
                [ "$gemini_on" = "true" ] && new_val=false || new_val=true
                local updated
                updated=$(jq --argjson v "$new_val" '.providers.gemini.enabled = $v' "$AI_USAGE_CONFIG")
                atomic_write "$AI_USAGE_CONFIG" "$updated"
                refresh_waybar
                ;;
            a)
                local new_val
                [ "$antigravity_on" = "true" ] && new_val=false || new_val=true
                local updated
                updated=$(jq --argjson v "$new_val" '.providers.antigravity.enabled = $v' "$AI_USAGE_CONFIG")
                atomic_write "$AI_USAGE_CONFIG" "$updated"
                refresh_waybar
                ;;
            b)
                return
                ;;
        esac
    done
}

# ── Log viewer ───────────────────────────────────────────────────────────────

show_logs() {
    while true; do
        clear
        echo ""
        gum style \
            --border rounded \
            --border-foreground 39 \
            --padding "0 2" \
            --margin "0 1" \
            --bold \
            "📋  Log Viewer"
        echo ""

        local choice
        choice=$(prompt_choice "a:All logs" "e:Errors only" "p:Filter by provider" "b:Back")

        case "$choice" in
            a) _show_log_pager "" ;;
            e) _show_log_pager "ERROR\|WARN" ;;
            p) _show_log_provider_filter ;;
            b) return ;;
        esac
    done
}

_show_log_provider_filter() {
    local provider
    provider=$(gum choose "claude" "codex" "gemini" "antigravity" \
        --cursor.foreground 39 \
        --item.foreground 255 \
        --header "Select provider:")
    [ -n "$provider" ] && _show_log_pager "\[$provider\]"
}

_show_log_pager() {
    local filter="$1"
    local log_file="$AI_USAGE_LOG_FILE"

    if [ ! -f "$log_file" ]; then
        gum style --foreground 196 "  No log file found."
        sleep 2
        return
    fi

    local content
    if [ -n "$filter" ]; then
        content=$(tac "$log_file" 2>/dev/null | grep -i "$filter" | head -100)
    else
        content=$(tac "$log_file" 2>/dev/null | head -100)
    fi

    if [ -z "$content" ]; then
        gum style --foreground 214 "  No matching log entries."
        sleep 2
        return
    fi

    if command -v gum &>/dev/null; then
        echo "$content" | gum pager
    else
        echo "$content" | less
    fi
}

# ── History screen ────────────────────────────────────────────────────────

show_history() {
    clear
    echo ""
    gum style \
        --border rounded \
        --border-foreground 39 \
        --padding "0 2" \
        --margin "0 1" \
        --bold \
        "  Usage History (sparklines)"
    echo ""

    local providers=("claude" "codex" "gemini" "antigravity")
    local names=("Claude" "Codex" "Gemini" "Antigravity")

    for i in "${!providers[@]}"; do
        local p="${providers[$i]}"
        local n="${names[$i]}"
        local history_file="$AI_USAGE_HISTORY_DIR/${p}.jsonl"

        if [ ! -f "$history_file" ]; then
            continue
        fi

        local count
        count=$(wc -l < "$history_file" 2>/dev/null || echo 0)
        [ "$count" -eq 0 ] && continue

        local spark_5h spark_7d
        spark_5h=$(get_sparkline "$p" "five_hour" 40)
        spark_7d=$(get_sparkline "$p" "seven_day" 40)

        printf '  %b%b%s%b  %b(%d samples)%b\n' "$BOLD" "$CYAN" "$n" "$RESET" "$DIM" "$count" "$RESET"
        [ -n "$spark_7d" ] && printf '  Weekly   %b%s%b\n' "$DIM" "$spark_7d" "$RESET"
        [ -n "$spark_5h" ] && printf '  Session  %b%s%b\n' "$DIM" "$spark_5h" "$RESET"
        echo ""
    done

    printf '  %bPress any key to return%b\n' "$DIM" "$RESET"
    read -r -s -n 1 < /dev/tty
}

# ── Clipboard export ─────────────────────────────────────────────────────

_get_clipboard_cmd() {
    if command -v wl-copy &>/dev/null; then echo "wl-copy"
    elif command -v xclip &>/dev/null; then echo "xclip -selection clipboard"
    elif command -v xsel &>/dev/null; then echo "xsel --clipboard --input"
    else echo ""; fi
}

_extract_pct() {
    local json="$1" field="$2"
    echo "$json" | jq -r ".$field // 0" 2>/dev/null | cut -d. -f1
}

copy_to_clipboard() {
    local clip_cmd
    clip_cmd=$(_get_clipboard_cmd)
    if [ -z "$clip_cmd" ]; then
        gum style --foreground 196 "  No clipboard tool found. Install wl-clipboard."
        sleep 2
        return
    fi

    local report
    report="AI Usage Report ($(date '+%Y-%m-%d %H:%M'))"
    report+=$'\n'"──────────────────────────────────"

    if $CLAUDE_OK; then
        local c5 c7 cp
        c5=$(_extract_pct "$CLAUDE_JSON" "five_hour")
        c7=$(_extract_pct "$CLAUDE_JSON" "seven_day")
        cp=$(echo "$CLAUDE_JSON" | jq -r '.plan // "?"' 2>/dev/null)
        report+=$'\n'"$(printf '%-14s 5h: %3d%%  7d: %3d%%  (%s)' 'Claude:' "$c5" "$c7" "$cp")"
    fi
    if $CODEX_OK; then
        local x5 x7 xp
        x5=$(_extract_pct "$CODEX_JSON" "five_hour")
        x7=$(_extract_pct "$CODEX_JSON" "seven_day")
        xp=$(echo "$CODEX_JSON" | jq -r '.plan // "?"' 2>/dev/null)
        report+=$'\n'"$(printf '%-14s 5h: %3d%%  7d: %3d%%  (%s)' 'Codex:' "$x5" "$x7" "$xp")"
    fi
    if $GEMINI_OK; then
        local g5 g7 gp
        g5=$(_extract_pct "$GEMINI_JSON" "five_hour")
        g7=$(_extract_pct "$GEMINI_JSON" "seven_day")
        gp=$(echo "$GEMINI_JSON" | jq -r '.plan // "?"' 2>/dev/null)
        report+=$'\n'"$(printf '%-14s 5h: %3d%%  7d: %3d%%  (%s)' 'Gemini:' "$g5" "$g7" "$gp")"
    fi
    if $ANTIGRAVITY_OK; then
        local a5 a7 ap
        a5=$(_extract_pct "$ANTIGRAVITY_JSON" "five_hour")
        a7=$(_extract_pct "$ANTIGRAVITY_JSON" "seven_day")
        ap=$(echo "$ANTIGRAVITY_JSON" | jq -r '.plan // "?"' 2>/dev/null)
        report+=$'\n'"$(printf '%-14s 5h: %3d%%  7d: %3d%%  (%s)' 'Antigravity:' "$a5" "$a7" "$ap")"
    fi

    echo "$report" | $clip_cmd 2>/dev/null
    gum style --foreground 82 "  ✓ Copied to clipboard!"
    sleep 1
}

# ── Main loop ─────────────────────────────────────────────────────────────────

main() {
    ensure_config
    fetch_all

    while true; do
        show_dashboard

        local choice
        choice=$(prompt_choice "r:Refresh" "h:History" "c:Copy to clipboard" "s:Settings" "l:View logs" "q:Quit")

        case "$choice" in
            r)
                rm -f "$AI_USAGE_CACHE_DIR"/ai-usage-cache-*.json
                fetch_all
                ;;
            h)
                show_history
                ;;
            c)
                copy_to_clipboard
                ;;
            s)
                show_settings
                rm -f "$AI_USAGE_CACHE_DIR"/ai-usage-cache-*.json
                fetch_all
                ;;
            l)
                show_logs
                ;;
            q)
                clear
                exit 0
                ;;
        esac
    done
}

main "$@"
