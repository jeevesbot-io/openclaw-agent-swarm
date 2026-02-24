#!/bin/bash
# respawn-agent.sh - Respawn a failed agent with updated context
# Usage: respawn-agent.sh <task-id>

set -euo pipefail

# Log script execution
SCRIPT_LOG="$HOME/.openclaw/swarm/logs/respawn-agent-$(date +%Y%m%d-%H%M%S).log"
mkdir -p "$(dirname "$SCRIPT_LOG")"
exec 1> >(tee -a "$SCRIPT_LOG")
exec 2>&1
echo "=== respawn-agent.sh started at $(date) ==="

TASK_ID=$1
REGISTRY="$HOME/.openclaw/swarm/active-tasks.json"

# Get task details
TASK=$(jq -r ".tasks[] | select(.id == \"$TASK_ID\")" "$REGISTRY")

if [ -z "$TASK" ]; then
  echo "ERROR: Task $TASK_ID not found in registry"
  exit 1
fi

REPO=$(echo "$TASK" | jq -r '.repo')
BRANCH=$(echo "$TASK" | jq -r '.branch')
ORIGINAL_PROMPT=$(echo "$TASK" | jq -r '.prompt')
ATTEMPTS=$(echo "$TASK" | jq -r '.attempts')
TMUX_SESSION=$(echo "$TASK" | jq -r '.tmuxSession')
WORKTREE=$(echo "$TASK" | jq -r '.worktree')
LOG_FILE="$HOME/.openclaw/swarm/logs/${TASK_ID}.log"

echo "Respawning agent for task $TASK_ID (attempt $ATTEMPTS)..."

# Kill existing tmux session if it exists
if tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
  echo "  Killing existing tmux session"
  tmux kill-session -t "$TMUX_SESSION"
fi

# Remove existing worktree if it exists
if [ -d "$WORKTREE" ]; then
  echo "  Removing existing worktree"
  cd "$HOME/projects/$REPO"
  git worktree remove "$WORKTREE" --force 2>/dev/null || rm -rf "$WORKTREE"
  
  # Also delete the branch
  git branch -D "$BRANCH" 2>/dev/null || true
fi

# Check for any error context in the log
if [ -f "$LOG_FILE" ]; then
  echo "  Analyzing previous failure..."
  LAST_ERROR=$(tail -50 "$LOG_FILE" | grep -i "error\|failed\|exception" | tail -5 || echo "")
  
  if [ -n "$LAST_ERROR" ]; then
    echo "  Previous errors found:"
    echo "$LAST_ERROR" | sed 's/^/    /'
  fi
fi

# Create updated prompt with failure context
UPDATED_PROMPT_FILE="$HOME/.openclaw/swarm/prompts/${TASK_ID}-retry-${ATTEMPTS}.txt"
cat > "$UPDATED_PROMPT_FILE" << EOF
RETRY ATTEMPT $ATTEMPTS

Previous attempt failed. Common failure reasons:
- Agent got stuck or ran out of context
- Build/test errors that blocked progress
- Merge conflicts with main branch

Previous prompt:
$ORIGINAL_PROMPT

Additional context for this retry:
- Focus on small, incremental changes
- If you encounter errors, fix them before proceeding
- Create a PR as soon as you have working code
- If stuck for >10 minutes on one problem, document what you tried and create a PR with your progress

Begin implementation:
EOF

# Spawn the agent again
echo "  Spawning new agent..."
"$HOME/.openclaw/swarm/scripts/spawn-agent.sh" "$REPO" "$BRANCH" "$TASK_ID" "$UPDATED_PROMPT_FILE"

# Update registry
TEMP_REGISTRY=$(mktemp)
jq "(.tasks[] | select(.id == \"$TASK_ID\") | .status) = \"running\" | (.tasks[] | select(.id == \"$TASK_ID\") | .needsRespawn) = false | (.tasks[] | select(.id == \"$TASK_ID\") | .lastRespawnAt) = $(date +%s)000" "$REGISTRY" > "$TEMP_REGISTRY"
mv "$TEMP_REGISTRY" "$REGISTRY"

echo "✓ Agent respawned successfully"
