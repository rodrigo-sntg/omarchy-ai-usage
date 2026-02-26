#!/bin/bash
# Gemini AI usage fetcher for waybar
# Reads OAuth credentials from Gemini CLI, refreshes token if needed, fetches quota data
# Based on CodexBar's Gemini provider approach

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

AI_USAGE_PROVIDER="gemini"
CACHE_FILE="$AI_USAGE_CACHE_DIR/ai-usage-cache-gemini.json"
CREDENTIALS_FILE="$HOME/.gemini/oauth_creds.json"
SETTINGS_FILE="$HOME/.gemini/settings.json"
QUOTA_URL="https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota"
LOAD_CODE_ASSIST_URL="https://cloudcode-pa.googleapis.com/v1internal:loadCodeAssist"
TOKEN_URL="https://oauth2.googleapis.com/token"

check_cache "$CACHE_FILE"

# Check auth type from settings
if [ -f "$SETTINGS_FILE" ]; then
    auth_type=$(jq -r '.authType // "oauth-personal"' "$SETTINGS_FILE" 2>/dev/null)
    case "$auth_type" in
        api-key|vertex-ai)
            error_json "unsupported auth type: $auth_type (only oauth-personal is supported)"
            ;;
    esac
fi

# Read credentials
if [ ! -f "$CREDENTIALS_FILE" ]; then
    error_json "credentials file not found: $CREDENTIALS_FILE (run 'gemini auth' first)"
fi

access_token=$(jq -r '.access_token // empty' "$CREDENTIALS_FILE" 2>/dev/null)
refresh_token=$(jq -r '.refresh_token // empty' "$CREDENTIALS_FILE" 2>/dev/null)
expiry_date=$(jq -r '.expiry_date // 0' "$CREDENTIALS_FILE" 2>/dev/null)

if [ -z "$access_token" ]; then
    error_json "access_token not found in credentials"
fi

# ── Extract OAuth client ID/secret from Gemini CLI ────────────────────────────

extract_client_credentials() {
    local gemini_bin oauth2_js

    gemini_bin=$(command -v gemini 2>/dev/null)
    if [ -z "$gemini_bin" ]; then
        log_warn "gemini CLI not found in PATH"
        return 1
    fi

    # Resolve symlinks to find the actual installation
    gemini_bin=$(readlink -f "$gemini_bin" 2>/dev/null || echo "$gemini_bin")
    local base_dir
    base_dir=$(dirname "$gemini_bin")

    # Search for oauth2.js in common locations
    local search_paths=(
        "$base_dir/../libexec/lib/node_modules/@google/gemini-cli/node_modules/@google/gemini-cli-core/dist/src/code_assist/oauth2.js"
        "$base_dir/../lib/node_modules/@google/gemini-cli/node_modules/@google/gemini-cli-core/dist/src/code_assist/oauth2.js"
        "$base_dir/../node_modules/@google/gemini-cli-core/dist/src/code_assist/oauth2.js"
        "$base_dir/node_modules/@google/gemini-cli-core/dist/src/code_assist/oauth2.js"
    )

    for path in "${search_paths[@]}"; do
        if [ -f "$path" ]; then
            oauth2_js="$path"
            break
        fi
    done

    # Fallback: use find
    if [ -z "$oauth2_js" ]; then
        oauth2_js=$(find "$(dirname "$base_dir")" -name "oauth2.js" -path "*/code_assist/*" 2>/dev/null | head -1)
    fi

    if [ -z "$oauth2_js" ] || [ ! -f "$oauth2_js" ]; then
        log_warn "oauth2.js not found in Gemini CLI installation"
        return 1
    fi

    log_info "extracting client credentials from $oauth2_js"

    # Extract client ID and secret via regex
    GEMINI_CLIENT_ID=$(grep -oP 'OAUTH_CLIENT_ID\s*=\s*["\x27]([^"\x27]+)["\x27]' "$oauth2_js" | head -1 | grep -oP '["'"'"'][^"'"'"']+["'"'"']' | tr -d "\"'")
    GEMINI_CLIENT_SECRET=$(grep -oP 'OAUTH_CLIENT_SECRET\s*=\s*["\x27]([^"\x27]+)["\x27]' "$oauth2_js" | head -1 | grep -oP '["'"'"'][^"'"'"']+["'"'"']' | tr -d "\"'")

    if [ -n "$GEMINI_CLIENT_ID" ] && [ -n "$GEMINI_CLIENT_SECRET" ]; then
        return 0
    fi
    log_warn "could not extract client ID/secret from oauth2.js"
    return 1
}

# ── Token refresh if expired ──────────────────────────────────────────────────

now_ms=$(( $(date +%s) * 1000 ))
if [ "$now_ms" -ge "$expiry_date" ] && [ -n "$refresh_token" ]; then
    log_info "access token expired, refreshing..."
    GEMINI_CLIENT_ID=""
    GEMINI_CLIENT_SECRET=""

    if ! extract_client_credentials; then
        error_json "could not extract OAuth client credentials from Gemini CLI"
    fi

    refresh_response=$(curl -sf -X POST "$TOKEN_URL" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "client_id=$GEMINI_CLIENT_ID" \
        -d "client_secret=$GEMINI_CLIENT_SECRET" \
        -d "refresh_token=$refresh_token" \
        -d "grant_type=refresh_token" \
        2>&1)

    if [ $? -ne 0 ] || [ -z "$refresh_response" ]; then
        log_error "token refresh request failed: $refresh_response"
        error_json "token refresh request failed"
    fi

    new_access_token=$(echo "$refresh_response" | jq -r '.access_token // empty')
    expires_in=$(echo "$refresh_response" | jq -r '.expires_in // empty')

    if [ -z "$new_access_token" ]; then
        err_msg=$(echo "$refresh_response" | jq -r '.error_description // .error // "unknown error"')
        log_error "token refresh failed: $err_msg"
        error_json "token refresh failed: $err_msg"
    fi

    access_token="$new_access_token"

    # Calculate new expiry in milliseconds
    if [ -n "$expires_in" ]; then
        new_expiry=$(( $(date +%s) * 1000 + expires_in * 1000 ))
    else
        new_expiry=$(( $(date +%s) * 1000 + 3600 * 1000 ))
    fi

    # Update credentials file atomically
    updated_creds=$(jq \
        --arg at "$new_access_token" \
        --argjson exp "$new_expiry" \
        '.access_token = $at | .expiry_date = $exp' \
        "$CREDENTIALS_FILE" 2>/dev/null)

    if [ $? -eq 0 ] && [ -n "$updated_creds" ]; then
        atomic_write "$CREDENTIALS_FILE" "$updated_creds"
        log_info "token refreshed successfully"
    else
        log_warn "failed to update credentials file"
    fi
fi

# ── Discover project ID via loadCodeAssist ────────────────────────────────────

project_id=""
plan="unknown"

log_info "discovering project via loadCodeAssist..."
code_assist_response=$(curl -sf -X POST "$LOAD_CODE_ASSIST_URL" \
    -H "Authorization: Bearer $access_token" \
    -H "Content-Type: application/json" \
    -d '{"metadata":{"ideType":"GEMINI_CLI","pluginType":"GEMINI"}}' \
    2>&1)

if [ -n "$code_assist_response" ]; then
    project_id=$(echo "$code_assist_response" | jq -r '.cloudaicompanionProject // empty' 2>/dev/null)

    # Detect plan/tier
    tier=$(echo "$code_assist_response" | jq -r '.tier // empty' 2>/dev/null)
    case "$tier" in
        standard-tier) plan="Paid" ;;
        free-tier)
            hd_claim=$(echo "$code_assist_response" | jq -r '.hdClaim // empty' 2>/dev/null)
            if [ -n "$hd_claim" ] && [ "$hd_claim" != "null" ]; then
                plan="Workspace"
            else
                plan="Free"
            fi
            ;;
        legacy-tier) plan="Legacy" ;;
        *) plan="${tier:-unknown}" ;;
    esac
    log_info "detected plan: $plan, project: ${project_id:-none}"
else
    log_warn "loadCodeAssist returned empty response"
fi

# ── Fetch quota ───────────────────────────────────────────────────────────────

quota_body='{}'
if [ -n "$project_id" ]; then
    quota_body=$(jq -n --arg p "$project_id" '{"project": $p}')
fi

log_info "fetching quota..."
quota_response=$(curl -sf -X POST "$QUOTA_URL" \
    -H "Authorization: Bearer $access_token" \
    -H "Content-Type: application/json" \
    -d "$quota_body" \
    2>&1)

if [ $? -ne 0 ] || [ -z "$quota_response" ]; then
    log_error "quota API request failed: $quota_response"
    error_json "quota API request failed"
fi

# Log raw response for debugging (truncated)
log_info "raw quota response: $(echo "$quota_response" | head -c 500)"

# ── Parse quota buckets ──────────────────────────────────────────────────────

output=$(echo "$quota_response" | jq -c --arg plan "$plan" "
    (.buckets // .quotaBuckets // []) |
    (map(select(.modelId // \"\" | test(\"pro\"; \"i\"))) | min_by(if .remainingFraction == null then 1 else .remainingFraction end)) as \$pro |
    (map(select(.modelId // \"\" | test(\"flash\"; \"i\"))) | min_by(if .remainingFraction == null then 1 else .remainingFraction end)) as \$flash |
    (min_by(if .remainingFraction == null then 1 else .remainingFraction end)) as \$worst |
    (\$pro // \$worst) as \$primary |
    (\$flash // \$worst) as \$secondary |
    {
        provider: \"gemini\",
        seven_day: (((1 - (if \$primary.remainingFraction == null then 1 else \$primary.remainingFraction end)) * 100) | floor),
        seven_day_reset: (\$primary.resetTime // \"\"),
        five_hour: (((1 - (if \$secondary.remainingFraction == null then 1 else \$secondary.remainingFraction end)) * 100) | floor),
        five_hour_reset: (\$secondary.resetTime // \"\"),
        plan: \$plan
    }
" 2>/dev/null)

if [ $? -ne 0 ] || [ -z "$output" ]; then
    error_json "failed to parse quota response"
fi

# Cache and output
cache_output "$CACHE_FILE" "$output"
