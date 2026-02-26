#!/bin/bash
# ai-usage --check — Diagnostic tool for omarchy-ai-usage
# Validates dependencies, credentials, network, and provider reachability.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

AI_USAGE_PROVIDER="check"

GREEN='\033[32m'
RED='\033[31m'
YELLOW='\033[33m'
DIM='\033[2m'
BOLD='\033[1m'
RESET='\033[0m'

pass=0
fail=0
warn=0

ok()   { printf "  ${GREEN}✓${RESET} %s\n" "$1"; ((pass++)); }
fail() { printf "  ${RED}✗${RESET} %s\n" "$1"; ((fail++)); }
skip() { printf "  ${YELLOW}⚠${RESET} %s\n" "$1"; ((warn++)); }

section() { printf "\n${BOLD}%s${RESET}\n" "$1"; }

# ── Dependencies ──────────────────────────────────────────────────────────────

section "Dependencies"

for cmd in jq curl gum bash; do
    if command -v "$cmd" &>/dev/null; then
        ver=$("$cmd" --version 2>/dev/null | head -1)
        ok "$cmd ${DIM}($ver)${RESET}"
    else
        fail "$cmd — not found"
    fi
done

# Optional deps
for cmd in shellcheck ss lsof; do
    if command -v "$cmd" &>/dev/null; then
        ok "$cmd ${DIM}(optional)${RESET}"
    else
        skip "$cmd — not found (optional)"
    fi
done

# ── Configuration ─────────────────────────────────────────────────────────────

section "Configuration"

if [ -f "$AI_USAGE_CONFIG" ]; then
    if jq empty "$AI_USAGE_CONFIG" 2>/dev/null; then
        ok "config file valid JSON ($AI_USAGE_CONFIG)"
    else
        fail "config file is malformed JSON ($AI_USAGE_CONFIG)"
    fi
else
    skip "config file not found (will use defaults)"
fi

# ── Log directory ─────────────────────────────────────────────────────────────

section "Logging"

if [ -d "$AI_USAGE_LOG_DIR" ]; then
    ok "log directory exists ($AI_USAGE_LOG_DIR)"
else
    mkdir -p "$AI_USAGE_LOG_DIR" 2>/dev/null
    if [ -d "$AI_USAGE_LOG_DIR" ]; then
        ok "log directory created ($AI_USAGE_LOG_DIR)"
    else
        fail "could not create log directory ($AI_USAGE_LOG_DIR)"
    fi
fi

if [ -f "$AI_USAGE_LOG_FILE" ]; then
    lines=$(wc -l < "$AI_USAGE_LOG_FILE")
    ok "log file exists ($lines lines)"
else
    skip "log file not yet created (will appear on first run)"
fi

# ── Provider: Claude ──────────────────────────────────────────────────────────

section "Provider: Claude"

CLAUDE_CREDS="$HOME/.claude/.credentials.json"
if [ -f "$CLAUDE_CREDS" ]; then
    ok "credentials file exists"
    oauth=$(jq -r '.claudeAiOauth.accessToken // empty' "$CLAUDE_CREDS" 2>/dev/null)
    if [ -n "$oauth" ]; then
        ok "accessToken present"
    else
        fail "accessToken missing from claudeAiOauth"
    fi

    refresh=$(jq -r '.claudeAiOauth.refreshToken // empty' "$CLAUDE_CREDS" 2>/dev/null)
    if [ -n "$refresh" ]; then
        ok "refreshToken present"
    else
        fail "refreshToken missing"
    fi
else
    fail "credentials file not found: $CLAUDE_CREDS"
    skip "run 'claude auth' to set up"
fi

# ── Provider: Codex ───────────────────────────────────────────────────────────

section "Provider: Codex"

CODEX_BIN="$HOME/.local/bin/codex"
CODEX_AUTH="$HOME/.codex/auth.json"

if [ -x "$CODEX_BIN" ]; then
    ok "codex binary found ($CODEX_BIN)"
else
    skip "codex binary not found — RPC method unavailable"
fi

if [ -f "$CODEX_AUTH" ]; then
    ok "auth file exists ($CODEX_AUTH)"
    token=$(jq -r '.tokens.access_token // .OPENAI_API_KEY // empty' "$CODEX_AUTH" 2>/dev/null)
    if [ -n "$token" ]; then
        ok "token present"
    else
        fail "no usable token in $CODEX_AUTH"
    fi
else
    skip "auth file not found — OAuth fallback unavailable"
fi

# ── Provider: Gemini ──────────────────────────────────────────────────────────

section "Provider: Gemini"

GEMINI_CREDS="$HOME/.gemini/oauth_creds.json"
if [ -f "$GEMINI_CREDS" ]; then
    ok "credentials file exists"
    at=$(jq -r '.access_token // empty' "$GEMINI_CREDS" 2>/dev/null)
    if [ -n "$at" ]; then
        ok "access_token present"
    else
        fail "access_token missing"
    fi
else
    fail "credentials file not found: $GEMINI_CREDS"
    skip "run 'gemini auth' to set up"
fi

if command -v gemini &>/dev/null; then
    ok "gemini CLI found"
else
    skip "gemini CLI not in PATH — token refresh will fail"
fi

# ── Provider: Antigravity ────────────────────────────────────────────────────

section "Provider: Antigravity (experimental)"

ag_pid=$(ps -ax -o pid=,command= 2>/dev/null | grep -i "language_server" | grep -i "antigravity" | head -1 | awk '{print $1}')
if [ -n "$ag_pid" ]; then
    ok "language server running (pid=$ag_pid)"
else
    skip "language server not running — start Antigravity first"
fi

# ── Network ───────────────────────────────────────────────────────────────────

section "Network"

if curl -sf --max-time 5 "https://api.anthropic.com" -o /dev/null 2>/dev/null; then
    ok "api.anthropic.com reachable"
else
    fail "api.anthropic.com unreachable"
fi

if curl -sf --max-time 5 "https://cloudcode-pa.googleapis.com" -o /dev/null 2>/dev/null; then
    ok "cloudcode-pa.googleapis.com reachable"
else
    fail "cloudcode-pa.googleapis.com unreachable"
fi

# ── Summary ───────────────────────────────────────────────────────────────────

printf "\n${BOLD}Summary${RESET}: ${GREEN}%d passed${RESET}, ${RED}%d failed${RESET}, ${YELLOW}%d warnings${RESET}\n\n" "$pass" "$fail" "$warn"

if [ "$fail" -gt 0 ]; then
    printf "Check ${BOLD}%s${RESET} for detailed logs.\n\n" "$AI_USAGE_LOG_FILE"
    exit 1
fi
exit 0
