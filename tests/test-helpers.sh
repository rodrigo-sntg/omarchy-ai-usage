#!/bin/bash
# test-helpers.sh — Minimal test framework for bash scripts

TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0
CURRENT_SUITE=""

# Set up isolated test environment
TEST_TMPDIR=$(mktemp -d)
export HOME="$TEST_TMPDIR/home"
mkdir -p "$HOME/.config/ai-usage" "$HOME/.cache/ai-usage/cache" "$HOME/.cache/ai-usage/history"

# Source lib.sh from the project
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$TEST_DIR")"
# shellcheck source=../scripts/lib.sh
source "$PROJECT_DIR/scripts/lib.sh"

suite() {
    CURRENT_SUITE="$1"
    printf '\n\033[1m%s\033[0m\n' "$CURRENT_SUITE"
}

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    TESTS_TOTAL=$(( TESTS_TOTAL + 1 ))
    if [ "$expected" = "$actual" ]; then
        TESTS_PASSED=$(( TESTS_PASSED + 1 ))
        printf '  \033[32m✓\033[0m %s\n' "$desc"
    else
        TESTS_FAILED=$(( TESTS_FAILED + 1 ))
        printf '  \033[31m✗\033[0m %s\n' "$desc"
        printf '    expected: %s\n' "$expected"
        printf '    actual:   %s\n' "$actual"
    fi
}

assert_contains() {
    local desc="$1" haystack="$2" needle="$3"
    TESTS_TOTAL=$(( TESTS_TOTAL + 1 ))
    if echo "$haystack" | grep -qF "$needle"; then
        TESTS_PASSED=$(( TESTS_PASSED + 1 ))
        printf '  \033[32m✓\033[0m %s\n' "$desc"
    else
        TESTS_FAILED=$(( TESTS_FAILED + 1 ))
        printf '  \033[31m✗\033[0m %s\n' "$desc"
        printf '    expected to contain: %s\n' "$needle"
        printf '    actual: %s\n' "$haystack"
    fi
}

assert_file_exists() {
    local desc="$1" file="$2"
    TESTS_TOTAL=$(( TESTS_TOTAL + 1 ))
    if [ -f "$file" ]; then
        TESTS_PASSED=$(( TESTS_PASSED + 1 ))
        printf '  \033[32m✓\033[0m %s\n' "$desc"
    else
        TESTS_FAILED=$(( TESTS_FAILED + 1 ))
        printf '  \033[31m✗\033[0m %s\n' "$desc"
        printf '    file not found: %s\n' "$file"
    fi
}

assert_exit_code() {
    local desc="$1" expected="$2"
    shift 2
    TESTS_TOTAL=$(( TESTS_TOTAL + 1 ))
    "$@" >/dev/null 2>&1
    local actual=$?
    if [ "$expected" -eq "$actual" ]; then
        TESTS_PASSED=$(( TESTS_PASSED + 1 ))
        printf '  \033[32m✓\033[0m %s\n' "$desc"
    else
        TESTS_FAILED=$(( TESTS_FAILED + 1 ))
        printf '  \033[31m✗\033[0m %s\n' "$desc"
        printf '    expected exit code: %s\n' "$expected"
        printf '    actual exit code:   %s\n' "$actual"
    fi
}

assert_json_valid() {
    local desc="$1" json="$2"
    TESTS_TOTAL=$(( TESTS_TOTAL + 1 ))
    if echo "$json" | jq . >/dev/null 2>&1; then
        TESTS_PASSED=$(( TESTS_PASSED + 1 ))
        printf '  \033[32m✓\033[0m %s\n' "$desc"
    else
        TESTS_FAILED=$(( TESTS_FAILED + 1 ))
        printf '  \033[31m✗\033[0m %s\n' "$desc"
        printf '    invalid JSON: %s\n' "$json"
    fi
}

assert_json_field() {
    local desc="$1" json="$2" field="$3" expected="$4"
    TESTS_TOTAL=$(( TESTS_TOTAL + 1 ))
    local actual
    actual=$(echo "$json" | jq -r "$field" 2>/dev/null)
    if [ "$expected" = "$actual" ]; then
        TESTS_PASSED=$(( TESTS_PASSED + 1 ))
        printf '  \033[32m✓\033[0m %s\n' "$desc"
    else
        TESTS_FAILED=$(( TESTS_FAILED + 1 ))
        printf '  \033[31m✗\033[0m %s\n' "$desc"
        printf '    field %s expected: %s\n' "$field" "$expected"
        printf '    actual: %s\n' "$actual"
    fi
}

test_summary() {
    echo ""
    printf '\033[1m─── Results ───\033[0m\n'
    printf 'Total: %d  Passed: \033[32m%d\033[0m  Failed: \033[31m%d\033[0m\n' "$TESTS_TOTAL" "$TESTS_PASSED" "$TESTS_FAILED"

    # Cleanup
    rm -rf "$TEST_TMPDIR"

    [ "$TESTS_FAILED" -eq 0 ]
}
