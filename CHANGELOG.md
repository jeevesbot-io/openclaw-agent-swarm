# Changelog

All notable changes to OpenClaw Agent Swarm will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-02-24

### Added
- Initial Phase 0 implementation
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
- 13 bugs discovered during validation
- 12 bugs fixed (92% fix rate)
- All critical/high/medium/low priority issues resolved

### Documentation
- README.md - GitHub introduction
- README-OPERATIONS.md - Operational documentation
- PHASE0-FINAL-SUMMARY.md - Complete implementation details
- ALL-BUGS-FIXED.md - Bug tracking and fixes
- BUGS-FOUND.md - Initial bug discovery
- BUGS-FIXED.md - Critical/high priority fixes

### Testing
- test-all-fixes.sh - Comprehensive validation (16 tests)
- test-fixes.sh - Initial bug validation (6 tests)
- test-spawn-dryrun.sh - End-to-end workflow test

### Constraints
- Tuned for 16GB RAM (max 2 parallel agents)
- Estimated $155-355/month operating cost at steady state

## [Unreleased]

### Planned for Phase 1
- [ ] Single agent end-to-end real task
- [ ] Prompt generation integration
- [ ] Human review workflow

### Planned for Phase 2
- [ ] Multi-model code reviews (Haiku/Sonnet/Opus via OpenRouter)
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
