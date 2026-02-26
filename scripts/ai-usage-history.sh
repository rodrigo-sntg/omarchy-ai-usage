#!/bin/bash
# ai-usage-history.sh — Usage history tracking with sparkline visualization
# Sourced by ai-usage.sh and ai-usage-tui.sh

# History directory
AI_USAGE_HISTORY_DIR="$HOME/.cache/ai-usage/history"

_ensure_history_dir() {
    [ -d "$AI_USAGE_HISTORY_DIR" ] || mkdir -p "$AI_USAGE_HISTORY_DIR" 2>/dev/null
}

# Record a usage snapshot. Usage: record_snapshot PROVIDER FIVE_HOUR SEVEN_DAY
record_snapshot() {
    local provider="$1" five_hour="$2" seven_day="$3"
    _ensure_history_dir

    local history_file="$AI_USAGE_HISTORY_DIR/${provider}.jsonl"
    local ts
    ts=$(date +%s)
    local line
    line=$(jq -n -c --argjson ts "$ts" --argjson fh "$five_hour" --argjson sd "$seven_day" \
        '{ts: $ts, five_hour: $fh, seven_day: $sd}')

    # Append to history
    echo "$line" >> "$history_file"

    # Prune old entries (keep last N days)
    local retention_days="${AI_USAGE_HISTORY_RETENTION:-7}"
    local cutoff
    cutoff=$(( ts - retention_days * 86400 ))
    if [ -f "$history_file" ]; then
        local tmp
        tmp=$(mktemp)
        jq -c "select(.ts >= $cutoff)" "$history_file" > "$tmp" 2>/dev/null
        if [ -s "$tmp" ]; then
            mv "$tmp" "$history_file"
        else
            rm -f "$tmp"
        fi
    fi
}

# Generate a sparkline from history. Usage: get_sparkline PROVIDER FIELD [COUNT]
# FIELD: "five_hour" or "seven_day"
# Returns unicode sparkline string
get_sparkline() {
    local provider="$1" field="$2" count="${3:-24}"
    local history_file="$AI_USAGE_HISTORY_DIR/${provider}.jsonl"

    if [ ! -f "$history_file" ]; then
        echo ""
        return
    fi

    local chars="▁▂▃▄▅▆▇█"
    local values
    values=$(tail -n "$count" "$history_file" | jq -r ".$field // 0" 2>/dev/null)

    if [ -z "$values" ]; then
        echo ""
        return
    fi

    local sparkline=""
    local val idx
    for val in $values; do
        # Map 0-100 to index 0-7
        val=$(printf "%.0f" "$val" 2>/dev/null || echo "0")
        [ "$val" -lt 0 ] 2>/dev/null && val=0
        [ "$val" -gt 100 ] 2>/dev/null && val=100
        idx=$(( val * 7 / 100 ))
        [ "$idx" -gt 7 ] && idx=7
        [ "$idx" -lt 0 ] && idx=0
        sparkline+="${chars:$idx:1}"
    done

    echo "$sparkline"
}
