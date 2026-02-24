# OpenClaw Agent Swarm

Multi-agent coding system for spawning Claude Code agents in isolated git worktrees with automated monitoring, intelligent retries, and comprehensive error handling.

Inspired by [Elvis Sun's OpenClaw + Codex orchestration system](https://x.com/elvissun/status/2025920521871716562).

## Features

- 🔀 **Git worktree isolation** - Each agent works in its own branch
- 🖥️ **tmux session management** - Monitor agents in real-time
- 🔄 **Intelligent retries** - Auto-respawn failed agents (max 3 attempts)
- ✅ **CI validation** - Checks all CI runs before marking PR ready
- 🔍 **Stuck agent detection** - Flags agents running >60min without PR
- 🧹 **Automatic cleanup** - Removes completed worktrees and branches
- 🔒 **Atomic updates** - File locking prevents registry corruption
- 📊 **Comprehensive logging** - All script execution logged
- 💾 **Disk space protection** - Validates 1GB minimum before spawn
- 🐍 **Python + Node.js** - Auto-installs dependencies (venv + npm/pnpm)

## Architecture

```
Jeeves (Orchestrator)
  ↓
Task Registry (active-tasks.json)
  ↓
spawn-agent.sh → Git Worktree + tmux → Claude Code
  ↓
check-agents.sh → Detect PR → Validate CI
  ↓
Notify → Human Review → Merge
  ↓
cleanup-agents.sh → Remove worktree + branch
```

## Quick Start

### Prerequisites

- OpenClaw installed and configured
- Claude Code CLI authenticated (`claude --auth`)
- GitHub CLI (`gh`) authenticated
- tmux installed
- jq installed

### Installation

```bash
# Clone to OpenClaw swarm directory
git clone https://github.com/jeevesbot-io/openclaw-agent-swarm.git ~/.openclaw/swarm

# Or if already exists, initialize git
cd ~/.openclaw/swarm
git init
git remote add origin https://github.com/jeevesbot-io/openclaw-agent-swarm.git

# Make scripts executable
chmod +x scripts/*.sh

# Initialize task registry
cp active-tasks.json.example active-tasks.json
```

### Basic Usage

```bash
# 1. Create a prompt file
cat > prompts/my-task.txt << EOF
Add a comprehensive README to the repository covering:
- Setup instructions
- Architecture overview
- API documentation
- Deployment steps
EOF

# 2. Spawn an agent
scripts/spawn-agent.sh \
  my-repo \
  agent/feat-readme \
  feat-readme-$(date +%Y%m%d-%H%M%S) \
  prompts/my-task.txt

# 3. Monitor the agent
tmux attach -t swarm-feat-readme-<timestamp>

# 4. Check agent status (run periodically)
scripts/check-agents.sh

# 5. Clean up when done
scripts/cleanup-agents.sh
```

## Components

### Core Scripts

- **spawn-agent.sh** - Creates worktree and spawns Claude Code agent
- **check-agents.sh** - Monitors all active agents (deterministic, no LLM calls)
- **cleanup-agents.sh** - Removes completed worktrees and updates stats
- **respawn-agent.sh** - Retries failed agents with updated context

### Task Registry

`active-tasks.json` tracks all agent state:

```json
{
  "tasks": [
    {
      "id": "feat-readme-20260224-120000",
      "repo": "my-repo",
      "branch": "agent/feat-readme",
      "worktree": "/Users/you/projects/my-repo-worktrees/agent/feat-readme",
      "tmuxSession": "swarm-feat-readme-20260224-120000",
      "status": "running",
      "attempts": 1,
      "maxAttempts": 3,
      "pr": null
    }
  ],
  "history": [],
  "stats": {
    "totalTasks": 0,
    "successRate": 0,
    "avgCompletionMinutes": 0
  }
}
```

### Configuration

Edit `active-tasks.json` config section:

```json
{
  "config": {
    "maxParallelAgents": 2,
    "maxAttempts": 3,
    "defaultModel": "anthropic/claude-sonnet-4",
    "checkIntervalMinutes": 10,
    "notifyOnComplete": true,
    "notifyOnFailure": true,
    "notifyOnStuck": true
  }
}
```

## Monitoring

### Manual Checks

```bash
# List all active agents
tmux list-sessions | grep swarm-

# Attach to an agent
tmux attach -t swarm-<task-id>

# Check agent status
scripts/check-agents.sh

# View agent log
tail -f logs/<task-id>.log

# View registry state
cat active-tasks.json | jq .
```

### Automated Monitoring (Optional)

Set up cron to run check-agents.sh every 10 minutes:

```bash
crontab -e

# Add:
*/10 * * * * ~/.openclaw/swarm/scripts/check-agents.sh >> ~/.openclaw/swarm/logs/monitor.log 2>&1
0 3 * * * ~/.openclaw/swarm/scripts/cleanup-agents.sh >> ~/.openclaw/swarm/logs/cleanup.log 2>&1
```

## Constraints

**RAM:** System is tuned for 16GB RAM (max 2 parallel agents)

**Memory per agent:**
- Node.js + deps: ~500-1000MB
- Build/test: ~500-800MB
- Claude Code: ~300-500MB
- **Total: ~1.5-2GB per agent**

To run more parallel agents, increase `maxParallelAgents` in config (requires more RAM).

## Troubleshooting

### Worktree creation fails

```bash
# Clean up stuck worktrees
cd ~/projects/<repo>
git worktree prune
```

### tmux session won't start

```bash
# Kill all sessions (nuclear option)
tmux kill-server
```

### Agent logs not appearing

```bash
# Check permissions
ls -la ~/.openclaw/swarm/logs/
```

### Out of memory

```bash
# Check memory usage
ps aux | grep -E 'node|claude|tmux' | awk '{print $2, $3, $4, $11}' | sort -k3 -rn

# Kill agents if needed
tmux kill-session -t swarm-<task-id>
```

### Registry corruption

```bash
# Validate JSON
cat active-tasks.json | jq .

# If corrupted, restore from backup or reinitialize
cp active-tasks.json.example active-tasks.json
```

## Development

### Running Tests

```bash
# Test all bug fixes
scripts/test-all-fixes.sh

# Test spawn workflow (dry-run, doesn't spawn agent)
scripts/test-spawn-dryrun.sh
```

### Adding New Repos

The system works with any git repository. Just ensure:

1. Repo exists in `~/projects/<repo-name>`
2. Repo has a GitHub remote
3. You have push access
4. gh CLI is authenticated

## Cost Estimates

**Per agent run:** ~$2-5 (depends on task complexity)

**With 50 tasks/month:**
- Agent runs: $100-250
- Code reviews (Phase 2+): $50-100
- Monitoring: $5
- **Total: $155-355/month**

Compare to hiring a developer: $8,000-15,000/month.

## Roadmap

- [x] **Phase 0:** Foundation (scripts, worktrees, monitoring) ✅
- [ ] **Phase 1:** Single agent end-to-end
- [ ] **Phase 2:** Multi-model code reviews (Haiku/Sonnet/Opus)
- [ ] **Phase 3:** Automated monitoring + retries (cron)
- [ ] **Phase 4:** Queue management + parallel agents
- [ ] **Phase 5:** Context-aware prompts (Obsidian integration)
- [ ] **Phase 6:** Proactive work detection (scan issues/logs)

## Documentation

- `README.md` - Operational documentation (local usage)
- `PHASE0-FINAL-SUMMARY.md` - Phase 0 implementation summary
- `ALL-BUGS-FIXED.md` - Bug fixes and validation
- `BUGS-FOUND.md` - Initial bug discovery
- `BUGS-FIXED.md` - Critical/high priority fixes

## Contributing

This is a personal project for my OpenClaw setup, but PRs welcome for:

- Bug fixes
- New language support (beyond Node.js/Python)
- Better error handling
- Performance improvements

## License

MIT

## Credits

Inspired by:
- **Elvis Sun** - [OpenClaw + Codex agent swarm](https://x.com/elvissun/status/2025920521871716562)
- **Stripe Minions** - Parallel agent orchestration
- **OpenClaw** - AI agent orchestration platform

Built by [Jeeves](https://github.com/jeevesbot-io) for [Nick Solly](https://github.com/solstice035).
