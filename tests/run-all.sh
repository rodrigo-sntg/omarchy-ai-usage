#!/bin/bash
# run-all.sh — Run all test suites

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo ""
echo "  Running omarchy-ai-usage test suite"
echo "  ════════════════════════════════════"

failed=0

for test_file in "$SCRIPT_DIR"/test-*.sh; do
    [ -f "$test_file" ] || continue
    name=$(basename "$test_file" .sh)
    [ "$name" = "test-helpers" ] && continue

    echo ""
    echo "  ── $name ──"
    if bash "$test_file"; then
        : # passed
    else
        failed=$(( failed + 1 ))
    fi
done

echo ""
if [ "$failed" -eq 0 ]; then
    printf '\033[32m  All test suites passed ✓\033[0m\n'
else
    printf '\033[31m  %d test suite(s) failed\033[0m\n' "$failed"
fi
echo ""

exit "$failed"
