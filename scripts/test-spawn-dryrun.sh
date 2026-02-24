#!/bin/bash
# Dry-run test of spawn-agent.sh - does everything except launch claude

set -euo pipefail

REPO="sports-dashboard"
BRANCH="agent/test-minimal"
TASK_ID="test-minimal-$(date +%Y%m%d-%H%M%S)"
PROMPT_FILE="$HOME/.openclaw/swarm/prompts/test-spawn-minimal.txt"

REPO_DIR="$HOME/projects/$REPO"
WORKTREE_BASE="$HOME/projects/${REPO}-worktrees"
WORKTREE_DIR="$WORKTREE_BASE/$BRANCH"
TMUX_SESSION="swarm-$TASK_ID"
LOG_FILE="$HOME/.openclaw/swarm/logs/${TASK_ID}.log"

echo "=== Dry-run spawn test ==="
echo "Repo: $REPO"
echo "Branch: $BRANCH"
echo "Task ID: $TASK_ID"
echo ""

# Validate
if [ ! -d "$REPO_DIR/.git" ]; then
  echo "ERROR: $REPO_DIR is not a git repository"
  exit 1
fi
echo "✓ Repo exists"

if [ ! -f "$PROMPT_FILE" ]; then
  echo "ERROR: Prompt file $PROMPT_FILE does not exist"
  exit 1
fi
echo "✓ Prompt file exists"

if tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
  echo "ERROR: tmux session $TMUX_SESSION already exists"
  exit 1
fi
echo "✓ No existing tmux session"

if [ -d "$WORKTREE_DIR" ]; then
  echo "ERROR: Worktree already exists at $WORKTREE_DIR"
  exit 1
fi
echo "✓ No existing worktree"

cd "$REPO_DIR"
if git show-ref --verify --quiet "refs/heads/$BRANCH"; then
  echo "ERROR: Branch $BRANCH already exists locally"
  exit 1
fi
echo "✓ No existing branch"

# Create directories
mkdir -p "$WORKTREE_BASE"
mkdir -p "$(dirname "$LOG_FILE")"
echo "✓ Directories created"

# Detect default branch
cd "$REPO_DIR"
DEFAULT_BRANCH=""
DEFAULT_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || echo "")
if [ -z "$DEFAULT_BRANCH" ]; then
  DEFAULT_BRANCH=$(gh repo view --json defaultBranchRef --jq .defaultBranchRef.name 2>/dev/null || echo "")
fi
if [ -z "$DEFAULT_BRANCH" ]; then
  for branch in main master dev develop; do
    if git show-ref --verify --quiet "refs/remotes/origin/$branch"; then
      DEFAULT_BRANCH="$branch"
      break
    fi
  done
fi
if [ -z "$DEFAULT_BRANCH" ]; then
  echo "ERROR: Could not detect default branch"
  exit 1
fi
echo "✓ Default branch: $DEFAULT_BRANCH"

# Create worktree
echo "Creating worktree..."
git worktree add "$WORKTREE_DIR" -b "$BRANCH" "origin/$DEFAULT_BRANCH" 2>&1 | tee -a "$LOG_FILE"
echo "✓ Worktree created"

# Check if dependencies need installing
cd "$WORKTREE_DIR"
if [ -f "package.json" ]; then
  echo "⚠  Would install npm/pnpm dependencies (skipped in dry-run)"
fi

# Create tmux session (but don't launch claude)
echo "Creating tmux session..."
tmux new-session -d -s "$TMUX_SESSION" -c "$WORKTREE_DIR"
echo "✓ tmux session created: $TMUX_SESSION"

# Test prompt reading
PROMPT_CONTENT=$(cat "$PROMPT_FILE" | sed "s/'/'\\\\''/g")
if [ -n "$PROMPT_CONTENT" ]; then
  echo "✓ Prompt read successfully (${#PROMPT_CONTENT} chars)"
else
  echo "ERROR: Failed to read prompt"
  exit 1
fi

# Send test command instead of claude
tmux send-keys -t "$TMUX_SESSION" "echo '=== DRY-RUN TEST: Would launch claude here ===' | tee -a $LOG_FILE" C-m
tmux send-keys -t "$TMUX_SESSION" "echo 'Prompt preview (first 100 chars):' | tee -a $LOG_FILE" C-m
tmux send-keys -t "$TMUX_SESSION" "echo '$(echo "$PROMPT_CONTENT" | head -c 100)...' | tee -a $LOG_FILE" C-m
tmux send-keys -t "$TMUX_SESSION" "echo 'Sleeping 5 seconds then exiting...' | tee -a $LOG_FILE" C-m
tmux send-keys -t "$TMUX_SESSION" "sleep 5" C-m

sleep 2
if tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
  echo "✓ tmux session running"
else
  echo "✗ tmux session died"
  exit 1
fi

echo ""
echo "=== Dry-run SUCCESS ✓ ==="
echo ""
echo "Created:"
echo "  Worktree: $WORKTREE_DIR"
echo "  Branch:   $BRANCH"
echo "  Session:  $TMUX_SESSION"
echo "  Log:      $LOG_FILE"
echo ""
echo "Inspect with:"
echo "  tmux attach -t $TMUX_SESSION"
echo "  cat $LOG_FILE"
echo ""
echo "Cleanup with:"
echo "  tmux kill-session -t $TMUX_SESSION"
echo "  cd $REPO_DIR && git worktree remove $WORKTREE_DIR"
echo "  git branch -D $BRANCH"
