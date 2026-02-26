#!/bin/bash
set -e

# omarchy-ai-usage uninstaller

WAYBAR_SCRIPTS="$HOME/.config/waybar/scripts"
WAYBAR_CONFIG="$HOME/.config/waybar/config.jsonc"
WAYBAR_STYLE="$HOME/.config/waybar/style.css"
AI_CONFIG_DIR="$HOME/.config/ai-usage"

echo ""
echo "  󰧑  omarchy-ai-usage uninstaller"
echo "  ─────────────────────────────────"
echo ""

# ── Remove scripts ────────────────────────────────────────────────────────────

echo "  Removing scripts..."
rm -f "$WAYBAR_SCRIPTS"/ai-usage*.sh
echo "  ✓ Scripts removed"

# ── Remove waybar module ──────────────────────────────────────────────────────

if grep -q '"custom/ai-usage"' "$WAYBAR_CONFIG" 2>/dev/null; then
    echo "  Removing module from waybar config..."
    cp "$WAYBAR_CONFIG" "${WAYBAR_CONFIG}.bak.$(date +%s)"

    tmp=$(mktemp)
    python3 -c "
import json, re

with open('$WAYBAR_CONFIG', 'r') as f:
    content = f.read()

clean = re.sub(r'//.*$', '', content, flags=re.MULTILINE)
data = json.loads(clean)

# Remove from modules-right
mods = data.get('modules-right', [])
data['modules-right'] = [m for m in mods if m != 'custom/ai-usage']

# Remove module definition
data.pop('custom/ai-usage', None)

with open('$tmp', 'w') as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
" 2>/dev/null

    if [ -s "$tmp" ]; then
        mv "$tmp" "$WAYBAR_CONFIG"
        echo "  ✓ Waybar config cleaned"
    else
        rm -f "$tmp"
        echo "  ⚠ Could not auto-clean waybar config. Remove manually."
    fi
fi

# ── Remove CSS ────────────────────────────────────────────────────────────────

if grep -q '#custom-ai-usage' "$WAYBAR_STYLE" 2>/dev/null; then
    echo "  Removing CSS styles..."
    cp "$WAYBAR_STYLE" "${WAYBAR_STYLE}.bak.$(date +%s)"
    tmp=$(mktemp)
    python3 -c "
import re

with open('$WAYBAR_STYLE', 'r') as f:
    css = f.read()

# Remove the entire AI Usage block: from comment marker to the last ai-usage rule
css = re.sub(r'/\* ===== AI Usage ===== \*/.*?#custom-ai-usage[^}]*\}', '', css, flags=re.DOTALL)

# Clean up excessive blank lines left behind
css = re.sub(r'\n{3,}', '\n\n', css)

with open('$tmp', 'w') as f:
    f.write(css)
" 2>/dev/null
    if [ -s "$tmp" ]; then
        mv "$tmp" "$WAYBAR_STYLE"
        echo "  ✓ CSS styles removed"
    else
        rm -f "$tmp"
        echo "  ⚠ Could not auto-clean CSS. Remove #custom-ai-usage rules manually."
    fi
fi

# ── Remove cache ──────────────────────────────────────────────────────────────

rm -f /tmp/ai-usage-cache-*.json
echo "  ✓ Cache cleared"

# ── Config ────────────────────────────────────────────────────────────────────

if [ -d "$AI_CONFIG_DIR" ]; then
    read -r -p "  Remove config ($AI_CONFIG_DIR)? [y/N] " answer
    if [[ "$answer" =~ ^[Yy]$ ]]; then
        rm -rf "$AI_CONFIG_DIR"
        echo "  ✓ Config removed"
    else
        echo "  ✓ Config preserved"
    fi
fi

# ── Restart waybar ────────────────────────────────────────────────────────────

echo ""
echo "  Restarting waybar..."
omarchy-restart-waybar 2>/dev/null || true
echo ""
echo "  ✓ Uninstall complete!"
echo ""
