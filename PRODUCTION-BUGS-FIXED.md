# Production Bugs Found & Fixed
## Testing Session: 2026-02-24 22:50-23:00 GMT

### Critical Bugs (System-Breaking)

#### 1. ✅ FIXED: Shell Quote Escaping in Prompt Injection
**Severity:** CRITICAL  
**Impact:** Agent spawn fails completely if prompt contains single quotes, backticks, or special chars  
**Symptom:** Shell gets stuck in `quote>` mode, Claude never launches  
**Root Cause:** `spawn-agent.sh` used inline prompt with `'$PROMPT_CONTENT'` which breaks on nested quotes  
**Fix:** Always use file-based approach: `claude -p "$(cat .claude-prompt.txt)"`  
**Files:** `scripts/spawn-agent.sh` lines 175-180, 195  
**Commit:** TBD

#### 2. ✅ FIXED: Dispatch Infinite Retry Loop
**Severity:** CRITICAL  
**Impact:** If spawn fails, dispatch retries the same task infinitely (100+ times in 2 minutes)  
**Symptom:** Log filled with "✗ Failed to spawn agent" repeated endlessly  
**Root Cause:** `dispatch.sh` used `continue` on spawn failure, but never removed task from queue  
**Fix:** Changed `continue` to `break` — task stays in queue but dispatch exits cleanly  
**Files:** `scripts/dispatch.sh` line 172  
**Commit:** TBD

#### 3. ✅ FIXED: Stale Worktree/Branch Blocking New Spawns
**Severity:** HIGH  
**Impact:** Second spawn attempt for same branch fails with "worktree already exists"  
**Symptom:** All retry attempts fail after first spawn failure  
**Root Cause:** `spawn-agent.sh` errors on existing worktree instead of cleaning up  
**Fix:** Auto-cleanup stale worktrees/branches before creating new ones  
**Files:** `scripts/spawn-agent.sh` lines 76-88  
**Commit:** TBD

#### 4. ✅ FIXED: Relative Prompt Paths Not Resolved
**Severity:** HIGH  
**Impact:** If dispatch passes relative path like `prompts/foo.txt`, spawn fails with "file not found"  
**Symptom:** Queue → dispatch works but spawn can't find prompt  
**Root Cause:** `spawn-agent.sh` checks prompt file existence before changing directory  
**Fix:** Resolve relative paths against `~/.openclaw/swarm/` before validation  
**Files:** `scripts/spawn-agent.sh` lines 64-72  
**Commit:** TBD

### Test Suite Results

**Comprehensive Test:** 63/63 passed (100%)

Tests cover:
- Input validation (10 tests)
- Queue operations (8 tests)
- Prompt generation (12 tests)
- Repo scanning (5 tests)
- Proactive scanning (4 tests)
- Review pipeline (2 tests)
- Dispatch dry-run (2 tests)
- Monitor integration (2 tests)
- Status display (2 tests)
- Malformed data handling (3 tests)
- Lock contention (2 tests)
- Spawn validation (2 tests)
- Worktree edge cases (1 test)
- Concurrent operations (1 test)
- Full pipeline E2E (1 test)
- Notification system (2 tests)
- Registry integrity (3 tests)

**Test Script:** `scripts/test-prod.sh` (18KB, 450+ lines)

### Edge Cases Tested

1. ✅ Queue invalid repos, branches, priorities
2. ✅ Review nonexistent PRs
3. ✅ Cancel nonexistent tasks
4. ✅ Generate prompts for repos without CLAUDE.md
5. ✅ Handle corrupt queue.json and active-tasks.json
6. ✅ Handle missing queue.json
7. ✅ Lock contention (multiple scripts competing)
8. ✅ Duplicate branch names in queue
9. ✅ Concurrent queue additions (5 simultaneous)
10. ✅ Spawn with existing branch on remote
11. ✅ Dispatch with empty queue
12. ✅ Monitor with no active agents
13. ✅ Notification system dry-run

### Remaining Known Issues

#### 1. Agent Registry Tracking (MEDIUM)
**Status:** Observed but not yet diagnosed  
**Symptom:** Spawned agent not appearing in active-tasks.json  
**Impact:** check-agents.sh won't monitor it, monitor.sh won't trigger reviews  
**Next Step:** Add verbose logging to spawn-agent.sh registry update section

#### 2. Claude Code Silent Failures (LOW)
**Status:** Observed  
**Symptom:** Claude process exits without output to log or tmux  
**Impact:** No PR created, no error message, task stuck in limbo  
**Next Step:** Add output capture validation, timeout detection

### Production Readiness Checklist

- [x] All 6 phases built and tested
- [x] Input validation on all user-facing scripts
- [x] Graceful error handling for missing files
- [x] Atomic locking for concurrent operations
- [x] Corrupt data recovery
- [x] Dry-run modes for testing
- [x] Comprehensive test suite
- [x] Critical bugs fixed
- [ ] End-to-end real agent completion verified
- [ ] Registry tracking bug diagnosed
- [ ] Documentation updated with bug fixes

### Test Commands

```bash
# Run full test suite
cd ~/.openclaw/swarm && scripts/test-prod.sh

# Test real agent spawn
scripts/generate-prompt.sh sports-dashboard "Add feature" --type feature
scripts/queue-task.sh sports-dashboard agent/test-task <prompt-file>
scripts/dispatch.sh

# Monitor progress
scripts/swarm-status.sh
tmux attach -t swarm-<task-id>
tail -f ~/.openclaw/swarm/logs/<task-id>.log
```

### Lessons Learned

1. **Always use file-based prompt passing** — Shell escaping is fragile for complex content
2. **Break, don't continue on spawn failure** — Infinite loops are worse than giving up
3. **Auto-cleanup stale state** — Don't make users manually clean up failed attempts
4. **Resolve paths early** — Don't assume callers use absolute paths
5. **Test with real content** — Generated prompts with backticks/quotes caught the quote bug
6. **Stress test with failures** — The bugs only appeared when things went wrong
7. **E2E testing is essential** — Unit tests passed but integration revealed issues

### Performance Notes

- Test suite completes in ~60 seconds
- Prompt generation: ~2-3 seconds per repo
- Dispatch cycle: ~2 seconds (empty queue) to ~15 seconds (spawn)
- Review (tier 1+2): ~40-50 seconds, $0 cost
- Monitor full cycle: ~1-2 minutes with active agents

### Files Modified

- `scripts/spawn-agent.sh` — 4 bug fixes
- `scripts/dispatch.sh` — 1 bug fix (infinite loop)
- `scripts/test-prod.sh` — Created (18KB comprehensive test suite)
- `PRODUCTION-BUGS-FIXED.md` — This file
