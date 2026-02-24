#!/bin/bash
# scan-issues.sh - Scan GitHub repos for actionable issues
# Usage: scan-issues.sh [--repo repo-name] [--label bug] [--limit 10] [--auto-queue]

set -euo pipefail

# --- Configuration ---
SWARM_DIR="$HOME/.openclaw/swarm"
PROJECTS_DIR="$HOME/projects"
SUGGESTIONS_DIR="$SWARM_DIR/suggestions"
STATE_DIR="$SWARM_DIR/state"
QUEUE_FILE="$SWARM_DIR/queue.json"
SCANNED_ISSUES_FILE="$STATE_DIR/scanned-issues.json"
ISSUES_SUGGESTIONS_FILE="$SUGGESTIONS_DIR/issues.json"
LOG_FILE="$SWARM_DIR/logs/scan-issues-$(date +%Y%m%d-%H%M%S).log"

# Known repos (hardcoded for now)
KNOWN_REPOS=("sports-dashboard" "MissionControls" "claude_jobhunt" "the-foundry")
REPO_OWNER="jeevesbot-io"

# Actionable labels (issues with these labels are prioritized)
ACTIONABLE_LABELS=("bug" "enhancement" "good first issue" "agent-friendly")

# --- Parse arguments ---
REPO_FILTER=""
LABEL_FILTER=""
LIMIT=20
AUTO_QUEUE=false

while [ $# -gt 0 ]; do
  case $1 in
    --repo)
      REPO_FILTER=$2
      shift 2
      ;;
    --label)
      LABEL_FILTER=$2
      shift 2
      ;;
    --limit)
      LIMIT=$2
      shift 2
      ;;
    --auto-queue)
      AUTO_QUEUE=true
      shift
      ;;
    *)
      echo "Usage: $0 [--repo repo-name] [--label bug] [--limit 10] [--auto-queue]"
      exit 1
      ;;
  esac
done

# --- Logging ---
mkdir -p "$(dirname "$LOG_FILE")"
exec 1> >(tee -a "$LOG_FILE")
exec 2>&1

log() { echo "[$(date +%H:%M:%S)] $*"; }

log "=== GitHub Issues Scanner Started ==="

# --- Initialize state file ---
if [ ! -f "$SCANNED_ISSUES_FILE" ]; then
  echo '{"scannedIssues":[]}' > "$SCANNED_ISSUES_FILE"
  log "Initialized scanned-issues.json"
fi

# --- Determine repos to scan ---
REPOS_TO_SCAN=()
if [ -n "$REPO_FILTER" ]; then
  # Check if specified repo exists
  if [ ! -d "$PROJECTS_DIR/$REPO_FILTER/.git" ]; then
    log "ERROR: Repository not found at $PROJECTS_DIR/$REPO_FILTER"
    exit 1
  fi
  REPOS_TO_SCAN=("$REPO_FILTER")
else
  # Scan all known repos
  for repo in "${KNOWN_REPOS[@]}"; do
    if [ -d "$PROJECTS_DIR/$repo/.git" ]; then
      REPOS_TO_SCAN+=("$repo")
    fi
  done
fi

log "Scanning ${#REPOS_TO_SCAN[@]} repo(s): ${REPOS_TO_SCAN[*]}"

# --- Load already scanned issues ---
SCANNED_ISSUES=$(jq -r '.scannedIssues[]' "$SCANNED_ISSUES_FILE" 2>/dev/null || echo "")

# --- Load queue to check for duplicates ---
QUEUED_ISSUE_NUMBERS=()
if [ -f "$QUEUE_FILE" ]; then
  QUEUED_ISSUE_NUMBERS=($(jq -r '.queue[] | select(.metadata.issueNumber != null) | "\(.repo)#\(.metadata.issueNumber)"' "$QUEUE_FILE" 2>/dev/null || echo ""))
fi

# --- Scan repos for issues ---
declare -a SUGGESTIONS=()
TOTAL_ISSUES=0
ACTIONABLE_COUNT=0

for repo in "${REPOS_TO_SCAN[@]}"; do
  log "Scanning $repo..."
  
  # Fetch open issues from GitHub
  GH_ARGS=(
    issue list
    --repo "$REPO_OWNER/$repo"
    --state open
    --json number,title,body,labels,assignees,createdAt
    --limit "$LIMIT"
  )
  
  # Add label filter if specified
  if [ -n "$LABEL_FILTER" ]; then
    GH_ARGS+=(--label "$LABEL_FILTER")
  fi
  
  ISSUES_JSON=$(gh "${GH_ARGS[@]}" 2>&1) || {
    log "WARNING: Failed to fetch issues for $repo, skipping..."
    continue
  }
  
  ISSUE_COUNT=$(echo "$ISSUES_JSON" | jq 'length')
  TOTAL_ISSUES=$((TOTAL_ISSUES + ISSUE_COUNT))
  log "Found $ISSUE_COUNT issue(s) in $repo"
  
  # Skip if no issues found
  if [ "$ISSUE_COUNT" -eq 0 ]; then
    continue
  fi
  
  # Process each issue
  for i in $(seq 0 $((ISSUE_COUNT - 1))); do
    ISSUE=$(echo "$ISSUES_JSON" | jq ".[$i]")
    
    ISSUE_NUMBER=$(echo "$ISSUE" | jq -r '.number')
    ISSUE_TITLE=$(echo "$ISSUE" | jq -r '.title')
    ISSUE_BODY=$(echo "$ISSUE" | jq -r '.body // ""')
    ISSUE_LABELS=$(echo "$ISSUE" | jq -r '[.labels[].name] | join(",")')
    ASSIGNEE_COUNT=$(echo "$ISSUE" | jq -r '.assignees | length')
    CREATED_AT=$(echo "$ISSUE" | jq -r '.createdAt')
    
    ISSUE_KEY="${repo}#${ISSUE_NUMBER}"
    
    # Skip if already assigned
    if [ "$ASSIGNEE_COUNT" -gt 0 ]; then
      log "  #$ISSUE_NUMBER: Already assigned, skipping"
      continue
    fi
    
    # Skip if already scanned
    if echo "$SCANNED_ISSUES" | grep -q "^$ISSUE_KEY$"; then
      log "  #$ISSUE_NUMBER: Already scanned, skipping"
      continue
    fi
    
    # Skip if already in queue
    if printf '%s\n' "${QUEUED_ISSUE_NUMBERS[@]}" | grep -q "^$ISSUE_KEY$"; then
      log "  #$ISSUE_NUMBER: Already queued, skipping"
      continue
    fi
    
    # Check if issue has actionable labels
    IS_ACTIONABLE=false
    PRIORITY="normal"
    ISSUE_TYPE="feature"
    
    for label in "${ACTIONABLE_LABELS[@]}"; do
      if echo "$ISSUE_LABELS" | grep -qi "$label"; then
        IS_ACTIONABLE=true
        
        # Set priority and type based on label
        case "$label" in
          bug)
            PRIORITY="high"
            ISSUE_TYPE="bugfix"
            ;;
          "good first issue"|"agent-friendly")
            PRIORITY="normal"
            ;;
          enhancement)
            PRIORITY="normal"
            ISSUE_TYPE="feature"
            ;;
        esac
        break
      fi
    done
    
    if [ "$IS_ACTIONABLE" = false ]; then
      log "  #$ISSUE_NUMBER: Not actionable (no matching labels), skipping"
      continue
    fi
    
    # Generate suggested branch name
    BRANCH_SUFFIX=$(echo "$ISSUE_TITLE" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | cut -c1-50)
    SUGGESTED_BRANCH="agent/${ISSUE_TYPE}-${BRANCH_SUFFIX}-${ISSUE_NUMBER}"
    
    # Generate suggestion
    ISSUE_URL="https://github.com/$REPO_OWNER/$repo/issues/$ISSUE_NUMBER"
    DESCRIPTION="GitHub Issue #$ISSUE_NUMBER: $ISSUE_TITLE"
    
    if [ ${#ISSUE_BODY} -gt 200 ]; then
      DESCRIPTION="$DESCRIPTION\n\n$(echo "$ISSUE_BODY" | head -c 200)..."
    elif [ -n "$ISSUE_BODY" ]; then
      DESCRIPTION="$DESCRIPTION\n\n$ISSUE_BODY"
    fi
    
    SUGGESTION=$(jq -n \
      --arg source "github-issue" \
      --argjson issueNumber "$ISSUE_NUMBER" \
      --arg issueTitle "$ISSUE_TITLE" \
      --arg issueUrl "$ISSUE_URL" \
      --arg repo "$repo" \
      --arg suggestedBranch "$SUGGESTED_BRANCH" \
      --arg suggestedPriority "$PRIORITY" \
      --arg suggestedType "$ISSUE_TYPE" \
      --arg title "$DESCRIPTION" \
      --arg description "$DESCRIPTION" \
      --arg detectedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      --arg labels "$ISSUE_LABELS" \
      --arg createdAt "$CREATED_AT" \
      '{
        source: $source,
        repo: $repo,
        title: $title,
        description: $description,
        suggestedBranch: $suggestedBranch,
        suggestedPriority: $suggestedPriority,
        suggestedType: $suggestedType,
        metadata: {
          issueNumber: $issueNumber,
          issueTitle: $issueTitle,
          issueUrl: $issueUrl,
          labels: $labels,
          createdAt: $createdAt
        },
        detectedAt: $detectedAt
      }')
    
    SUGGESTIONS+=("$SUGGESTION")
    ACTIONABLE_COUNT=$((ACTIONABLE_COUNT + 1))
    
    log "  ✓ #$ISSUE_NUMBER: Actionable ($ISSUE_TYPE, priority: $PRIORITY)"
    
    # Add to scanned issues
    jq --arg issue "$ISSUE_KEY" '.scannedIssues += [$issue]' "$SCANNED_ISSUES_FILE" > "$SCANNED_ISSUES_FILE.tmp"
    mv "$SCANNED_ISSUES_FILE.tmp" "$SCANNED_ISSUES_FILE"
    
    # Auto-queue if requested
    if [ "$AUTO_QUEUE" = true ]; then
      log "    Auto-queueing..."
      
      # Generate prompt
      PROMPT_TEXT="Fix GitHub Issue #$ISSUE_NUMBER: $ISSUE_TITLE

Repository: $repo
Issue URL: $ISSUE_URL
Labels: $ISSUE_LABELS

Description:
$ISSUE_BODY

## Task
1. Read the issue description carefully
2. Investigate the codebase to understand the problem
3. Implement a fix
4. Write tests if applicable
5. Create a PR with clear description linking to the issue

## Requirements
- Reference issue #$ISSUE_NUMBER in PR description
- Follow existing code style
- Add appropriate tests
- Update docs if needed"
      
      # Save prompt to file
      PROMPT_FILE="$SWARM_DIR/prompts/issue-${ISSUE_NUMBER}-${repo}-$(date +%s).txt"
      mkdir -p "$(dirname "$PROMPT_FILE")"
      echo "$PROMPT_TEXT" > "$PROMPT_FILE"
      
      # Queue task
      "$SWARM_DIR/scripts/queue-task.sh" \
        "$repo" \
        "$SUGGESTED_BRANCH" \
        "$PROMPT_FILE" \
        --priority "$PRIORITY" \
        --queued-by "scan-issues" \
        --estimate 30 || {
          log "    WARNING: Failed to queue task"
        }
    fi
  done
done

# --- Write suggestions to file ---
if [ ${#SUGGESTIONS[@]} -gt 0 ]; then
  log "Writing ${#SUGGESTIONS[@]} suggestion(s) to $ISSUES_SUGGESTIONS_FILE"
  
  SUGGESTIONS_JSON=$(printf '%s\n' "${SUGGESTIONS[@]}" | jq -s '.')
  PAYLOAD=$(jq -n \
    --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --argjson suggestions "$SUGGESTIONS_JSON" \
    '{timestamp: $timestamp, suggestions: $suggestions}')
  
  echo "$PAYLOAD" | jq '.' > "$ISSUES_SUGGESTIONS_FILE"
else
  log "No actionable issues found"
  
  # Write empty suggestions file
  jq -n \
    --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{timestamp: $timestamp, suggestions: []}' > "$ISSUES_SUGGESTIONS_FILE"
fi

# --- Summary ---
log "=== Scan Complete ==="
log "Total issues found: $TOTAL_ISSUES"
log "Actionable issues: $ACTIONABLE_COUNT"
log "Suggestions file: $ISSUES_SUGGESTIONS_FILE"

exit 0
