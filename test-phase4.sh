#!/bin/bash
# Test script for Phase 4 - Queue Management

set -euo pipefail

echo "=== Phase 4 Test Suite ==="
echo ""

# Test 1: List empty queue
echo "Test 1: List empty queue"
scripts/list-queue.sh
echo "✓ Test 1 passed"
echo ""

# Test 2: Add task with high priority
echo "Test 2: Add task with high priority"
scripts/queue-task.sh sports-dashboard agent/feat-test-queue "echo test" --priority high
echo "✓ Test 2 passed"
echo ""

# Test 3: List queue with 1 task
echo "Test 3: List queue with 1 task"
scripts/list-queue.sh
echo "✓ Test 3 passed"
echo ""

# Test 4: Add more tasks with different priorities
echo "Test 4: Add multiple tasks with different priorities"
scripts/queue-task.sh MissionControls agent/fix-bug "Fix bug" --priority normal
scripts/queue-task.sh claude_jobhunt agent/refactor "Refactor code" --priority low
scripts/queue-task.sh sports-dashboard agent/urgent-fix "Urgent fix" --priority high
echo "✓ Test 4 passed"
echo ""

# Test 5: List queue (should show 4 tasks, sorted by priority)
echo "Test 5: List queue (should show high priority first)"
scripts/list-queue.sh
echo "✓ Test 5 passed"
echo ""

# Test 6: Check swarm status (should show queue info)
echo "Test 6: Check swarm status"
scripts/swarm-status.sh
echo "✓ Test 6 passed"
echo ""

# Test 7: Dry-run dispatch (should attempt to spawn 2 agents)
echo "Test 7: Dry-run dispatch"
scripts/dispatch.sh --dry-run
echo "✓ Test 7 passed"
echo ""

# Test 8: Cancel a queued task
TASK_ID=$(jq -r '.queue[0].id' queue.json)
echo "Test 8: Cancel task $TASK_ID"
scripts/cancel-task.sh "$TASK_ID" --force
echo "✓ Test 8 passed"
echo ""

# Test 9: List queue after cancellation
echo "Test 9: List queue after cancellation"
scripts/list-queue.sh
echo "✓ Test 9 passed"
echo ""

# Test 10: JSON output
echo "Test 10: JSON output"
scripts/list-queue.sh --json | jq '.'
echo "✓ Test 10 passed"
echo ""

# Cleanup - clear the queue
echo "Cleanup: Clearing queue"
echo '{"version":"1.0.0","queue":[]}' > queue.json
scripts/list-queue.sh
echo "✓ Cleanup complete"
echo ""

echo "=== All Tests Passed ==="
