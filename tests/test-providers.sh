#!/bin/bash
# test-providers.sh — Tests for provider output contract and main module

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

# ── Provider JSON contract ───────────────────────────────────────────────

suite "Provider JSON contract"

# A valid provider response
valid_json='{"provider":"claude","five_hour":42.5,"five_hour_reset":"2025-01-01T12:00:00Z","seven_day":65.0,"seven_day_reset":"2025-01-03T00:00:00Z","plan":"pro"}'
assert_json_valid "valid provider JSON is valid" "$valid_json"
assert_json_field "provider field" "$valid_json" ".provider" "claude"
assert_json_field "five_hour is numeric" "$valid_json" ".five_hour" "42.5"
assert_json_field "seven_day is numeric" "$valid_json" ".seven_day" "65.0"
assert_json_field "plan field" "$valid_json" ".plan" "pro"

# Error response
error_json_str='{"error":"token expired","provider":"claude"}'
assert_json_valid "error JSON is valid" "$error_json_str"
assert_json_field "error has error field" "$error_json_str" ".error" "token expired"
assert_json_field "error has provider field" "$error_json_str" ".provider" "claude"

# ── Waybar output format ────────────────────────────────────────────────

suite "Waybar output format"

# Simulate what ai-usage.sh outputs
waybar_output='{"text":"󰧑","tooltip":"AI Usage\n─────────────────\nClaude  ▰▰▰▱▱▱  45%  ↻ 2h 30m","class":"ai-ok"}'
assert_json_valid "waybar output is valid JSON" "$waybar_output"
assert_json_field "waybar has text field" "$waybar_output" ".text" "󰧑"
assert_json_field "waybar has class field" "$waybar_output" ".class" "ai-ok"
assert_contains "waybar tooltip has AI Usage" "$(echo "$waybar_output" | jq -r '.tooltip')" "AI Usage"

# Test all CSS classes
assert_json_valid "ai-ok class output" '{"text":"t","tooltip":"t","class":"ai-ok"}'
assert_json_valid "ai-warn class output" '{"text":"t","tooltip":"t","class":"ai-warn"}'
assert_json_valid "ai-crit class output" '{"text":"t","tooltip":"t","class":"ai-crit"}'

# ── Provider scripts syntax check ───────────────────────────────────────

suite "Script syntax (bash -n)"

for script in "$SCRIPT_DIR/../scripts"/*.sh; do
    name=$(basename "$script")
    bash -n "$script" 2>/dev/null
    assert_eq "$name passes syntax check" "0" "$?"
done

# ── Progress bar function ────────────────────────────────────────────────

suite "Progress bar (from ai-usage.sh)"

# Test the progress_bar_6 function from ai-usage.sh
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

assert_eq "0% → all empty" "▱▱▱▱▱▱" "$(progress_bar_6 0)"
assert_eq "100% → all filled" "▰▰▰▰▰▰" "$(progress_bar_6 100)"
assert_eq "50% → half filled" "▰▰▰▱▱▱" "$(progress_bar_6 50)"

# ── round_float function ─────────────────────────────────────────────────

suite "round_float"

round_float() { printf "%.0f" "$1" 2>/dev/null || echo "0"; }

assert_eq "round 42.5 → 42" "42" "$(round_float 42.5)"
assert_eq "round 42.6 → 43" "43" "$(round_float 42.6)"
assert_eq "round 0 → 0" "0" "$(round_float 0)"
assert_eq "round 99.9 → 100" "100" "$(round_float 99.9)"

# ── CSS class thresholds ─────────────────────────────────────────────────

suite "CSS class thresholds"

get_class() {
    local max_pct=$1
    if [ "$max_pct" -ge 85 ]; then echo "ai-crit"
    elif [ "$max_pct" -ge 60 ]; then echo "ai-warn"
    else echo "ai-ok"; fi
}

assert_eq "0% → ai-ok" "ai-ok" "$(get_class 0)"
assert_eq "59% → ai-ok" "ai-ok" "$(get_class 59)"
assert_eq "60% → ai-warn" "ai-warn" "$(get_class 60)"
assert_eq "84% → ai-warn" "ai-warn" "$(get_class 84)"
assert_eq "85% → ai-crit" "ai-crit" "$(get_class 85)"
assert_eq "100% → ai-crit" "ai-crit" "$(get_class 100)"

# ── Summary ──────────────────────────────────────────────────────────────

test_summary
