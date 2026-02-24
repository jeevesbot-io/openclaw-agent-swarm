#!/bin/bash
# review-pr.sh - Multi-tier AI code review orchestrator
#
# Tier 1 (Haiku)  - Quick scan    - Claude CLI (FREE)
# Tier 2 (Sonnet) - Thorough      - Claude CLI (FREE)
# Tier 3 (Alt)    - 2nd opinion   - OpenRouter (non-Anthropic, ~$0.10-0.50)
#
# Usage: review-pr.sh <repo> <pr-number> [--tier 1,2,3] [--post-comment] [--json]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SWARM_DIR="$(dirname "$SCRIPT_DIR")"

# Source both backends
source "$SCRIPT_DIR/lib/claude-review.sh"
source "$SCRIPT_DIR/lib/openrouter.sh"

# --- Argument parsing ---
REPO=""
PR_NUMBER=""
TIERS="1,2"
POST_COMMENT=false
JSON_OUTPUT=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --tier)   TIERS="$2"; shift 2 ;;
    --post-comment) POST_COMMENT=true; shift ;;
    --json)   JSON_OUTPUT=true; shift ;;
    *)
      if [ -z "$REPO" ]; then REPO="$1"
      elif [ -z "$PR_NUMBER" ]; then PR_NUMBER="$1"
      else echo "ERROR: Unknown argument: $1" >&2; exit 1; fi
      shift ;;
  esac
done

if [ -z "$REPO" ] || [ -z "$PR_NUMBER" ]; then
  cat >&2 <<EOF
Usage: review-pr.sh <repo> <pr-number> [options]

Tiers:
  1  Quick scan   (Haiku via Claude CLI — FREE)
  2  Thorough     (Sonnet via Claude CLI — FREE)
  3  Alt opinion  (Gemini via OpenRouter — ~\$0.10-0.50)

Options:
  --tier 1,2,3      Which tiers to run (default: 1,2)
  --post-comment    Post review as PR comment on GitHub
  --json            Output full JSON result
EOF
  exit 1
fi

# --- Logging ---
LOG_FILE="$SWARM_DIR/logs/review-$REPO-$PR_NUMBER-$(date +%Y%m%d-%H%M%S).log"
mkdir -p "$(dirname "$LOG_FILE")"
log() { echo "[$(date +%H:%M:%S)] $*" | tee -a "$LOG_FILE"; }

log "=== PR Review: $REPO #$PR_NUMBER | Tiers: $TIERS ==="

# --- Fetch PR data ---
log "Fetching PR metadata..."
PR_METADATA=$(gh pr view "$PR_NUMBER" --repo "jeevesbot-io/$REPO" --json title,body,changedFiles 2>&1) || {
  log "ERROR: Failed to fetch PR metadata"; exit 1
}
PR_TITLE=$(echo "$PR_METADATA" | jq -r '.title')
PR_BODY=$(echo "$PR_METADATA" | jq -r '.body // ""')
CHANGED_FILES=$(echo "$PR_METADATA" | jq -r '.changedFiles')
log "Title: $PR_TITLE | Files: $CHANGED_FILES"

log "Fetching PR diff..."
PR_DIFF=$(gh pr diff "$PR_NUMBER" --repo "jeevesbot-io/$REPO" 2>&1) || {
  log "ERROR: Failed to fetch PR diff"; exit 1
}
DIFF_SIZE=${#PR_DIFF}
log "Diff: $DIFF_SIZE bytes"

# Truncate very large diffs
if [ "$DIFF_SIZE" -gt 102400 ]; then
  log "WARNING: Diff >100KB, truncating"
  PR_DIFF="${PR_DIFF:0:102400}

... [TRUNCATED: Diff exceeds 100KB]"
fi

# Build context for reviewers
PR_CONTEXT="# Pull Request Review

**Repository:** $REPO
**PR #$PR_NUMBER:** $PR_TITLE
**Changed Files:** $CHANGED_FILES

**Description:**
$PR_BODY

---

**Diff:**
\`\`\`diff
$PR_DIFF
\`\`\`"

# --- Review execution ---
declare -a REVIEW_RESULTS

run_tier_review() {
  local tier=$1
  local prompt_file="$SWARM_DIR/prompts/review-tier${tier}.txt"

  if [ ! -f "$prompt_file" ]; then
    echo "ERROR: Prompt file not found: $prompt_file" >&2; return 1
  fi

  local system_prompt
  system_prompt=$(cat "$prompt_file")
  local start_time=$(date +%s)
  local response=""
  local model_label=""
  local cost="0.00"

  case $tier in
    1)
      model_label="haiku (Claude CLI — free)"
      echo "[$(date +%H:%M:%S)] Tier 1: Quick scan with Haiku..." >> "$LOG_FILE"
      response=$(claude_review "haiku" "$system_prompt" "$PR_CONTEXT" 2>> "$LOG_FILE") || return 1
      ;;
    2)
      model_label="sonnet (Claude CLI — free)"
      echo "[$(date +%H:%M:%S)] Tier 2: Thorough review with Sonnet..." >> "$LOG_FILE"
      response=$(claude_review "sonnet" "$system_prompt" "$PR_CONTEXT" 2>> "$LOG_FILE") || return 1
      ;;
    3)
      model_label="google/gemini-2.5-pro (OpenRouter)"
      echo "[$(date +%H:%M:%S)] Tier 3: Alternative perspective with Gemini..." >> "$LOG_FILE"
      response=$(openrouter_chat "google/gemini-2.5-pro" "$system_prompt" "$PR_CONTEXT" 4096 2>> "$LOG_FILE") || return 1
      ;;
    *)
      echo "ERROR: Invalid tier: $tier" >&2; return 1 ;;
  esac

  local end_time=$(date +%s)
  local duration=$((end_time - start_time))

  # Strip markdown code fences if present
  if echo "$response" | grep -q '```json'; then
    response=$(echo "$response" | awk '/```json/{flag=1;next}/```/{flag=0}flag')
  elif echo "$response" | grep -q '```'; then
    response=$(echo "$response" | awk '/```/{flag=!flag;next}flag')
  fi

  # Validate JSON
  if ! echo "$response" | jq -e . >/dev/null 2>&1; then
    log "ERROR: Tier $tier response is not valid JSON"
    echo "Raw: $response" >> "$LOG_FILE"
    return 1
  fi

  local score summary issues suggestions alternatives
  score=$(echo "$response" | jq -r '.score // 0')
  summary=$(echo "$response" | jq -r '.summary // "No summary"')
  issues=$(echo "$response" | jq -c '.issues // []')
  suggestions=$(echo "$response" | jq -c '.suggestions // []')
  alternatives=$(echo "$response" | jq -c '.alternatives // []')

  echo "[$(date +%H:%M:%S)] Tier $tier: score=$score, ${duration}s, $model_label" >> "$LOG_FILE"

  jq -n \
    --argjson tier "$tier" \
    --arg model "$model_label" \
    --argjson score "$score" \
    --argjson duration "$duration" \
    --arg summary "$summary" \
    --argjson issues "$issues" \
    --argjson suggestions "$suggestions" \
    --argjson alternatives "$alternatives" \
    '{tier: $tier, model: $model, score: $score, duration_seconds: $duration,
      summary: $summary, issues: $issues, suggestions: $suggestions, alternatives: $alternatives}'
}

# Run requested tiers
IFS=',' read -ra TIER_ARRAY <<< "$TIERS"
for tier in "${TIER_ARRAY[@]}"; do
  tier=$(echo "$tier" | tr -d ' ')
  if result=$(run_tier_review "$tier"); then
    REVIEW_RESULTS+=("$result")
  else
    log "WARNING: Tier $tier failed, continuing..."
  fi
done

if [ ${#REVIEW_RESULTS[@]} -eq 0 ]; then
  log "ERROR: All reviews failed"; exit 1
fi

# --- Scoring ---
# Weights: tier1=0.2, tier2=0.5, tier3=0.3
OVERALL_SCORE=0
TOTAL_WEIGHT=0

for result in "${REVIEW_RESULTS[@]}"; do
  tier=$(echo "$result" | jq -r '.tier')
  score=$(echo "$result" | jq -r '.score')
  case $tier in
    1) weight=0.2 ;; 2) weight=0.5 ;; 3) weight=0.3 ;; *) weight=0 ;;
  esac
  OVERALL_SCORE=$(awk "BEGIN {printf \"%.2f\", $OVERALL_SCORE + ($score * $weight)}")
  TOTAL_WEIGHT=$(awk "BEGIN {printf \"%.2f\", $TOTAL_WEIGHT + $weight}")
done

if (( $(echo "$TOTAL_WEIGHT > 0" | bc -l) )); then
  OVERALL_SCORE=$(awk "BEGIN {printf \"%.1f\", $OVERALL_SCORE / $TOTAL_WEIGHT}")
fi

# Recommendation
RECOMMENDATION="reject"
if (( $(echo "$OVERALL_SCORE >= 8" | bc -l) )); then RECOMMENDATION="approve"
elif (( $(echo "$OVERALL_SCORE >= 6" | bc -l) )); then RECOMMENDATION="approve_with_suggestions"
elif (( $(echo "$OVERALL_SCORE >= 4" | bc -l) )); then RECOMMENDATION="request_changes"
fi

log "Overall: $OVERALL_SCORE/10 → $RECOMMENDATION"

# --- Output ---
REVIEWS_JSON=$(printf '%s\n' "${REVIEW_RESULTS[@]}" | jq -s '.')

FINAL_RESULT=$(jq -n \
  --argjson pr "$PR_NUMBER" \
  --arg repo "$REPO" \
  --argjson reviews "$REVIEWS_JSON" \
  --argjson overall_score "$OVERALL_SCORE" \
  --arg recommendation "$RECOMMENDATION" \
  '{pr: $pr, repo: $repo, reviews: $reviews, overall_score: $overall_score, recommendation: $recommendation}')

echo "$FINAL_RESULT" | jq '.' >> "$LOG_FILE"

# Human-readable summary
SUMMARY="## 🤖 AI Code Review — PR #$PR_NUMBER

**Overall Score:** $OVERALL_SCORE/10
**Recommendation:** $(echo "$RECOMMENDATION" | tr '_' ' ' | awk '{for(i=1;i<=NF;i++)sub(/./,toupper(substr($i,1,1)),$i)}1')

"

for result in "${REVIEW_RESULTS[@]}"; do
  tier=$(echo "$result" | jq -r '.tier')
  model=$(echo "$result" | jq -r '.model')
  score=$(echo "$result" | jq -r '.score')
  summary=$(echo "$result" | jq -r '.summary')
  issue_count=$(echo "$result" | jq -r '.issues | length')
  suggestion_count=$(echo "$result" | jq -r '.suggestions | length')

  SUMMARY+="### Tier $tier ($model) — $score/10

$summary

"
  if [ "$issue_count" -gt 0 ]; then
    SUMMARY+="**Issues ($issue_count):**
$(echo "$result" | jq -r '.issues[] | "- **[\(.severity // "medium" | ascii_upcase)]** \(.file // ""):\(.line // 0) — \(.message)"')

"
  fi
  if [ "$suggestion_count" -gt 0 ]; then
    SUMMARY+="**Suggestions ($suggestion_count):**
$(echo "$result" | jq -r '.suggestions[] | "- \(.)"')

"
  fi
done

SUMMARY+="---
*Review by agent swarm — $(date)*"

if [ "$JSON_OUTPUT" = true ]; then
  echo "$FINAL_RESULT"
else
  echo "$SUMMARY"
fi

if [ "$POST_COMMENT" = true ]; then
  log "Posting review as PR comment..."
  echo "$SUMMARY" | gh pr comment "$PR_NUMBER" --repo "jeevesbot-io/$REPO" --body-file - || {
    log "ERROR: Failed to post PR comment"
  }
fi

log "=== Review complete ==="
