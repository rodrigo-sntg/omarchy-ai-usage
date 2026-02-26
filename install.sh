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

# Wrapper for the main module
cat > "$WAYBAR_SCRIPTS/ai-usage.sh" << EOF
#!/bin/bash
# Waybar wrapper for ai-usage
exec "$LIB_DIR/ai-usage.sh" "\$@"
EOF

# Wrapper for the TUI
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

# ── Add waybar module ─────────────────────────────────────────────────────────

if ! grep -q '"custom/ai-usage"' "$WAYBAR_CONFIG" 2>/dev/null; then
    echo "  Adding module to waybar config"
    cp "$WAYBAR_CONFIG" "${WAYBAR_CONFIG}.bak.$(date +%s)"

    tmp=$(mktemp)
    python3 -c "
import json, re

with open('$WAYBAR_CONFIG', 'r') as f:
    content = f.read()

clean = re.sub(r'//.*$', '', content, flags=re.MULTILINE)
data = json.loads(clean)

# Add to modules-right at the very beginning (leftmost of the right section)
mods = data.get('modules-right', [])
if 'custom/ai-usage' not in mods:
    # Insert at position 0 to be the leftmost of the right block
    mods.insert(0, 'custom/ai-usage')
    # If separators exist, ensure one follows to give breathing room
    if 'custom/separator-right' in mods:
        # Find where it was just inserted and put separator after
        mods.insert(1, 'custom/separator-right')
    data['modules-right'] = mods

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
        echo "  ✓ Waybar config updated"
    else
        rm -f "$tmp"
        echo "  ⚠ Could not auto-update waybar config."
    fi
else
    echo "  ✓ Waybar module already configured"
fi

# ── Add CSS ───────────────────────────────────────────────────────────────────

if ! grep -q '#custom-ai-usage' "$WAYBAR_STYLE" 2>/dev/null; then
    echo "  Adding CSS styles"
    cp "$WAYBAR_STYLE" "${WAYBAR_STYLE}.bak.$(date +%s)"

    cat >> "$WAYBAR_STYLE" << 'CSS'

/* ===== AI Usage ===== */

#custom-ai-usage {
  padding: 0 10px;
  font-size: 14px;
  transition: all 0.2s ease;
}

#custom-ai-usage.ai-ok {
  color: #a6e3a1;
}

#custom-ai-usage.ai-warn {
  color: #FFC107;
}

#custom-ai-usage.ai-crit {
  color: #D35F5F;
}

#custom-ai-usage:hover {
  color: #e68e0d;
}
CSS
    echo "  ✓ CSS styles added"
else
    echo "  ✓ CSS styles already present"
fi

# ── Restart waybar ────────────────────────────────────────────────────────────

echo ""
echo "  Restarting waybar..."
pkill -RTMIN+9 waybar 2>/dev/null || true
omarchy-restart-waybar 2>/dev/null || true
echo ""
echo "  ✓ Installation complete!"
echo ""
