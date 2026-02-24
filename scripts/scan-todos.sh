#!/bin/bash
# scan-todos.sh - Scan source code for TODO/FIXME comments
# Usage: scan-todos.sh [--repo repo-name]

set -euo pipefail

# --- Configuration ---
SWARM_DIR="$HOME/.openclaw/swarm"
PROJECTS_DIR="$HOME/projects"
SUGGESTIONS_DIR="$SWARM_DIR/suggestions"
TODOS_SUGGESTIONS_FILE="$SUGGESTIONS_DIR/todos.json"
LOG_FILE="$SWARM_DIR/logs/scan-todos-$(date +%Y%m%d-%H%M%S).log"

# Known repos
KNOWN_REPOS=("sports-dashboard" "MissionControls" "claude_jobhunt" "the-foundry")

# Directories to exclude
EXCLUDE_DIRS=(
  "node_modules"
  ".venv"
  "venv"
  "__pycache__"
  ".git"
  "dist"
  "build"
  ".pytest_cache"
  ".mypy_cache"
  "coverage"
)

# --- Parse arguments ---
REPO_FILTER=""

while [ $# -gt 0 ]; do
  case $1 in
    --repo)
      REPO_FILTER=$2
      shift 2
      ;;
    *)
      echo "Usage: $0 [--repo repo-name]"
      exit 1
      ;;
  esac
done

# --- Logging ---
mkdir -p "$(dirname "$LOG_FILE")"
exec 1> >(tee -a "$LOG_FILE")
exec 2>&1

log() { echo "[$(date +%H:%M:%S)] $*"; }

log "=== TODO/FIXME Scanner Started ==="

# --- Determine repos to scan ---
REPOS_TO_SCAN=()
if [ -n "$REPO_FILTER" ]; then
  if [ ! -d "$PROJECTS_DIR/$REPO_FILTER/.git" ]; then
    log "ERROR: Repository not found at $PROJECTS_DIR/$REPO_FILTER"
    exit 1
  fi
  REPOS_TO_SCAN=("$REPO_FILTER")
else
  for repo in "${KNOWN_REPOS[@]}"; do
    if [ -d "$PROJECTS_DIR/$repo/.git" ]; then
      REPOS_TO_SCAN+=("$repo")
    fi
  done
fi

log "Scanning ${#REPOS_TO_SCAN[@]} repo(s): ${REPOS_TO_SCAN[*]}"

# --- Scan repos ---
declare -a SUGGESTIONS=()
TOTAL_TODOS=0
TOTAL_FIXMES=0
TOTAL_HACKS=0
TOTAL_XXXS=0

for repo in "${REPOS_TO_SCAN[@]}"; do
  log "Scanning $repo..."
  
  REPO_PATH="$PROJECTS_DIR/$repo"
  cd "$REPO_PATH"
  
  # Build grep exclude arguments
  EXCLUDE_ARGS=""
  for dir in "${EXCLUDE_DIRS[@]}"; do
    EXCLUDE_ARGS="$EXCLUDE_ARGS --exclude-dir=$dir"
  done
  
  # Run grep for each pattern type
  TODO_RESULTS=$(grep -rn "TODO" . \
    --include="*.py" --include="*.ts" --include="*.js" --include="*.vue" \
    --include="*.jsx" --include="*.tsx" --include="*.sh" \
    $EXCLUDE_ARGS 2>/dev/null || true)
  
  FIXME_RESULTS=$(grep -rn "FIXME" . \
    --include="*.py" --include="*.ts" --include="*.js" --include="*.vue" \
    --include="*.jsx" --include="*.tsx" --include="*.sh" \
    $EXCLUDE_ARGS 2>/dev/null || true)
  
  HACK_RESULTS=$(grep -rn "HACK" . \
    --include="*.py" --include="*.ts" --include="*.js" --include="*.vue" \
    --include="*.jsx" --include="*.tsx" --include="*.sh" \
    $EXCLUDE_ARGS 2>/dev/null || true)
  
  XXX_RESULTS=$(grep -rn "XXX" . \
    --include="*.py" --include="*.ts" --include="*.js" --include="*.vue" \
    --include="*.jsx" --include="*.tsx" --include="*.sh" \
    $EXCLUDE_ARGS 2>/dev/null || true)
  
  # Count results
  REPO_TODO_COUNT=0
  REPO_FIXME_COUNT=0
  REPO_HACK_COUNT=0
  REPO_XXX_COUNT=0
  
  if [ -n "$TODO_RESULTS" ]; then
    REPO_TODO_COUNT=$(echo "$TODO_RESULTS" | wc -l | tr -d ' ')
    TOTAL_TODOS=$((TOTAL_TODOS + REPO_TODO_COUNT))
  fi
  
  if [ -n "$FIXME_RESULTS" ]; then
    REPO_FIXME_COUNT=$(echo "$FIXME_RESULTS" | wc -l | tr -d ' ')
    TOTAL_FIXMES=$((TOTAL_FIXMES + REPO_FIXME_COUNT))
  fi
  
  if [ -n "$HACK_RESULTS" ]; then
    REPO_HACK_COUNT=$(echo "$HACK_RESULTS" | wc -l | tr -d ' ')
    TOTAL_HACKS=$((TOTAL_HACKS + REPO_HACK_COUNT))
  fi
  
  if [ -n "$XXX_RESULTS" ]; then
    REPO_XXX_COUNT=$(echo "$XXX_RESULTS" | wc -l | tr -d ' ')
    TOTAL_XXXS=$((TOTAL_XXXS + REPO_XXX_COUNT))
  fi
  
  # Generate suggestion if any found
  if [ $((REPO_TODO_COUNT + REPO_FIXME_COUNT + REPO_HACK_COUNT + REPO_XXX_COUNT)) -gt 0 ]; then
    # Build file list (top 10 files with most comments)
    ALL_RESULTS="$TODO_RESULTS
$FIXME_RESULTS
$HACK_RESULTS
$XXX_RESULTS"
    
    # Extract unique files and count occurrences
    FILES_WITH_COMMENTS=$(echo "$ALL_RESULTS" | grep -v '^$' | cut -d: -f1 | sort | uniq -c | sort -rn | head -10)
    
    # Build JSON array of files
    FILE_ENTRIES=()
    while IFS= read -r line; do
      if [ -n "$line" ]; then
        COUNT=$(echo "$line" | awk '{print $1}')
        FILE=$(echo "$line" | awk '{print $2}')
        FILE_ENTRIES+=("{\"file\":\"$FILE\",\"count\":$COUNT}")
      fi
    done <<< "$FILES_WITH_COMMENTS"
    
    if [ ${#FILE_ENTRIES[@]} -gt 0 ]; then
      FILES_JSON=$(printf '%s\n' "${FILE_ENTRIES[@]}" | jq -s '.')
    else
      FILES_JSON="[]"
    fi
    
    SUGGESTION=$(jq -n \
      --arg source "todo-scan" \
      --arg repo "$repo" \
      --arg title "Found $REPO_FIXME_COUNT FIXME(s), $REPO_TODO_COUNT TODO(s), $REPO_HACK_COUNT HACK(s), $REPO_XXX_COUNT XXX(s) in $repo" \
      --arg description "Code contains comments that indicate work to be done" \
      --arg detectedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      --argjson files "$FILES_JSON" \
      '{
        source: $source,
        repo: $repo,
        title: $title,
        description: $description,
        metadata: {
          todoCount: '"$REPO_TODO_COUNT"',
          fixmeCount: '"$REPO_FIXME_COUNT"',
          hackCount: '"$REPO_HACK_COUNT"',
          xxxCount: '"$REPO_XXX_COUNT"',
          files: $files
        },
        detectedAt: $detectedAt
      }')
    
    SUGGESTIONS+=("$SUGGESTION")
    log "  ✓ Found $REPO_FIXME_COUNT FIXME(s), $REPO_TODO_COUNT TODO(s), $REPO_HACK_COUNT HACK(s), $REPO_XXX_COUNT XXX(s)"
  else
    log "  No TODO/FIXME/HACK/XXX comments found"
  fi
done

# --- Write suggestions ---
if [ ${#SUGGESTIONS[@]} -gt 0 ]; then
  log "Writing ${#SUGGESTIONS[@]} suggestion(s) to $TODOS_SUGGESTIONS_FILE"
  
  SUGGESTIONS_JSON=$(printf '%s\n' "${SUGGESTIONS[@]}" | jq -s '.')
  PAYLOAD=$(jq -n \
    --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --argjson suggestions "$SUGGESTIONS_JSON" \
    '{timestamp: $timestamp, suggestions: $suggestions}')
  
  echo "$PAYLOAD" | jq '.' > "$TODOS_SUGGESTIONS_FILE"
else
  log "No TODOs/FIXMEs found"
  
  jq -n \
    --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{timestamp: $timestamp, suggestions: []}' > "$TODOS_SUGGESTIONS_FILE"
fi

# --- Summary ---
log "=== Scan Complete ==="
log "TODOs found: $TOTAL_TODOS"
log "FIXMEs found: $TOTAL_FIXMES"
log "HACKs found: $TOTAL_HACKS"
log "XXXs found: $TOTAL_XXXS"
log "Suggestions file: $TODOS_SUGGESTIONS_FILE"

exit 0
