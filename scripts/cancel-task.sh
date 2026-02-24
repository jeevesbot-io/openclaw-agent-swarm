#!/bin/bash
# cancel-task.sh - Cancel a queued or running task
# Usage: cancel-task.sh <task-id> [--force]

set -euo pipefail

# --- Configuration ---
SWARM_DIR="$HOME/.openclaw/swarm"
QUEUE_FILE="$SWARM_DIR/queue.json"
REGISTRY="$SWARM_DIR/active-tasks.json"
QUEUE_LOCK="$SWARM_DIR/queue.lock.d"
REGISTRY_LOCK="$SWARM_DIR/active-tasks.lock.d"
SCRIPTS_DIR="$SWARM_DIR/scripts"

# --- Logging ---
LOG_FILE="$SWARM_DIR/logs/cancel-task-$(date +%Y%m%d-%H%M%S).log"
mkdir -p "$(dirname "$LOG_FILE")"
exec 1> >(tee -a "$LOG_FILE")
exec 2>&1

log() { echo "[$(date +%H:%M:%S)] $*"; }

# --- Parse arguments ---
if [ $# -lt 1 ]; then
  echo "Usage: $0 <task-id> [--force]"
  exit 1
fi

TASK_ID=$1
FORCE=false

if [ "${2:-}" = "--force" ]; then
  FORCE=true
fi

log "=== Cancel Task: $TASK_ID ==="

# --- Check if task is in queue ---
if [ -f "$QUEUE_FILE" ]; then
  IN_QUEUE=$(jq -r --arg id "$TASK_ID" '.queue[] | select(.id == $id) | .id' "$QUEUE_FILE")
  
  if [ -n "$IN_QUEUE" ]; then
    log "Task found in queue"
    
    # Ask for confirmation unless --force
    if [ "$FORCE" = false ]; then
      echo -n "Remove task from queue? [y/N] "
      read -r CONFIRM
      if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        echo "Cancelled"
        exit 0
      fi
    fi
    
    # Acquire queue lock
    LOCK_ACQUIRED=false
    for i in {1..50}; do
      if mkdir "$QUEUE_LOCK" 2>/dev/null; then
        LOCK_ACQUIRED=true
        break
      fi
      sleep 0.1
    done
    
    if [ "$LOCK_ACQUIRED" = false ]; then
      echo "ERROR: Could not acquire queue lock after 5s"
      exit 1
    fi
    
    trap "rmdir '$QUEUE_LOCK' 2>/dev/null || true" EXIT
    
    # Remove from queue
    TEMP_QUEUE=$(mktemp)
    jq --arg id "$TASK_ID" '.queue |= map(select(.id != $id))' "$QUEUE_FILE" > "$TEMP_QUEUE"
    mv "$TEMP_QUEUE" "$QUEUE_FILE"
    
    log "✓ Task removed from queue"
    exit 0
  fi
fi

# --- Check if task is in active registry ---
if [ ! -f "$REGISTRY" ]; then
  echo "ERROR: Task not found in queue or registry"
  exit 1
fi

TASK=$(jq -r --arg id "$TASK_ID" '.tasks[] | select(.id == $id)' "$REGISTRY")

if [ -z "$TASK" ] || [ "$TASK" = "null" ]; then
  echo "ERROR: Task not found in queue or registry"
  exit 1
fi

log "Task found in active registry"

# Extract task details
TMUX_SESSION=$(echo "$TASK" | jq -r '.tmuxSession')
WORKTREE=$(echo "$TASK" | jq -r '.worktree')
STATUS=$(echo "$TASK" | jq -r '.status')

log "  Status:  $STATUS"
log "  Session: $TMUX_SESSION"
log "  Worktree: $WORKTREE"

# Ask for confirmation unless --force
if [ "$FORCE" = false ]; then
  echo -n "Kill running agent and cleanup? [y/N] "
  read -r CONFIRM
  if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "Cancelled"
    exit 0
  fi
fi

# --- Kill tmux session if running ---
if tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
  log "Killing tmux session: $TMUX_SESSION"
  tmux kill-session -t "$TMUX_SESSION" || true
  log "✓ Session killed"
else
  log "⚠️  Tmux session not found (may have already exited)"
fi

# --- Run cleanup-agents.sh for this task ---
if [ -f "$SCRIPTS_DIR/cleanup-agents.sh" ]; then
  log "Running cleanup for $TASK_ID..."
  "$SCRIPTS_DIR/cleanup-agents.sh" "$TASK_ID" || {
    log "⚠️  Cleanup script failed, continuing..."
  }
else
  log "⚠️  cleanup-agents.sh not found, skipping cleanup"
fi

# --- Move task to history with cancelled status ---
log "Updating registry..."

# Acquire registry lock
LOCK_ACQUIRED=false
for i in {1..50}; do
  if mkdir "$REGISTRY_LOCK" 2>/dev/null; then
    LOCK_ACQUIRED=true
    break
  fi
  sleep 0.1
done

if [ "$LOCK_ACQUIRED" = false ]; then
  echo "ERROR: Could not acquire registry lock after 5s"
  exit 1
fi

trap "rmdir '$REGISTRY_LOCK' 2>/dev/null || true" EXIT

# Update registry: remove from tasks, add to history with cancelled status
TEMP_REGISTRY=$(mktemp)
jq --arg id "$TASK_ID" \
   --argjson cancelledAt "$(date +%s)000" \
   '(.tasks[] | select(.id == $id) | .status) = "cancelled" |
    (.tasks[] | select(.id == $id) | .cancelledAt) = $cancelledAt |
    .history += [.tasks[] | select(.id == $id)] |
    .tasks |= map(select(.id != $id))' "$REGISTRY" > "$TEMP_REGISTRY"

if [ $? -eq 0 ]; then
  mv "$TEMP_REGISTRY" "$REGISTRY"
  log "✓ Task moved to history with status 'cancelled'"
else
  echo "ERROR: Failed to update registry"
  rm -f "$TEMP_REGISTRY"
  exit 1
fi

log "✓ Task cancelled successfully"
exit 0
