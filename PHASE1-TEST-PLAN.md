# Phase 1 Test Plan

**Objective:** Spawn one Claude Code agent for a real task, validate the full lifecycle.

**Approach:** TDD — define success/failure criteria first, then execute.

---

## Test 0: Auth Validation

**Given** Claude CLI is installed  
**When** we run a minimal Claude command  
**Then** it should respond without auth errors

```bash
claude -p "Reply with exactly: PHASE1_AUTH_OK" \
  --model anthropic/claude-sonnet-4 \
  --dangerously-skip-permissions 2>&1
```

**Pass:** Output contains "PHASE1_AUTH_OK"  
**Fail:** Contains "401", "expired", or "authentication_error"  
**Blocker:** Cannot proceed without this

---

## Test 1: Prompt Generation

**Given** the sports-dashboard repo exists at ~/projects/sports-dashboard  
**When** Jeeves generates a prompt  
**Then** the prompt file should:
- [ ] Exist at ~/.openclaw/swarm/prompts/<task-id>.txt
- [ ] Be >500 bytes (substantial enough)
- [ ] Be <100KB (within inline limit)
- [ ] Contain repo name
- [ ] Contain clear task description
- [ ] Contain completion criteria (including "create a PR")
- [ ] Contain branch naming instruction

**Validation:**
```bash
PROMPT=~/.openclaw/swarm/prompts/<task-id>.txt
[ -f "$PROMPT" ] && echo "EXISTS"
wc -c < "$PROMPT"  # should be 500-102400
grep -c "sports-dashboard" "$PROMPT"  # should be >0
grep -c "PR\|pull request" "$PROMPT"  # should be >0
```

---

## Test 2: Agent Spawn

**Given** prompt file exists and Claude auth is valid  
**When** spawn-agent.sh runs  
**Then:**
- [ ] Exit code 0
- [ ] Worktree created at ~/projects/sports-dashboard-worktrees/agent/<branch>
- [ ] Worktree contains repo files (not empty)
- [ ] tmux session exists (swarm-<task-id>)
- [ ] Task added to active-tasks.json with status "running"
- [ ] Log file created at ~/.openclaw/swarm/logs/<task-id>.log
- [ ] Branch exists locally

**Validation:**
```bash
# After spawn
[ -d "$WORKTREE" ] && ls "$WORKTREE" | head -5  # not empty
tmux has-session -t "swarm-$TASK_ID" 2>/dev/null && echo "SESSION_EXISTS"
jq ".tasks[] | select(.id == \"$TASK_ID\") | .status" ~/.openclaw/swarm/active-tasks.json
[ -f ~/.openclaw/swarm/logs/${TASK_ID}.log ] && echo "LOG_EXISTS"
```

---

## Test 3: Agent Execution (Observe)

**Given** agent is running in tmux  
**When** we attach to the session  
**Then:**
- [ ] Claude Code is running (not crashed)
- [ ] It's reading files / exploring the repo
- [ ] It's making progress (not stuck in a loop)
- [ ] No permission errors
- [ ] No dependency errors

**Validation (manual):**
```bash
tmux attach -t "swarm-$TASK_ID"
# Watch for ~5 minutes
# Ctrl-B D to detach
```

**Also check log:**
```bash
tail -50 ~/.openclaw/swarm/logs/${TASK_ID}.log
```

---

## Test 4: Agent Creates Commits

**Given** agent has been running for some time  
**When** we check the worktree  
**Then:**
- [ ] New files created (README.md or similar)
- [ ] Git log shows commits by the agent
- [ ] Commits have meaningful messages

**Validation:**
```bash
cd "$WORKTREE"
git log --oneline -5
git diff --stat HEAD~1 2>/dev/null
```

---

## Test 5: Agent Creates PR

**Given** agent has committed changes  
**When** it pushes and creates a PR  
**Then:**
- [ ] Branch pushed to remote
- [ ] PR created on GitHub
- [ ] PR has a description
- [ ] PR targets correct base branch (dev)
- [ ] PR is from agent/* branch

**Validation:**
```bash
gh pr list --repo jeevesbot-io/sports-dashboard --head "agent/<branch>" --json number,title,state
```

---

## Test 6: check-agents.sh Detects PR

**Given** agent has created a PR  
**When** check-agents.sh runs  
**Then:**
- [ ] Detects PR number
- [ ] Updates task status in registry
- [ ] Reports PR ready for review
- [ ] Exit code 10 (needs attention)

**Validation:**
```bash
~/.openclaw/swarm/scripts/check-agents.sh 2>&1
jq '.tasks[0] | {status, pr}' ~/.openclaw/swarm/active-tasks.json
```

---

## Test 7: Cleanup

**Given** task is complete (PR merged or closed)  
**When** cleanup-agents.sh runs  
**Then:**
- [ ] tmux session killed
- [ ] Worktree removed
- [ ] Branch deleted (local)
- [ ] Task moved to history in registry
- [ ] Stats updated

**Validation:**
```bash
~/.openclaw/swarm/scripts/cleanup-agents.sh 2>&1
tmux has-session -t "swarm-$TASK_ID" 2>/dev/null || echo "SESSION_GONE"
[ ! -d "$WORKTREE" ] && echo "WORKTREE_GONE"
jq '.history | length' ~/.openclaw/swarm/active-tasks.json  # should be 1
jq '.stats' ~/.openclaw/swarm/active-tasks.json
```

---

## Failure Scenarios to Watch For

### F1: Claude crashes on startup
- **Symptom:** tmux session exits immediately
- **Detection:** `tmux has-session` fails within 30s of spawn
- **Response:** Check log for error, fix and respawn

### F2: Claude can't find/read files
- **Symptom:** Agent asks "what files exist?" repeatedly
- **Detection:** Log shows repeated file listing
- **Response:** Check worktree has correct files, re-prompt with explicit paths

### F3: Claude goes off-task
- **Symptom:** Agent starts modifying unrelated files
- **Detection:** Git diff shows unexpected changes
- **Response:** Kill session, refine prompt, respawn

### F4: Claude can't push to remote
- **Symptom:** Git push fails (auth, permissions)
- **Detection:** Log shows push error
- **Response:** Check gh auth, verify repo permissions

### F5: Claude can't create PR
- **Symptom:** gh pr create fails
- **Detection:** Log shows PR creation error
- **Response:** Check gh CLI auth, create PR manually if needed

### F6: Agent runs forever (stuck)
- **Symptom:** >60 min runtime, no PR
- **Detection:** check-agents.sh flags as stuck
- **Response:** Attach to tmux, assess state, kill if truly stuck

---

## Task Selection

**Chosen task:** Add comprehensive README.md to sports-dashboard

**Why:**
- Documentation only — no code changes, no build risk
- Repo needs it (currently has minimal/no README)
- Easy to verify quality (read the output)
- Low cost (~$3-8 estimated)
- Good first test — exercises file creation, git, PR workflow

**What the agent should produce:**
- README.md with: project overview, setup instructions, architecture, API docs, deployment
- Clean commit history
- PR with description
- No other files modified

---

## Timing

- **Test 0 (auth):** 30 seconds
- **Test 1 (prompt):** 5 minutes (Jeeves generates)
- **Test 2 (spawn):** 2 minutes
- **Test 3 (observe):** 5-10 minutes
- **Test 4 (commits):** 15-45 minutes (agent working time)
- **Test 5 (PR):** Depends on agent completion
- **Test 6 (detection):** 2 minutes
- **Test 7 (cleanup):** 2 minutes

**Total estimated:** 30-60 minutes active, up to 2 hours wall clock

---

## Go/No-Go Checklist

Before spawning the agent:

- [ ] Test 0 passes (auth works)
- [ ] Prompt file generated and validated
- [ ] No other agents running (registry empty)
- [ ] Disk space >1GB free
- [ ] No pending changes in sports-dashboard
- [ ] Remote is accessible (gh repo view works)
