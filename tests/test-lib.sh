#!/bin/bash
# test-lib.sh — Unit tests for lib.sh functions

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

# ── Logging tests ──────────────────────────────────────────────────────────

suite "Logging"

AI_USAGE_PROVIDER="test"
log_info "test message"
assert_file_exists "log file created" "$AI_USAGE_LOG_FILE"

last_line=$(tail -1 "$AI_USAGE_LOG_FILE")
assert_contains "log_info writes INFO level" "$last_line" "[INFO ]"
assert_contains "log_info includes provider" "$last_line" "[test]"
assert_contains "log_info includes message" "$last_line" "test message"

log_warn "warning msg"
last_line=$(tail -1 "$AI_USAGE_LOG_FILE")
assert_contains "log_warn writes WARN level" "$last_line" "[WARN ]"

log_error "error msg"
last_line=$(tail -1 "$AI_USAGE_LOG_FILE")
assert_contains "log_error writes ERROR level" "$last_line" "[ERROR]"

# ── Rotate log tests ──────────────────────────────────────────────────────

suite "Log rotation"

# Fill log beyond max
for i in $(seq 1 1010); do
    echo "line $i" >> "$AI_USAGE_LOG_FILE"
done
lines_before=$(wc -l < "$AI_USAGE_LOG_FILE")
rotate_log
lines_after=$(wc -l < "$AI_USAGE_LOG_FILE")
assert_eq "rotate_log trims oversized log" "1000" "$lines_after"

# ── error_json tests ──────────────────────────────────────────────────────

suite "error_json"

AI_USAGE_PROVIDER="test-provider"
# error_json exits, so run in subshell
output=$(AI_USAGE_PROVIDER="test-provider" bash -c "source '$SCRIPT_DIR/../scripts/lib.sh'; export HOME='$HOME'; error_json 'something broke'" 2>/dev/null)
assert_json_valid "error_json produces valid JSON" "$output"
assert_json_field "error_json sets error message" "$output" ".error" "something broke"
assert_json_field "error_json sets provider" "$output" ".provider" "test-provider"

# ── atomic_write tests ────────────────────────────────────────────────────

suite "atomic_write"

test_file="$TEST_TMPDIR/atomic_test.txt"
atomic_write "$test_file" "hello world"
assert_file_exists "atomic_write creates file" "$test_file"
content=$(cat "$test_file")
assert_eq "atomic_write writes content" "hello world" "$content"

# Overwrite
atomic_write "$test_file" "new content"
content=$(cat "$test_file")
assert_eq "atomic_write overwrites" "new content" "$content"

# Nested directory
nested_file="$TEST_TMPDIR/a/b/c/nested.txt"
atomic_write "$nested_file" "deep"
assert_file_exists "atomic_write creates nested dirs" "$nested_file"

# ── check_cache tests ────────────────────────────────────────────────────

suite "check_cache"

cache_file="$AI_USAGE_CACHE_DIR/test-cache.json"
echo '{"test": true}' > "$cache_file"
# Fresh cache should output and exit
output=$(bash -c "source '$SCRIPT_DIR/../scripts/lib.sh'; export HOME='$HOME'; check_cache '$cache_file'; echo 'NOT_CACHED'" 2>/dev/null)
assert_contains "fresh cache returns content" "$output" '{"test": true}'

# Stale cache: set mtime to 2 minutes ago
touch -d "2 minutes ago" "$cache_file"
output=$(bash -c "source '$SCRIPT_DIR/../scripts/lib.sh'; export HOME='$HOME'; check_cache '$cache_file'; echo 'NOT_CACHED'" 2>/dev/null)
assert_contains "stale cache falls through" "$output" "NOT_CACHED"

# Missing cache
output=$(bash -c "source '$SCRIPT_DIR/../scripts/lib.sh'; export HOME='$HOME'; check_cache '/nonexistent/file'; echo 'NOT_CACHED'" 2>/dev/null)
assert_contains "missing cache falls through" "$output" "NOT_CACHED"

# ── cache_output tests ───────────────────────────────────────────────────

suite "cache_output"

cache_file2="$AI_USAGE_CACHE_DIR/test-output.json"
output=$(cache_output "$cache_file2" '{"cached": 1}')
assert_eq "cache_output prints content" '{"cached": 1}' "$output"
assert_file_exists "cache_output writes file" "$cache_file2"

# ── resolve_libexec_dir tests ────────────────────────────────────────────

suite "resolve_libexec_dir"

# Create fake libexec dir
mkdir -p "$HOME/.local/libexec/ai-usage"
result=$(resolve_libexec_dir)
assert_eq "resolve_libexec_dir finds local libexec" "$HOME/.local/libexec/ai-usage" "$result"

# ── Summary ──────────────────────────────────────────────────────────────

test_summary
