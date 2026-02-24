#!/bin/bash
# scan-deps.sh - Scan repos for outdated dependencies
# Usage: scan-deps.sh [--repo repo-name] [--auto-queue]

set -euo pipefail

# --- Configuration ---
SWARM_DIR="$HOME/.openclaw/swarm"
PROJECTS_DIR="$HOME/projects"
SUGGESTIONS_DIR="$SWARM_DIR/suggestions"
STATE_DIR="$SWARM_DIR/state"
SCANNED_DEPS_FILE="$STATE_DIR/scanned-deps.json"
DEPS_SUGGESTIONS_FILE="$SUGGESTIONS_DIR/deps.json"
LOG_FILE="$SWARM_DIR/logs/scan-deps-$(date +%Y%m%d-%H%M%S).log"

# Known repos
KNOWN_REPOS=("sports-dashboard" "MissionControls" "claude_jobhunt" "the-foundry")

# --- Parse arguments ---
REPO_FILTER=""
AUTO_QUEUE=false

while [ $# -gt 0 ]; do
  case $1 in
    --repo)
      REPO_FILTER=$2
      shift 2
      ;;
    --auto-queue)
      AUTO_QUEUE=true
      shift
      ;;
    *)
      echo "Usage: $0 [--repo repo-name] [--auto-queue]"
      exit 1
      ;;
  esac
done

# --- Logging ---
mkdir -p "$(dirname "$LOG_FILE")"
exec 1> >(tee -a "$LOG_FILE")
exec 2>&1

log() { echo "[$(date +%H:%M:%S)] $*"; }

log "=== Dependency Scanner Started ==="

# --- Initialize state file ---
if [ ! -f "$SCANNED_DEPS_FILE" ]; then
  echo '{"repos":{}}' > "$SCANNED_DEPS_FILE"
  log "Initialized scanned-deps.json"
fi

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
TOTAL_UPDATES=0
SECURITY_UPDATES=0
MAJOR_UPDATES=0
MINOR_UPDATES=0

for repo in "${REPOS_TO_SCAN[@]}"; do
  log "Scanning $repo..."
  
  REPO_PATH="$PROJECTS_DIR/$repo"
  cd "$REPO_PATH"
  
  # --- Python dependencies ---
  if [ -f "requirements.txt" ] || [ -f "pyproject.toml" ]; then
    log "  Checking Python dependencies..."
    
    # Check if venv exists
    VENV_PATH=""
    if [ -d ".venv" ]; then
      VENV_PATH=".venv"
    elif [ -d "venv" ]; then
      VENV_PATH="venv"
    fi
    
    if [ -n "$VENV_PATH" ]; then
      # Activate venv and check for outdated packages
      source "$VENV_PATH/bin/activate"
      
      OUTDATED_OUTPUT=$(pip list --outdated --format=json 2>/dev/null || echo "[]")
      OUTDATED_COUNT=$(echo "$OUTDATED_OUTPUT" | jq 'length')
      
      if [ "$OUTDATED_COUNT" -gt 0 ]; then
        log "    Found $OUTDATED_COUNT outdated Python package(s)"
        
        # Categorize updates
        declare -a PYTHON_SECURITY=()
        declare -a PYTHON_MAJOR=()
        declare -a PYTHON_MINOR=()
        
        for i in $(seq 0 $((OUTDATED_COUNT - 1))); do
          PACKAGE=$(echo "$OUTDATED_OUTPUT" | jq -r ".[$i].name")
          CURRENT=$(echo "$OUTDATED_OUTPUT" | jq -r ".[$i].version")
          LATEST=$(echo "$OUTDATED_OUTPUT" | jq -r ".[$i].latest_version")
          
          # Parse versions
          CURRENT_MAJOR=$(echo "$CURRENT" | cut -d. -f1)
          LATEST_MAJOR=$(echo "$LATEST" | cut -d. -f1)
          
          UPDATE_TYPE="patch"
          PRIORITY="normal"
          
          if [ "$CURRENT_MAJOR" != "$LATEST_MAJOR" ]; then
            UPDATE_TYPE="major"
            PRIORITY="low"
            PYTHON_MAJOR+=("{\"package\":\"$PACKAGE\",\"current\":\"$CURRENT\",\"latest\":\"$LATEST\",\"type\":\"major\"}")
            MAJOR_UPDATES=$((MAJOR_UPDATES + 1))
          else
            UPDATE_TYPE="minor"
            PRIORITY="normal"
            PYTHON_MINOR+=("{\"package\":\"$PACKAGE\",\"current\":\"$CURRENT\",\"latest\":\"$LATEST\",\"type\":\"minor\"}")
            MINOR_UPDATES=$((MINOR_UPDATES + 1))
          fi
          
          TOTAL_UPDATES=$((TOTAL_UPDATES + 1))
        done
        
        # Generate suggestions for batched updates
        if [ ${#PYTHON_MINOR[@]} -gt 0 ]; then
          UPDATES_JSON=$(printf '%s\n' "${PYTHON_MINOR[@]}" | jq -s '.')
          
          SUGGESTION=$(jq -n \
            --arg source "dependency-update" \
            --arg repo "$repo" \
            --arg scope "backend" \
            --argjson updates "$UPDATES_JSON" \
            --arg suggestedBranch "agent/deps-python-minor-updates" \
            --arg suggestedPriority "normal" \
            --arg suggestedType "deps" \
            --arg title "Update Python dependencies (${#PYTHON_MINOR[@]} packages)" \
            --arg description "Batch update for Python minor/patch versions" \
            --arg detectedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
            '{
              source: $source,
              repo: $repo,
              scope: $scope,
              title: $title,
              description: $description,
              suggestedBranch: $suggestedBranch,
              suggestedPriority: $suggestedPriority,
              suggestedType: $suggestedType,
              metadata: {
                updates: $updates
              },
              detectedAt: $detectedAt
            }')
          
          SUGGESTIONS+=("$SUGGESTION")
          log "    ✓ Added Python minor updates suggestion (${#PYTHON_MINOR[@]} packages)"
        fi
        
        if [ ${#PYTHON_MAJOR[@]} -gt 0 ]; then
          UPDATES_JSON=$(printf '%s\n' "${PYTHON_MAJOR[@]}" | jq -s '.')
          
          SUGGESTION=$(jq -n \
            --arg source "dependency-update" \
            --arg repo "$repo" \
            --arg scope "backend" \
            --argjson updates "$UPDATES_JSON" \
            --arg suggestedBranch "agent/deps-python-major-updates" \
            --arg suggestedPriority "low" \
            --arg suggestedType "deps" \
            --arg title "Update Python dependencies - MAJOR versions (${#PYTHON_MAJOR[@]} packages)" \
            --arg description "Major version updates - requires careful testing" \
            --arg detectedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
            '{
              source: $source,
              repo: $repo,
              scope: $scope,
              title: $title,
              description: $description,
              suggestedBranch: $suggestedBranch,
              suggestedPriority: $suggestedPriority,
              suggestedType: $suggestedType,
              metadata: {
                updates: $updates
              },
              detectedAt: $detectedAt
            }')
          
          SUGGESTIONS+=("$SUGGESTION")
          log "    ✓ Added Python major updates suggestion (${#PYTHON_MAJOR[@]} packages)"
        fi
      else
        log "    All Python packages up to date"
      fi
      
      deactivate
    else
      log "    No venv found, skipping Python dependency check"
    fi
  fi
  
  # --- Node.js dependencies ---
  if [ -f "package.json" ]; then
    log "  Checking Node.js dependencies..."
    
    if [ ! -d "node_modules" ]; then
      log "    node_modules not found, skipping npm check"
    else
      # Check for outdated npm packages
      OUTDATED_JSON=$(npm outdated --json 2>/dev/null || echo "{}")
      OUTDATED_COUNT=$(echo "$OUTDATED_JSON" | jq 'keys | length')
      
      if [ "$OUTDATED_COUNT" -gt 0 ]; then
        log "    Found $OUTDATED_COUNT outdated npm package(s)"
        
        # Categorize updates
        declare -a NPM_MAJOR=()
        declare -a NPM_MINOR=()
        
        for package in $(echo "$OUTDATED_JSON" | jq -r 'keys[]'); do
          CURRENT=$(echo "$OUTDATED_JSON" | jq -r ".[\"$package\"].current")
          LATEST=$(echo "$OUTDATED_JSON" | jq -r ".[\"$package\"].latest")
          
          # Parse versions
          CURRENT_MAJOR=$(echo "$CURRENT" | cut -d. -f1)
          LATEST_MAJOR=$(echo "$LATEST" | cut -d. -f1)
          
          if [ "$CURRENT_MAJOR" != "$LATEST_MAJOR" ]; then
            NPM_MAJOR+=("{\"package\":\"$package\",\"current\":\"$CURRENT\",\"latest\":\"$LATEST\",\"type\":\"major\"}")
            MAJOR_UPDATES=$((MAJOR_UPDATES + 1))
          else
            NPM_MINOR+=("{\"package\":\"$package\",\"current\":\"$CURRENT\",\"latest\":\"$LATEST\",\"type\":\"minor\"}")
            MINOR_UPDATES=$((MINOR_UPDATES + 1))
          fi
          
          TOTAL_UPDATES=$((TOTAL_UPDATES + 1))
        done
        
        # Generate suggestions
        if [ ${#NPM_MINOR[@]} -gt 0 ]; then
          UPDATES_JSON=$(printf '%s\n' "${NPM_MINOR[@]}" | jq -s '.')
          
          SUGGESTION=$(jq -n \
            --arg source "dependency-update" \
            --arg repo "$repo" \
            --arg scope "frontend" \
            --argjson updates "$UPDATES_JSON" \
            --arg suggestedBranch "agent/deps-npm-minor-updates" \
            --arg suggestedPriority "normal" \
            --arg suggestedType "deps" \
            --arg title "Update npm dependencies (${#NPM_MINOR[@]} packages)" \
            --arg description "Batch update for npm minor/patch versions" \
            --arg detectedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
            '{
              source: $source,
              repo: $repo,
              scope: $scope,
              title: $title,
              description: $description,
              suggestedBranch: $suggestedBranch,
              suggestedPriority: $suggestedPriority,
              suggestedType: $suggestedType,
              metadata: {
                updates: $updates
              },
              detectedAt: $detectedAt
            }')
          
          SUGGESTIONS+=("$SUGGESTION")
          log "    ✓ Added npm minor updates suggestion (${#NPM_MINOR[@]} packages)"
        fi
        
        if [ ${#NPM_MAJOR[@]} -gt 0 ]; then
          UPDATES_JSON=$(printf '%s\n' "${NPM_MAJOR[@]}" | jq -s '.')
          
          SUGGESTION=$(jq -n \
            --arg source "dependency-update" \
            --arg repo "$repo" \
            --arg scope "frontend" \
            --argjson updates "$UPDATES_JSON" \
            --arg suggestedBranch "agent/deps-npm-major-updates" \
            --arg suggestedPriority "low" \
            --arg suggestedType "deps" \
            --arg title "Update npm dependencies - MAJOR versions (${#NPM_MAJOR[@]} packages)" \
            --arg description "Major version updates - requires careful testing" \
            --arg detectedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
            '{
              source: $source,
              repo: $repo,
              scope: $scope,
              title: $title,
              description: $description,
              suggestedBranch: $suggestedBranch,
              suggestedPriority: $suggestedPriority,
              suggestedType: $suggestedType,
              metadata: {
                updates: $updates
              },
              detectedAt: $detectedAt
            }')
          
          SUGGESTIONS+=("$SUGGESTION")
          log "    ✓ Added npm major updates suggestion (${#NPM_MAJOR[@]} packages)"
        fi
      else
        log "    All npm packages up to date"
      fi
    fi
  fi
  
  # Update state with last scan timestamp
  TIMESTAMP=$(date +%s)
  jq --arg repo "$repo" --argjson timestamp "$TIMESTAMP" \
    '.repos[$repo] = {lastScan: $timestamp}' \
    "$SCANNED_DEPS_FILE" > "$SCANNED_DEPS_FILE.tmp"
  mv "$SCANNED_DEPS_FILE.tmp" "$SCANNED_DEPS_FILE"
done

# --- Write suggestions ---
if [ ${#SUGGESTIONS[@]} -gt 0 ]; then
  log "Writing ${#SUGGESTIONS[@]} suggestion(s) to $DEPS_SUGGESTIONS_FILE"
  
  SUGGESTIONS_JSON=$(printf '%s\n' "${SUGGESTIONS[@]}" | jq -s '.')
  PAYLOAD=$(jq -n \
    --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --argjson suggestions "$SUGGESTIONS_JSON" \
    '{timestamp: $timestamp, suggestions: $suggestions}')
  
  echo "$PAYLOAD" | jq '.' > "$DEPS_SUGGESTIONS_FILE"
else
  log "No dependency updates found"
  
  jq -n \
    --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{timestamp: $timestamp, suggestions: []}' > "$DEPS_SUGGESTIONS_FILE"
fi

# --- Summary ---
log "=== Scan Complete ==="
log "Total updates found: $TOTAL_UPDATES"
log "  Security: $SECURITY_UPDATES"
log "  Major: $MAJOR_UPDATES"
log "  Minor/patch: $MINOR_UPDATES"
log "Suggestions file: $DEPS_SUGGESTIONS_FILE"

exit 0
