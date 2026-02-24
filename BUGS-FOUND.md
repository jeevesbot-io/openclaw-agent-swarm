# Bugs Found in Phase 0 Implementation

**Date:** 2026-02-24  
**Discovered during:** Validation pass before Phase 1

## Critical Bugs (Must Fix Before Testing)

### 1. Default Branch Detection Fails
**File:** `spawn-agent.sh` line 42  
**Issue:** `git symbolic-ref refs/remotes/origin/HEAD` fails on most repos
**Test output:**
```bash
$ cd ~/projects/sports-dashboard && git symbolic-ref refs/remotes/origin/HEAD
fatal: ref refs/remotes/origin/HEAD is not a symbolic ref
```

**Impact:** Script will crash immediately when trying to spawn agent  
**Fix needed:** Fallback strategy to detect default branch:
1. Try symbolic-ref
2. Fall back to `gh repo view --json defaultBranchRef`
3. Fall back to checking for main/master/dev in order
4. Fail with clear error if none found

---

### 2. Claude Code Prompt Delivery Method Wrong
**File:** `spawn-agent.sh` line 77  
**Issue:** Using stdin redirect `< $PROMPT_FILE` but claude expects prompt as argument
**Test:**
```bash
$ echo "test" | claude -p
# Doesn't read from stdin, expects: claude -p "test"
```

**Impact:** Agent will start but won't receive the prompt  
**Fix needed:** Read prompt file and pass as argument:
```bash
PROMPT=$(cat "$PROMPT_FILE")
claude --model anthropic/claude-sonnet-4 --dangerously-skip-permissions "$PROMPT"
```

**Concern:** Command line length limits for very long prompts. May need to use a different method for large prompts.

---

### 3. Retry Attempt Logic Off-By-One
**File:** `check-agents.sh` line 53  
**Issue:** Uses `-lt` (less than) instead of `-le` (less than or equal)
```bash
if [ $NEW_ATTEMPTS -lt $MAX_ATTEMPTS ]; then
```

**Impact:** If maxAttempts=3, agent only gets 2 retries (attempts 1 and 2), not 3  
**Fix needed:** Change to `-le` to allow up to and including maxAttempts

---

## High Priority Bugs (Will Cause Issues)

### 4. CI Status Check Assumes Single Check
**File:** `check-agents.sh` line 69  
**Issue:** `gh pr checks` returns array of all CI checks, not single check
```bash
CI_STATUS=$(gh pr checks "$PR_NUM" --repo "$REPO_REMOTE" --json state --jq '.[0].state' 2>/dev/null || echo "PENDING")
```

**Impact:** Only checks first CI check, ignores others. PR marked as passing even if later checks fail  
**Fix needed:** Check all CI runs and only mark passed if ALL are SUCCESS:
```bash
CI_STATUS=$(gh pr checks "$PR_NUM" --repo "$REPO_REMOTE" --json state --jq 'if all(.[]; .state == "SUCCESS") then "SUCCESS" elif any(.[]; .state == "FAILURE") then "FAILURE" else "PENDING" end' 2>/dev/null || echo "PENDING")
```

---

### 5. Remote URL Parsing Fragile
**File:** `check-agents.sh` lines 41, 64  
**Issue:** Assumes all git remotes end in `.git` and uses fragile sed regex
```bash
git remote get-url origin | sed 's/.*[:/]\([^/]*\/[^/]*\)\.git/\1/'
```

**Impact:** Breaks on URLs without .git suffix, or non-standard formats  
**Fix needed:** Use `gh` CLI for repo detection:
```bash
REPO_REMOTE=$(git -C "$HOME/projects/$REPO" remote get-url origin | sed 's|https://github.com/||' | sed 's|git@github.com:||' | sed 's|\.git$||')
```
Better yet, just use `gh repo view --json nameWithOwner --jq .nameWithOwner`

---

## Medium Priority Bugs (Edge Cases)

### 6. No Existing Worktree Check
**File:** `spawn-agent.sh`  
**Issue:** Doesn't check if worktree already exists at target path  
**Impact:** `git worktree add` will fail with cryptic error if worktree exists  
**Fix needed:** Check before creating:
```bash
if [ -d "$WORKTREE_DIR" ]; then
  echo "ERROR: Worktree already exists at $WORKTREE_DIR"
  echo "  Remove it first: git worktree remove $WORKTREE_DIR"
  exit 1
fi
```

---

### 7. Python venv Activation Doesn't Persist to tmux
**File:** `spawn-agent.sh` lines 60-70  
**Issue:** `source .venv/bin/activate` in bash script doesn't affect tmux session  
**Impact:** Claude Code running in tmux won't have venv activated, will use system Python  
**Fix needed:** Activate venv inside tmux command:
```bash
tmux send-keys -t "$TMUX_SESSION" "source .venv/bin/activate && claude ..." C-m
```

---

### 8. No Cleanup of Failed Worktree Creation
**File:** `spawn-agent.sh`  
**Issue:** If dependency install fails after worktree created, worktree is orphaned  
**Impact:** Manual cleanup needed, clutters disk  
**Fix needed:** Trap errors and cleanup on failure:
```bash
trap 'cleanup_on_error' ERR
cleanup_on_error() {
  if [ -d "$WORKTREE_DIR" ]; then
    cd "$REPO_DIR"
    git worktree remove "$WORKTREE_DIR" --force
  fi
}
```

---

### 9. Task Registry Updates Not Atomic
**File:** `check-agents.sh` throughout  
**Issue:** Multiple temp file writes could race if script runs in parallel  
**Impact:** Task registry corruption if check-agents runs overlapping  
**Fix needed:** File locking or ensure only one instance runs via lockfile

---

### 10. No Validation of jq Parsing Success
**File:** `check-agents.sh` throughout  
**Issue:** `jq` commands assume JSON structure, no error handling  
**Impact:** Silent failures if task registry schema doesn't match expectations  
**Fix needed:** Validate jq output before using:
```bash
TASK_ID=$(echo "$TASK" | jq -r '.id')
if [ -z "$TASK_ID" ] || [ "$TASK_ID" = "null" ]; then
  echo "ERROR: Failed to parse task ID"
  continue
fi
```

---

## Low Priority Issues (Polish)

### 11. Claude Code Auth Expired
**Test output:**
```bash
$ claude -p "test"
Failed to authenticate. API Error: 401 OAuth token has expired
```

**Impact:** Can't test claude commands, but this is user-level auth issue  
**Fix needed:** User needs to re-auth claude CLI (not a script bug)

---

### 12. No Disk Space Check
**File:** `spawn-agent.sh`  
**Issue:** Doesn't check available disk space before creating worktree  
**Impact:** Could fail mid-install if disk full  
**Fix needed:** Check before starting:
```bash
AVAILABLE=$(df -k "$WORKTREE_BASE" | tail -1 | awk '{print $4}')
if [ $AVAILABLE -lt 1048576 ]; then  # Less than 1GB
  echo "ERROR: Low disk space (${AVAILABLE}KB available)"
  exit 1
fi
```

---

### 13. No Logging of Script Execution
**File:** All scripts  
**Issue:** Only agent output logged, not script execution itself  
**Impact:** Hard to debug script failures  
**Fix needed:** Add script execution logging:
```bash
exec 1> >(tee -a "$HOME/.openclaw/swarm/logs/spawn-$(date +%Y%m%d-%H%M%S).log")
exec 2>&1
```

---

## Summary

**Critical bugs that prevent basic functionality:** 3  
**High priority bugs that cause incorrect behavior:** 3  
**Medium priority edge cases:** 4  
**Low priority polish issues:** 3  
**Total bugs:** 13

**Estimate to fix all critical + high priority bugs:** 2-3 hours  
**Re-testing needed:** Yes, full end-to-end test after fixes

**Recommendation:** Fix critical and high priority bugs before proceeding to Phase 1. Medium/low can be addressed as encountered.

---

**Nick was right to call this out.** Moving fast doesn't mean cutting corners on validation.
