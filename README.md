# Agent Swarm - Multi-Agent Coding System

**Status:** Phase 0 Complete (Foundation)  
**Created:** 2026-02-24  
**Inspired by:** Elvis Sun's OpenClaw + Codex/Claude Code orchestration

## Overview

This is a multi-agent coding system where Jeeves orchestrates Claude Code agents running in parallel git worktrees with automated testing, multi-model code review, and intelligent monitoring.

## Architecture

```
Jeeves (Orchestrator)
  ↓
Task Registry (active-tasks.json)
  ↓
Spawn Agent → Git Worktree + tmux Session → Claude Code
  ↓
Monitor (check-agents.sh) → Detect PR creation → Trigger Reviews
  ↓
Notify Nick → Review → Merge
  ↓
Cleanup (cleanup-agents.sh) → Remove worktree + branch
```

## Directory Structure

```
~/.openclaw/swarm/
├── README.md                 # This file
├── active-tasks.json         # Task registry (state)
├── scripts/
│   ├── spawn-agent.sh       # Create worktree + spawn agent
│   ├── check-agents.sh      # Monitor agents (cron)
│   ├── cleanup-agents.sh    # Remove completed worktrees
│   └── respawn-agent.sh     # Retry failed agents
├── prompts/
│   └── <task-id>.txt        # Generated prompts
└── logs/
    └── <task-id>.log        # Agent execution logs
```

## Task Registry Schema

See `active-tasks.json` for the full schema. Key fields:

- `tasks[]` - Active agent tasks
- `history[]` - Completed tasks (moved by cleanup)
- `stats{}` - Success rate, avg completion time, total cost
- `config{}` - System configuration (max parallel agents, retry limits, etc.)

## Scripts

### spawn-agent.sh

Creates a git worktree and spawns a Claude Code agent in a tmux session.

**Usage:**
```bash
~/.openclaw/swarm/scripts/spawn-agent.sh <repo> <branch> <task-id> <prompt-file>
```

**Example:**
```bash
~/.openclaw/swarm/scripts/spawn-agent.sh \
  sports-dashboard \
  agent/feat-match-predictions \
  feat-match-predictions-20260224-190000 \
  ~/.openclaw/swarm/prompts/feat-match-predictions-20260224-190000.txt
```

**What it does:**
1. Creates worktree in `~/projects/<repo>-worktrees/<branch>`
2. Installs dependencies (npm/pnpm or Python venv)
3. Spawns tmux session `swarm-<task-id>`
4. Launches Claude Code with the prompt
5. Logs everything to `~/.openclaw/swarm/logs/<task-id>.log`

### check-agents.sh

Monitors all active agents. **Deterministic and token-efficient** - no LLM calls.

**Runs via cron:** Every 10 minutes

**What it checks:**
- Is tmux session still alive?
- Has a PR been created?
- What's the CI status?
- Is the agent stuck (>60min without PR)?

**Exit codes:**
- `0` - All good, no action needed
- `10` - Needs human attention (PR ready, stuck, or failed)
- `11` - Needs respawn (failed but < max attempts)

**Usage:**
```bash
~/.openclaw/swarm/scripts/check-agents.sh
```

### cleanup-agents.sh

Removes worktrees, tmux sessions, and local branches for completed tasks.

**What it cleans:**
- Tasks with status: `completed`, `pr_merged`, `failed_max_attempts`

**Updates:**
- Moves tasks from `tasks[]` to `history[]`
- Recalculates success rate and avg completion time

**Usage:**
```bash
~/.openclaw/swarm/scripts/cleanup-agents.sh
```

### respawn-agent.sh

Retries a failed agent with updated context and failure analysis.

**What it does:**
1. Kills existing tmux session
2. Removes existing worktree
3. Analyzes previous log for errors
4. Creates updated prompt with failure context
5. Spawns new agent
6. Updates registry (increments attempt count)

**Usage:**
```bash
~/.openclaw/swarm/scripts/respawn-agent.sh <task-id>
```

## Constraints

**RAM:** 16GB Mac mini limits us to **2 agents in parallel**.

**Memory per agent (estimated):**
- Node.js process: ~200-400MB
- Dependencies: ~300-500MB
- Build/test: ~500-800MB
- Claude Code runtime: ~300-500MB
- **Total: ~1.5-2GB per agent**

**Safe operating range:** 2 agents + Jeeves + OS/apps = 8-10GB used, leaves 6-8GB buffer.

## Repositories in Scope

| Repo | Priority | Branch |
|------|----------|--------|
| sports-dashboard | High | dev |
| MissionControls | High | main |
| claude_jobhunt | High | feature/openclaw-agents-phase1-3 |
| footballdash | Medium | main |
| the-foundry | Medium | main |
| schoolEmailsMaster | Low | main |

**Excluded:** `booklore`, `karakeep` (third-party), `foundry-showcase`, `abhi-mission-control` (forks/duplicates)

## Configuration Decisions

1. **GitHub auth:** Use existing `gh` CLI
2. **Branch naming:** `agent/feat-*` (clear distinction from manual branches)
3. **Auto-merge:** Always manual (Nick reviews everything)
4. **Model selection:** Always Sonnet for now (consistency)
5. **Notifications:** Only when PR ready or agent stuck (reduce noise)
6. **War Room:** Runs parallel (adds tasks to queue)

## Cost Projections

### Monthly Operating (Steady State)
- Agent runs: $100-250/month (50 tasks @ $2-5 each)
- Code reviews: $50-100/month (50 PRs @ $1-2 each)
- Monitoring: $5/month
- **Total: $155-355/month**

### Implementation Cost
- **Phase 0 (Foundation):** $0 (Jeeves only, no agents spawned)
- **Phase 1-6:** $63-115 over 7-8 weeks

## Phase 0 Status: ✅ COMPLETE

**Completed tasks:**
- [x] Create directory structure
- [x] Initialize task registry JSON
- [x] Write spawn-agent.sh
- [x] Write check-agents.sh
- [x] Write cleanup-agents.sh
- [x] Write respawn-agent.sh
- [x] Make scripts executable
- [x] Test git worktree creation (sports-dashboard)
- [x] Test tmux session management
- [x] Document system (this README)

**Ready for Phase 1:** Spawn first agent for real task

## Next Steps (Phase 1)

**Goal:** Complete one task end-to-end with a single agent.

**Tasks:**
1. Pick simple task (e.g., "add comprehensive README to sports-dashboard")
2. Generate prompt with Jeeves
3. Spawn agent manually
4. Monitor in tmux
5. Wait for PR
6. Manual review and merge
7. Cleanup worktree
8. Document learnings

**Estimated time:** 10-15 hours  
**Estimated cost:** $5-10

## Troubleshooting

### Worktree creation fails
```bash
# Clean up stuck worktrees
cd ~/projects/<repo>
git worktree prune
```

### tmux session won't start
```bash
# Kill stuck sessions
tmux kill-server  # Nuclear option, kills ALL sessions
```

### Agent logs not appearing
```bash
# Check log file permissions
ls -la ~/.openclaw/swarm/logs/
```

### Out of memory
```bash
# Check current usage
ps aux | grep -E 'node|claude|tmux' | awk '{print $2, $3, $4, $11}' | sort -k3 -rn | head -10

# Kill agents if needed
tmux kill-session -t swarm-<task-id>
```

## Monitoring Commands

```bash
# List all active agents
tmux list-sessions | grep swarm-

# Attach to an agent (watch it work)
tmux attach -t swarm-<task-id>

# Check agent status
~/.openclaw/swarm/scripts/check-agents.sh

# View task registry
cat ~/.openclaw/swarm/active-tasks.json | jq .

# View agent log
tail -f ~/.openclaw/swarm/logs/<task-id>.log
```

## Cron Setup (Phase 3)

**Not yet configured** - will be added in Phase 3.

Planned cron jobs:
```bash
# Check agents every 10 minutes
*/10 * * * * ~/.openclaw/swarm/scripts/check-agents.sh >> ~/.openclaw/swarm/logs/monitor.log 2>&1

# Cleanup completed tasks daily at 3am
0 3 * * * ~/.openclaw/swarm/scripts/cleanup-agents.sh >> ~/.openclaw/swarm/logs/cleanup.log 2>&1
```

---

**System ready for Phase 1 testing.**
