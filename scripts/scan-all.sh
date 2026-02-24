#!/bin/bash
# scan-all.sh - Run all proactive work scanners
# Usage: scan-all.sh [--auto-queue] [--repo repo-name]

set -euo pipefail

# --- Configuration ---
SWARM_DIR="$HOME/.openclaw/swarm"
SCRIPTS_DIR="$SWARM_DIR/scripts"
SUGGESTIONS_DIR="$SWARM_DIR/suggestions"
LOG_FILE="$SWARM_DIR/logs/scan-all-$(date +%Y%m%d-%H%M%S).log"

# --- Parse arguments ---
AUTO_QUEUE=false
REPO_FILTER=""

while [ $# -gt 0 ]; do
  case $1 in
    --auto-queue)
      AUTO_QUEUE=true
      shift
      ;;
    --repo)
      REPO_FILTER=$2
      shift 2
      ;;
    *)
      echo "Usage: $0 [--auto-queue] [--repo repo-name]"
      exit 1
      ;;
  esac
done

# --- Logging ---
mkdir -p "$(dirname "$LOG_FILE")"
exec 1> >(tee -a "$LOG_FILE")
exec 2>&1

log() { echo "[$(date +%H:%M:%S)] $*"; }

log "=== Proactive Work Scanner Started ==="
echo ""
echo "🔍 Proactive Work Scan"
echo "━━━━━━━━━━━━━━━━━━━━━━"

# --- Build scanner arguments ---
SCANNER_ARGS=()
if [ -n "$REPO_FILTER" ]; then
  SCANNER_ARGS+=(--repo "$REPO_FILTER")
fi

if [ "$AUTO_QUEUE" = true ]; then
  SCANNER_ARGS+=(--auto-queue)
fi

# --- Run scan-issues.sh ---
log "Running GitHub Issues scanner..."
ISSUES_EXIT=0
if [ ${#SCANNER_ARGS[@]} -gt 0 ]; then
  "$SCRIPTS_DIR/scan-issues.sh" "${SCANNER_ARGS[@]}" || ISSUES_EXIT=$?
else
  "$SCRIPTS_DIR/scan-issues.sh" || ISSUES_EXIT=$?
fi

if [ $ISSUES_EXIT -ne 0 ]; then
  log "WARNING: Issues scanner failed with exit code $ISSUES_EXIT"
fi

# --- Run scan-deps.sh ---
log "Running Dependency scanner..."
DEPS_EXIT=0
if [ ${#SCANNER_ARGS[@]} -gt 0 ]; then
  "$SCRIPTS_DIR/scan-deps.sh" "${SCANNER_ARGS[@]}" || DEPS_EXIT=$?
else
  "$SCRIPTS_DIR/scan-deps.sh" || DEPS_EXIT=$?
fi

if [ $DEPS_EXIT -ne 0 ]; then
  log "WARNING: Dependency scanner failed with exit code $DEPS_EXIT"
fi

# --- Run scan-todos.sh ---
log "Running TODO/FIXME scanner..."
TODOS_EXIT=0

# Remove --auto-queue from args for scan-todos.sh (it doesn't support it)
TODOS_ARGS=()
if [ -n "$REPO_FILTER" ]; then
  TODOS_ARGS+=(--repo "$REPO_FILTER")
fi

if [ ${#TODOS_ARGS[@]} -gt 0 ]; then
  "$SCRIPTS_DIR/scan-todos.sh" "${TODOS_ARGS[@]}" || TODOS_EXIT=$?
else
  "$SCRIPTS_DIR/scan-todos.sh" || TODOS_EXIT=$?
fi

if [ $TODOS_EXIT -ne 0 ]; then
  log "WARNING: TODO scanner failed with exit code $TODOS_EXIT"
fi

# --- Parse results ---
ISSUES_COUNT=0
ISSUES_BUGS=0
ISSUES_ENHANCEMENTS=0

if [ -f "$SUGGESTIONS_DIR/issues.json" ]; then
  ISSUES_COUNT=$(jq -r '.suggestions | length' "$SUGGESTIONS_DIR/issues.json" 2>/dev/null || echo "0")
  
  if [ "$ISSUES_COUNT" -gt 0 ]; then
    ISSUES_BUGS=$(jq -r '[.suggestions[] | select(.suggestedType == "bugfix")] | length' "$SUGGESTIONS_DIR/issues.json" 2>/dev/null || echo "0")
    ISSUES_ENHANCEMENTS=$(jq -r '[.suggestions[] | select(.suggestedType == "feature")] | length' "$SUGGESTIONS_DIR/issues.json" 2>/dev/null || echo "0")
  fi
fi

DEPS_COUNT=0
DEPS_SECURITY=0
DEPS_MAJOR=0
DEPS_MINOR=0

if [ -f "$SUGGESTIONS_DIR/deps.json" ]; then
  DEPS_COUNT=$(jq -r '.suggestions | length' "$SUGGESTIONS_DIR/deps.json" 2>/dev/null || echo "0")
  
  if [ "$DEPS_COUNT" -gt 0 ]; then
    DEPS_SECURITY=$(jq -r '[.suggestions[] | select(.suggestedPriority == "high")] | length' "$SUGGESTIONS_DIR/deps.json" 2>/dev/null || echo "0")
    DEPS_MAJOR=$(jq -r '[.suggestions[] | select(.suggestedPriority == "low")] | length' "$SUGGESTIONS_DIR/deps.json" 2>/dev/null || echo "0")
    DEPS_MINOR=$(jq -r '[.suggestions[] | select(.suggestedPriority == "normal")] | length' "$SUGGESTIONS_DIR/deps.json" 2>/dev/null || echo "0")
  fi
fi

TODOS_COUNT=0
FIXMES_COUNT=0

if [ -f "$SUGGESTIONS_DIR/todos.json" ]; then
  TODOS_SUGGESTIONS=$(jq -r '.suggestions | length' "$SUGGESTIONS_DIR/todos.json" 2>/dev/null || echo "0")
  
  if [ "$TODOS_SUGGESTIONS" -gt 0 ]; then
    TODOS_COUNT=$(jq -r '[.suggestions[].metadata.todoCount] | add' "$SUGGESTIONS_DIR/todos.json" 2>/dev/null || echo "0")
    FIXMES_COUNT=$(jq -r '[.suggestions[].metadata.fixmeCount] | add' "$SUGGESTIONS_DIR/todos.json" 2>/dev/null || echo "0")
  fi
fi

# --- Display report ---
echo ""
echo "GitHub Issues:  $ISSUES_COUNT actionable ($ISSUES_BUGS bug, $ISSUES_ENHANCEMENTS enhancements)"
echo "Dependencies:   $DEPS_COUNT updates ($DEPS_SECURITY security, $DEPS_MAJOR major, $DEPS_MINOR minor)"
echo "TODOs/FIXMEs:  $((TODOS_COUNT + FIXMES_COUNT)) found ($FIXMES_COUNT FIXME, $TODOS_COUNT TODO)"
echo "━━━━━━━━━━━━━━━━━━━━━━"

if [ "$ISSUES_COUNT" -gt 0 ] || [ "$DEPS_COUNT" -gt 0 ] || [ "$((TODOS_COUNT + FIXMES_COUNT))" -gt 0 ]; then
  echo "Suggestions written to $SUGGESTIONS_DIR/"
  echo ""
  echo "📋 Files:"
  [ "$ISSUES_COUNT" -gt 0 ] && echo "  - issues.json ($ISSUES_COUNT suggestions)"
  [ "$DEPS_COUNT" -gt 0 ] && echo "  - deps.json ($DEPS_COUNT suggestions)"
  [ "$((TODOS_COUNT + FIXMES_COUNT))" -gt 0 ] && echo "  - todos.json ($TODOS_SUGGESTIONS repos scanned)"
else
  echo "No actionable work found"
fi

echo ""
log "=== Scan Complete ==="

# --- Exit code ---
# 0: success, scanners ran
# 1: all scanners failed
# 2: some scanners failed

FAILED_COUNT=0
[ $ISSUES_EXIT -ne 0 ] && FAILED_COUNT=$((FAILED_COUNT + 1))
[ $DEPS_EXIT -ne 0 ] && FAILED_COUNT=$((FAILED_COUNT + 1))
[ $TODOS_EXIT -ne 0 ] && FAILED_COUNT=$((FAILED_COUNT + 1))

if [ $FAILED_COUNT -eq 3 ]; then
  log "ERROR: All scanners failed"
  exit 1
elif [ $FAILED_COUNT -gt 0 ]; then
  log "WARNING: $FAILED_COUNT scanner(s) failed"
  exit 2
fi

exit 0
