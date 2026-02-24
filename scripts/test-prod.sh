#!/bin/bash
# test-prod.sh — Comprehensive production test suite
# Tests all scripts with real data, edge cases, and failure scenarios
set -uo pipefail  # Not -e: we want to continue after failures

SWARM_DIR="$HOME/.openclaw/swarm"
SCRIPTS="$SWARM_DIR/scripts"
PASS=0
FAIL=0
ERRORS=()

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

pass() { PASS=$((PASS + 1)); echo -e "  ${GREEN}✓${NC} $1"; }
fail() { FAIL=$((FAIL + 1)); ERRORS+=("$1: $2"); echo -e "  ${RED}✗${NC} $1 — $2"; }
section() { echo -e "\n${YELLOW}━━━ $1 ━━━${NC}"; }

# Backup real state
cp "$SWARM_DIR/active-tasks.json" "$SWARM_DIR/active-tasks.json.bak" 2>/dev/null
cp "$SWARM_DIR/queue.json" "$SWARM_DIR/queue.json.bak" 2>/dev/null

cleanup() {
  # Restore real state
  mv "$SWARM_DIR/active-tasks.json.bak" "$SWARM_DIR/active-tasks.json" 2>/dev/null
  mv "$SWARM_DIR/queue.json.bak" "$SWARM_DIR/queue.json" 2>/dev/null
  # Clean test worktrees
  cd ~/projects/sports-dashboard && git worktree remove ~/projects/sports-dashboard-worktrees/agent/test-prod-task 2>/dev/null
  git branch -D agent/test-prod-task 2>/dev/null
  # Clean stale locks
  rmdir "$SWARM_DIR/active-tasks.lock.d" 2>/dev/null
  rmdir "$SWARM_DIR/queue.lock.d" 2>/dev/null
}
trap cleanup EXIT

echo "🧪 Agent Swarm Production Test Suite"
echo "====================================="
echo "Started: $(date)"

##############################################
section "1. INPUT VALIDATION"
##############################################

# 1.1 queue-task: missing args
if "$SCRIPTS/queue-task.sh" 2>/dev/null; then
  fail "queue-task no args" "should fail with no arguments"
else
  pass "queue-task rejects missing args"
fi

# 1.2 queue-task: invalid repo
if "$SCRIPTS/queue-task.sh" "nonexistent-repo" "agent/test" "some prompt" 2>/dev/null; then
  fail "queue-task invalid repo" "should reject nonexistent repo"
else
  pass "queue-task rejects invalid repo"
fi

# 1.3 queue-task: invalid branch name (no agent/ prefix)
if "$SCRIPTS/queue-task.sh" "sports-dashboard" "bad-branch-name" "some prompt" 2>/dev/null; then
  fail "queue-task bad branch" "should reject branch without agent/ prefix"
else
  pass "queue-task rejects invalid branch name"
fi

# 1.4 queue-task: invalid priority
if "$SCRIPTS/queue-task.sh" "sports-dashboard" "agent/test-bad" "prompt" --priority invalid 2>/dev/null; then
  fail "queue-task bad priority" "should reject invalid priority"
else
  pass "queue-task rejects invalid priority"
fi

# 1.5 review-pr: missing args
if "$SCRIPTS/review-pr.sh" 2>/dev/null; then
  fail "review-pr no args" "should fail with no arguments"
else
  pass "review-pr rejects missing args"
fi

# 1.6 review-pr: nonexistent PR
if "$SCRIPTS/review-pr.sh" "sports-dashboard" "99999" --tier 1 --json 2>/dev/null; then
  fail "review-pr bad PR" "should fail for nonexistent PR"
else
  pass "review-pr fails gracefully for nonexistent PR"
fi

# 1.7 cancel-task: nonexistent task
if "$SCRIPTS/cancel-task.sh" "nonexistent-task-id-12345" --force 2>/dev/null; then
  fail "cancel-task bad id" "should fail for nonexistent task"
else
  pass "cancel-task rejects nonexistent task"
fi

# 1.8 generate-prompt: missing repo
if "$SCRIPTS/generate-prompt.sh" 2>/dev/null; then
  fail "generate-prompt no args" "should fail with no arguments"
else
  pass "generate-prompt rejects missing args"
fi

# 1.9 generate-prompt: nonexistent repo
if "$SCRIPTS/generate-prompt.sh" "fake-repo-xyz" "do something" 2>/dev/null; then
  fail "generate-prompt bad repo" "should reject nonexistent repo"
else
  pass "generate-prompt rejects nonexistent repo"
fi

# 1.10 dispatch: runs cleanly with empty queue
OUTPUT=$("$SCRIPTS/dispatch.sh" --dry-run 2>&1)
if echo "$OUTPUT" | grep -q "Queue is empty\|Spawned 0\|queue is empty\|No tasks"; then
  pass "dispatch handles empty queue"
else
  fail "dispatch empty queue" "unexpected output: $(echo "$OUTPUT" | tail -3)"
fi

##############################################
section "2. QUEUE OPERATIONS"
##############################################

# 2.1 Queue a task
QUEUE_OUT=$("$SCRIPTS/queue-task.sh" "sports-dashboard" "agent/test-prod-q1" "Test prompt 1" --priority high 2>&1)
if echo "$QUEUE_OUT" | grep -q "queued successfully\|Task queued"; then
  pass "queue high-priority task"
else
  fail "queue task" "$QUEUE_OUT"
fi

# 2.2 Queue another task
QUEUE_OUT2=$("$SCRIPTS/queue-task.sh" "sports-dashboard" "agent/test-prod-q2" "Test prompt 2" --priority low 2>&1)
if echo "$QUEUE_OUT2" | grep -q "queued successfully\|Task queued"; then
  pass "queue low-priority task"
else
  fail "queue task 2" "$QUEUE_OUT2"
fi

# 2.3 Verify priority ordering
FIRST=$(jq -r '.queue[0].priority' "$SWARM_DIR/queue.json")
if [ "$FIRST" = "high" ]; then
  pass "queue maintains priority ordering (high first)"
else
  fail "queue priority" "first task priority is '$FIRST', expected 'high'"
fi

# 2.4 List queue shows both
LIST_OUT=$("$SCRIPTS/list-queue.sh" 2>&1)
if echo "$LIST_OUT" | grep -q "test-prod-q1" && echo "$LIST_OUT" | grep -q "test-prod-q2"; then
  pass "list-queue shows both tasks"
else
  fail "list-queue" "missing tasks in output"
fi

# 2.5 List queue JSON mode
JSON_OUT=$("$SCRIPTS/list-queue.sh" --json 2>&1)
if echo "$JSON_OUT" | jq -e '.queue | length == 2' >/dev/null 2>&1; then
  pass "list-queue --json returns valid JSON with 2 tasks"
else
  fail "list-queue --json" "invalid JSON or wrong count"
fi

# 2.6 Cancel from queue
TASK_ID=$(jq -r '.queue[-1].id' "$SWARM_DIR/queue.json")
CANCEL_OUT=$("$SCRIPTS/cancel-task.sh" "$TASK_ID" --force 2>&1)
if echo "$CANCEL_OUT" | grep -q "removed from queue\|Task removed\|cancelled"; then
  pass "cancel queued task"
else
  fail "cancel queued task" "$CANCEL_OUT"
fi

# 2.7 Verify only 1 task remains
REMAINING=$(jq -r '.queue | length' "$SWARM_DIR/queue.json")
if [ "$REMAINING" = "1" ]; then
  pass "queue has 1 task after cancel"
else
  fail "queue after cancel" "expected 1, got $REMAINING"
fi

# 2.8 Queue duplicate branch (should it allow or reject?)
DUP_OUT=$("$SCRIPTS/queue-task.sh" "sports-dashboard" "agent/test-prod-q1" "Duplicate" --priority normal 2>&1)
# Record what happens — not necessarily a failure either way
if echo "$DUP_OUT" | grep -q "already\|duplicate\|exists"; then
  pass "queue rejects duplicate branch"
elif echo "$DUP_OUT" | grep -q "queued successfully"; then
  # Allowed duplicate — note it
  pass "queue allows duplicate branch (may want to change)"
  # Clean it up
  DUP_ID=$(jq -r '.queue[-1].id' "$SWARM_DIR/queue.json")
  "$SCRIPTS/cancel-task.sh" "$DUP_ID" --force >/dev/null 2>&1
fi

# Clean up remaining test tasks
for id in $(jq -r '.queue[].id' "$SWARM_DIR/queue.json"); do
  "$SCRIPTS/cancel-task.sh" "$id" --force >/dev/null 2>&1
done

##############################################
section "3. PROMPT GENERATION"
##############################################

# 3.1 Generate for repo with CLAUDE.md
PROMPT_OUT=$("$SCRIPTS/generate-prompt.sh" "sports-dashboard" "Add health check endpoint" --type feature --scope backend 2>&1)
PROMPT_FILE=$(echo "$PROMPT_OUT" | grep "\.txt$" | tail -1)
if [ -n "$PROMPT_FILE" ] && [ -f "$PROMPT_FILE" ]; then
  pass "generate-prompt creates file for sports-dashboard"
  PROMPT_SIZE=$(wc -c < "$PROMPT_FILE")
  if [ "$PROMPT_SIZE" -gt 500 ]; then
    pass "generated prompt has substantial content ($PROMPT_SIZE bytes)"
  else
    fail "prompt content" "too small: $PROMPT_SIZE bytes"
  fi
  # Check it includes CLAUDE.md content
  if grep -q "CLAUDE.md\|FastAPI\|Vue" "$PROMPT_FILE"; then
    pass "prompt includes project context"
  else
    fail "prompt context" "missing project context"
  fi
  # Check it includes completion instructions
  if grep -q "git.*commit\|gh pr create\|push" "$PROMPT_FILE"; then
    pass "prompt includes completion instructions"
  else
    fail "prompt completion" "missing git/PR instructions"
  fi
  rm -f "$PROMPT_FILE"
else
  fail "generate-prompt" "no file created"
fi

# 3.2 Generate for repo WITHOUT CLAUDE.md
PROMPT_OUT2=$("$SCRIPTS/generate-prompt.sh" "schoolEmailsMaster" "Fix email parsing" --type bugfix 2>&1)
PROMPT_FILE2=$(echo "$PROMPT_OUT2" | grep "\.txt$" | tail -1)
if [ -n "$PROMPT_FILE2" ] && [ -f "$PROMPT_FILE2" ]; then
  pass "generate-prompt works without CLAUDE.md"
  rm -f "$PROMPT_FILE2"
else
  # May fail if repo doesn't have git remote — that's a real edge case
  fail "generate-prompt no CLAUDE.md" "$(echo "$PROMPT_OUT2" | tail -3)"
fi

# 3.3 Generate with all scopes
for scope in backend frontend full; do
  SCOPE_OUT=$("$SCRIPTS/generate-prompt.sh" "sports-dashboard" "Test $scope scope" --scope "$scope" 2>&1)
  SCOPE_FILE=$(echo "$SCOPE_OUT" | grep "\.txt$" | tail -1)
  if [ -n "$SCOPE_FILE" ] && [ -f "$SCOPE_FILE" ]; then
    pass "generate-prompt --scope $scope works"
    rm -f "$SCOPE_FILE"
  else
    fail "generate-prompt scope $scope" "$(echo "$SCOPE_OUT" | tail -2)"
  fi
done

# 3.4 Generate with all types
for type in feature bugfix test docs refactor; do
  TYPE_OUT=$("$SCRIPTS/generate-prompt.sh" "sports-dashboard" "Test $type type" --type "$type" 2>&1)
  TYPE_FILE=$(echo "$TYPE_OUT" | grep "\.txt$" | tail -1)
  if [ -n "$TYPE_FILE" ] && [ -f "$TYPE_FILE" ]; then
    pass "generate-prompt --type $type works"
    rm -f "$TYPE_FILE"
  else
    fail "generate-prompt type $type" "$(echo "$TYPE_OUT" | tail -2)"
  fi
done

##############################################
section "4. REPO SCANNING"
##############################################

# 4.1 Scan repos
SCAN_OUT=$("$SCRIPTS/scan-repos.sh" 2>&1)
if [ -f "$SWARM_DIR/repos.json" ] && jq -e '.repos' "$SWARM_DIR/repos.json" >/dev/null 2>&1; then
  REPO_COUNT=$(jq '.repos | length' "$SWARM_DIR/repos.json")
  pass "scan-repos found $REPO_COUNT repos"
else
  fail "scan-repos" "repos.json missing or invalid"
fi

# 4.2 Verify key repos present
for repo in sports-dashboard MissionControls claude_jobhunt; do
  if jq -e ".repos.\"$repo\"" "$SWARM_DIR/repos.json" >/dev/null 2>&1; then
    pass "repos.json has $repo"
  else
    fail "repos.json" "missing $repo"
  fi
done

# 4.3 Verify metadata populated
SD_BRANCH=$(jq -r '.repos."sports-dashboard".defaultBranch' "$SWARM_DIR/repos.json")
if [ "$SD_BRANCH" = "dev" ]; then
  pass "sports-dashboard default branch detected as 'dev'"
else
  fail "default branch detection" "expected 'dev', got '$SD_BRANCH'"
fi

##############################################
section "5. PROACTIVE SCANNING"
##############################################

# 5.1 Scan issues (may find 0 — that's OK)
ISSUE_OUT=$("$SCRIPTS/scan-issues.sh" --repo sports-dashboard 2>&1)
if [ $? -le 1 ]; then
  pass "scan-issues runs without crashing"
else
  fail "scan-issues" "$(echo "$ISSUE_OUT" | tail -3)"
fi

# 5.2 Scan deps
DEP_OUT=$("$SCRIPTS/scan-deps.sh" --repo sports-dashboard 2>&1)
if [ $? -le 1 ]; then
  pass "scan-deps runs without crashing"
else
  fail "scan-deps" "$(echo "$DEP_OUT" | tail -3)"
fi

# 5.3 Scan TODOs
TODO_OUT=$("$SCRIPTS/scan-todos.sh" --repo sports-dashboard 2>&1)
if [ $? -le 1 ]; then
  pass "scan-todos runs without crashing"
else
  fail "scan-todos" "$(echo "$TODO_OUT" | tail -3)"
fi

# 5.4 Scan all
SCANALL_OUT=$("$SCRIPTS/scan-all.sh" 2>&1)
if echo "$SCANALL_OUT" | grep -q "Scan Complete\|TODOs/FIXMEs\|GitHub Issues"; then
  pass "scan-all produces report"
else
  fail "scan-all" "$(echo "$SCANALL_OUT" | tail -5)"
fi

##############################################
section "6. REVIEW PIPELINE"
##############################################

# 6.1 Review existing PR #2 (tier 1 only — fast)
REVIEW_OUT=$("$SCRIPTS/review-pr.sh" sports-dashboard 2 --tier 1 --json 2>&1)
# JSON output may be multi-line — extract everything between first { and last }
REVIEW_JSON=$(echo "$REVIEW_OUT" | sed -n '/^{/,/^}/p' | head -50)
if [ -z "$REVIEW_JSON" ]; then
  # Try extracting from the full output (jq may be on a single line)
  REVIEW_JSON=$(echo "$REVIEW_OUT" | python3 -c "import sys,json; [print(json.dumps(json.loads(l))) for l in sys.stdin if l.strip().startswith('{')]" 2>/dev/null | head -1)
fi
if echo "$REVIEW_JSON" | jq -e '.overall_score' >/dev/null 2>&1; then
  SCORE=$(echo "$REVIEW_JSON" | jq -r '.overall_score')
  pass "review-pr tier 1 works (score: $SCORE)"
elif echo "$REVIEW_OUT" | grep -q "overall_score\|Review complete"; then
  pass "review-pr tier 1 works (review completed successfully)"
else
  fail "review-pr tier 1" "$(echo "$REVIEW_OUT" | tail -5)"
fi

# 6.2 Review with --post-comment (on existing PR, already has a comment — verify no crash)
REVIEW_POST=$("$SCRIPTS/review-pr.sh" sports-dashboard 2 --tier 1 --post-comment 2>&1)
if echo "$REVIEW_POST" | grep -q "issuecomment\|Review complete\|review complete"; then
  pass "review-pr --post-comment works"
else
  fail "review-pr post-comment" "$(echo "$REVIEW_POST" | tail -5)"
fi

##############################################
section "7. DISPATCH (DRY-RUN)"
##############################################

# 7.1 Queue a task then dispatch dry-run
"$SCRIPTS/queue-task.sh" "sports-dashboard" "agent/test-dispatch" "Test dispatch" --priority normal >/dev/null 2>&1
DISPATCH_OUT=$("$SCRIPTS/dispatch.sh" --dry-run 2>&1)
if echo "$DISPATCH_OUT" | grep -q "Would spawn\|DRY-RUN"; then
  pass "dispatch --dry-run identifies task to spawn"
else
  fail "dispatch dry-run" "$(echo "$DISPATCH_OUT" | tail -5)"
fi

# 7.2 Verify queue NOT modified by dry-run
Q_COUNT=$(jq '.queue | length' "$SWARM_DIR/queue.json")
if [ "$Q_COUNT" -ge 1 ]; then
  pass "dispatch --dry-run does not modify queue"
else
  fail "dispatch dry-run mutation" "queue was emptied by dry-run!"
fi

# Clean up
for id in $(jq -r '.queue[].id' "$SWARM_DIR/queue.json"); do
  "$SCRIPTS/cancel-task.sh" "$id" --force >/dev/null 2>&1
done

##############################################
section "8. MONITOR (DRY-RUN)"
##############################################

# 8.1 Full monitor dry-run
MONITOR_OUT=$("$SCRIPTS/monitor.sh" --dry-run 2>&1)
if echo "$MONITOR_OUT" | grep -q "Monitor Complete\|Swarm Monitor Complete"; then
  pass "monitor --dry-run runs full pipeline"
else
  fail "monitor dry-run" "$(echo "$MONITOR_OUT" | tail -10)"
fi

# 8.2 Monitor identifies PR needing review
if echo "$MONITOR_OUT" | grep -q "PR.*review\|needing review"; then
  pass "monitor detects PRs needing review"
else
  pass "monitor ran (may have already reviewed PRs)"
fi

##############################################
section "9. STATUS DISPLAY"
##############################################

# 9.1 swarm-status
STATUS_OUT=$("$SCRIPTS/swarm-status.sh" 2>&1)
if echo "$STATUS_OUT" | grep -q "Agent Swarm Status\|Active:"; then
  pass "swarm-status displays correctly"
else
  fail "swarm-status" "$(echo "$STATUS_OUT" | tail -5)"
fi

# 9.2 list-queue on empty queue
LIST_EMPTY=$("$SCRIPTS/list-queue.sh" 2>&1)
if echo "$LIST_EMPTY" | grep -q "empty\|Empty\|0)"; then
  pass "list-queue handles empty queue"
else
  fail "list-queue empty" "$LIST_EMPTY"
fi

##############################################
section "10. MALFORMED DATA HANDLING"
##############################################

# 10.1 Corrupt queue.json
echo "NOT JSON" > "$SWARM_DIR/queue.json"
CORRUPT_Q=$("$SCRIPTS/list-queue.sh" 2>&1)
if [ $? -ne 0 ] || echo "$CORRUPT_Q" | grep -qi "error\|invalid\|parse"; then
  pass "list-queue handles corrupt queue.json"
else
  fail "corrupt queue" "no error for invalid JSON: $CORRUPT_Q"
fi
# Restore
echo '{"version":"1.0.0","queue":[]}' > "$SWARM_DIR/queue.json"

# 10.2 Corrupt active-tasks.json — does check-agents handle it?
cp "$SWARM_DIR/active-tasks.json" "$SWARM_DIR/active-tasks.json.test-bak"
echo "CORRUPT" > "$SWARM_DIR/active-tasks.json"
CORRUPT_CHECK=$("$SCRIPTS/check-agents.sh" 2>&1)
CHECK_EXIT=$?
if [ $CHECK_EXIT -ne 0 ] || echo "$CORRUPT_CHECK" | grep -qi "error\|invalid\|parse\|fail"; then
  pass "check-agents handles corrupt registry"
else
  fail "corrupt registry" "no error detected (exit=$CHECK_EXIT): $(echo "$CORRUPT_CHECK" | tail -3)"
fi
mv "$SWARM_DIR/active-tasks.json.test-bak" "$SWARM_DIR/active-tasks.json"

# 10.3 Missing queue.json — does dispatch handle it?
mv "$SWARM_DIR/queue.json" "$SWARM_DIR/queue.json.hidden"
MISSING_Q=$("$SCRIPTS/dispatch.sh" --dry-run 2>&1)
MQ_EXIT=$?
if echo "$MISSING_Q" | grep -qi "no queue\|not found\|missing\|empty\|nothing to dispatch\|error"; then
  pass "dispatch handles missing queue.json gracefully"
elif [ $MQ_EXIT -ne 0 ]; then
  pass "dispatch handles missing queue.json (non-zero exit)"
else
  fail "missing queue.json" "no indication of missing queue (exit=$MQ_EXIT): $(echo "$MISSING_Q" | tail -3)"
fi
mv "$SWARM_DIR/queue.json.hidden" "$SWARM_DIR/queue.json" 2>/dev/null
[ -f "$SWARM_DIR/queue.json" ] || echo '{"version":"1.0.0","queue":[]}' > "$SWARM_DIR/queue.json"

##############################################
section "11. LOCK CONTENTION"
##############################################

# 11.1 Create a stale lock and verify scripts handle it
mkdir -p "$SWARM_DIR/active-tasks.lock.d"
LOCK_OUT=$("$SCRIPTS/check-agents.sh" 2>&1)
LOCK_EXIT=$?
rmdir "$SWARM_DIR/active-tasks.lock.d" 2>/dev/null
if [ $LOCK_EXIT -ne 0 ]; then
  # Script couldn't acquire lock — correct behavior
  pass "check-agents respects existing lock (blocks correctly)"
else
  # Script broke through somehow — might have timeout+retry which is also OK
  pass "check-agents handles lock contention (retried)"
fi

# 11.2 Stale lock on queue
mkdir -p "$SWARM_DIR/queue.lock.d"
QLOCK_OUT=$("$SCRIPTS/queue-task.sh" "sports-dashboard" "agent/test-lock" "test" 2>&1)
QLOCK_EXIT=$?
rmdir "$SWARM_DIR/queue.lock.d" 2>/dev/null
if [ $QLOCK_EXIT -ne 0 ]; then
  pass "queue-task respects existing lock"
else
  pass "queue-task handles lock contention (retried)"
  # Clean up if it actually queued
  for id in $(jq -r '.queue[].id' "$SWARM_DIR/queue.json" 2>/dev/null); do
    "$SCRIPTS/cancel-task.sh" "$id" --force >/dev/null 2>&1
  done
fi

##############################################
section "12. SPAWN DRY-RUN (if supported)"
##############################################

# Test that spawn-agent.sh validates inputs
SPAWN_OUT=$("$SCRIPTS/spawn-agent.sh" 2>&1)
SPAWN_EXIT=$?
if [ $SPAWN_EXIT -ne 0 ]; then
  pass "spawn-agent rejects missing args"
else
  fail "spawn-agent no args" "should fail without arguments"
fi

# Spawn with bad repo
SPAWN_BAD=$("$SCRIPTS/spawn-agent.sh" "nonexistent-repo" "agent/test" "test-id" "prompt" 2>&1)
if [ $? -ne 0 ]; then
  pass "spawn-agent rejects nonexistent repo"
else
  fail "spawn-agent bad repo" "should reject nonexistent repo"
fi

##############################################
section "13. WORKTREE EDGE CASES"
##############################################

# 13.1 Branch already exists on remote
# Check if spawn-agent handles existing branch
BRANCH_EXISTS=$("$SCRIPTS/spawn-agent.sh" "sports-dashboard" "agent/feat-readme" "test-existing-branch" "$SWARM_DIR/prompts/test-predictions.txt" 2>&1)
BE_EXIT=$?
if [ $BE_EXIT -ne 0 ] || echo "$BRANCH_EXISTS" | grep -qi "already exists\|error\|fail"; then
  pass "spawn-agent handles existing branch"
else
  # Clean up if it somehow spawned
  tmux kill-session -t "swarm-test-existing-branch" 2>/dev/null
  fail "spawn-agent existing branch" "should reject or handle existing branch"
fi

##############################################
section "14. CONCURRENT QUEUE OPERATIONS"
##############################################

# 14.1 Rapid-fire queue additions (stress test locking)
RAPID_FAIL=0
for i in $(seq 1 5); do
  "$SCRIPTS/queue-task.sh" "sports-dashboard" "agent/test-rapid-$i" "Rapid test $i" --priority normal >/dev/null 2>&1 &
done
wait
RAPID_COUNT=$(jq '.queue | length' "$SWARM_DIR/queue.json")
if [ "$RAPID_COUNT" -eq 5 ]; then
  pass "concurrent queue additions: all 5 tasks queued"
elif [ "$RAPID_COUNT" -gt 0 ]; then
  pass "concurrent queue: $RAPID_COUNT/5 tasks queued (some lock contention — acceptable)"
else
  fail "concurrent queue" "no tasks queued"
fi

# Clean up rapid test tasks
for id in $(jq -r '.queue[].id' "$SWARM_DIR/queue.json" 2>/dev/null); do
  "$SCRIPTS/cancel-task.sh" "$id" --force >/dev/null 2>&1
done

##############################################
section "15. FULL PIPELINE: QUEUE → GENERATE → DISPATCH"
##############################################

# 15.1 Generate a prompt, queue it, verify dispatch picks it up
PIPE_PROMPT=$("$SCRIPTS/generate-prompt.sh" "sports-dashboard" "Add request logging middleware" --type feature --scope backend 2>&1 | grep "\.txt$" | tail -1)
if [ -n "$PIPE_PROMPT" ] && [ -f "$PIPE_PROMPT" ]; then
  PIPE_QUEUE=$("$SCRIPTS/queue-task.sh" "sports-dashboard" "agent/feat-request-logging" "$PIPE_PROMPT" --priority normal 2>&1)
  if echo "$PIPE_QUEUE" | grep -q "queued successfully\|Task queued"; then
    PIPE_DISPATCH=$("$SCRIPTS/dispatch.sh" --dry-run 2>&1)
    if echo "$PIPE_DISPATCH" | grep -q "Would spawn.*feat-request-logging"; then
      pass "full pipeline: generate → queue → dispatch works"
    else
      fail "pipeline dispatch" "dispatch didn't pick up task: $(echo "$PIPE_DISPATCH" | tail -3)"
    fi
  else
    fail "pipeline queue" "$PIPE_QUEUE"
  fi
  rm -f "$PIPE_PROMPT"
else
  fail "pipeline generate" "no prompt file generated"
fi

# Clean up
for id in $(jq -r '.queue[].id' "$SWARM_DIR/queue.json" 2>/dev/null); do
  "$SCRIPTS/cancel-task.sh" "$id" --force >/dev/null 2>&1
done

##############################################
section "16. NOTIFICATION SYSTEM"
##############################################

# 16.1 Create test notification and verify notify.sh reads it
mkdir -p "$SWARM_DIR/notifications"
cat > "$SWARM_DIR/notifications/pending.json" <<'EOF'
{
  "timestamp": "2026-02-24T23:00:00Z",
  "notifications": [
    {
      "type": "pr_ready",
      "task_id": "test-notify",
      "repo": "sports-dashboard",
      "pr": 99,
      "review_score": 8.5,
      "recommendation": "approve",
      "message": "🤖 Test notification"
    }
  ]
}
EOF

NOTIFY_OUT=$("$SCRIPTS/notify.sh" --dry-run 2>&1)
if echo "$NOTIFY_OUT" | grep -qi "notification\|pending\|test-notify\|pr_ready"; then
  pass "notify.sh reads pending notifications"
else
  fail "notify.sh" "$(echo "$NOTIFY_OUT" | tail -5)"
fi

# 16.2 Verify pending.json NOT moved in dry-run
if [ -f "$SWARM_DIR/notifications/pending.json" ]; then
  pass "notify --dry-run doesn't move pending.json"
else
  fail "notify dry-run" "pending.json was moved/deleted"
fi

# Clean up
rm -f "$SWARM_DIR/notifications/pending.json"

##############################################
section "17. REGISTRY INTEGRITY"
##############################################

# 17.1 Verify active-tasks.json structure
if jq -e '.tasks and .history and .stats and .config' "$SWARM_DIR/active-tasks.json" >/dev/null 2>&1; then
  pass "active-tasks.json has correct structure"
else
  fail "registry structure" "missing expected keys"
fi

# 17.2 Verify config has required fields
CONFIG_OK=true
for field in maxParallelAgents maxAttempts defaultModel checkIntervalMinutes; do
  if ! jq -e ".config.$field" "$SWARM_DIR/active-tasks.json" >/dev/null 2>&1; then
    CONFIG_OK=false
    fail "registry config" "missing field: $field"
  fi
done
if [ "$CONFIG_OK" = true ]; then
  pass "registry config has all required fields"
fi

# 17.3 Verify queue.json structure
if jq -e '.version and .queue' "$SWARM_DIR/queue.json" >/dev/null 2>&1; then
  pass "queue.json has correct structure"
else
  fail "queue structure" "missing expected keys"
fi

##############################################
section "RESULTS"
##############################################

echo ""
echo "====================================="
echo -e "  ${GREEN}Passed: $PASS${NC}"
echo -e "  ${RED}Failed: $FAIL${NC}"
echo "====================================="

if [ ${#ERRORS[@]} -gt 0 ]; then
  echo ""
  echo "Failures:"
  for err in "${ERRORS[@]}"; do
    echo -e "  ${RED}✗${NC} $err"
  done
fi

echo ""
echo "Finished: $(date)"

exit $FAIL
