#!/bin/bash
set -e

# omarchy-ai-usage installer
# Adds AI usage monitoring (Claude, Codex, Gemini, Antigravity) to Waybar
# Works from: git clone (./install.sh) or AUR package (omarchy-ai-usage-setup)

# Detect script source: AUR installs to /usr/share, git clone uses relative path
if [ -d "/usr/share/omarchy-ai-usage/scripts" ]; then
    SOURCE_DIR="/usr/share/omarchy-ai-usage/scripts"
else
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    SOURCE_DIR="$SCRIPT_DIR/scripts"
fi

LIBEXEC_DIR="$HOME/.local/libexec/ai-usage"
WAYBAR_SCRIPTS="$HOME/.config/waybar/scripts"
WAYBAR_CONFIG="$HOME/.config/waybar/config.jsonc"
WAYBAR_STYLE="$HOME/.config/waybar/style.css"
AI_CONFIG_DIR="$HOME/.config/ai-usage"
AI_CONFIG="$AI_CONFIG_DIR/config.json"
AI_CACHE_DIR="$HOME/.cache/ai-usage"

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

# ── Install scripts to XDG libexec ───────────────────────────────────────────

echo "  Installing scripts to $LIBEXEC_DIR/"
mkdir -p "$LIBEXEC_DIR"
cp "$SOURCE_DIR/lib.sh" "$LIBEXEC_DIR/"
cp "$SOURCE_DIR/ai-usage-claude.sh" "$LIBEXEC_DIR/"
cp "$SOURCE_DIR/ai-usage-codex.sh" "$LIBEXEC_DIR/"
cp "$SOURCE_DIR/ai-usage-gemini.sh" "$LIBEXEC_DIR/"
cp "$SOURCE_DIR/ai-usage-antigravity.sh" "$LIBEXEC_DIR/"
cp "$SOURCE_DIR/ai-usage.sh" "$LIBEXEC_DIR/"
cp "$SOURCE_DIR/ai-usage-tui.sh" "$LIBEXEC_DIR/"
cp "$SOURCE_DIR/ai-usage-check.sh" "$LIBEXEC_DIR/"
chmod +x "$LIBEXEC_DIR"/*.sh
echo "  ✓ Scripts installed"

# ── Create thin waybar wrappers ──────────────────────────────────────────────

echo "  Creating waybar wrappers in $WAYBAR_SCRIPTS/"
mkdir -p "$WAYBAR_SCRIPTS"

cat > "$WAYBAR_SCRIPTS/ai-usage.sh" << 'WRAPPER'
#!/bin/bash
# Thin wrapper — delegates to XDG libexec
exec "$HOME/.local/libexec/ai-usage/ai-usage.sh" "$@"
WRAPPER

cat > "$WAYBAR_SCRIPTS/ai-usage-tui.sh" << 'WRAPPER'
#!/bin/bash
# Thin wrapper — delegates to XDG libexec
exec "$HOME/.local/libexec/ai-usage/ai-usage-tui.sh" "$@"
WRAPPER

chmod +x "$WAYBAR_SCRIPTS/ai-usage.sh" "$WAYBAR_SCRIPTS/ai-usage-tui.sh"
echo "  ✓ Waybar wrappers created"

# ── Create cache/log directory ───────────────────────────────────────────────

mkdir -p "$AI_CACHE_DIR"
echo "  ✓ Cache directory ready ($AI_CACHE_DIR)"

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

    # Backup
    cp "$WAYBAR_CONFIG" "${WAYBAR_CONFIG}.bak.$(date +%s)"

    tmp=$(mktemp)
    python3 -c "
import json, re

with open('$WAYBAR_CONFIG', 'r') as f:
    content = f.read()

# Remove comments for JSON parsing
clean = re.sub(r'//.*$', '', content, flags=re.MULTILINE)
data = json.loads(clean)

# Add to modules-right before 'custom/weather' (leftmost position)
mods = data.get('modules-right', [])
if 'custom/ai-usage' not in mods:
    try:
        idx = mods.index('custom/weather')
        mods.insert(idx, 'custom/ai-usage')
    except ValueError:
        mods.insert(0, 'custom/ai-usage')
    data['modules-right'] = mods

# Add module definition
data['custom/ai-usage'] = {
    'exec': '~/.config/waybar/scripts/ai-usage.sh',
    'return-type': 'json',
    'interval': 60,
    'signal': 9,
    'tooltip': True,
    'format': '{}',
    'on-click': 'omarchy-launch-floating-terminal-with-presentation ~/.config/waybar/scripts/ai-usage-tui.sh'
}

with open('$tmp', 'w') as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
" 2>/dev/null

    if [ -s "$tmp" ]; then
        mv "$tmp" "$WAYBAR_CONFIG"
        echo "  ✓ Waybar config updated"
    else
        rm -f "$tmp"
        echo "  ⚠ Could not auto-update waybar config. Add manually."
    fi
else
    echo "  ✓ Waybar module already configured"
fi

# ── Add CSS ───────────────────────────────────────────────────────────────────

if ! grep -q '#custom-ai-usage' "$WAYBAR_STYLE" 2>/dev/null; then
    echo "  Adding CSS styles"

    # Backup
    cp "$WAYBAR_STYLE" "${WAYBAR_STYLE}.bak.$(date +%s)"

    cat >> "$WAYBAR_STYLE" << 'CSS'

/* ===== AI Usage ===== */

#custom-ai-usage {
  padding: 0 6px;
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
omarchy-restart-waybar 2>/dev/null || true
echo ""
echo "  ✓ Installation complete!"
echo ""
echo "  The 󰧑 icon should now appear in your waybar."
echo "  Click it to open the AI Usage dashboard."
echo ""
echo "  Scripts:  $LIBEXEC_DIR/"
echo "  Config:   $AI_CONFIG"
echo "  Logs:     $AI_CACHE_DIR/ai-usage.log"
echo "  Wrappers: $WAYBAR_SCRIPTS/ai-usage*.sh"
echo ""
