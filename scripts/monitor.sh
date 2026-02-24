#!/bin/bash
# monitor.sh — Swarm monitoring orchestrator (called by cron every 5-10 min)
# Checks agents → triggers reviews → respawns failures → sends notifications

set -euo pipefail

# --- Configuration ---
SWARM_DIR="$HOME/.openclaw/swarm"
REGISTRY="$SWARM_DIR/active-tasks.json"
SCRIPTS_DIR="$SWARM_DIR/scripts"
NOTIFICATIONS_DIR="$SWARM_DIR/notifications"
NOTIFICATIONS_FILE="$NOTIFICATIONS_DIR/pending.json"
LOG_FILE="$SWARM_DIR/logs/monitor-$(date +%Y%m%d-%H%M%S).log"

# Dry-run mode (skip actual actions)
DRY_RUN=false
if [ "${1:-}" = "--dry-run" ]; then
  DRY_RUN=true
  echo "DRY RUN MODE - No actual actions will be taken"
fi

# --- Logging ---
mkdir -p "$(dirname "$LOG_FILE")"
exec 1> >(tee -a "$LOG_FILE")
exec 2>&1

log() { echo "[$(date +%H:%M:%S)] $*"; }

log "=== Swarm Monitor Started ==="

# --- Error handling ---
trap 'log "ERROR: Monitor failed at line $LINENO"; exit 1' ERR

# --- 1. Run check-agents.sh ---
log "Running check-agents.sh..."
CHECK_EXIT=0
"$SCRIPTS_DIR/check-agents.sh" || CHECK_EXIT=$?

case $CHECK_EXIT in
  0)  log "All agents healthy" ;;
  10) log "Agents need attention (review/stuck/failed)" ;;
  11) log "Agents need respawning" ;;
  *)  log "WARNING: check-agents.sh failed with exit code $CHECK_EXIT" ;;
esac

# If check-agents.sh failed catastrophically, bail out
if [ $CHECK_EXIT -gt 11 ]; then
  log "ERROR: check-agents.sh failed, aborting monitor run"
  exit 1
fi

# --- 2. Parse registry for tasks needing action ---
if [ ! -f "$REGISTRY" ]; then
  log "ERROR: Registry not found at $REGISTRY"
  exit 1
fi

TASK_COUNT=$(jq -r '.tasks | length' "$REGISTRY" 2>/dev/null || echo "0")
log "Found $TASK_COUNT task(s) in registry"

if [ "$TASK_COUNT" = "0" ]; then
  log "No tasks to monitor, exiting"
  exit 0
fi

# Initialize notifications array
declare -a NOTIFICATIONS=()

# --- 3. Review PRs that haven't been reviewed yet ---
log "Checking for PRs needing review..."
NEEDS_REVIEW=$(jq -r '[.tasks[] | select(.status == "pr_created" or .status == "ready_for_review") | select(.checks.reviewed != true)] | length' "$REGISTRY")
log "Found $NEEDS_REVIEW PR(s) needing review"

if [ "$NEEDS_REVIEW" -gt 0 ]; then
  # Get indices of tasks needing review
  REVIEW_INDICES=$(jq -r '[.tasks | to_entries[] | select(.value.status == "pr_created" or .value.status == "ready_for_review") | select(.value.checks.reviewed != true) | .key] | .[]' "$REGISTRY")
  
  for idx in $REVIEW_INDICES; do
    TASK=$(jq -r ".tasks[$idx]" "$REGISTRY")
    TASK_ID=$(echo "$TASK" | jq -r '.id')
    REPO=$(echo "$TASK" | jq -r '.repo')
    PR_NUM=$(echo "$TASK" | jq -r '.pr')
    
    log "Reviewing PR #$PR_NUM in $REPO (task: $TASK_ID)..."
    
    if [ "$DRY_RUN" = true ]; then
      log "[DRY-RUN] Would run: review-pr.sh $REPO $PR_NUM --tier 1,2 --post-comment --json"
      # Mock review result for dry-run
      REVIEW_SCORE="8.5"
      RECOMMENDATION="approve"
    else
      # Run review-pr.sh and capture JSON output
      REVIEW_RESULT=$("$SCRIPTS_DIR/review-pr.sh" "$REPO" "$PR_NUM" --tier 1,2 --post-comment --json 2>&1) || {
        log "WARNING: Review failed for PR #$PR_NUM, continuing..."
        continue
      }
      
      # Extract score and recommendation from JSON
      REVIEW_SCORE=$(echo "$REVIEW_RESULT" | jq -r '.overall_score // 0')
      RECOMMENDATION=$(echo "$REVIEW_RESULT" | jq -r '.recommendation // "unknown"')
    fi
    
    log "Review complete: score=$REVIEW_SCORE, recommendation=$RECOMMENDATION"
    
    # Update registry with review results
    TEMP_REGISTRY=$(mktemp)
    jq "(.tasks[$idx].checks.reviewed) = true | 
        (.tasks[$idx].checks.reviewScore) = $REVIEW_SCORE | 
        (.tasks[$idx].checks.reviewRecommendation) = \"$RECOMMENDATION\" |
        (.tasks[$idx].checks.reviewedAt) = $(date +%s)000" "$REGISTRY" > "$TEMP_REGISTRY"
    
    if [ "$DRY_RUN" = false ]; then
      mv "$TEMP_REGISTRY" "$REGISTRY"
    else
      rm "$TEMP_REGISTRY"
    fi
    
    # Add notification
    PR_URL="https://github.com/jeevesbot-io/$REPO/pull/$PR_NUM"
    NOTIFICATION=$(jq -n \
      --arg type "pr_ready" \
      --arg task_id "$TASK_ID" \
      --arg repo "$REPO" \
      --argjson pr "$PR_NUM" \
      --argjson score "$REVIEW_SCORE" \
      --arg recommendation "$RECOMMENDATION" \
      --arg message "🤖 PR #$PR_NUM ready for review\n📊 Score: $REVIEW_SCORE/10 ($RECOMMENDATION)\n🔗 $PR_URL" \
      '{type: $type, task_id: $task_id, repo: $repo, pr: $pr, review_score: $score, recommendation: $recommendation, message: $message}')
    
    NOTIFICATIONS+=("$NOTIFICATION")
  done
fi

# --- 4. Check for stuck agents ---
log "Checking for stuck agents..."
STUCK_COUNT=$(jq -r '[.tasks[] | select(.status == "stuck") | select(.checks.notified != true)] | length' "$REGISTRY")
log "Found $STUCK_COUNT stuck agent(s)"

if [ "$STUCK_COUNT" -gt 0 ]; then
  STUCK_INDICES=$(jq -r '[.tasks | to_entries[] | select(.value.status == "stuck") | select(.value.checks.notified != true) | .key] | .[]' "$REGISTRY")
  
  for idx in $STUCK_INDICES; do
    TASK=$(jq -r ".tasks[$idx]" "$REGISTRY")
    TASK_ID=$(echo "$TASK" | jq -r '.id')
    REPO=$(echo "$TASK" | jq -r '.repo')
    BRANCH=$(echo "$TASK" | jq -r '.branch')
    START_TIME=$(echo "$TASK" | jq -r '.startedAt')
    CURRENT_TIME=$(date +%s)000
    ELAPSED_MINUTES=$(( (CURRENT_TIME - START_TIME) / 60000 ))
    
    log "Agent stuck: $TASK_ID (running for ${ELAPSED_MINUTES}min)"
    
    # Add notification
    NOTIFICATION=$(jq -n \
      --arg type "agent_stuck" \
      --arg task_id "$TASK_ID" \
      --arg repo "$REPO" \
      --arg branch "$BRANCH" \
      --argjson elapsed "$ELAPSED_MINUTES" \
      --arg message "⚠️ Agent stuck: $TASK_ID (running >${ELAPSED_MINUTES}min)\n📦 Repo: $REPO\n🌿 Branch: $BRANCH" \
      '{type: $type, task_id: $task_id, repo: $repo, branch: $branch, elapsed_minutes: $elapsed, message: $message}')
    
    NOTIFICATIONS+=("$NOTIFICATION")
    
    # Mark as notified
    TEMP_REGISTRY=$(mktemp)
    jq "(.tasks[$idx].checks.notified) = true" "$REGISTRY" > "$TEMP_REGISTRY"
    
    if [ "$DRY_RUN" = false ]; then
      mv "$TEMP_REGISTRY" "$REGISTRY"
    else
      rm "$TEMP_REGISTRY"
    fi
  done
fi

# --- 5. Check for permanently failed agents ---
log "Checking for permanently failed agents..."
FAILED_COUNT=$(jq -r '[.tasks[] | select(.status == "failed_max_attempts") | select(.checks.notified != true)] | length' "$REGISTRY")
log "Found $FAILED_COUNT permanently failed agent(s)"

if [ "$FAILED_COUNT" -gt 0 ]; then
  FAILED_INDICES=$(jq -r '[.tasks | to_entries[] | select(.value.status == "failed_max_attempts") | select(.value.checks.notified != true) | .key] | .[]' "$REGISTRY")
  
  for idx in $FAILED_INDICES; do
    TASK=$(jq -r ".tasks[$idx]" "$REGISTRY")
    TASK_ID=$(echo "$TASK" | jq -r '.id')
    REPO=$(echo "$TASK" | jq -r '.repo')
    ATTEMPTS=$(echo "$TASK" | jq -r '.attempts')
    MAX_ATTEMPTS=$(echo "$TASK" | jq -r '.maxAttempts')
    
    log "Agent failed permanently: $TASK_ID (${ATTEMPTS}/${MAX_ATTEMPTS} attempts)"
    
    # Add notification
    NOTIFICATION=$(jq -n \
      --arg type "agent_failed" \
      --arg task_id "$TASK_ID" \
      --arg repo "$REPO" \
      --argjson attempts "$ATTEMPTS" \
      --argjson max_attempts "$MAX_ATTEMPTS" \
      --arg message "❌ Agent failed permanently: $TASK_ID\n📦 Repo: $REPO\n🔄 Attempts: ${ATTEMPTS}/${MAX_ATTEMPTS}" \
      '{type: $type, task_id: $task_id, repo: $repo, attempts: $attempts, max_attempts: $max_attempts, message: $message}')
    
    NOTIFICATIONS+=("$NOTIFICATION")
    
    # Mark as notified
    TEMP_REGISTRY=$(mktemp)
    jq "(.tasks[$idx].checks.notified) = true" "$REGISTRY" > "$TEMP_REGISTRY"
    
    if [ "$DRY_RUN" = false ]; then
      mv "$TEMP_REGISTRY" "$REGISTRY"
    else
      rm "$TEMP_REGISTRY"
    fi
  done
fi

# --- 6. Respawn failed agents ---
log "Checking for agents needing respawn..."
RESPAWN_COUNT=$(jq -r '[.tasks[] | select(.needsRespawn == true)] | length' "$REGISTRY")
log "Found $RESPAWN_COUNT agent(s) needing respawn"

if [ "$RESPAWN_COUNT" -gt 0 ]; then
  RESPAWN_TASKS=$(jq -r '[.tasks[] | select(.needsRespawn == true) | .id] | .[]' "$REGISTRY")
  
  for TASK_ID in $RESPAWN_TASKS; do
    TASK=$(jq -r ".tasks[] | select(.id == \"$TASK_ID\")" "$REGISTRY")
    ATTEMPTS=$(echo "$TASK" | jq -r '.attempts')
    MAX_ATTEMPTS=$(echo "$TASK" | jq -r '.maxAttempts')
    
    log "Respawning agent: $TASK_ID (attempt $ATTEMPTS/$MAX_ATTEMPTS)..."
    
    if [ "$DRY_RUN" = true ]; then
      log "[DRY-RUN] Would run: respawn-agent.sh $TASK_ID"
    else
      "$SCRIPTS_DIR/respawn-agent.sh" "$TASK_ID" || {
        log "WARNING: Respawn failed for $TASK_ID, continuing..."
        continue
      }
    fi
    
    # Add notification
    NOTIFICATION=$(jq -n \
      --arg type "agent_respawned" \
      --arg task_id "$TASK_ID" \
      --argjson attempt "$ATTEMPTS" \
      --argjson max_attempts "$MAX_ATTEMPTS" \
      --arg message "🔄 Agent respawned: $TASK_ID (attempt $ATTEMPTS/$MAX_ATTEMPTS)" \
      '{type: $type, task_id: $task_id, attempt: $attempt, max_attempts: $max_attempts, message: $message}')
    
    NOTIFICATIONS+=("$NOTIFICATION")
  done
fi

# --- 7. Write notifications ---
if [ ${#NOTIFICATIONS[@]} -gt 0 ]; then
  log "Writing ${#NOTIFICATIONS[@]} notification(s) to $NOTIFICATIONS_FILE"
  
  # Build notifications JSON
  NOTIFICATIONS_JSON=$(printf '%s\n' "${NOTIFICATIONS[@]}" | jq -s '.')
  NOTIFICATION_PAYLOAD=$(jq -n \
    --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --argjson notifications "$NOTIFICATIONS_JSON" \
    '{timestamp: $timestamp, notifications: $notifications}')
  
  if [ "$DRY_RUN" = true ]; then
    log "[DRY-RUN] Would write notifications:"
    echo "$NOTIFICATION_PAYLOAD" | jq '.'
  else
    mkdir -p "$NOTIFICATIONS_DIR"
    echo "$NOTIFICATION_PAYLOAD" | jq '.' > "$NOTIFICATIONS_FILE"
    log "Notifications written to $NOTIFICATIONS_FILE"
  fi
else
  log "No notifications to send"
fi

log "=== Swarm Monitor Complete ==="
exit 0
