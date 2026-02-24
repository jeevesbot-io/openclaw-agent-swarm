#!/bin/bash
# queue-task.sh - Add a task to the queue
# Usage: queue-task.sh <repo> <branch> <prompt-file-or-text> [--priority high|normal|low] [--id custom-id]

set -euo pipefail

# --- Configuration ---
SWARM_DIR="$HOME/.openclaw/swarm"
QUEUE_FILE="$SWARM_DIR/queue.json"
QUEUE_LOCK="$SWARM_DIR/queue.lock.d"
PROMPTS_DIR="$SWARM_DIR/prompts"
PROJECTS_DIR="$HOME/projects"

# --- Logging ---
LOG_FILE="$SWARM_DIR/logs/queue-task-$(date +%Y%m%d-%H%M%S).log"
mkdir -p "$(dirname "$LOG_FILE")"
exec 1> >(tee -a "$LOG_FILE")
exec 2>&1

log() { echo "[$(date +%H:%M:%S)] $*"; }

# --- Parse arguments ---
if [ $# -lt 3 ]; then
  echo "Usage: $0 <repo> <branch> <prompt-file-or-text> [--priority high|normal|low] [--id custom-id]"
  echo ""
  echo "Examples:"
  echo "  $0 sports-dashboard agent/feat-auth prompts/auth.txt --priority high"
  echo "  $0 MissionControls agent/fix-bug 'Fix the authentication bug' --priority normal"
  exit 1
fi

REPO=$1
BRANCH=$2
PROMPT_ARG=$3
shift 3

# Default values
PRIORITY="normal"
TASK_ID=""
QUEUED_BY="${USER:-unknown}"
ESTIMATED_MINUTES=15

# Parse optional arguments
while [ $# -gt 0 ]; do
  case $1 in
    --priority)
      PRIORITY=$2
      shift 2
      ;;
    --id)
      TASK_ID=$2
      shift 2
      ;;
    --queued-by)
      QUEUED_BY=$2
      shift 2
      ;;
    --estimate)
      ESTIMATED_MINUTES=$2
      shift 2
      ;;
    *)
      echo "ERROR: Unknown option: $1"
      exit 1
      ;;
  esac
done

# Validate priority
if [[ ! "$PRIORITY" =~ ^(high|normal|low)$ ]]; then
  echo "ERROR: Priority must be 'high', 'normal', or 'low'"
  exit 1
fi

# --- Validate repo ---
if [ ! -d "$PROJECTS_DIR/$REPO/.git" ]; then
  echo "ERROR: Repository not found at $PROJECTS_DIR/$REPO"
  exit 1
fi
log "✓ Repository exists: $PROJECTS_DIR/$REPO"

# --- Validate branch name ---
if [[ ! "$BRANCH" =~ ^agent/ ]]; then
  echo "ERROR: Branch name must start with 'agent/'"
  exit 1
fi
log "✓ Branch name valid: $BRANCH"

# --- Handle prompt (file or inline text) ---
PROMPT_PATH=""
if [ -f "$PROMPT_ARG" ]; then
  # It's a file - validate it exists
  PROMPT_PATH="$PROMPT_ARG"
  log "✓ Using prompt file: $PROMPT_PATH"
elif [ -f "$PROMPTS_DIR/$PROMPT_ARG" ]; then
  # Try in prompts/ directory
  PROMPT_PATH="$PROMPTS_DIR/$PROMPT_ARG"
  log "✓ Using prompt file: $PROMPT_PATH"
else
  # Treat as inline text - save to prompts/
  mkdir -p "$PROMPTS_DIR"
  
  # Generate filename from branch name
  BRANCH_SUFFIX=$(echo "$BRANCH" | sed 's/^agent\///')
  PROMPT_FILENAME="${BRANCH_SUFFIX}-$(date +%s).txt"
  PROMPT_PATH="$PROMPTS_DIR/$PROMPT_FILENAME"
  
  echo "$PROMPT_ARG" > "$PROMPT_PATH"
  log "✓ Saved inline prompt to: $PROMPT_PATH"
fi

# --- Generate task ID if not provided ---
if [ -z "$TASK_ID" ]; then
  BRANCH_SUFFIX=$(echo "$BRANCH" | sed 's/^agent\///')
  TASK_ID="${BRANCH_SUFFIX}-$(date +%s)"
  log "✓ Generated task ID: $TASK_ID"
else
  log "✓ Using custom task ID: $TASK_ID"
fi

# --- Acquire lock ---
LOCK_ACQUIRED=false
for i in {1..50}; do
  if mkdir "$QUEUE_LOCK" 2>/dev/null; then
    LOCK_ACQUIRED=true
    break
  fi
  sleep 0.1
done

if [ "$LOCK_ACQUIRED" = false ]; then
  echo "ERROR: Could not acquire queue lock after 5s"
  exit 1
fi

# Ensure lock is released on exit
trap "rmdir '$QUEUE_LOCK' 2>/dev/null || true" EXIT

# --- Initialize queue.json if needed ---
if [ ! -f "$QUEUE_FILE" ]; then
  echo '{"version":"1.0.0","queue":[]}' > "$QUEUE_FILE"
  log "✓ Initialized queue.json"
fi

# --- Check for duplicate task ID ---
DUPLICATE=$(jq -r --arg id "$TASK_ID" '.queue[] | select(.id == $id) | .id' "$QUEUE_FILE")
if [ -n "$DUPLICATE" ]; then
  echo "ERROR: Task ID '$TASK_ID' already exists in queue"
  exit 1
fi

# --- Add task to queue ---
TEMP_QUEUE=$(mktemp)
jq --arg id "$TASK_ID" \
   --arg repo "$REPO" \
   --arg branch "$BRANCH" \
   --arg prompt "$PROMPT_PATH" \
   --arg priority "$PRIORITY" \
   --argjson queuedAt "$(date +%s)000" \
   --arg queuedBy "$QUEUED_BY" \
   --argjson estimatedMinutes "$ESTIMATED_MINUTES" \
   '.queue += [{
     id: $id,
     repo: $repo,
     branch: $branch,
     prompt: $prompt,
     priority: $priority,
     queuedAt: $queuedAt,
     queuedBy: $queuedBy,
     estimatedMinutes: $estimatedMinutes,
     dependencies: [],
     metadata: {}
   }]' "$QUEUE_FILE" > "$TEMP_QUEUE"

if [ $? -ne 0 ]; then
  echo "ERROR: Failed to update queue (jq error)"
  rm -f "$TEMP_QUEUE"
  exit 1
fi

mv "$TEMP_QUEUE" "$QUEUE_FILE"

# --- Calculate queue position ---
# Position is based on priority (high > normal > low), then FIFO within same priority
POSITION=1
for task_priority in high normal low; do
  if [ "$task_priority" = "$PRIORITY" ]; then
    # Count tasks with same priority that were queued before this one
    BEFORE_COUNT=$(jq -r --arg priority "$PRIORITY" --argjson queuedAt "$(date +%s)000" \
      '[.queue[] | select(.priority == $priority) | select(.queuedAt < $queuedAt)] | length' "$QUEUE_FILE")
    POSITION=$((POSITION + BEFORE_COUNT))
    break
  else
    # Count all tasks with higher priority
    HIGHER_COUNT=$(jq -r --arg priority "$task_priority" \
      '[.queue[] | select(.priority == $priority)] | length' "$QUEUE_FILE")
    POSITION=$((POSITION + HIGHER_COUNT))
  fi
done

# --- Output success ---
echo "✓ Task queued successfully"
echo "  ID:       $TASK_ID"
echo "  Repo:     $REPO"
echo "  Branch:   $BRANCH"
echo "  Priority: $PRIORITY"
echo "  Position: #$POSITION in queue"
echo "  Prompt:   $PROMPT_PATH"

exit 0
