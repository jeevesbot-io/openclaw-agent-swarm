#!/bin/bash
# list-queue.sh - Display queued tasks
# Usage: list-queue.sh [--json]

set -euo pipefail

# --- Configuration ---
SWARM_DIR="$HOME/.openclaw/swarm"
QUEUE_FILE="$SWARM_DIR/queue.json"

# --- Parse arguments ---
OUTPUT_JSON=false
if [ "${1:-}" = "--json" ]; then
  OUTPUT_JSON=true
fi

# --- Check queue exists ---
if [ ! -f "$QUEUE_FILE" ]; then
  if [ "$OUTPUT_JSON" = true ]; then
    echo '{"queue":[],"count":0}'
  else
    echo "Queue is empty (no queue.json)"
  fi
  exit 0
fi

# --- Get queue data ---
QUEUE_COUNT=$(jq -r '.queue | length' "$QUEUE_FILE")

if [ "$OUTPUT_JSON" = true ]; then
  # Output JSON
  jq -r '{queue: .queue, count: (.queue | length)}' "$QUEUE_FILE"
  exit 0
fi

# --- Human-readable output ---
if [ "$QUEUE_COUNT" = "0" ]; then
  echo "Queue is empty"
  exit 0
fi

echo "📋 Queued Tasks ($QUEUE_COUNT)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Sort queue by priority (high > normal > low), then by queuedAt (FIFO)
SORTED_QUEUE=$(jq -r '
  .queue 
  | sort_by(
      (if .priority == "high" then 0 elif .priority == "normal" then 1 else 2 end),
      .queuedAt
    )
  | to_entries[]
  | "\(.key + 1)|\(.value.priority)|\(.value.id)|\(.value.repo)|\(.value.queuedAt)"
' "$QUEUE_FILE")

CURRENT_TIME=$(date +%s)000
POSITION=1

while IFS='|' read -r pos priority task_id repo queued_at; do
  # Calculate age
  AGE_MS=$((CURRENT_TIME - queued_at))
  AGE_MINUTES=$((AGE_MS / 60000))
  
  if [ "$AGE_MINUTES" -lt 60 ]; then
    AGE="${AGE_MINUTES}m ago"
  elif [ "$AGE_MINUTES" -lt 1440 ]; then
    AGE_HOURS=$((AGE_MINUTES / 60))
    AGE="${AGE_HOURS}h ago"
  else
    AGE_DAYS=$((AGE_MINUTES / 1440))
    AGE="${AGE_DAYS}d ago"
  fi
  
  # Format priority
  case "$priority" in
    high)   PRIORITY_BADGE="[HIGH]" ;;
    normal) PRIORITY_BADGE="[NORM]" ;;
    low)    PRIORITY_BADGE="[LOW ]" ;;
    *)      PRIORITY_BADGE="[????]" ;;
  esac
  
  echo "  $POSITION. $PRIORITY_BADGE $task_id ($repo) — queued $AGE"
  POSITION=$((POSITION + 1))
done <<< "$SORTED_QUEUE"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

exit 0
