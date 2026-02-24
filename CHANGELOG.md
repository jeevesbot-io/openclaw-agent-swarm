# Changelog

All notable changes to OpenClaw Agent Swarm will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] - 2026-02-24

### Added — Phase 1: First Real Agent Runs
- Sub-agent orchestration via OpenClaw sessions_spawn
- Two successful agent runs:
  1. README generation for sports-dashboard (PR #1) — via OpenClaw sub-agent
  2. Prediction module tests for sports-dashboard — via swarm pipeline (spawn-agent.sh → tmux → Claude Code CLI)
- PHASE1-TEST-PLAN.md — TDD test plan with 8 tests and 6 failure scenarios
- PHASE1-READY.md — Readiness confirmation after gap fixes
- JEEVES-INTEGRATION.md — Complete orchestration workflow documentation
- test-registry-integration.sh — Registry update validation

### Fixed
- **Task registry integration** (CRITICAL) — spawn-agent.sh now updates active-tasks.json
- **macOS file locking** — Replaced Linux-only flock with mkdir-based atomic locking
- **Large prompt handling** — Size detection with file-based fallback for >100KB prompts
- **Claude model names** — Corrected from `anthropic/claude-sonnet-4` (OpenRouter format) to `sonnet` alias (Claude CLI format)
- **Model version** — Updated from Sonnet 4 to Sonnet 4.6 (current)

### Key Learnings
- Claude Code CLI uses aliases (`sonnet`, `opus`, `haiku`) not `anthropic/` prefixed names
- OAuth tokens expire — need periodic `claude auth login`
- `flock` doesn't exist on macOS — use `mkdir` for atomic locking
- OpenClaw sub-agents can orchestrate swarm scripts effectively
- Prompt quality directly determines agent output quality

## [0.1.0] - 2026-02-24

### Added — Phase 0: Foundation
- Core scripts: spawn-agent, check-agents, cleanup-agents, respawn-agent
- Task registry with JSON state tracking
- Git worktree isolation per agent
- tmux session management
- Intelligent retry logic (max 3 attempts)
- CI validation (all checks must pass)
- Stuck agent detection (>60min timeout)
- Automatic cleanup with error trapping
- File locking for atomic registry updates
- Disk space validation (1GB minimum)
- Python venv + Node.js dependency support
- Comprehensive execution logging
- Test suites with 16/16 tests passing
- Comprehensive documentation (32KB across 6 files)

### Fixed
- 13 bugs discovered during validation, 12 fixed (92%)

## [Unreleased]

### Planned for Phase 2
- [ ] Multi-model code reviews (Haiku/Sonnet/Opus via OpenRouter)
- [ ] Review script (review-pr.sh)
- [ ] Review result parsing and PR comments
- [ ] Cost tracking per task

### Planned for Phase 3
- [ ] Automated monitoring via cron
- [ ] Auto-respawn on failures
- [ ] Telegram notifications integration

### Planned for Phase 4
- [ ] Queue management system
- [ ] Parallel agent coordination (respecting RAM limits)
- [ ] War Room API integration

### Planned for Phase 5
- [ ] Context-aware prompt generation
- [ ] Obsidian vault integration
- [ ] Git history analysis

### Planned for Phase 6
- [ ] Proactive work detection
- [ ] GitHub issues scanning
- [ ] Log/error monitoring
- [ ] Dependency update automation
