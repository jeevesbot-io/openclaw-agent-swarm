#!/bin/bash
# test-scanners.sh - Test proactive work detection scanners
# Usage: test-scanners.sh [--repo repo-name]

set -euo pipefail

SWARM_DIR="$HOME/.openclaw/swarm"
SCRIPTS_DIR="$SWARM_DIR/scripts"

echo "🧪 Testing Proactive Work Detection Scanners"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Parse arguments
TEST_REPO="sports-dashboard"
if [ "${1:-}" = "--repo" ]; then
  TEST_REPO=$2
fi

# --- Test 1: scan-issues.sh ---
echo "1️⃣  Testing scan-issues.sh --repo $TEST_REPO"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
"$SCRIPTS_DIR/scan-issues.sh" --repo "$TEST_REPO" --limit 5
EXIT_CODE=$?
if [ $EXIT_CODE -eq 0 ]; then
  echo "✅ scan-issues.sh passed"
else
  echo "❌ scan-issues.sh failed with exit code $EXIT_CODE"
fi
echo ""

# --- Test 2: scan-deps.sh ---
echo "2️⃣  Testing scan-deps.sh --repo $TEST_REPO"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
"$SCRIPTS_DIR/scan-deps.sh" --repo "$TEST_REPO"
EXIT_CODE=$?
if [ $EXIT_CODE -eq 0 ]; then
  echo "✅ scan-deps.sh passed"
else
  echo "❌ scan-deps.sh failed with exit code $EXIT_CODE"
fi
echo ""

# --- Test 3: scan-todos.sh ---
echo "3️⃣  Testing scan-todos.sh --repo $TEST_REPO"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
"$SCRIPTS_DIR/scan-todos.sh" --repo "$TEST_REPO"
EXIT_CODE=$?
if [ $EXIT_CODE -eq 0 ]; then
  echo "✅ scan-todos.sh passed"
else
  echo "❌ scan-todos.sh failed with exit code $EXIT_CODE"
fi
echo ""

# --- Test 4: scan-all.sh ---
echo "4️⃣  Testing scan-all.sh"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
"$SCRIPTS_DIR/scan-all.sh"
EXIT_CODE=$?
if [ $EXIT_CODE -eq 0 ]; then
  echo "✅ scan-all.sh passed"
else
  echo "❌ scan-all.sh failed with exit code $EXIT_CODE"
fi
echo ""

# --- Test 5: Verify output files ---
echo "5️⃣  Verifying output files"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

PASS_COUNT=0
FAIL_COUNT=0

# Check suggestions directory
if [ -d "$SWARM_DIR/suggestions" ]; then
  echo "✅ suggestions/ directory exists"
  PASS_COUNT=$((PASS_COUNT + 1))
else
  echo "❌ suggestions/ directory missing"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# Check state directory
if [ -d "$SWARM_DIR/state" ]; then
  echo "✅ state/ directory exists"
  PASS_COUNT=$((PASS_COUNT + 1))
else
  echo "❌ state/ directory missing"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# Check issues.json
if [ -f "$SWARM_DIR/suggestions/issues.json" ]; then
  if jq '.' "$SWARM_DIR/suggestions/issues.json" >/dev/null 2>&1; then
    echo "✅ suggestions/issues.json is valid JSON"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "❌ suggestions/issues.json is invalid JSON"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
else
  echo "❌ suggestions/issues.json missing"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# Check deps.json
if [ -f "$SWARM_DIR/suggestions/deps.json" ]; then
  if jq '.' "$SWARM_DIR/suggestions/deps.json" >/dev/null 2>&1; then
    echo "✅ suggestions/deps.json is valid JSON"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "❌ suggestions/deps.json is invalid JSON"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
else
  echo "❌ suggestions/deps.json missing"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# Check todos.json
if [ -f "$SWARM_DIR/suggestions/todos.json" ]; then
  if jq '.' "$SWARM_DIR/suggestions/todos.json" >/dev/null 2>&1; then
    echo "✅ suggestions/todos.json is valid JSON"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "❌ suggestions/todos.json is invalid JSON"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
else
  echo "❌ suggestions/todos.json missing"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# Check scanned-issues.json
if [ -f "$SWARM_DIR/state/scanned-issues.json" ]; then
  if jq '.' "$SWARM_DIR/state/scanned-issues.json" >/dev/null 2>&1; then
    echo "✅ state/scanned-issues.json is valid JSON"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "❌ state/scanned-issues.json is invalid JSON"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
else
  echo "❌ state/scanned-issues.json missing"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# Check scanned-deps.json
if [ -f "$SWARM_DIR/state/scanned-deps.json" ]; then
  if jq '.' "$SWARM_DIR/state/scanned-deps.json" >/dev/null 2>&1; then
    echo "✅ state/scanned-deps.json is valid JSON"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "❌ state/scanned-deps.json is invalid JSON"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
else
  echo "❌ state/scanned-deps.json missing"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test Results: $PASS_COUNT passed, $FAIL_COUNT failed"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ $FAIL_COUNT -eq 0 ]; then
  echo "✅ All tests passed!"
  exit 0
else
  echo "❌ Some tests failed"
  exit 1
fi
