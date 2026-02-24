#!/bin/bash
# dispatch.sh - Queue dispatcher (spawns agents from queue when slots available)
# Usage: dispatch.sh [--dry-run]

set -euo pipefail

# --- Configuration ---
SWARM_DIR="$HOME/.openclaw/swarm"
QUEUE_FILE="$SWARM_DIR/queue.json"
REGISTRY="$SWARM_DIR/active-tasks.json"
QUEUE_LOCK="$SWARM_DIR/queue.lock.d"
REGISTRY_LOCK="$SWARM_DIR/active-tasks.lock.d"
SCRIPTS_DIR="$SWARM_DIR/scripts"

# --- Logging ---
LOG_FILE="$SWARM_DIR/logs/dispatch-$(date +%Y%m%d-%H%M%S).log"
mkdir -p "$(dirname "$LOG_FILE")"
exec 1> >(tee -a "$LOG_FILE")
exec 2>&1

log() { echo "[$(date +%H:%M:%S)] $*"; }

# --- Dry-run mode ---
DRY_RUN=false
if [ "${1:-}" = "--dry-run" ]; then
  DRY_RUN=true
  log "DRY RUN MODE - No actual actions will be taken"
fi

log "=== Dispatch Started ==="

# --- Error handling ---
trap 'log "ERROR: Dispatch failed at line $LINENO"; exit 1' ERR

# --- Check if queue exists ---
if [ ! -f "$QUEUE_FILE" ]; then
  log "No queue file found, nothing to dispatch"
  exit 0
fi

# --- Check if registry exists ---
if [ ! -f "$REGISTRY" ]; then
  log "ERROR: Registry not found at $REGISTRY"
  exit 1
fi

# --- Read config from registry ---
MAX_PARALLEL=$(jq -r '.config.maxParallelAgents // 2' "$REGISTRY")
log "Max parallel agents: $MAX_PARALLEL"

# --- Count currently active agents ---
ACTIVE_COUNT=$(jq -r '[.tasks[] | select(.status == "running" or .status == "spawned")] | length' "$REGISTRY")
log "Currently active agents: $ACTIVE_COUNT"

# --- Check available slots ---
AVAILABLE_SLOTS=$((MAX_PARALLEL - ACTIVE_COUNT))
log "Available slots: $AVAILABLE_SLOTS"

if [ "$AVAILABLE_SLOTS" -le 0 ]; then
  QUEUE_COUNT=$(jq -r '.queue | length' "$QUEUE_FILE")
  log "Queue has $QUEUE_COUNT task(s) waiting, all agent slots full"
  exit 0
fi

# --- Check system resources (RAM) ---
log "Checking system memory..."

# Get total RAM in bytes (use full path for sysctl on macOS)
if [ -f /usr/sbin/sysctl ]; then
  TOTAL_RAM=$(/usr/sbin/sysctl -n hw.memsize)
  TOTAL_RAM_GB=$(echo "scale=2; $TOTAL_RAM / 1073741824" | bc)
  log "Total RAM: ${TOTAL_RAM_GB}GB"
else
  log "⚠️  sysctl not found, skipping RAM check"
fi

# Check memory pressure (macOS specific)
if command -v memory_pressure &> /dev/null; then
  MEMORY_PRESSURE=$(memory_pressure 2>/dev/null | grep -o 'System-wide memory free percentage: [0-9]*' | awk '{print $5}' || echo "unknown")
  
  if [ "$MEMORY_PRESSURE" != "unknown" ]; then
    log "Memory free: ${MEMORY_PRESSURE}%"
    
    # If less than 10% free, consider it critical
    if [ "$MEMORY_PRESSURE" -lt 10 ]; then
      log "⚠️  CRITICAL memory pressure (${MEMORY_PRESSURE}% free), skipping dispatch"
      exit 0
    elif [ "$MEMORY_PRESSURE" -lt 20 ]; then
      log "⚠️  WARNING: Low memory (${MEMORY_PRESSURE}% free), limiting to 1 spawn"
      AVAILABLE_SLOTS=1
    fi
  else
    log "⚠️  Could not determine memory pressure, proceeding cautiously"
  fi
else
  log "⚠️  memory_pressure not available, skipping memory check"
fi

# --- Acquire locks (queue and registry) ---
log "Acquiring locks..."

# Try to acquire both locks
QUEUE_LOCK_ACQUIRED=false
REGISTRY_LOCK_ACQUIRED=false

for i in {1..50}; do
  if mkdir "$QUEUE_LOCK" 2>/dev/null; then
    QUEUE_LOCK_ACQUIRED=true
    break
  fi
  sleep 0.1
done

if [ "$QUEUE_LOCK_ACQUIRED" = false ]; then
  log "ERROR: Could not acquire queue lock after 5s"
  exit 1
fi

for i in {1..50}; do
  if mkdir "$REGISTRY_LOCK" 2>/dev/null; then
    REGISTRY_LOCK_ACQUIRED=true
    break
  fi
  sleep 0.1
done

if [ "$REGISTRY_LOCK_ACQUIRED" = false ]; then
  log "ERROR: Could not acquire registry lock after 5s"
  rmdir "$QUEUE_LOCK"
  exit 1
fi

# Ensure locks are released on exit
trap "rmdir '$QUEUE_LOCK' '$REGISTRY_LOCK' 2>/dev/null || true" EXIT

log "✓ Locks acquired"

# --- Process queue ---
SPAWNED_COUNT=0

while [ "$SPAWNED_COUNT" -lt "$AVAILABLE_SLOTS" ]; do
  # Get highest priority task from queue
  # Priority: high > normal > low, then FIFO within same priority
  NEXT_TASK=$(jq -r '
    .queue 
    | sort_by(
        (if .priority == "high" then 0 elif .priority == "normal" then 1 else 2 end),
        .queuedAt
      )
    | .[0] // empty
  ' "$QUEUE_FILE")
  
  if [ -z "$NEXT_TASK" ] || [ "$NEXT_TASK" = "null" ]; then
    log "Queue is empty, stopping dispatch"
    break
  fi
  
  # Extract task details
  TASK_ID=$(echo "$NEXT_TASK" | jq -r '.id')
  REPO=$(echo "$NEXT_TASK" | jq -r '.repo')
  BRANCH=$(echo "$NEXT_TASK" | jq -r '.branch')
  PROMPT=$(echo "$NEXT_TASK" | jq -r '.prompt')
  PRIORITY=$(echo "$NEXT_TASK" | jq -r '.priority')
  
  log "Dispatching task: $TASK_ID (priority: $PRIORITY)"
  log "  Repo:   $REPO"
  log "  Branch: $BRANCH"
  log "  Prompt: $PROMPT"
  
  if [ "$DRY_RUN" = true ]; then
    log "[DRY-RUN] Would spawn: $SCRIPTS_DIR/spawn-agent.sh $REPO $BRANCH $TASK_ID $PROMPT"
  else
    # Spawn the agent
    if "$SCRIPTS_DIR/spawn-agent.sh" "$REPO" "$BRANCH" "$TASK_ID" "$PROMPT" >> "$LOG_FILE" 2>&1; then
      log "✓ Agent spawned successfully"
    else
      log "✗ Failed to spawn agent for $TASK_ID"
      log "  Leaving task in queue — will retry on next dispatch cycle"
      # CRITICAL: break, don't continue — otherwise we retry the same task infinitely
      break
    fi
  fi
  
  # Remove task from queue (skip in dry-run)
  if [ "$DRY_RUN" = false ]; then
    TEMP_QUEUE=$(mktemp)
    jq --arg id "$TASK_ID" '.queue |= map(select(.id != $id))' "$QUEUE_FILE" > "$TEMP_QUEUE"
    mv "$TEMP_QUEUE" "$QUEUE_FILE"
    log "✓ Task removed from queue"
  else
    log "[DRY-RUN] Would remove task from queue"
  fi
  
  SPAWNED_COUNT=$((SPAWNED_COUNT + 1))
  
  # Small delay between spawns to avoid overwhelming the system
  if [ "$SPAWNED_COUNT" -lt "$AVAILABLE_SLOTS" ]; then
    sleep 2
  fi
done

log "=== Dispatch Complete ==="
log "Spawned $SPAWNED_COUNT agent(s)"

exit 0
