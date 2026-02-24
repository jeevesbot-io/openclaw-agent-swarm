#!/bin/bash
# openrouter.sh - Reusable OpenRouter API wrapper
# Source this file to use: source scripts/lib/openrouter.sh

# Usage: openrouter_chat <model> <system_prompt> <user_message> <max_tokens>
# Returns: Raw response content (stdout)
# Logs: Cost and timing info to stderr
openrouter_chat() {
  local model="$1"
  local system_prompt="$2"
  local user_message="$3"
  local max_tokens="${4:-4096}"
  
  # Fetch API key from 1Password
  local api_key
  if ! api_key=$(op read "op://Jeeves/OPENROUTER_API_KEY/credential" 2>/dev/null); then
    echo "ERROR: Failed to fetch OPENROUTER_API_KEY from 1Password" >&2
    echo "Make sure op CLI is authenticated and the key exists" >&2
    return 1
  fi
  
  if [ -z "$api_key" ]; then
    echo "ERROR: OPENROUTER_API_KEY is empty" >&2
    return 1
  fi
  
  # Build request payload
  local request_payload
  request_payload=$(jq -n \
    --arg model "$model" \
    --arg system "$system_prompt" \
    --arg user "$user_message" \
    --argjson max_tokens "$max_tokens" \
    '{
      model: $model,
      messages: [
        {role: "system", content: $system},
        {role: "user", content: $user}
      ],
      max_tokens: $max_tokens
    }')
  
  # Make API call
  local start_time=$(date +%s)
  local response
  local http_code
  local temp_response=$(mktemp)
  local temp_headers=$(mktemp)
  
  http_code=$(curl -s -w "%{http_code}" -o "$temp_response" \
    -D "$temp_headers" \
    https://openrouter.ai/api/v1/chat/completions \
    -H "Authorization: Bearer $api_key" \
    -H "Content-Type: application/json" \
    -d "$request_payload")
  
  local end_time=$(date +%s)
  local duration=$((end_time - start_time))
  
  # Check HTTP status
  if [ "$http_code" != "200" ]; then
    echo "ERROR: OpenRouter API returned HTTP $http_code" >&2
    cat "$temp_response" >&2
    rm -f "$temp_response" "$temp_headers"
    return 1
  fi
  
  # Parse response
  response=$(cat "$temp_response")
  
  # Extract content
  local content
  content=$(echo "$response" | jq -r '.choices[0].message.content // empty')
  
  if [ -z "$content" ]; then
    echo "ERROR: Failed to parse response content" >&2
    echo "$response" >&2
    rm -f "$temp_response" "$temp_headers"
    return 1
  fi
  
  # Extract cost info from response (OpenRouter includes usage in response body)
  local prompt_tokens=$(echo "$response" | jq -r '.usage.prompt_tokens // 0')
  local completion_tokens=$(echo "$response" | jq -r '.usage.completion_tokens // 0')
  local total_tokens=$(echo "$response" | jq -r '.usage.total_tokens // 0')
  
  # Log timing and token info
  echo "OpenRouter API call completed in ${duration}s" >&2
  echo "Model: $model" >&2
  echo "Tokens: prompt=$prompt_tokens, completion=$completion_tokens, total=$total_tokens" >&2
  
  # Calculate approximate cost (per model)
  # Rates are per 1M tokens: input / output
  local cost_usd=0
  case "$model" in
    "anthropic/claude-haiku"*|"anthropic/claude-3-haiku"*|"anthropic/claude-4-haiku"*)
      # Haiku: $0.80 / $4.00 per 1M tokens
      cost_usd=$(awk "BEGIN {printf \"%.4f\", ($prompt_tokens * 0.80 + $completion_tokens * 4.00) / 1000000}")
      ;;
    "anthropic/claude-sonnet"*|"anthropic/claude-3-sonnet"*|"anthropic/claude-4-sonnet"*)
      # Sonnet: $3.00 / $15.00 per 1M tokens
      cost_usd=$(awk "BEGIN {printf \"%.4f\", ($prompt_tokens * 3.00 + $completion_tokens * 15.00) / 1000000}")
      ;;
    "anthropic/claude-opus"*|"anthropic/claude-3-opus"*|"anthropic/claude-4-opus"*)
      # Opus: $15.00 / $75.00 per 1M tokens
      cost_usd=$(awk "BEGIN {printf \"%.4f\", ($prompt_tokens * 15.00 + $completion_tokens * 75.00) / 1000000}")
      ;;
    *)
      echo "WARNING: Unknown model pricing for $model, cost estimate unavailable" >&2
      ;;
  esac
  
  if [ "$cost_usd" != "0" ]; then
    echo "Estimated cost: \$$cost_usd USD" >&2
  fi
  
  # Clean up
  rm -f "$temp_response" "$temp_headers"
  
  # Return content
  echo "$content"
}

# Export function for use in other scripts
export -f openrouter_chat 2>/dev/null || true
