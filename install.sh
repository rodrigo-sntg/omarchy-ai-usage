#!/bin/bash
set -e

# omarchy-ai-usage installer
# Adds AI usage monitoring (Claude, Codex, Gemini, Antigravity) to Waybar

# Detect script source
if [ -d "/usr/share/omarchy-ai-usage/scripts" ]; then
    SOURCE_DIR="/usr/share/omarchy-ai-usage/scripts"
else
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    SOURCE_DIR="$SCRIPT_DIR/scripts"
fi

LIB_DIR="$HOME/.local/libexec/ai-usage"
WAYBAR_SCRIPTS="$HOME/.config/waybar/scripts"
WAYBAR_CONFIG="$HOME/.config/waybar/config.jsonc"
WAYBAR_STYLE="$HOME/.config/waybar/style.css"
AI_CONFIG_DIR="$HOME/.config/ai-usage"
AI_CONFIG="$AI_CONFIG_DIR/config.json"
AI_CACHE_DIR="$HOME/.cache/ai-usage/cache"

echo ""
echo "  󰧑  omarchy-ai-usage installer"
echo "  ─────────────────────────────"
echo ""

# ── Check dependencies ────────────────────────────────────────────────────────

missing=()
command -v jq &>/dev/null || missing+=("jq")
command -v curl &>/dev/null || missing+=("curl")
command -v gum &>/dev/null || missing+=("gum")

if [ ${#missing[@]} -gt 0 ]; then
    echo "  Installing missing dependencies: ${missing[*]}"
    yay -S --noconfirm "${missing[@]}" 2>/dev/null || sudo pacman -S --noconfirm "${missing[@]}"
    echo ""
fi

# ── Check source scripts exist ───────────────────────────────────────────────

if [ ! -d "$SOURCE_DIR" ] || [ ! -f "$SOURCE_DIR/ai-usage.sh" ]; then
    echo "  ✗ Scripts not found at $SOURCE_DIR"
    exit 1
fi

# ── Copy scripts to libexec ──────────────────────────────────────────────────

echo "  Installing scripts to $LIB_DIR/"
mkdir -p "$LIB_DIR"
mkdir -p "$AI_CACHE_DIR"

# Copy all scripts from source
cp "$SOURCE_DIR"/*.sh "$LIB_DIR/"
chmod +x "$LIB_DIR"/*.sh
echo "  ✓ Scripts installed"

# ── Create Waybar wrappers ───────────────────────────────────────────────────

echo "  Creating Waybar wrappers in $WAYBAR_SCRIPTS/"
mkdir -p "$WAYBAR_SCRIPTS"

cat > "$WAYBAR_SCRIPTS/ai-usage.sh" << EOF
#!/bin/bash
# Waybar wrapper for ai-usage
exec "$LIB_DIR/ai-usage.sh" "\$@"
EOF

cat > "$WAYBAR_SCRIPTS/ai-usage-tui.sh" << EOF
#!/bin/bash
# Waybar wrapper for ai-usage-tui
exec "$LIB_DIR/ai-usage-tui.sh" "\$@"
EOF

chmod +x "$WAYBAR_SCRIPTS"/ai-usage*.sh
echo "  ✓ Wrappers created"

# ── Create default config ─────────────────────────────────────────────────────

if [ ! -f "$AI_CONFIG" ]; then
    echo "  Creating default config at $AI_CONFIG"
    mkdir -p "$AI_CONFIG_DIR"
    cat > "$AI_CONFIG" << 'EOF'
{
  "display_mode": "icon",
  "refresh_interval": 60,
  "cache_ttl_seconds": 55,
  "notifications_enabled": true,
  "notify_warn_threshold": 80,
  "notify_critical_threshold": 95,
  "notify_cooldown_minutes": 15,
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
    echo "  ✓ Config created"
else
    echo "  ✓ Config already exists (preserved)"
fi

# ── Add/Update waybar module ──────────────────────────────────────────────────

echo "  Updating waybar module configuration"
[ -f "$WAYBAR_CONFIG" ] && cp "$WAYBAR_CONFIG" "${WAYBAR_CONFIG}.bak.$(date +%s)"

tmp=$(mktemp)
python3 -c "
import json, re

with open('$WAYBAR_CONFIG', 'r') as f:
    content = f.read()

# Clean comments for JSON parsing
clean = re.sub(r'//.*$', '', content, flags=re.MULTILINE)
data = json.loads(clean)

# Update modules-right position
mods = data.get('modules-right', [])
# Remove existing occurrences to avoid duplicates and fix position
mods = [m for m in mods if m != 'custom/ai-usage' and m != 'custom/separator-right']

# Insert at the beginning: ai-usage then a separator
mods.insert(0, 'custom/separator-right')
mods.insert(0, 'custom/ai-usage')
data['modules-right'] = mods

# Always update the module definition to ensure paths are correct
data['custom/ai-usage'] = {
    'exec': '$WAYBAR_SCRIPTS/ai-usage.sh',
    'return-type': 'json',
    'interval': 60,
    'signal': 9,
    'tooltip': True,
    'format': '{}',
    'on-click': 'omarchy-launch-floating-terminal-with-presentation $WAYBAR_SCRIPTS/ai-usage-tui.sh'
}

with open('$tmp', 'w') as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
" 2>/dev/null

if [ -s "$tmp" ]; then
    mv "$tmp" "$WAYBAR_CONFIG"
    echo "  ✓ Waybar module position and config updated"
else
    rm -f "$tmp"
    echo "  ⚠ Could not update waybar config."
fi

# ── Add/Update CSS ───────────────────────────────────────────────────────────

echo "  Updating CSS styles"
[ -f "$WAYBAR_STYLE" ] && cp "$WAYBAR_STYLE" "${WAYBAR_STYLE}.bak.$(date +%s)"

# Remove old block if it exists
tmp_css=$(mktemp)
python3 -c "
import re
with open('$WAYBAR_STYLE', 'r') as f:
    content = f.read()

# Remove existing block
content = re.sub(r'/\* ===== AI Usage ===== \*/.*?#custom-ai-usage[^}]*\}', '', content, flags=re.DOTALL)
content = content.strip() + '\n\n'

# Add new block
content += '/* ===== AI Usage ===== */\n\n'
content += '#custom-ai-usage {\n'
content += '  padding: 0 10px;\n'
content += '  font-size: 14px;\n'
content += '  transition: all 0.2s ease;\n'
content += '}\n\n'
content += '#custom-ai-usage.ai-ok { color: #a6e3a1; }\n'
content += '#custom-ai-usage.ai-warn { color: #FFC107; }\n'
content += '#custom-ai-usage.ai-crit { color: #D35F5F; }\n'
content += '#custom-ai-usage:hover { color: #e68e0d; }\n\n'
content += '/* Light theme overrides */\n'
content += '#custom-ai-usage.ai-usage-light.ai-ok { color: #40a02b; }\n'
content += '#custom-ai-usage.ai-usage-light.ai-warn { color: #df8e1d; }\n'
content += '#custom-ai-usage.ai-usage-light.ai-crit { color: #d20f39; }\n'
content += '#custom-ai-usage.ai-usage-light:hover { color: #fe640b; }\n'

with open('$tmp_css', 'w') as f:
    f.write(content)
" 2>/dev/null

if [ -s "$tmp_css" ]; then
    mv "$tmp_css" "$WAYBAR_STYLE"
    echo "  ✓ CSS styles updated"
else
    rm -f "$tmp_css"
    echo "  ⚠ Could not update CSS."
fi

# ── Restart waybar ────────────────────────────────────────────────────────────

echo ""
echo "  Restarting waybar..."
pkill -RTMIN+9 waybar 2>/dev/null || true
omarchy-restart-waybar 2>/dev/null || true
echo ""
echo "  ✓ Installation complete!"
echo ""
