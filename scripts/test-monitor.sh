#!/bin/bash
# test-monitor.sh — Test the monitoring flow with mock data
# Creates a test registry, runs monitor in dry-run mode, validates output

set -euo pipefail

SWARM_DIR="$HOME/.openclaw/swarm"
TEST_DIR="$SWARM_DIR/test-output"
SCRIPTS_DIR="$SWARM_DIR/scripts"

echo "=== Swarm Monitor Test Suite ==="
echo ""

# --- Setup ---
echo "Setting up test environment..."
mkdir -p "$TEST_DIR"

# Backup real registry if it exists
REGISTRY="$SWARM_DIR/active-tasks.json"
BACKUP_REGISTRY=""
if [ -f "$REGISTRY" ]; then
  BACKUP_REGISTRY="$REGISTRY.backup-$(date +%s)"
  cp "$REGISTRY" "$BACKUP_REGISTRY"
  echo "  ✓ Backed up real registry to $BACKUP_REGISTRY"
fi

# --- Test 1: Empty registry ---
echo ""
echo "Test 1: Empty registry"
cat > "$REGISTRY" << 'EOF'
{
  "version": "1.0.0",
  "tasks": [],
  "history": [],
  "stats": {
    "totalTasks": 0,
    "successRate": 0,
    "avgCompletionMinutes": 0,
    "totalCost": 0
  },
  "config": {
    "maxParallelAgents": 2,
    "maxAttempts": 3,
    "defaultModel": "sonnet",
    "checkIntervalMinutes": 10
  }
}
EOF

"$SCRIPTS_DIR/monitor.sh" --dry-run > "$TEST_DIR/test1.log" 2>&1 || true
if grep -q "No tasks to monitor" "$TEST_DIR/test1.log"; then
  echo "  ✓ Pass: Empty registry handled correctly"
else
  echo "  ✗ Fail: Empty registry not handled correctly"
  cat "$TEST_DIR/test1.log"
fi

# --- Test 2: PR needing review ---
echo ""
echo "Test 2: PR needing review"
cat > "$REGISTRY" << 'EOF'
{
  "version": "1.0.0",
  "tasks": [
    {
      "id": "test-task-1",
      "repo": "sports-dashboard",
      "branch": "agent/test-branch",
      "worktree": "/Users/jeeves/projects/sports-dashboard-worktrees/agent/test-branch",
      "tmuxSession": "swarm-test-task-1",
      "agent": "claude-code",
      "model": "sonnet",
      "status": "pr_created",
      "startedAt": 1771964687000,
      "attempts": 1,
      "maxAttempts": 3,
      "pr": 999,
      "checks": {
        "prCreated": true,
        "ciPassed": true,
        "reviewsPassed": false
      }
    }
  ],
  "history": [],
  "stats": {"totalTasks": 0, "successRate": 0, "avgCompletionMinutes": 0, "totalCost": 0},
  "config": {"maxParallelAgents": 2, "maxAttempts": 3, "defaultModel": "sonnet"}
}
EOF

"$SCRIPTS_DIR/monitor.sh" --dry-run > "$TEST_DIR/test2.log" 2>&1 || true
if grep -q "Would run: review-pr.sh" "$TEST_DIR/test2.log" && grep -q "pr_ready" "$TEST_DIR/test2.log"; then
  echo "  ✓ Pass: PR review triggered correctly"
else
  echo "  ✗ Fail: PR review not triggered"
  cat "$TEST_DIR/test2.log"
fi

# --- Test 3: Stuck agent ---
echo ""
echo "Test 3: Stuck agent"
STUCK_START_TIME=$(( $(date +%s)000 - 3700000 ))  # 61 minutes ago
cat > "$REGISTRY" << EOF
{
  "version": "1.0.0",
  "tasks": [
    {
      "id": "test-task-stuck",
      "repo": "sports-dashboard",
      "branch": "agent/stuck-branch",
      "worktree": "/Users/jeeves/projects/sports-dashboard-worktrees/agent/stuck-branch",
      "tmuxSession": "swarm-test-stuck",
      "agent": "claude-code",
      "model": "sonnet",
      "status": "stuck",
      "startedAt": $STUCK_START_TIME,
      "attempts": 1,
      "maxAttempts": 3,
      "checks": {}
    }
  ],
  "history": [],
  "stats": {"totalTasks": 0, "successRate": 0, "avgCompletionMinutes": 0, "totalCost": 0},
  "config": {"maxParallelAgents": 2, "maxAttempts": 3, "defaultModel": "sonnet"}
}
EOF

"$SCRIPTS_DIR/monitor.sh" --dry-run > "$TEST_DIR/test3.log" 2>&1 || true
if grep -q "agent_stuck" "$TEST_DIR/test3.log"; then
  echo "  ✓ Pass: Stuck agent notification created"
else
  echo "  ✗ Fail: Stuck agent not detected"
  cat "$TEST_DIR/test3.log"
fi

# --- Test 4: Failed agent needing respawn ---
echo ""
echo "Test 4: Failed agent needing respawn"
cat > "$REGISTRY" << 'EOF'
{
  "version": "1.0.0",
  "tasks": [
    {
      "id": "test-task-failed",
      "repo": "sports-dashboard",
      "branch": "agent/failed-branch",
      "worktree": "/Users/jeeves/projects/sports-dashboard-worktrees/agent/failed-branch",
      "tmuxSession": "swarm-test-failed",
      "agent": "claude-code",
      "model": "sonnet",
      "status": "failed",
      "startedAt": 1771964687000,
      "attempts": 1,
      "maxAttempts": 3,
      "needsRespawn": true,
      "checks": {}
    }
  ],
  "history": [],
  "stats": {"totalTasks": 0, "successRate": 0, "avgCompletionMinutes": 0, "totalCost": 0},
  "config": {"maxParallelAgents": 2, "maxAttempts": 3, "defaultModel": "sonnet"}
}
EOF

"$SCRIPTS_DIR/monitor.sh" --dry-run > "$TEST_DIR/test4.log" 2>&1 || true
if grep -q "Would run: respawn-agent.sh" "$TEST_DIR/test4.log" && grep -q "agent_respawned" "$TEST_DIR/test4.log"; then
  echo "  ✓ Pass: Respawn triggered correctly"
else
  echo "  ✗ Fail: Respawn not triggered"
  cat "$TEST_DIR/test4.log"
fi

# --- Test 5: Permanently failed agent ---
echo ""
echo "Test 5: Permanently failed agent"
cat > "$REGISTRY" << 'EOF'
{
  "version": "1.0.0",
  "tasks": [
    {
      "id": "test-task-max-failed",
      "repo": "sports-dashboard",
      "branch": "agent/max-failed-branch",
      "worktree": "/Users/jeeves/projects/sports-dashboard-worktrees/agent/max-failed-branch",
      "tmuxSession": "swarm-test-max-failed",
      "agent": "claude-code",
      "model": "sonnet",
      "status": "failed_max_attempts",
      "startedAt": 1771964687000,
      "attempts": 3,
      "maxAttempts": 3,
      "checks": {}
    }
  ],
  "history": [],
  "stats": {"totalTasks": 0, "successRate": 0, "avgCompletionMinutes": 0, "totalCost": 0},
  "config": {"maxParallelAgents": 2, "maxAttempts": 3, "defaultModel": "sonnet"}
}
EOF

"$SCRIPTS_DIR/monitor.sh" --dry-run > "$TEST_DIR/test5.log" 2>&1 || true
if grep -q "agent_failed" "$TEST_DIR/test5.log"; then
  echo "  ✓ Pass: Permanent failure notification created"
else
  echo "  ✗ Fail: Permanent failure not detected"
  cat "$TEST_DIR/test5.log"
fi

# --- Cleanup ---
echo ""
echo "Cleaning up..."
if [ -n "$BACKUP_REGISTRY" ]; then
  mv "$BACKUP_REGISTRY" "$REGISTRY"
  echo "  ✓ Restored original registry"
fi

echo ""
echo "=== Test Suite Complete ==="
echo "Test logs saved to: $TEST_DIR/"
echo ""
echo "To inspect test output:"
echo "  cat $TEST_DIR/test*.log"
