#!/bin/bash
# Antigravity AI usage fetcher for waybar
# Probes the local Antigravity language server for quota data
# Based on CodexBar's Antigravity provider approach (experimental)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

AI_USAGE_PROVIDER="antigravity"
CACHE_FILE="$AI_USAGE_CACHE_DIR/ai-usage-cache-antigravity.json"

check_cache "$CACHE_FILE"

# ── Process detection ─────────────────────────────────────────────────────────
# Find the Antigravity language server process and extract CSRF token + port

csrf_token=""
extension_port=""
server_pid=""

while IFS= read -r line; do
    pid=$(echo "$line" | awk '{print $1}')
    cmd=$(echo "$line" | cut -d' ' -f2-)

    # Match language_server with antigravity markers
    if echo "$cmd" | grep -qi "language_server" && echo "$cmd" | grep -qi "antigravity"; then
        server_pid="$pid"

        # Extract --csrf_token
        csrf_token=$(echo "$cmd" | grep -oP -- '--csrf_token\s+\K\S+')

        # Extract --extension_server_port
        extension_port=$(echo "$cmd" | grep -oP -- '--extension_server_port\s+\K\S+')

        break
    fi
done < <(ps -ax -o pid=,command= 2>/dev/null)

if [ -z "$server_pid" ]; then
    error_json "Antigravity language server not running" "open Antigravity IDE to start the server"
fi

if [ -z "$csrf_token" ]; then
    error_json "could not extract CSRF token from process" "Antigravity may need to be restarted"
fi

log_info "found Antigravity server (pid=$server_pid, extension_port=${extension_port:-none})"

# ── Port discovery ────────────────────────────────────────────────────────────
# Find all listening ports for the server process

declare -a ports=()

# Try ss first (Linux), then lsof as fallback
if command -v ss &>/dev/null; then
    while IFS= read -r port; do
        [ -n "$port" ] && ports+=("$port")
    done < <(ss -tlnp 2>/dev/null | grep "pid=$server_pid" | grep -oP ':\K[0-9]+(?=\s)' | sort -u)
fi

# Fallback to lsof if ss didn't find ports
if [ ${#ports[@]} -eq 0 ] && command -v lsof &>/dev/null; then
    while IFS= read -r port; do
        [ -n "$port" ] && ports+=("$port")
    done < <(lsof -nP -iTCP -sTCP:LISTEN -p "$server_pid" 2>/dev/null | awk 'NR>1{print $9}' | grep -oP ':\K[0-9]+$' | sort -u)
fi

# Add extension_port if not already in the list
if [ -n "$extension_port" ]; then
    local_has=false
    for p in "${ports[@]}"; do
        [ "$p" = "$extension_port" ] && local_has=true && break
    done
    $local_has || ports+=("$extension_port")
fi

if [ ${#ports[@]} -eq 0 ]; then
    error_json "no listening ports found (pid=$server_pid)" "install 'ss' or 'lsof' for port discovery"
fi

log_info "discovered ${#ports[@]} port(s): ${ports[*]}"

# ── Connect port probe ───────────────────────────────────────────────────────
# Probe each port with GetUnleashData to find the correct connect port

connect_port=""
for port in "${ports[@]}"; do
    # Try HTTPS first
    response=$(curl -sf --insecure --max-time 3 \
        -X POST "https://127.0.0.1:$port/exa.language_server_pb.LanguageServerService/GetUnleashData" \
        -H "X-Codeium-Csrf-Token: $csrf_token" \
        -H "Connect-Protocol-Version: 1" \
        -H "Content-Type: application/json" \
        -d '{}' \
        2>/dev/null)

    if [ $? -eq 0 ]; then
        connect_port="$port"
        connect_scheme="https"
        break
    fi

    # Try HTTP fallback
    response=$(curl -sf --max-time 3 \
        -X POST "http://127.0.0.1:$port/exa.language_server_pb.LanguageServerService/GetUnleashData" \
        -H "X-Codeium-Csrf-Token: $csrf_token" \
        -H "Connect-Protocol-Version: 1" \
        -H "Content-Type: application/json" \
        -d '{}' \
        2>/dev/null)

    if [ $? -eq 0 ]; then
        connect_port="$port"
        connect_scheme="http"
        break
    fi
done

if [ -z "$connect_port" ]; then
    error_json "could not find connect port" "Antigravity server may be initializing; try again"
fi

log_info "connected on $connect_scheme://127.0.0.1:$connect_port"

# ── Fetch user status / quota ─────────────────────────────────────────────────

request_body='{"metadata":{"ideName":"antigravity","extensionName":"antigravity","locale":"en","ideVersion":"unknown"}}'

log_info "fetching user status..."
user_status=$(retry_curl -s --insecure --max-time 5 \
    -X POST "${connect_scheme}://127.0.0.1:${connect_port}/exa.language_server_pb.LanguageServerService/GetUserStatus" \
    -H "X-Codeium-Csrf-Token: $csrf_token" \
    -H "Connect-Protocol-Version: 1" \
    -H "Content-Type: application/json" \
    -d "$request_body")

if [ $? -ne 0 ] || [ -z "$user_status" ]; then
    log_warn "GetUserStatus failed, trying GetCommandModelConfigs..."
    user_status=$(retry_curl -s --insecure --max-time 5 \
        -X POST "${connect_scheme}://127.0.0.1:${connect_port}/exa.language_server_pb.LanguageServerService/GetCommandModelConfigs" \
        -H "X-Codeium-Csrf-Token: $csrf_token" \
        -H "Connect-Protocol-Version: 1" \
        -H "Content-Type: application/json" \
        -d "$request_body")

    if [ $? -ne 0 ] || [ -z "$user_status" ]; then
        error_json "failed to fetch quota from Antigravity server" "server may be restarting; try again"
    fi
fi

# Log raw response for debugging (larger buffer to avoid truncation)
log_info "raw user_status response: $(echo "$user_status" | head -c 5000)"

# ── Parse quota ───────────────────────────────────────────────────────────────

plan_name=$(echo "$user_status" | jq -r '.userStatus.planStatus.planInfo.planName // .userStatus.planName // .planName // "unknown"' 2>/dev/null)

output=$(echo "$user_status" | jq -c --arg plan "$plan_name" '
    # 1. Credit-based detection for Pro plan
    (.userStatus.planStatus.planInfo.monthlyPromptCredits // 0) as $monthly_prompt |
    (.userStatus.planStatus.availablePromptCredits // -1) as $available_prompt |
    (.userStatus.planStatus.planInfo.monthlyFlowCredits // 0) as $monthly_flow |
    (.userStatus.planStatus.availableFlowCredits // -1) as $available_flow |

    # 2. Fractional-based detection (fallback or for Free plan)
    (
        .userStatus.cascadeModelConfigData.clientModelConfigs //
        .cascadeModelConfigData.clientModelConfigs //
        []
    ) as $configs |

    # Calculate percentages
    (
        if ($monthly_prompt > 0 and $available_prompt >= 0) then
            (1 - ($available_prompt / $monthly_prompt))
        else
            ([ $configs[] | select(.modelLabel // "" | test("claude|opus|sonnet"; "i")) | .quotaInfo.remainingFraction // 1.0 ] | min | (1 - .))
        end
    ) as $primary_usage |

    (
        if ($monthly_flow > 0 and $available_flow >= 0) then
            (1 - ($available_flow / $monthly_flow))
        else
            ([ $configs[] | select(.modelLabel // "" | test("pro|flash|gemini"; "i")) | .quotaInfo.remainingFraction // 1.0 ] | min | (1 - .))
        end
    ) as $secondary_usage |

    {
        provider: "antigravity",
        seven_day: (($primary_usage * 100) | floor),
        seven_day_reset: "",
        five_hour: (($secondary_usage * 100) | floor),
        five_hour_reset: "",
        plan: $plan
    }
' 2>/dev/null)

if [ $? -ne 0 ] || [ -z "$output" ]; then
    error_json "failed to parse Antigravity quota response" "server API may have changed; check logs"
fi

# Cache and output
cache_output "$CACHE_FILE" "$output"
