#!/bin/bash
# spawn-agent.sh - Spawn a Claude Code agent in a git worktree
# Usage: spawn-agent.sh <repo> <branch> <task-id> <prompt-file>

set -euo pipefail

# Log script execution
SCRIPT_LOG="$HOME/.openclaw/swarm/logs/spawn-agent-$(date +%Y%m%d-%H%M%S).log"
mkdir -p "$(dirname "$SCRIPT_LOG")"
exec 1> >(tee -a "$SCRIPT_LOG")
exec 2>&1
echo "=== spawn-agent.sh started at $(date) ==="

REPO=$1
BRANCH=$2
TASK_ID=$3
PROMPT_FILE=$4

# Configuration
REPO_DIR="$HOME/projects/$REPO"
WORKTREE_BASE="$HOME/projects/${REPO}-worktrees"
WORKTREE_DIR="$WORKTREE_BASE/$BRANCH"
TMUX_SESSION="swarm-$TASK_ID"
LOG_FILE="$HOME/.openclaw/swarm/logs/${TASK_ID}.log"
WORKTREE_CREATED=false
BRANCH_CREATED=false
TMUX_CREATED=false

# Cleanup function for errors
cleanup_on_error() {
  echo ""
  echo "ERROR: Spawn failed, cleaning up..."
  
  if [ "$TMUX_CREATED" = true ]; then
    tmux kill-session -t "$TMUX_SESSION" 2>/dev/null || true
    echo "  Killed tmux session: $TMUX_SESSION"
  fi
  
  if [ "$WORKTREE_CREATED" = true ]; then
    cd "$REPO_DIR"
    git worktree remove "$WORKTREE_DIR" --force 2>/dev/null || rm -rf "$WORKTREE_DIR"
    echo "  Removed worktree: $WORKTREE_DIR"
  fi
  
  if [ "$BRANCH_CREATED" = true ]; then
    cd "$REPO_DIR"
    git branch -D "$BRANCH" 2>/dev/null || true
    echo "  Deleted branch: $BRANCH"
  fi
  
  echo "Cleanup complete."
  exit 1
}

# Set trap to cleanup on error
trap cleanup_on_error ERR

# Validate inputs
if [ ! -d "$REPO_DIR/.git" ]; then
  echo "ERROR: $REPO_DIR is not a git repository"
  exit 1
fi

# Resolve prompt file path (may be relative to swarm dir)
if [ ! -f "$PROMPT_FILE" ]; then
  # Try resolving relative to swarm directory
  if [ -f "$HOME/.openclaw/swarm/$PROMPT_FILE" ]; then
    PROMPT_FILE="$HOME/.openclaw/swarm/$PROMPT_FILE"
  else
    echo "ERROR: Prompt file $PROMPT_FILE does not exist"
    exit 1
  fi
fi

# Check if session already exists
if tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
  echo "ERROR: tmux session $TMUX_SESSION already exists"
  exit 1
fi

# Clean up stale worktree/branch if they exist (from previous failed runs)
cd "$REPO_DIR"
if [ -d "$WORKTREE_DIR" ]; then
  echo "⚠️  Cleaning up stale worktree at $WORKTREE_DIR"
  git worktree remove "$WORKTREE_DIR" --force 2>/dev/null || rm -rf "$WORKTREE_DIR"
fi

if git show-ref --verify --quiet "refs/heads/$BRANCH"; then
  echo "⚠️  Cleaning up stale branch $BRANCH"
  git branch -D "$BRANCH" 2>/dev/null || true
fi

# Check available disk space (need at least 1GB)
mkdir -p "$WORKTREE_BASE"
AVAILABLE_KB=$(df -k "$WORKTREE_BASE" | tail -1 | awk '{print $4}')
AVAILABLE_GB=$(echo "scale=2; $AVAILABLE_KB / 1048576" | bc)

if [ "$AVAILABLE_KB" -lt 1048576 ]; then
  echo "ERROR: Low disk space (${AVAILABLE_GB}GB available, need at least 1GB)"
  echo "  Free up space before spawning agents"
  exit 1
fi
echo "Disk space available: ${AVAILABLE_GB}GB"

# Create log directory
mkdir -p "$(dirname "$LOG_FILE")"

# Detect default branch
cd "$REPO_DIR"
DEFAULT_BRANCH=""

# Try symbolic-ref first
DEFAULT_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || echo "")

# Fallback: try gh CLI
if [ -z "$DEFAULT_BRANCH" ]; then
  DEFAULT_BRANCH=$(gh repo view --json defaultBranchRef --jq .defaultBranchRef.name 2>/dev/null || echo "")
fi

# Fallback: check common branch names
if [ -z "$DEFAULT_BRANCH" ]; then
  for branch in main master dev develop; do
    if git show-ref --verify --quiet "refs/remotes/origin/$branch"; then
      DEFAULT_BRANCH="$branch"
      break
    fi
  done
fi

# Final check
if [ -z "$DEFAULT_BRANCH" ]; then
  echo "ERROR: Could not detect default branch"
  exit 1
fi

echo "Creating worktree from $DEFAULT_BRANCH..."
git worktree add "$WORKTREE_DIR" -b "$BRANCH" "origin/$DEFAULT_BRANCH" 2>&1 | tee -a "$LOG_FILE"
WORKTREE_CREATED=true
BRANCH_CREATED=true

# Navigate to worktree
cd "$WORKTREE_DIR"

# Install dependencies if package.json exists
if [ -f "package.json" ]; then
  echo "Installing dependencies..."
  if command -v pnpm &> /dev/null; then
    pnpm install --frozen-lockfile 2>&1 | tee -a "$LOG_FILE"
  elif [ -f "pnpm-lock.yaml" ]; then
    echo "WARNING: pnpm-lock.yaml exists but pnpm not found, using npm"
    npm ci 2>&1 | tee -a "$LOG_FILE"
  else
    npm ci 2>&1 | tee -a "$LOG_FILE"
  fi
fi

# Python projects - install dependencies if requirements.txt exists
VENV_PATH=""
if [ -f "requirements.txt" ]; then
  echo "Installing Python dependencies..."
  if [ -f ".venv/bin/activate" ]; then
    VENV_PATH=".venv/bin/activate"
    source .venv/bin/activate
  elif [ -f "venv/bin/activate" ]; then
    VENV_PATH="venv/bin/activate"
    source venv/bin/activate
  else
    python3 -m venv .venv
    VENV_PATH=".venv/bin/activate"
    source .venv/bin/activate
  fi
  pip install -r requirements.txt 2>&1 | tee -a "$LOG_FILE"
fi

# Read prompt file
PROMPT_SIZE=$(wc -c < "$PROMPT_FILE")
echo "Prompt size: $PROMPT_SIZE bytes"

# Always use file-based approach for reliability
# Inline prompt breaks with single quotes, backticks, and special chars
echo "Copying prompt to worktree (file-based execution)"
WORKTREE_PROMPT="$WORKTREE_DIR/.claude-prompt.txt"
cp "$PROMPT_FILE" "$WORKTREE_PROMPT"
PROMPT_METHOD="file"

# Create the tmux session with Claude Code
echo "Spawning Claude Code agent in tmux session: $TMUX_SESSION"
tmux new-session -d -s "$TMUX_SESSION" -c "$WORKTREE_DIR"
TMUX_CREATED=true

# Send the claude command to the tmux session
tmux send-keys -t "$TMUX_SESSION" "echo '=== AGENT START: $(date) ===' >> $LOG_FILE" C-m

# Activate venv in tmux if Python project
if [ -n "$VENV_PATH" ]; then
  tmux send-keys -t "$TMUX_SESSION" "source $VENV_PATH" C-m
fi

# Send Claude command using file-based prompt (always)
# Using -p flag with file input is most reliable for complex prompts
tmux send-keys -t "$TMUX_SESSION" "claude -p \"\$(cat .claude-prompt.txt)\" --model sonnet --dangerously-skip-permissions 2>&1 | tee -a $LOG_FILE" C-m

# Wait a moment then check if agent started
sleep 2
if tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
  # Success - disable error trap
  trap - ERR
  
  # Add task to registry
  REGISTRY="$HOME/.openclaw/swarm/active-tasks.json"
  LOCKDIR="$HOME/.openclaw/swarm/active-tasks.lock.d"
  
  # Acquire lock (mkdir is atomic on Unix)
  LOCK_ACQUIRED=false
  for i in {1..50}; do
    if mkdir "$LOCKDIR" 2>/dev/null; then
      LOCK_ACQUIRED=true
      break
    fi
    sleep 0.1
  done
  
  if [ "$LOCK_ACQUIRED" = false ]; then
    echo "⚠️  Could not acquire registry lock after 5s, task not added to registry"
    echo "   Task is running but won't be monitored by check-agents.sh"
  else
    # Add task to registry
    TEMP_REGISTRY=$(mktemp)
    jq --arg id "$TASK_ID" \
       --arg repo "$REPO" \
       --arg branch "$BRANCH" \
       --arg worktree "$WORKTREE_DIR" \
       --arg session "$TMUX_SESSION" \
       --argjson startedAt "$(date +%s)000" \
       --arg prompt "$PROMPT_FILE" \
       '.tasks += [{
         id: $id,
         repo: $repo,
         branch: $branch,
         worktree: $worktree,
         tmuxSession: $session,
         agent: "claude-code",
         model: .config.defaultModel,
         description: "",
         prompt: $prompt,
         priority: "normal",
         status: "running",
         startedAt: $startedAt,
         lastChecked: null,
         attempts: 1,
         maxAttempts: .config.maxAttempts,
         notifyOnComplete: .config.notifyOnComplete,
         pr: null,
         checks: {
           prCreated: false,
           ciPassed: false,
           reviewsPassed: false
         }
       }]' "$REGISTRY" > "$TEMP_REGISTRY"
    
    if [ $? -eq 0 ]; then
      mv "$TEMP_REGISTRY" "$REGISTRY"
      echo "✓ Task added to registry"
    else
      echo "✗ Failed to update registry (jq error)"
      rm -f "$TEMP_REGISTRY"
    fi
    
    # Release lock
    rmdir "$LOCKDIR"
  fi
  
  echo "✓ Agent spawned successfully"
  echo "  Worktree: $WORKTREE_DIR"
  echo "  Session:  $TMUX_SESSION"
  echo "  Log:      $LOG_FILE"
  echo "  Registry: $REGISTRY"
  echo ""
  echo "Monitor with: tmux attach -t $TMUX_SESSION"
  echo "Check status: ~/.openclaw/swarm/scripts/check-agents.sh"
else
  echo "✗ Failed to spawn agent"
  exit 1
fi
