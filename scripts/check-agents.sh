#!/bin/bash
# check-agents.sh - Monitor all active agents (deterministic, token-efficient)
# Called by cron every 10 minutes

set -euo pipefail

# Log script execution
SCRIPT_LOG="$HOME/.openclaw/swarm/logs/check-agents-$(date +%Y%m%d-%H%M%S).log"
mkdir -p "$(dirname "$SCRIPT_LOG")"
exec 1> >(tee -a "$SCRIPT_LOG")
exec 2>&1
echo "=== check-agents.sh started at $(date) ==="

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

# Copy registry to temp file for safe updates
cp "$REGISTRY" "$TEMP_REGISTRY"

# Parse active tasks
TASK_COUNT=$(jq -r '.tasks | length' "$TEMP_REGISTRY" 2>/dev/null)

if [ -z "$TASK_COUNT" ] || [ "$TASK_COUNT" = "null" ]; then
  echo "ERROR: Failed to parse task registry (invalid JSON?)"
  exit 3
fi

if [ "$TASK_COUNT" -eq 0 ]; then
  echo "No active agents to check"
  rmdir "$LOCKDIR" 2>/dev/null || true
  exit 0
fi

echo "Checking $TASK_COUNT active agent(s)..."

# Iterate through each task
for i in $(seq 0 $((TASK_COUNT - 1))); do
  TASK=$(jq -r ".tasks[$i]" "$TEMP_REGISTRY")
  TASK_ID=$(echo "$TASK" | jq -r '.id')
  TMUX_SESSION=$(echo "$TASK" | jq -r '.tmuxSession')
  REPO=$(echo "$TASK" | jq -r '.repo')
  BRANCH=$(echo "$TASK" | jq -r '.branch')
  STATUS=$(echo "$TASK" | jq -r '.status')
  ATTEMPTS=$(echo "$TASK" | jq -r '.attempts')
  MAX_ATTEMPTS=$(echo "$TASK" | jq -r '.maxAttempts')
  
  # Validate critical fields
  if [ -z "$TASK_ID" ] || [ "$TASK_ID" = "null" ]; then
    echo "  ⚠️  Task $i has invalid ID, skipping"
    continue
  fi
  
  if [ -z "$TMUX_SESSION" ] || [ "$TMUX_SESSION" = "null" ]; then
    echo "  ⚠️  Task $TASK_ID has invalid tmux session, skipping"
    continue
  fi
  
  echo "  Task: $TASK_ID (status: $STATUS, attempt: $ATTEMPTS/$MAX_ATTEMPTS)"
  
  # Check if tmux session exists
  if ! tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
    echo "    ⚠️  tmux session died unexpectedly"
    
    # Check if PR was created before death
    # Get repo name using gh CLI for reliability
    cd "$HOME/projects/$REPO"
    REPO_REMOTE=$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null || git remote get-url origin | sed 's|https://github.com/||' | sed 's|git@github.com:||' | sed 's|\.git$||')
    PR_NUM=$(gh pr list --repo "$REPO_REMOTE" --head "$BRANCH" --json number --jq '.[0].number' 2>/dev/null || echo "")
    
    if [ -n "$PR_NUM" ]; then
      echo "    ✓ PR #$PR_NUM was created, marking complete"
      jq ".tasks[$i].status = \"pr_created\" | .tasks[$i].pr = $PR_NUM | .tasks[$i].completedAt = $(date +%s)000" "$TEMP_REGISTRY" > "$TEMP_REGISTRY.new"
      mv "$TEMP_REGISTRY.new" "$TEMP_REGISTRY"
    else
      echo "    ✗ No PR created, marking failed"
      NEW_ATTEMPTS=$((ATTEMPTS + 1))
      if [ $NEW_ATTEMPTS -le $MAX_ATTEMPTS ]; then
        echo "    ↻ Will respawn (attempt $NEW_ATTEMPTS/$MAX_ATTEMPTS)"
        jq ".tasks[$i].status = \"failed\" | .tasks[$i].attempts = $NEW_ATTEMPTS | .tasks[$i].needsRespawn = true" "$TEMP_REGISTRY" > "$TEMP_REGISTRY.new"
        mv "$TEMP_REGISTRY.new" "$TEMP_REGISTRY"
      else
        echo "    ✗ Max attempts reached, marking as failed permanently"
        jq ".tasks[$i].status = \"failed_max_attempts\" | .tasks[$i].completedAt = $(date +%s)000" "$TEMP_REGISTRY" > "$TEMP_REGISTRY.new"
        mv "$TEMP_REGISTRY.new" "$TEMP_REGISTRY"
      fi
    fi
    continue
  fi
  
  # Session exists, check if PR created
  cd "$HOME/projects/$REPO"
  REPO_REMOTE=$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null || git remote get-url origin | sed 's|https://github.com/||' | sed 's|git@github.com:||' | sed 's|\.git$||')
  PR_NUM=$(gh pr list --repo "$REPO_REMOTE" --head "$BRANCH" --json number --jq '.[0].number' 2>/dev/null || echo "")
  
  if [ -n "$PR_NUM" ]; then
    echo "    ✓ PR #$PR_NUM created"
    
    # Check CI status - all checks must pass
    CI_STATUS=$(gh pr checks "$PR_NUM" --repo "$REPO_REMOTE" --json state --jq 'if length == 0 then "PENDING" elif all(.[]; .state == "SUCCESS") then "SUCCESS" elif any(.[]; .state == "FAILURE") then "FAILURE" else "PENDING" end' 2>/dev/null || echo "PENDING")
    echo "    CI status: $CI_STATUS"
    
    # Update task with PR info
    jq ".tasks[$i].pr = $PR_NUM | .tasks[$i].checks.prCreated = true | .tasks[$i].status = \"pr_created\"" "$TEMP_REGISTRY" > "$TEMP_REGISTRY.new"
    mv "$TEMP_REGISTRY.new" "$TEMP_REGISTRY"
    
    if [ "$CI_STATUS" = "SUCCESS" ]; then
      jq ".tasks[$i].checks.ciPassed = true | .tasks[$i].status = \"ready_for_review\"" "$TEMP_REGISTRY" > "$TEMP_REGISTRY.new"
      mv "$TEMP_REGISTRY.new" "$TEMP_REGISTRY"
      echo "    ✓ Ready for review"
    fi
  else
    # Check for stuck agents (running for >60 minutes without PR)
    START_TIME=$(echo "$TASK" | jq -r '.startedAt')
    CURRENT_TIME=$(date +%s)000
    ELAPSED_MINUTES=$(( (CURRENT_TIME - START_TIME) / 60000 ))
    
    if [ $ELAPSED_MINUTES -gt 60 ]; then
      echo "    ⚠️  Agent stuck (running for ${ELAPSED_MINUTES}min without PR)"
      jq ".tasks[$i].status = \"stuck\"" "$TEMP_REGISTRY" > "$TEMP_REGISTRY.new"
      mv "$TEMP_REGISTRY.new" "$TEMP_REGISTRY"
    else
      echo "    ⏳ Still working (${ELAPSED_MINUTES}min elapsed)"
    fi
  fi
done

# Write updated registry back
mv "$TEMP_REGISTRY" "$REGISTRY"

# Count tasks needing attention
NEEDS_REVIEW=$(jq -r '[.tasks[] | select(.status == "ready_for_review")] | length' "$REGISTRY")
STUCK=$(jq -r '[.tasks[] | select(.status == "stuck")] | length' "$REGISTRY")
FAILED=$(jq -r '[.tasks[] | select(.status == "failed_max_attempts")] | length' "$REGISTRY")
NEEDS_RESPAWN=$(jq -r '[.tasks[] | select(.needsRespawn == true)] | length' "$REGISTRY")

echo ""
echo "Summary:"
echo "  Ready for review: $NEEDS_REVIEW"
echo "  Stuck: $STUCK"
echo "  Failed: $FAILED"
echo "  Needs respawn: $NEEDS_RESPAWN"

# Release lock
rmdir "$LOCKDIR" 2>/dev/null || true

# Return exit code indicating if action needed
if [ $NEEDS_REVIEW -gt 0 ] || [ $STUCK -gt 0 ] || [ $FAILED -gt 0 ]; then
  exit 10  # Jeeves should be notified
elif [ $NEEDS_RESPAWN -gt 0 ]; then
  exit 11  # Jeeves should respawn agents
else
  exit 0   # All good
fi
