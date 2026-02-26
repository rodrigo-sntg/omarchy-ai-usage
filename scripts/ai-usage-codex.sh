#!/bin/bash
# Codex AI usage fetcher for waybar
# Method 1 (Primary): JSON-RPC via codex app-server
# Method 2 (Fallback): OAuth API via chatgpt.com backend
#
# Output: JSON with provider, five_hour, five_hour_reset, seven_day,
#         seven_day_reset, plan, and source fields.

CACHE_FILE="/tmp/ai-usage-cache-codex.json"
CACHE_MAX_AGE=55  # seconds
AUTH_FILE="$HOME/.codex/auth.json"
CODEX_BIN="$HOME/.local/bin/codex"
USAGE_API_URL="https://chatgpt.com/backend-api/wham/usage"

# Timeouts
RPC_REQUEST_TIMEOUT=5   # seconds to wait for each RPC response
RPC_TOTAL_TIMEOUT=15    # total seconds for entire RPC attempt

error_exit() {
    echo "{\"error\":\"$1\",\"provider\":\"codex\"}"
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

# Helper: convert unix timestamp (seconds) to ISO 8601
unix_to_iso() {
    local ts="$1"
    if [ -n "$ts" ] && [ "$ts" != "null" ] && [ "$ts" -gt 0 ] 2>/dev/null; then
        date -u -d "@$ts" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || echo ""
    else
        echo ""
    fi
}

# Helper: build output JSON from RPC-style data
# Args: primary_pct primary_reset_ts secondary_pct secondary_reset_ts plan_type source
build_output() {
    local primary_pct="${1:-0}"
    local primary_reset="${2:-}"
    local secondary_pct="${3:-0}"
    local secondary_reset="${4:-}"
    local plan="${5:-unknown}"
    local source="$6"

    local primary_iso
    local secondary_iso
    primary_iso=$(unix_to_iso "$primary_reset")
    secondary_iso=$(unix_to_iso "$secondary_reset")

    jq -n -c \
        --argjson five_hour "$primary_pct" \
        --arg five_hour_reset "$primary_iso" \
        --argjson seven_day "$secondary_pct" \
        --arg seven_day_reset "$secondary_iso" \
        --arg plan "$plan" \
        --arg source "$source" \
        '{
            provider: "codex",
            five_hour: $five_hour,
            five_hour_reset: $five_hour_reset,
            seven_day: $seven_day,
            seven_day_reset: $seven_day_reset,
            plan: $plan,
            source: $source
        }'
}

# ── Method 1: JSON-RPC via codex app-server ──────────────────────────────────

try_rpc() {
    # Check codex binary exists
    if [ ! -x "$CODEX_BIN" ]; then
        return 1
    fi

    local tmpdir
    tmpdir=$(mktemp -d "/tmp/codex-rpc-XXXXXX") || return 1

    local fifo_in="$tmpdir/stdin"
    local fifo_out="$tmpdir/stdout"
    mkfifo "$fifo_in" "$fifo_out" 2>/dev/null || { rm -rf "$tmpdir"; return 1; }

    local codex_pid=""
    local rpc_result=""

    # Cleanup function (invoked via trap)
    # shellcheck disable=SC2329
    cleanup_rpc() {
        if [ -n "$codex_pid" ] && kill -0 "$codex_pid" 2>/dev/null; then
            kill "$codex_pid" 2>/dev/null
            wait "$codex_pid" 2>/dev/null
        fi
        rm -rf "$tmpdir" 2>/dev/null
    }
    trap cleanup_rpc RETURN

    # Start codex app-server with stdin/stdout from FIFOs
    # Use timeout to prevent indefinite hangs
    timeout "$RPC_TOTAL_TIMEOUT" "$CODEX_BIN" app-server < "$fifo_in" > "$fifo_out" 2>/dev/null &
    codex_pid=$!

    # Open write end of input FIFO (non-blocking to prevent deadlock)
    exec 3>"$fifo_in"

    # Send initialize request
    local init_req='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"clientInfo":{"name":"waybar-ai-usage","version":"1.0.0"}}}'
    echo "$init_req" >&3

    # Read initialize response (with timeout)
    local init_response
    init_response=$(timeout "$RPC_REQUEST_TIMEOUT" head -n 1 < "$fifo_out" 2>/dev/null)
    if [ $? -ne 0 ] || [ -z "$init_response" ]; then
        exec 3>&-
        return 1
    fi

    # Check it's a valid response with id:1
    local init_id
    init_id=$(echo "$init_response" | jq -r '.id // empty' 2>/dev/null)
    if [ "$init_id" != "1" ]; then
        exec 3>&-
        return 1
    fi

    # Send initialized notification
    echo '{"jsonrpc":"2.0","method":"initialized"}' >&3

    # Send rateLimits request
    local rate_req='{"jsonrpc":"2.0","id":2,"method":"account/rateLimits/read"}'
    echo "$rate_req" >&3

    # Read responses until we get id:2 (may receive notifications in between)
    local rate_response=""
    local attempts=0
    local max_attempts=20
    while [ $attempts -lt $max_attempts ]; do
        local line
        line=$(timeout "$RPC_REQUEST_TIMEOUT" head -n 1 < "$fifo_out" 2>/dev/null)
        if [ $? -ne 0 ] || [ -z "$line" ]; then
            exec 3>&-
            return 1
        fi

        local resp_id
        resp_id=$(echo "$line" | jq -r '.id // empty' 2>/dev/null)
        if [ "$resp_id" = "2" ]; then
            rate_response="$line"
            break
        fi
        attempts=$((attempts + 1))
    done

    # Close the input pipe
    exec 3>&-

    if [ -z "$rate_response" ]; then
        return 1
    fi

    # Check for error in response
    local rpc_error
    rpc_error=$(echo "$rate_response" | jq -r '.error // empty' 2>/dev/null)
    if [ -n "$rpc_error" ]; then
        return 1
    fi

    # Parse the rate limits from the result
    local result
    result=$(echo "$rate_response" | jq '.result' 2>/dev/null)
    if [ -z "$result" ] || [ "$result" = "null" ]; then
        return 1
    fi

    local primary_pct secondary_pct primary_reset secondary_reset plan_type
    primary_pct=$(echo "$result" | jq '.rateLimits.primary.usedPercent // 0' 2>/dev/null)
    primary_reset=$(echo "$result" | jq '.rateLimits.primary.resetsAt // 0' 2>/dev/null)
    secondary_pct=$(echo "$result" | jq '.rateLimits.secondary.usedPercent // 0' 2>/dev/null)
    secondary_reset=$(echo "$result" | jq '.rateLimits.secondary.resetsAt // 0' 2>/dev/null)
    plan_type=$(echo "$result" | jq -r '.rateLimits.planType // "unknown"' 2>/dev/null)

    rpc_result=$(build_output "$primary_pct" "$primary_reset" "$secondary_pct" "$secondary_reset" "$plan_type" "rpc")
    if [ -n "$rpc_result" ]; then
        echo "$rpc_result"
        return 0
    fi
    return 1
}

# ── Method 2: OAuth API fallback ─────────────────────────────────────────────

try_api() {
    if [ ! -f "$AUTH_FILE" ]; then
        return 1
    fi

    # Read tokens from auth.json
    local access_token account_id api_key

    access_token=$(jq -r '.tokens.access_token // empty' "$AUTH_FILE" 2>/dev/null)
    account_id=$(jq -r '.tokens.account_id // empty' "$AUTH_FILE" 2>/dev/null)
    api_key=$(jq -r '.OPENAI_API_KEY // empty' "$AUTH_FILE" 2>/dev/null)

    # Use access_token preferably, fall back to OPENAI_API_KEY
    local token=""
    if [ -n "$access_token" ]; then
        token="$access_token"
    elif [ -n "$api_key" ]; then
        token="$api_key"
    else
        return 1
    fi

    # Build curl headers
    local curl_args=(-sf "$USAGE_API_URL" -H "Authorization: Bearer $token" -H "User-Agent: ai-usage-waybar")
    if [ -n "$account_id" ]; then
        curl_args+=(-H "ChatGPT-Account-Id: $account_id")
    fi

    local api_response
    api_response=$(curl "${curl_args[@]}" 2>/dev/null)
    if [ $? -ne 0 ] || [ -z "$api_response" ]; then
        return 1
    fi

    # Check for error in response
    local api_error
    api_error=$(echo "$api_response" | jq -r '.error // .detail // empty' 2>/dev/null)
    if [ -n "$api_error" ]; then
        return 1
    fi

    # Parse the OAuth API response
    # Format: { "rate_limit": { "primary_window": { "used_percent": int, "reset_at": unix_int, ... }, "secondary_window": { ... } } }
    local primary_pct secondary_pct primary_reset secondary_reset
    primary_pct=$(echo "$api_response" | jq '.rate_limit.primary_window.used_percent // 0' 2>/dev/null)
    primary_reset=$(echo "$api_response" | jq '.rate_limit.primary_window.reset_at // 0' 2>/dev/null)
    secondary_pct=$(echo "$api_response" | jq '.rate_limit.secondary_window.used_percent // 0' 2>/dev/null)
    secondary_reset=$(echo "$api_response" | jq '.rate_limit.secondary_window.reset_at // 0' 2>/dev/null)

    local api_result
    api_result=$(build_output "$primary_pct" "$primary_reset" "$secondary_pct" "$secondary_reset" "plus" "api")
    if [ -n "$api_result" ]; then
        echo "$api_result"
        return 0
    fi
    return 1
}

# ── Main ─────────────────────────────────────────────────────────────────────

cache_and_exit() {
    echo "$1" > "$CACHE_FILE"
    cat "$CACHE_FILE"
    exit 0
}

# Try Method 1: RPC
if rpc_output=$(try_rpc 2>/dev/null) && [ -n "$rpc_output" ]; then
    cache_and_exit "$rpc_output"
fi

# Try Method 2: OAuth API
if api_output=$(try_api 2>/dev/null) && [ -n "$api_output" ]; then
    cache_and_exit "$api_output"
fi

# Both methods failed
error_exit "both RPC and API methods failed"
