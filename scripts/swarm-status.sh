#!/bin/bash
# swarm-status.sh — Quick status overview of the agent swarm
# Usage: swarm-status.sh

set -euo pipefail

# --- Configuration ---
SWARM_DIR="$HOME/.openclaw/swarm"
REGISTRY="$SWARM_DIR/active-tasks.json"

# --- Parse registry ---
if [ ! -f "$REGISTRY" ]; then
  echo "ERROR: Registry not found at $REGISTRY"
  exit 1
fi

# Count tasks by status
ACTIVE=$(jq -r '[.tasks[] | select(.status == "running")] | length' "$REGISTRY")
PENDING=$(jq -r '[.tasks[] | select(.status == "pr_created" or .status == "ready_for_review")] | length' "$REGISTRY")
DONE=$(jq -r '[.tasks[] | select(.status == "completed")] | length' "$REGISTRY")
STUCK=$(jq -r '[.tasks[] | select(.status == "stuck")] | length' "$REGISTRY")
FAILED=$(jq -r '[.tasks[] | select(.status == "failed_max_attempts")] | length' "$REGISTRY")
TOTAL=$(jq -r '.tasks | length' "$REGISTRY")

# Get details of pending tasks
PENDING_DETAILS=""
if [ "$PENDING" -gt 0 ]; then
  PENDING_DETAILS=$(jq -r '[.tasks[] | select(.status == "pr_created" or .status == "ready_for_review")] | map("\(.id): \(.status), PR #\(.pr)") | join(", ")' "$REGISTRY")
fi

# Get details of done tasks
DONE_DETAILS=""
if [ "$DONE" -gt 0 ]; then
  DONE_DETAILS=$(jq -r '[.tasks[] | select(.status == "completed")] | map("\(.id): completed") | join(", ")' "$REGISTRY")
fi

# Check when last check happened (look for most recent check-agents log)
LAST_CHECK_FILE=$(ls -t "$SWARM_DIR/logs/check-agents-"*.log 2>/dev/null | head -1 || echo "")
if [ -n "$LAST_CHECK_FILE" ]; then
  LAST_CHECK_TIME=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M:%S" "$LAST_CHECK_FILE" 2>/dev/null || stat -c "%y" "$LAST_CHECK_FILE" 2>/dev/null | cut -d. -f1 || echo "unknown")
  LAST_CHECK_AGO=$(( ($(date +%s) - $(stat -f "%m" "$LAST_CHECK_FILE" 2>/dev/null || stat -c "%Y" "$LAST_CHECK_FILE" 2>/dev/null)) / 60 ))
else
  LAST_CHECK_TIME="never"
  LAST_CHECK_AGO="∞"
fi

# Calculate next check (assuming 10 min interval)
CHECK_INTERVAL=10
if [ "$LAST_CHECK_AGO" = "∞" ]; then
  NEXT_CHECK="unknown"
else
  NEXT_CHECK_MINUTES=$((CHECK_INTERVAL - LAST_CHECK_AGO))
  if [ "$NEXT_CHECK_MINUTES" -lt 0 ]; then
    NEXT_CHECK="overdue by $((0 - NEXT_CHECK_MINUTES)) min"
  else
    NEXT_CHECK="in $NEXT_CHECK_MINUTES min"
  fi
fi

# --- Output ---
echo "🤖 Agent Swarm Status"
echo "━━━━━━━━━━━━━━━━━━━━━━"
echo "Active:  $ACTIVE"

if [ "$PENDING" -gt 0 ] && [ -n "$PENDING_DETAILS" ]; then
  echo "Pending: $PENDING ($PENDING_DETAILS)"
else
  echo "Pending: $PENDING"
fi

if [ "$DONE" -gt 0 ] && [ -n "$DONE_DETAILS" ]; then
  echo "Done:    $DONE ($DONE_DETAILS)"
else
  echo "Done:    $DONE"
fi

if [ "$STUCK" -gt 0 ]; then
  echo "Stuck:   $STUCK ⚠️"
fi

if [ "$FAILED" -gt 0 ]; then
  echo "Failed:  $FAILED ❌"
fi

echo "━━━━━━━━━━━━━━━━━━━━━━"
echo "Last check: $LAST_CHECK_AGO min ago"
echo "Next check: $NEXT_CHECK"

exit 0
