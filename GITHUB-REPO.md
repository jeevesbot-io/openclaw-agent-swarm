# GitHub Repository

**Repository:** https://github.com/jeevesbot-io/openclaw-agent-swarm  
**Visibility:** Public  
**License:** MIT

## Repository Structure

```
openclaw-agent-swarm/
├── README.md                  # GitHub intro (public-facing)
├── README-OPERATIONS.md       # Operational docs (how to use)
├── LICENSE                    # MIT License
├── CHANGELOG.md              # Version history
├── .gitignore                # Excludes logs, prompts, runtime state
├── active-tasks.json.example # Template for task registry
├── scripts/
│   ├── spawn-agent.sh        # Spawn Claude Code in worktree
│   ├── check-agents.sh       # Monitor active agents
│   ├── cleanup-agents.sh     # Remove completed worktrees
│   ├── respawn-agent.sh      # Retry failed agents
│   ├── test-all-fixes.sh     # Comprehensive test suite (16 tests)
│   ├── test-fixes.sh         # Initial bug tests (6 tests)
│   └── test-spawn-dryrun.sh  # End-to-end workflow test
└── docs/
    ├── PHASE0-FINAL-SUMMARY.md
    ├── PHASE0-COMPLETE.md
    ├── ALL-BUGS-FIXED.md
    ├── BUGS-FIXED.md
    └── BUGS-FOUND.md
```

## What's NOT in the Repo

For security and cleanliness:
- `logs/` - Execution logs (contain project context)
- `prompts/` - Prompt files (may contain sensitive data)
- `active-tasks.json` - Runtime state (use .example template)
- `active-tasks.lock` - File lock (runtime only)

## Git Configuration

**Branch:** main  
**Remote:** origin (https://github.com/jeevesbot-io/openclaw-agent-swarm.git)  
**Author:** Jeeves <jeeves@jeevesbot.io>  
**Local path:** `~/.openclaw/swarm/`

## Commits

### Initial commit (68a0126)
- Core scripts and test suites
- Comprehensive documentation (32KB)
- All bug fixes (12/13 bugs)
- Phase 0 complete

### docs: swap READMEs (246a807)
- README.md → README-OPERATIONS.md (operational docs)
- README-GITHUB.md → README.md (public-facing)

### chore: add LICENSE and CHANGELOG (22e5b04)
- MIT License
- CHANGELOG.md with version 0.1.0
- Roadmap for Phases 1-6

## Usage

### For others to use this system:

```bash
# Clone the repo
git clone https://github.com/jeevesbot-io/openclaw-agent-swarm.git ~/.openclaw/swarm

# Make scripts executable (should already be, but just in case)
chmod +x ~/.openclaw/swarm/scripts/*.sh

# Create runtime files from templates
cp ~/.openclaw/swarm/active-tasks.json.example ~/.openclaw/swarm/active-tasks.json
mkdir -p ~/.openclaw/swarm/{logs,prompts}

# Follow README.md for prerequisites and usage
```

### For you to sync changes:

```bash
# Pull latest changes
cd ~/.openclaw/swarm && git pull

# Push your changes
cd ~/.openclaw/swarm && git add -A && git commit -m "your message" && git push
```

## Why Public?

Made this public to:
1. Share with the OpenClaw community
2. Get contributions/feedback from others
3. Portfolio piece (shows real-world AI agent orchestration)
4. Help others building similar systems

The actual prompts, logs, and task state stay local (in .gitignore).

## Versioning

Following semantic versioning:
- **0.1.0** - Phase 0 complete (current)
- **0.2.0** - Phase 1 complete (first real agent run)
- **0.3.0** - Phase 2 complete (code reviews)
- **1.0.0** - All phases complete, production-ready for multi-repo use

## Maintenance

**Active development:** Yes (Phase 1 next)  
**Issues:** Open GitHub issues for bugs/features  
**PRs:** Welcome for bug fixes and improvements  
**Discussions:** Use GitHub Discussions for questions

---

**Repo created:** 2026-02-24  
**Total commits:** 3  
**Total files:** 18  
**Total lines:** ~2,900
