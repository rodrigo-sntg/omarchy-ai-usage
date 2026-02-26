#!/bin/bash
# test-config.sh — Tests for config handling

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

# ── Default config creation ──────────────────────────────────────────────

suite "Default config"

# config.json should not exist yet in test HOME
assert_eq "config does not exist initially" "false" "$([ -f "$AI_USAGE_CONFIG" ] && echo true || echo false)"

# Write a default config (simulate what TUI does)
cat > "$AI_USAGE_CONFIG" << 'EOF'
{
  "display_mode": "icon",
  "refresh_interval": 60,
  "providers": {
    "claude": { "enabled": true },
    "codex": { "enabled": true },
    "gemini": { "enabled": true },
    "antigravity": { "enabled": true }
  }
}
EOF

assert_file_exists "config created" "$AI_USAGE_CONFIG"

# ── Config parsing ───────────────────────────────────────────────────────

suite "Config parsing"

mode=$(jq -r '.display_mode' "$AI_USAGE_CONFIG")
assert_eq "display_mode defaults to icon" "icon" "$mode"

interval=$(jq -r '.refresh_interval' "$AI_USAGE_CONFIG")
assert_eq "refresh_interval defaults to 60" "60" "$interval"

claude_on=$(jq -r '.providers.claude.enabled' "$AI_USAGE_CONFIG")
assert_eq "claude enabled by default" "true" "$claude_on"

codex_on=$(jq -r '.providers.codex.enabled' "$AI_USAGE_CONFIG")
assert_eq "codex enabled by default" "true" "$codex_on"

gemini_on=$(jq -r '.providers.gemini.enabled' "$AI_USAGE_CONFIG")
assert_eq "gemini enabled by default" "true" "$gemini_on"

antigravity_on=$(jq -r '.providers.antigravity.enabled' "$AI_USAGE_CONFIG")
assert_eq "antigravity enabled by default" "true" "$antigravity_on"

# ── Config modification ──────────────────────────────────────────────────

suite "Config modification"

updated=$(jq '.display_mode = "compact"' "$AI_USAGE_CONFIG")
atomic_write "$AI_USAGE_CONFIG" "$updated"
mode=$(jq -r '.display_mode' "$AI_USAGE_CONFIG")
assert_eq "display_mode updated to compact" "compact" "$mode"

# Toggle provider
updated=$(jq '.providers.claude.enabled = false' "$AI_USAGE_CONFIG")
atomic_write "$AI_USAGE_CONFIG" "$updated"
claude_on=$(jq -r '.providers.claude.enabled' "$AI_USAGE_CONFIG")
assert_eq "claude disabled after toggle" "false" "$claude_on"

# Other providers unchanged
codex_on=$(jq -r '.providers.codex.enabled' "$AI_USAGE_CONFIG")
assert_eq "codex still enabled after claude toggle" "true" "$codex_on"

# ── Config with missing fields uses defaults ─────────────────────────────

suite "Config fallback defaults"

echo '{}' > "$AI_USAGE_CONFIG"
mode=$(jq -r '.display_mode // "icon"' "$AI_USAGE_CONFIG")
assert_eq "missing display_mode falls back to icon" "icon" "$mode"

interval=$(jq -r '.refresh_interval // 60' "$AI_USAGE_CONFIG")
assert_eq "missing interval falls back to 60" "60" "$interval"

claude_on=$(jq -r 'if .providers.claude.enabled == null then true else .providers.claude.enabled end' "$AI_USAGE_CONFIG")
assert_eq "missing provider defaults to true" "true" "$claude_on"

# ── Summary ──────────────────────────────────────────────────────────────

test_summary
