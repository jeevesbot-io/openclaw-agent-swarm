# Changelog

## [1.0.0] - 2026-02-24

### 🎉 All 6 Phases Complete

Full agent swarm system built in a single session.

### Phase 0 — Foundation
- Core scripts: spawn-agent, check-agents, cleanup-agents, respawn-agent
- Task registry (active-tasks.json), git worktree isolation, tmux sessions
- 16/16 tests passing, 13 bugs found and fixed

### Phase 1 — First Real Agents
- Two successful end-to-end agent runs (README PR, predictions tests PR)
- Claude Code CLI integration verified (auth, model aliases)
- TDD test plan with 8 tests and 6 failure scenarios

### Phase 2 — Automated Code Reviews
- review-pr.sh: Multi-tier review orchestrator
- Tier 1 (Haiku) + Tier 2 (Sonnet): Claude CLI — **FREE** via Max subscription
- Tier 3 (Gemini): OpenRouter — non-Anthropic models only
- claude-review.sh + openrouter.sh reusable libraries
- Tested: 8.3-9.0/10 scores, 39-43s per review, $0 cost

### Phase 3 — Monitoring & Notifications
- monitor.sh: Full pipeline (check → review → dispatch → respawn → notify)
- notify.sh: Notification sender with dry-run support
- swarm-status.sh: Quick status overview
- Heartbeat integration documentation

### Phase 4 — Queue Management
- queue-task.sh: Priority-based task queue (high/normal/low)
- dispatch.sh: RAM-aware parallel coordination (max 2 agents)
- cancel-task.sh: Cancel queued or kill active tasks
- list-queue.sh: View queue with priority ordering

### Phase 5 — Context-Aware Prompt Generation
- generate-prompt.sh: Auto-gathers CLAUDE.md, git history, tech stack, Obsidian notes
- scan-repos.sh: Builds repos.json with auto-detected metadata
- lib/repo-context.sh: Reusable repo analysis library
- 7 repos scanned and registered

### Phase 6 — Proactive Work Detection
- scan-issues.sh: GitHub issues scanner with label filtering
- scan-deps.sh: Python + Node.js dependency update detection
- scan-todos.sh: TODO/FIXME/HACK scanner across source files
- scan-all.sh: Orchestrates all scanners (runs every 6 hours)
- State tracking to avoid re-processing

### Stats
- **28 shell scripts** in scripts/
- **~6,500 lines** of bash
- **7 repos** registered
- **3 prompt templates**
- **$0 review cost** (tiers 1+2 free via subscription)
- **Built in ~2 hours** using sub-agent parallelism
