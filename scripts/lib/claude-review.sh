#!/bin/bash
# claude-review.sh - Claude CLI wrapper for code reviews (FREE via Max subscription)
# Source this file to use: source scripts/lib/claude-review.sh

# Usage: claude_review <model_alias> <system_prompt> <user_message>
# Returns: Raw response content (stdout)
# Logs: Timing info to stderr
#
# Model aliases: haiku, sonnet, opus (resolved by Claude CLI to latest version)
claude_review() {
  local model_alias="$1"
  local system_prompt="$2"
  local user_message="$3"

  # Validate model alias
  case "$model_alias" in
    haiku|sonnet|opus) ;;
    *)
      echo "ERROR: Invalid model alias '$model_alias'. Use: haiku, sonnet, opus" >&2
      return 1
      ;;
  esac

  # Build the full prompt (system + user combined for -p mode)
  local full_prompt="$system_prompt

---

$user_message"

  local start_time=$(date +%s)

  # Run Claude CLI in print mode (one-shot, no session)
  local response
  response=$(claude -p "$full_prompt" --model "$model_alias" --dangerously-skip-permissions 2>/dev/null) || {
    echo "ERROR: Claude CLI failed for model '$model_alias'" >&2
    echo "Check auth: claude auth status" >&2
    return 1
  }

  local end_time=$(date +%s)
  local duration=$((end_time - start_time))

  echo "Claude $model_alias review completed in ${duration}s (FREE via subscription)" >&2

  echo "$response"
}
