#!/bin/bash
# generate-prompt-interactive.sh - Interactive prompt generator
# Usage: generate-prompt-interactive.sh <repo>

set -euo pipefail

# Configuration
SWARM_DIR="$HOME/.openclaw/swarm"
SCRIPTS_DIR="$SWARM_DIR/scripts"
PROJECTS_DIR="$HOME/projects"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Pretty log
log() { echo -e "${BLUE}→${NC} $*"; }
success() { echo -e "${GREEN}✓${NC} $*"; }
error() { echo -e "${RED}✗${NC} $*" >&2; }
prompt() { echo -e "${YELLOW}?${NC} $*"; }

# Usage
if [ $# -lt 1 ]; then
  cat >&2 << EOF
Usage: $0 <repo>

Interactive prompt generator for agent swarm tasks.

Examples:
  $0 sports-dashboard
  $0 MissionControls
  $0 claude_jobhunt
EOF
  exit 1
fi

REPO="$1"
REPO_PATH="$PROJECTS_DIR/$REPO"

# Validate repo exists
if [ ! -d "$REPO_PATH/.git" ]; then
  error "Repository not found: $REPO_PATH"
  echo "" >&2
  echo "Available repos in $PROJECTS_DIR:" >&2
  ls -1 "$PROJECTS_DIR" | grep -v '\..*' | head -10 >&2
  exit 1
fi

log "Interactive Prompt Generator for ${BOLD}$REPO${NC}"
echo ""

# Step 1: Task type
prompt "What type of change?"
echo "  1) feature     - New functionality"
echo "  2) bugfix      - Fix a bug"
echo "  3) test        - Add tests"
echo "  4) docs        - Documentation"
echo "  5) refactor    - Code cleanup/refactor"
echo -n "Choice [1-5]: "
read -r TYPE_CHOICE

case $TYPE_CHOICE in
  1) TYPE="feature" ;;
  2) TYPE="bugfix" ;;
  3) TYPE="test" ;;
  4) TYPE="docs" ;;
  5) TYPE="refactor" ;;
  *)
    error "Invalid choice"
    exit 1
    ;;
esac

success "Type: $TYPE"
echo ""

# Step 2: Task description
prompt "Describe the task:"
echo -n "> "
read -r TASK_DESC

if [ -z "$TASK_DESC" ]; then
  error "Task description cannot be empty"
  exit 1
fi

success "Task: $TASK_DESC"
echo ""

# Step 3: Scope
prompt "What scope?"
echo "  1) full       - Entire repository"
echo "  2) backend    - Backend code only"
echo "  3) frontend   - Frontend code only"
echo -n "Choice [1-3]: "
read -r SCOPE_CHOICE

case $SCOPE_CHOICE in
  1) SCOPE="full" ;;
  2) SCOPE="backend" ;;
  3) SCOPE="frontend" ;;
  *)
    error "Invalid choice"
    exit 1
    ;;
esac

success "Scope: $SCOPE"
echo ""

# Step 4: Branch name (auto-suggest)
BRANCH_SUFFIX=$(echo "$TASK_DESC" | tr '[:upper:]' '[:lower:]' | tr -s ' ' '-' | sed 's/[^a-z0-9-]//g' | cut -c1-40)
SUGGESTED_BRANCH="agent/${TYPE}-${BRANCH_SUFFIX}"

prompt "Branch name?"
echo "  Suggested: ${BOLD}$SUGGESTED_BRANCH${NC}"
echo -n "  Press Enter to accept, or type custom name: "
read -r BRANCH_INPUT

if [ -z "$BRANCH_INPUT" ]; then
  BRANCH="$SUGGESTED_BRANCH"
else
  # Ensure it starts with agent/
  if [[ ! "$BRANCH_INPUT" =~ ^agent/ ]]; then
    BRANCH="agent/$BRANCH_INPUT"
  else
    BRANCH="$BRANCH_INPUT"
  fi
fi

success "Branch: $BRANCH"
echo ""

# Step 5: Specific files to focus on
prompt "Any specific files to focus on? (optional, comma-separated)"
echo -n "> "
read -r FOCUS_FILES

if [ -n "$FOCUS_FILES" ]; then
  success "Will mention: $FOCUS_FILES"
  # Append to task description
  TASK_DESC="$TASK_DESC\n\nFocus on these files: $FOCUS_FILES"
fi
echo ""

# Step 6: Generate prompt
log "Generating prompt..."
PROMPT_PATH=$("$SCRIPTS_DIR/generate-prompt.sh" "$REPO" "$TASK_DESC" --type "$TYPE" --scope "$SCOPE" --branch "$BRANCH" 2>&1 | tail -1)

if [ ! -f "$PROMPT_PATH" ]; then
  error "Failed to generate prompt"
  exit 1
fi

success "Prompt generated: $PROMPT_PATH"
echo ""

# Step 7: Review
prompt "Review the prompt? [y/N]"
read -r REVIEW_CHOICE

if [[ "$REVIEW_CHOICE" =~ ^[Yy]$ ]]; then
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  cat "$PROMPT_PATH"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
fi

# Step 8: Confirm
prompt "Queue this task? [Y/n]"
read -r CONFIRM_CHOICE

if [[ "$CONFIRM_CHOICE" =~ ^[Nn]$ ]]; then
  log "Prompt saved but not queued"
  echo ""
  echo "To queue manually:"
  echo "  $SCRIPTS_DIR/queue-task.sh $REPO $BRANCH $PROMPT_PATH"
  exit 0
fi

# Step 9: Priority
prompt "Priority? [1=high, 2=normal, 3=low, default=2]"
echo -n "Choice: "
read -r PRIORITY_CHOICE

case $PRIORITY_CHOICE in
  1) PRIORITY="high" ;;
  3) PRIORITY="low" ;;
  *) PRIORITY="normal" ;;
esac

# Queue the task
log "Queueing task with priority: $PRIORITY..."
"$SCRIPTS_DIR/queue-task.sh" "$REPO" "$BRANCH" "$PROMPT_PATH" --priority "$PRIORITY"

if [ $? -eq 0 ]; then
  echo ""
  success "Task queued successfully!"
  echo ""
  echo "Next steps:"
  echo "  - Monitor queue:  cat $SWARM_DIR/queue.json | jq '.queue'"
  echo "  - Process queue:  $SCRIPTS_DIR/process-queue.sh"
  echo "  - Check agents:   $SCRIPTS_DIR/check-agents.sh"
else
  error "Failed to queue task"
  exit 1
fi

exit 0
