#!/bin/bash
# Claude AI usage fetcher for waybar
# Reads OAuth credentials, refreshes token if needed, fetches usage data

CACHE_FILE="/tmp/ai-usage-cache-claude.json"
CACHE_MAX_AGE=55  # seconds
CREDENTIALS_FILE="$HOME/.claude/.credentials.json"
CLIENT_ID="9d1c250a-e61b-44d9-88ed-5944d1962f5e"
TOKEN_URL="https://platform.claude.com/v1/oauth/token"
USAGE_URL="https://api.anthropic.com/api/oauth/usage"

error_exit() {
    echo "{\"error\":\"$1\"}"
    exit 1
}

# Check cache
if [ -f "$CACHE_FILE" ]; then
    cache_age=$(( $(date +%s) - $(stat -c %Y "$CACHE_FILE") ))
    if [ "$cache_age" -lt "$CACHE_MAX_AGE" ]; then
        cat "$CACHE_FILE"
        exit 0
    fi
fi

# Read credentials
if [ ! -f "$CREDENTIALS_FILE" ]; then
    error_exit "credentials file not found: $CREDENTIALS_FILE"
fi

oauth_json=$(jq -r '.claudeAiOauth' "$CREDENTIALS_FILE" 2>/dev/null)
if [ -z "$oauth_json" ] || [ "$oauth_json" = "null" ]; then
    error_exit "claudeAiOauth not found in credentials"
fi

access_token=$(echo "$oauth_json" | jq -r '.accessToken')
refresh_token=$(echo "$oauth_json" | jq -r '.refreshToken')
expires_at=$(echo "$oauth_json" | jq -r '.expiresAt')
rate_limit_tier=$(echo "$oauth_json" | jq -r '.rateLimitTier // "unknown"')

if [ -z "$access_token" ] || [ "$access_token" = "null" ]; then
    error_exit "accessToken not found in credentials"
fi

if [ -z "$refresh_token" ] || [ "$refresh_token" = "null" ]; then
    error_exit "refreshToken not found in credentials"
fi

# Check if token is expired (expiresAt is in milliseconds)
now_ms=$(( $(date +%s) * 1000 ))
if [ "$now_ms" -ge "$expires_at" ]; then
    # Refresh the token
    refresh_response=$(curl -sf -X POST "$TOKEN_URL" \
        -H "Content-Type: application/json" \
        -d "{\"grant_type\":\"refresh_token\",\"refresh_token\":\"$refresh_token\",\"client_id\":\"$CLIENT_ID\"}" \
        2>/dev/null)

    if [ $? -ne 0 ] || [ -z "$refresh_response" ]; then
        error_exit "token refresh request failed"
    fi

    new_access_token=$(echo "$refresh_response" | jq -r '.access_token // empty')
    new_refresh_token=$(echo "$refresh_response" | jq -r '.refresh_token // empty')
    expires_in=$(echo "$refresh_response" | jq -r '.expires_in // empty')

    if [ -z "$new_access_token" ]; then
        err_msg=$(echo "$refresh_response" | jq -r '.error // "unknown error"')
        error_exit "token refresh failed: $err_msg"
    fi

    access_token="$new_access_token"

    # Calculate new expiresAt in milliseconds
    if [ -n "$expires_in" ]; then
        new_expires_at=$(( $(date +%s) * 1000 + expires_in * 1000 ))
    else
        # Default to 1 hour if expires_in not provided
        new_expires_at=$(( $(date +%s) * 1000 + 3600 * 1000 ))
    fi

    # Update credentials file
    updated_creds=$(jq \
        --arg at "$new_access_token" \
        --arg rt "${new_refresh_token:-$refresh_token}" \
        --argjson ea "$new_expires_at" \
        '.claudeAiOauth.accessToken = $at |
         .claudeAiOauth.refreshToken = (if $rt != "" then $rt else .claudeAiOauth.refreshToken end) |
         .claudeAiOauth.expiresAt = $ea' \
        "$CREDENTIALS_FILE" 2>/dev/null)

    if [ $? -eq 0 ] && [ -n "$updated_creds" ]; then
        echo "$updated_creds" > "$CREDENTIALS_FILE"
    fi
fi

# Fetch usage data
usage_response=$(curl -sf "$USAGE_URL" \
    -H "Authorization: Bearer $access_token" \
    -H "anthropic-beta: oauth-2025-04-20" \
    -H "User-Agent: ai-usage-waybar" \
    2>/dev/null)

if [ $? -ne 0 ] || [ -z "$usage_response" ]; then
    error_exit "usage API request failed"
fi

# Check for API error
api_error=$(echo "$usage_response" | jq -r '.error // empty' 2>/dev/null)
if [ -n "$api_error" ]; then
    error_exit "usage API error: $api_error"
fi

# Parse the response and build output
# API returns .utilization (percentage) and .resets_at (ISO 8601)
output=$(echo "$usage_response" | jq -c --arg plan "$rate_limit_tier" '{
    provider: "claude",
    five_hour: (.five_hour.utilization // 0),
    five_hour_reset: (.five_hour.resets_at // ""),
    seven_day: (.seven_day.utilization // 0),
    seven_day_reset: (.seven_day.resets_at // ""),
    plan: $plan,
    raw: (. | tostring)
}' 2>/dev/null)

if [ $? -ne 0 ] || [ -z "$output" ]; then
    error_exit "failed to parse usage response"
fi

# Cache and output
echo "$output" > "$CACHE_FILE"
cat "$CACHE_FILE"
