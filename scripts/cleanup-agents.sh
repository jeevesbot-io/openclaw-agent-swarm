#!/bin/bash
# cleanup-agents.sh - Clean up completed worktrees and tmux sessions
# Run manually or via daily cron

set -euo pipefail

# Log script execution
SCRIPT_LOG="$HOME/.openclaw/swarm/logs/cleanup-agents-$(date +%Y%m%d-%H%M%S).log"
mkdir -p "$(dirname "$SCRIPT_LOG")"
exec 1> >(tee -a "$SCRIPT_LOG")
exec 2>&1
echo "=== cleanup-agents.sh started at $(date) ==="

REGISTRY="$HOME/.openclaw/swarm/active-tasks.json"
LOCKDIR="$HOME/.openclaw/swarm/active-tasks.lock.d"
TEMP_REGISTRY=$(mktemp)

# Acquire lock to prevent concurrent modifications (mkdir is atomic)
LOCK_ACQUIRED=false
for i in {1..50}; do
  if mkdir "$LOCKDIR" 2>/dev/null; then
    LOCK_ACQUIRED=true
    break
  fi
  sleep 0.1
done

if [ "$LOCK_ACQUIRED" = false ]; then
  echo "ERROR: Another instance is already running, could not acquire lock after 5s"
  exit 2
fi

# Copy registry
cp "$REGISTRY" "$TEMP_REGISTRY"

echo "Cleaning up completed agents..."

# Find completed tasks (PR merged or explicitly marked complete)
COMPLETED_TASKS=$(jq -r '.tasks[] | select(.status == "completed" or .status == "pr_merged" or .status == "failed_max_attempts") | .id' "$TEMP_REGISTRY")

if [ -z "$COMPLETED_TASKS" ]; then
  echo "No completed tasks to clean up"
  exit 0
fi

for TASK_ID in $COMPLETED_TASKS; do
  echo "  Cleaning up $TASK_ID..."
  
  # Get task details
  TASK=$(jq -r ".tasks[] | select(.id == \"$TASK_ID\")" "$TEMP_REGISTRY")
  TMUX_SESSION=$(echo "$TASK" | jq -r '.tmuxSession')
  WORKTREE=$(echo "$TASK" | jq -r '.worktree')
  REPO=$(echo "$TASK" | jq -r '.repo')
  BRANCH=$(echo "$TASK" | jq -r '.branch')
  
  # Kill tmux session if exists
  if tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
    echo "    Killing tmux session $TMUX_SESSION"
    tmux kill-session -t "$TMUX_SESSION"
  fi
  
  # Remove worktree
  if [ -d "$WORKTREE" ]; then
    echo "    Removing worktree $WORKTREE"
    cd "$HOME/projects/$REPO"
    git worktree remove "$WORKTREE" --force 2>/dev/null || rm -rf "$WORKTREE"
  fi
  
  # Remove branch (remote will be cleaned up by GitHub when PR merged)
  cd "$HOME/projects/$REPO"
  if git show-ref --verify --quiet "refs/heads/$BRANCH"; then
    echo "    Deleting local branch $BRANCH"
    git branch -D "$BRANCH" 2>/dev/null || true
  fi
  
  # Move task to history
  jq ".history += [.tasks[] | select(.id == \"$TASK_ID\")] | .tasks = [.tasks[] | select(.id != \"$TASK_ID\")]" "$TEMP_REGISTRY" > "$TEMP_REGISTRY.new"
  mv "$TEMP_REGISTRY.new" "$TEMP_REGISTRY"
  
  echo "    ✓ Cleaned up $TASK_ID"
done

# Update stats
TOTAL_HISTORY=$(jq -r '.history | length' "$TEMP_REGISTRY")
SUCCESS_COUNT=$(jq -r '[.history[] | select(.status == "completed" or .status == "pr_merged")] | length' "$TEMP_REGISTRY")
SUCCESS_RATE=$(echo "scale=2; $SUCCESS_COUNT / $TOTAL_HISTORY" | bc -l 2>/dev/null || echo "0")

# Calculate average completion time
AVG_TIME=$(jq -r '[.history[] | select(.completedAt != null) | (.completedAt - .startedAt) / 60000] | add / length' "$TEMP_REGISTRY" 2>/dev/null || echo "0")

jq ".stats.totalTasks = $TOTAL_HISTORY | .stats.successRate = $SUCCESS_RATE | .stats.avgCompletionMinutes = $AVG_TIME" "$TEMP_REGISTRY" > "$TEMP_REGISTRY.new"
mv "$TEMP_REGISTRY.new" "$TEMP_REGISTRY"

# Write back
mv "$TEMP_REGISTRY" "$REGISTRY"

# Release lock
rmdir "$LOCKDIR" 2>/dev/null || true

echo ""
echo "Cleanup complete."
echo "  Total tasks processed: $TOTAL_HISTORY"
echo "  Success rate: $(echo "$SUCCESS_RATE * 100" | bc)%"
echo "  Average completion time: ${AVG_TIME} minutes"
