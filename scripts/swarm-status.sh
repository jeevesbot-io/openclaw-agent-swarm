#!/bin/bash
# swarm-status.sh — Quick status overview of the agent swarm
# Usage: swarm-status.sh

set -euo pipefail

# --- Configuration ---
SWARM_DIR="$HOME/.openclaw/swarm"
REGISTRY="$SWARM_DIR/active-tasks.json"
QUEUE_FILE="$SWARM_DIR/queue.json"

# --- Parse registry ---
if [ ! -f "$REGISTRY" ]; then
  echo "ERROR: Registry not found at $REGISTRY"
  exit 1
fi

# Get max parallel agents from config
MAX_PARALLEL=$(jq -r '.config.maxParallelAgents // 2' "$REGISTRY")

# Count tasks by status
ACTIVE=$(jq -r '[.tasks[] | select(.status == "running" or .status == "spawned")] | length' "$REGISTRY")
PENDING=$(jq -r '[.tasks[] | select(.status == "pr_created" or .status == "ready_for_review")] | length' "$REGISTRY")
DONE=$(jq -r '[.tasks[] | select(.status == "completed")] | length' "$REGISTRY")
STUCK=$(jq -r '[.tasks[] | select(.status == "stuck")] | length' "$REGISTRY")
FAILED=$(jq -r '[.tasks[] | select(.status == "failed_max_attempts")] | length' "$REGISTRY")
TOTAL=$(jq -r '.tasks | length' "$REGISTRY")

# Count queued tasks
QUEUE_COUNT=0
QUEUE_HIGH=0
QUEUE_NORMAL=0
QUEUE_LOW=0
if [ -f "$QUEUE_FILE" ]; then
  QUEUE_COUNT=$(jq -r '.queue | length' "$QUEUE_FILE")
  QUEUE_HIGH=$(jq -r '[.queue[] | select(.priority == "high")] | length' "$QUEUE_FILE")
  QUEUE_NORMAL=$(jq -r '[.queue[] | select(.priority == "normal")] | length' "$QUEUE_FILE")
  QUEUE_LOW=$(jq -r '[.queue[] | select(.priority == "low")] | length' "$QUEUE_FILE")
fi

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
echo "Active:  $ACTIVE/$MAX_PARALLEL slots"

# Build queue summary
if [ "$QUEUE_COUNT" -gt 0 ]; then
  QUEUE_SUMMARY=""
  if [ "$QUEUE_HIGH" -gt 0 ]; then
    QUEUE_SUMMARY="${QUEUE_SUMMARY}$QUEUE_HIGH high"
  fi
  if [ "$QUEUE_NORMAL" -gt 0 ]; then
    if [ -n "$QUEUE_SUMMARY" ]; then
      QUEUE_SUMMARY="${QUEUE_SUMMARY}, "
    fi
    QUEUE_SUMMARY="${QUEUE_SUMMARY}$QUEUE_NORMAL normal"
  fi
  if [ "$QUEUE_LOW" -gt 0 ]; then
    if [ -n "$QUEUE_SUMMARY" ]; then
      QUEUE_SUMMARY="${QUEUE_SUMMARY}, "
    fi
    QUEUE_SUMMARY="${QUEUE_SUMMARY}$QUEUE_LOW low"
  fi
  echo "Queued:  $QUEUE_COUNT ($QUEUE_SUMMARY)"
else
  echo "Queued:  0"
fi

# Count done today
TODAY=$(date +%Y-%m-%d)
DONE_TODAY=$(jq -r --arg today "$TODAY" '[.history[] | select(.status == "completed") | select(.completedAt / 1000 | strftime("%Y-%m-%d") == $today)] | length' "$REGISTRY" 2>/dev/null || echo "0")
echo "Done:    $DONE_TODAY today"

if [ "$FAILED" -gt 0 ]; then
  echo "Failed:  $FAILED ❌"
fi

# Show queue details if any
if [ "$QUEUE_COUNT" -gt 0 ]; then
  echo "━━━━━━━━━━━━━━━━━━━━━━"
  echo "Queue:"
  
  # Get sorted queue (priority then FIFO)
  QUEUE_DETAILS=$(jq -r '
    .queue 
    | sort_by(
        (if .priority == "high" then 0 elif .priority == "normal" then 1 else 2 end),
        .queuedAt
      )
    | to_entries[]
    | "\(.key + 1)|\(.value.priority)|\(.value.id)|\(.value.repo)|\(.value.queuedAt)"
  ' "$QUEUE_FILE" 2>/dev/null || echo "")
  
  if [ -n "$QUEUE_DETAILS" ]; then
    CURRENT_TIME=$(date +%s)000
    POSITION=1
    
    # Show up to 5 queued tasks
    echo "$QUEUE_DETAILS" | head -5 | while IFS='|' read -r pos priority task_id repo queued_at; do
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
    done
    
    if [ "$QUEUE_COUNT" -gt 5 ]; then
      echo "  ... and $((QUEUE_COUNT - 5)) more"
    fi
  fi
fi

echo "━━━━━━━━━━━━━━━━━━━━━━"
echo "Last check: $LAST_CHECK_AGO min ago"

exit 0
