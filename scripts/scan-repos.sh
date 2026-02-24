#!/bin/bash
# scan-repos.sh - Build/update repos.json registry
# Usage: scan-repos.sh [--repo specific-repo]

set -euo pipefail

# Configuration
SWARM_DIR="$HOME/.openclaw/swarm"
REGISTRY_FILE="$SWARM_DIR/repos.json"
PROJECTS_DIR="$HOME/projects"
LIB_DIR="$SWARM_DIR/scripts/lib"

# Source repo-context library
source "$LIB_DIR/repo-context.sh"

# Log
log() { echo "[$(date +%H:%M:%S)] $*"; }

# Parse arguments
SPECIFIC_REPO=""
if [ $# -gt 0 ]; then
  if [ "$1" = "--repo" ]; then
    SPECIFIC_REPO="$2"
  fi
fi

# Initialize or load registry
if [ ! -f "$REGISTRY_FILE" ]; then
  log "Creating new registry..."
  echo '{"version":"1.0.0","repos":{},"lastScanned":null}' > "$REGISTRY_FILE"
fi

TEMP_REGISTRY=$(mktemp)
cp "$REGISTRY_FILE" "$TEMP_REGISTRY"

# Scan function
scan_repo() {
  local repo_name="$1"
  local repo_path="$PROJECTS_DIR/$repo_name"
  
  if [ ! -d "$repo_path/.git" ]; then
    log "⊘ $repo_name - not a git repo, skipping"
    return
  fi
  
  log "→ Scanning $repo_name..."
  
  cd "$repo_path"
  
  # Gather metadata
  local default_branch=$(get_default_branch "$repo_path")
  local owner=$(get_repo_owner "$repo_path")
  local tech_stack=$(detect_tech_stack "$repo_path")
  local has_claude_md="false"
  if [ -f "CLAUDE.md" ]; then
    has_claude_md="true"
  fi
  
  # Check for Obsidian project
  local obsidian_project=""
  local obsidian_base="$HOME/Obsidian/jeeves/1-Projects"
  if [ -d "$obsidian_base" ]; then
    local project_folder=$(find "$obsidian_base" -maxdepth 1 -type d -iname "*$repo_name*" 2>/dev/null | head -1)
    if [ -n "$project_folder" ]; then
      obsidian_project=$(basename "$project_folder")
    fi
  fi
  
  # Current timestamp
  local now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  
  # Build tech stack array
  local tech_stack_json="[]"
  if [ -n "$tech_stack" ]; then
    tech_stack_json=$(echo "$tech_stack" | jq -R 'split(",") | map(select(length > 0))')
  fi
  
  # Update registry
  jq --arg name "$repo_name" \
     --arg path "$repo_path" \
     --arg branch "$default_branch" \
     --arg owner "$owner" \
     --argjson techStack "$tech_stack_json" \
     --argjson hasClaudeMd "$has_claude_md" \
     --arg obsidian "$obsidian_project" \
     --arg scanned "$now" \
     '.repos[$name] = {
       path: $path,
       defaultBranch: $branch,
       owner: $owner,
       techStack: $techStack,
       hasClaudeMd: $hasClaudeMd,
       obsidianProject: (if $obsidian == "" then null else $obsidian end),
       lastScanned: $scanned
     }' "$TEMP_REGISTRY" > "$TEMP_REGISTRY.tmp"
  
  mv "$TEMP_REGISTRY.tmp" "$TEMP_REGISTRY"
  
  log "✓ $repo_name - $owner/$repo_name [$default_branch] (${tech_stack:-none})"
}

# Scan repos
if [ -n "$SPECIFIC_REPO" ]; then
  # Scan specific repo
  scan_repo "$SPECIFIC_REPO"
else
  # Scan all repos in ~/projects/
  log "Scanning all repositories in $PROJECTS_DIR..."
  
  COUNT=0
  for dir in "$PROJECTS_DIR"/*; do
    if [ -d "$dir/.git" ]; then
      REPO_NAME=$(basename "$dir")
      scan_repo "$REPO_NAME"
      COUNT=$((COUNT + 1))
    fi
  done
  
  log "Scanned $COUNT repositories"
fi

# Update lastScanned timestamp
NOW_FINAL=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
jq --arg scanned "$NOW_FINAL" '.lastScanned = $scanned' "$TEMP_REGISTRY" > "$TEMP_REGISTRY.tmp"
mv "$TEMP_REGISTRY.tmp" "$TEMP_REGISTRY"

# Write final registry
mv "$TEMP_REGISTRY" "$REGISTRY_FILE"

log "✓ Registry updated: $REGISTRY_FILE"
log "View with: cat $REGISTRY_FILE | jq '.repos | keys'"

exit 0
