# Jeeves Integration Guide

This document describes how Jeeves orchestrates the agent swarm system.

## Overview

Jeeves acts as the **orchestrator** - spawning agents, monitoring progress, and notifying when human review is needed. The shell scripts handle the low-level operations.

## Workflow

### 1. Task Intake

**Sources:**
- War Room task queue (`http://localhost:5055/api/warroom/tasks/queue`)
- Direct Telegram requests from Nick
- Proactive work detection (Phase 6)

**Decision criteria:**
- Is this a coding task?
- Is it well-scoped?
- Which repo does it target?
- Estimated complexity (simple/medium/complex)?

### 2. Prompt Generation

**Jeeves generates comprehensive prompts including:**

```
PROJECT CONTEXT:
- Repository: <repo-name>
- Current branch: <branch>
- Purpose: <from Obsidian/MEMORY.md>

TASK:
<Clear, specific task description>

REQUIREMENTS:
- <Bullet list of requirements>
- Include tests
- Follow existing code style
- Create PR when complete

CONTEXT FILES:
<Relevant code snippets, architecture docs>

CONSTRAINTS:
- Do not modify <sensitive files>
- Stay within <directory scope>

COMPLETION CRITERIA:
- Tests pass
- PR created with description
- No linting errors
```

**Prompt is written to:** `~/.openclaw/swarm/prompts/<task-id>.txt`

### 3. Agent Spawning

**Jeeves calls spawn script via exec tool:**

```bash
~/.openclaw/swarm/scripts/spawn-agent.sh \
  <repo-name> \
  agent/<branch-name> \
  <task-id> \
  ~/.openclaw/swarm/prompts/<task-id>.txt
```

**Parameters:**
- `repo-name` - Must exist in `~/projects/`
- `branch-name` - Descriptive, prefixed with `agent/`
- `task-id` - Unique identifier (e.g., `feat-readme-20260224-193000`)
- `prompt-file` - Path to generated prompt

**Script returns:**
- Exit code 0 = success
- Outputs worktree path, tmux session, log file
- Updates `active-tasks.json` automatically

### 4. Monitoring

**Option A: Manual checks (Phase 1)**

Jeeves periodically runs:

```bash
~/.openclaw/swarm/scripts/check-agents.sh
```

**Returns:**
- Exit 0 = all agents running normally
- Exit 10 = needs attention (PR ready, stuck, or failed)
- Exit 11 = needs respawn (failed but < max attempts)

**Jeeves parses output for:**
- Tasks ready for review
- Stuck agents (>60min without PR)
- Failed agents

**Option B: Cron monitoring (Phase 3)**

Cron runs `check-agents.sh` every 10 minutes, Jeeves only responds when exit code 10/11.

### 5. Human Notification

**When PR ready (status = "ready_for_review"):**

Jeeves sends Telegram message:

```
🤖 Agent PR Ready

Task: feat-readme-20260224-193000
Repo: sports-dashboard
PR: #42
CI: ✅ All checks passed

Review: https://github.com/jeevesbot-io/sports-dashboard/pull/42
```

**When agent stuck (status = "stuck"):**

```
⚠️ Agent Stuck

Task: feat-readme-20260224-193000
Runtime: 73 minutes (no PR created)

Check log: ~/.openclaw/swarm/logs/feat-readme-20260224-193000.log
Attach: tmux attach -t swarm-feat-readme-20260224-193000
```

**When agent failed (status = "failed_max_attempts"):**

```
❌ Agent Failed

Task: feat-readme-20260224-193000
Attempts: 3/3
Last error: <from log>

Log: ~/.openclaw/swarm/logs/feat-readme-20260224-193000.log
```

### 6. Respawn Decision

**Jeeves decides whether to respawn based on:**
- Error analysis (from logs)
- Attempt count (< max)
- Whether issue is fixable (wrong direction vs. auth failure)

**If respawning:**

```bash
~/.openclaw/swarm/scripts/respawn-agent.sh <task-id>
```

**Script:**
- Analyzes previous failure
- Creates updated prompt with context
- Respawns agent in fresh worktree
- Increments attempt count

### 7. Cleanup

**After PR merged:**

Nick manually marks task complete, Jeeves updates registry:

```bash
# Update status in active-tasks.json
jq '(.tasks[] | select(.id == "<task-id>") | .status) = "completed"' \
  active-tasks.json > active-tasks.json.tmp
mv active-tasks.json.tmp active-tasks.json
```

**Then run cleanup:**

```bash
~/.openclaw/swarm/scripts/cleanup-agents.sh
```

**Script:**
- Removes worktrees
- Kills tmux sessions
- Deletes branches
- Moves tasks to history
- Updates success stats

---

## Jeeves Helper Functions

### spawn_agent(repo, branch, task_id, prompt)

```
1. Write prompt to ~/.openclaw/swarm/prompts/<task-id>.txt
2. Exec spawn-agent.sh with parameters
3. Parse output for success/failure
4. Return { success, worktree, session, log }
```

### check_agents()

```
1. Exec check-agents.sh
2. Parse exit code
3. If exit 10/11, read active-tasks.json for details
4. Return { status, tasks_ready, tasks_stuck, tasks_failed }
```

### get_agent_status(task_id)

```
1. Read active-tasks.json
2. Find task by id
3. Return task object with status, pr, checks, attempts
```

### notify_pr_ready(task_id)

```
1. Get task details from registry
2. Format Telegram message
3. Send via message tool
4. Include PR link, CI status, review instructions
```

### respawn_agent(task_id)

```
1. Exec respawn-agent.sh <task-id>
2. Script handles everything (analysis, prompt update, respawn)
3. Return { success, new_attempt_count }
```

### cleanup_completed()

```
1. Exec cleanup-agents.sh
2. Script handles removal and stats update
3. Return { cleaned_count, success_rate, avg_time }
```

---

## Phase 1 Simplified Workflow

For the first real agent run, Jeeves does this **manually** (no cron, no automation):

1. **Nick requests task** via Telegram
2. **Jeeves generates prompt** with full context
3. **Jeeves spawns agent** via spawn-agent.sh
4. **Jeeves monitors** by running check-agents.sh every 10-15 minutes
5. **When PR ready**, Jeeves notifies Nick
6. **Nick reviews and merges** manually
7. **Jeeves runs cleanup** via cleanup-agents.sh
8. **Retrospective:** What worked? What broke? What needs fixing?

**No automation yet** - just proving the workflow works end-to-end.

---

## Error Handling

### Agent spawn fails

**Jeeves checks:**
- Exit code from spawn-agent.sh
- stderr output
- Common causes: disk full, auth expired, repo not found

**Recovery:**
- Fix issue (free space, re-auth claude)
- Retry spawn

### Agent stuck

**Jeeves checks:**
- How long has it been stuck?
- tmux session still alive?
- Log file for last activity

**Recovery:**
- Attach to tmux, check what it's doing
- If truly stuck, kill and respawn
- Update prompt to focus more narrowly

### CI fails

**Jeeves checks:**
- Which CI check failed?
- Error message from gh pr checks

**Recovery:**
- Update prompt with CI failure context
- Respawn agent to fix issues

### Registry corruption

**Jeeves checks:**
- jq can parse active-tasks.json
- Task IDs are unique
- No orphaned worktrees

**Recovery:**
- Restore from backup if available
- Manually rebuild registry from active tmux sessions + worktrees

---

## Configuration

**Registry location:** `~/.openclaw/swarm/active-tasks.json`

**Key settings:**
```json
{
  "config": {
    "maxParallelAgents": 2,
    "maxAttempts": 3,
    "defaultModel": "anthropic/claude-sonnet-4",
    "checkIntervalMinutes": 10
  }
}
```

**Jeeves respects these limits** - won't spawn more than maxParallelAgents, won't respawn beyond maxAttempts.

---

## Testing

Before using in production, Jeeves should:

1. **Test spawn** - Spawn agent with trivial task, verify registry updates
2. **Test monitoring** - Run check-agents.sh, verify output parsing
3. **Test notification** - Send test Telegram message with PR link
4. **Test cleanup** - Clean up test agent, verify worktree removed
5. **Test respawn** - Simulate failure, verify respawn works

---

## Future Enhancements

### Phase 2: Multi-model reviews

Jeeves triggers reviews after PR created:

```bash
~/.openclaw/swarm/scripts/review-pr.sh <pr-number> <repo>
```

Returns reviews from Haiku/Sonnet/Opus.

### Phase 3: Automated monitoring

Cron runs check-agents.sh, only pings Jeeves on exit 10/11.

### Phase 4: Queue management

Jeeves maintains task queue, spawns agents based on priority + available slots.

### Phase 5: Context-aware prompts

Jeeves pulls context from:
- Obsidian vault
- MEMORY.md
- Git history (what worked before)
- Customer notes (if applicable)

### Phase 6: Proactive work

Jeeves scans for work:
- GitHub issues (unassigned)
- Sentry errors
- Failing CI on main branch
- Outdated dependencies

---

**This integration guide defines the contract between Jeeves and the swarm system.**
