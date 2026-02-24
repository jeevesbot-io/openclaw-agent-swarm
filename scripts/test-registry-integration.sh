#!/bin/bash
# Test that spawn-agent.sh properly updates the task registry

set -e

echo "=== Testing Registry Integration ==="
echo ""

# Backup current registry
cp ~/.openclaw/swarm/active-tasks.json ~/.openclaw/swarm/active-tasks.json.backup
echo "✓ Backed up registry"

# Create a minimal test prompt
TEST_PROMPT=$(mktemp)
echo "Create a file called TEST.txt with content 'registry test'" > "$TEST_PROMPT"
echo "✓ Created test prompt"

# Check current task count
BEFORE_COUNT=$(jq '.tasks | length' ~/.openclaw/swarm/active-tasks.json)
echo "Tasks before spawn: $BEFORE_COUNT"

# Spawn agent (but kill it immediately - we just want to test registry)
TASK_ID="registry-test-$(date +%Y%m%d-%H%M%S)"
echo ""
echo "Spawning test agent..."
~/.openclaw/swarm/scripts/spawn-agent.sh \
  sports-dashboard \
  agent/registry-test \
  "$TASK_ID" \
  "$TEST_PROMPT" 2>&1 | tail -10

# Wait for registry update
sleep 2

# Check if task was added
AFTER_COUNT=$(jq '.tasks | length' ~/.openclaw/swarm/active-tasks.json)
echo ""
echo "Tasks after spawn: $AFTER_COUNT"

if [ "$AFTER_COUNT" -gt "$BEFORE_COUNT" ]; then
  echo "✓ Task added to registry"
  
  # Verify task details
  TASK=$(jq ".tasks[] | select(.id == \"$TASK_ID\")" ~/.openclaw/swarm/active-tasks.json)
  
  if [ -n "$TASK" ]; then
    echo "✓ Task found in registry"
    
    TASK_STATUS=$(echo "$TASK" | jq -r '.status')
    TASK_REPO=$(echo "$TASK" | jq -r '.repo')
    TASK_SESSION=$(echo "$TASK" | jq -r '.tmuxSession')
    
    echo ""
    echo "Task details:"
    echo "  ID: $TASK_ID"
    echo "  Status: $TASK_STATUS"
    echo "  Repo: $TASK_REPO"
    echo "  Session: $TASK_SESSION"
    
    if [ "$TASK_STATUS" = "running" ] && [ "$TASK_REPO" = "sports-dashboard" ]; then
      echo ""
      echo "✅ Registry integration test PASSED"
      TEST_PASSED=true
    else
      echo ""
      echo "❌ Task details incorrect"
      TEST_PASSED=false
    fi
  else
    echo "❌ Task not found in registry"
    TEST_PASSED=false
  fi
else
  echo "❌ Task not added to registry"
  TEST_PASSED=false
fi

# Cleanup
echo ""
echo "Cleaning up test agent..."
if tmux has-session -t "swarm-$TASK_ID" 2>/dev/null; then
  tmux kill-session -t "swarm-$TASK_ID"
  echo "✓ Killed tmux session"
fi

cd ~/projects/sports-dashboard
if [ -d ~/projects/sports-dashboard-worktrees/agent/registry-test ]; then
  git worktree remove ~/projects/sports-dashboard-worktrees/agent/registry-test --force 2>/dev/null || \
    rm -rf ~/projects/sports-dashboard-worktrees/agent/registry-test
  echo "✓ Removed worktree"
fi

if git show-ref --verify --quiet refs/heads/agent/registry-test; then
  git branch -D agent/registry-test 2>/dev/null || true
  echo "✓ Deleted branch"
fi

rm -f "$TEST_PROMPT"
echo "✓ Removed test prompt"

# Restore registry
mv ~/.openclaw/swarm/active-tasks.json.backup ~/.openclaw/swarm/active-tasks.json
echo "✓ Restored registry"

echo ""
if [ "$TEST_PASSED" = true ]; then
  echo "✅ Test completed successfully"
  exit 0
else
  echo "❌ Test failed"
  exit 1
fi
