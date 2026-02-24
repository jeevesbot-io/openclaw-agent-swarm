# Phase 2: Automated Code Reviews

## Overview

After an agent creates a PR, automatically review it using multiple AI models before notifying the human. This catches obvious issues, improves code quality, and saves human review time.

## Architecture

```
Agent creates PR
  ↓
check-agents.sh detects PR
  ↓
review-pr.sh <pr-number> <repo>
  ↓
┌─────────────────────────────────┐
│  Tier 1: Quick Scan (Haiku)     │  ~$0.01, 10-15s
│  - Syntax issues, obvious bugs  │
│  - Style violations              │
│  - Missing tests/docs warning    │
└─────────────┬───────────────────┘
              ↓
┌─────────────────────────────────┐
│  Tier 2: Thorough (Sonnet)      │  ~$0.15-0.30, 30-60s
│  - Logic correctness             │
│  - Edge cases                    │
│  - Architecture fit              │
│  - Test quality                  │
└─────────────┬───────────────────┘
              ↓ (optional, for complex PRs)
┌─────────────────────────────────┐
│  Tier 3: Deep (Opus)            │  ~$0.75-1.50, 60-120s
│  - Security implications         │
│  - Performance concerns          │
│  - Design decisions              │
│  - Alternative approaches        │
└─────────────┬───────────────────┘
              ↓
Post review summary as PR comment
  ↓
Notify human: "PR #X ready, review score: 8/10"
```

## Review Script: review-pr.sh

### Usage
```bash
scripts/review-pr.sh <repo> <pr-number> [--tier 1|2|3|all] [--post-comment]
```

### Parameters
- `repo` — Repository name (in ~/projects/)
- `pr-number` — GitHub PR number
- `--tier` — Which review tiers to run (default: 1,2)
- `--post-comment` — Post results as PR comment on GitHub

### What it does

1. Fetch PR diff: `gh pr diff <number> --repo <owner>/<repo>`
2. Fetch PR metadata: title, description, changed files, base branch
3. For each tier, call OpenRouter API with the diff + review prompt
4. Parse results into structured format
5. Optionally post as PR comment
6. Return JSON summary with scores and findings

### Output Format

```json
{
  "pr": 2,
  "repo": "sports-dashboard",
  "reviews": [
    {
      "tier": 1,
      "model": "haiku",
      "score": 8,
      "duration_seconds": 12,
      "cost_usd": 0.01,
      "summary": "Clean test file, good coverage",
      "issues": [],
      "suggestions": [
        "Consider adding a test for concurrent predictions"
      ]
    },
    {
      "tier": 2,
      "model": "sonnet",
      "score": 7,
      "duration_seconds": 45,
      "cost_usd": 0.22,
      "summary": "Good test structure, minor gaps",
      "issues": [
        {
          "severity": "medium",
          "file": "backend/tests/test_predictions.py",
          "line": 42,
          "message": "Test data doesn't cover the edge case where both teams have 0 goals"
        }
      ],
      "suggestions": [
        "Add parametrized tests for different season values",
        "Mock the database session for faster execution"
      ]
    }
  ],
  "overall_score": 7.5,
  "recommendation": "approve_with_suggestions",
  "total_cost_usd": 0.23
}
```

### Recommendation Values
- `approve` — No issues found, safe to merge
- `approve_with_suggestions` — Minor suggestions, safe to merge
- `request_changes` — Issues found that should be addressed
- `reject` — Significant problems, needs rework

## OpenRouter Integration

### API Call
```bash
curl -s https://openrouter.ai/api/v1/chat/completions \
  -H "Authorization: Bearer $OPENROUTER_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "anthropic/claude-haiku-4-5",
    "messages": [
      {"role": "system", "content": "<review prompt>"},
      {"role": "user", "content": "<PR diff + context>"}
    ],
    "max_tokens": 4096
  }'
```

### Models
| Tier | Model | OpenRouter ID | Cost (input/output per 1M) |
|------|-------|--------------|---------------------------|
| 1 | Haiku 4.5 | anthropic/claude-haiku-4-5 | $0.80 / $4.00 |
| 2 | Sonnet 4.5 | anthropic/claude-sonnet-4-5 | $3.00 / $15.00 |
| 3 | Opus 4.6 | anthropic/claude-opus-4-6 | $15.00 / $75.00 |

### API Key
```bash
OPENROUTER_API_KEY=$(op read "op://Jeeves/OpenRouter API/credential")
```

## Review Prompts

### Tier 1 (Haiku) — Quick Scan
```
You are a code reviewer doing a quick scan. Review this PR diff for:
1. Syntax errors or obvious bugs
2. Style violations (inconsistent naming, formatting)
3. Missing error handling
4. Hardcoded values that should be configurable
5. Missing or inadequate tests

Be concise. Flag only real issues, not nitpicks.

Respond in JSON: { score: 1-10, summary: "...", issues: [...], suggestions: [...] }
```

### Tier 2 (Sonnet) — Thorough Review
```
You are a senior developer reviewing a PR. Analyze this diff thoroughly:
1. Logic correctness — does the code do what it claims?
2. Edge cases — what inputs could break this?
3. Architecture fit — does this follow the project's patterns?
4. Test quality — are the tests meaningful or just coverage theatre?
5. Maintainability — will this be easy to modify later?
6. Performance — any obvious bottlenecks?

Context about the project will be provided. Reference specific lines.

Respond in JSON: { score: 1-10, summary: "...", issues: [{severity, file, line, message}], suggestions: [...] }
```

### Tier 3 (Opus) — Deep Analysis
```
You are a principal engineer reviewing a PR. Go deep:
1. Security — any vulnerabilities introduced?
2. Design decisions — are there better approaches?
3. Scalability — how does this behave at scale?
4. Testing strategy — is the testing approach sound?
5. Alternative implementations — what would you do differently?
6. Long-term implications — technical debt introduced?

Be thorough but fair. Suggest concrete improvements with code examples where helpful.

Respond in JSON: { score: 1-10, summary: "...", issues: [{severity, file, line, message}], suggestions: [...], alternatives: [...] }
```

## Integration with Swarm Pipeline

### In check-agents.sh

When a PR is detected, trigger review:

```bash
# After detecting PR
if [ "$PR_CREATED" = true ]; then
  # Run reviews (tiers 1 and 2 by default)
  REVIEW_RESULT=$(scripts/review-pr.sh "$REPO" "$PR_NUMBER" --tier 1,2 --post-comment)
  OVERALL_SCORE=$(echo "$REVIEW_RESULT" | jq '.overall_score')
  RECOMMENDATION=$(echo "$REVIEW_RESULT" | jq -r '.recommendation')
  
  # Update registry with review results
  jq "(.tasks[] | select(.id == \"$TASK_ID\") | .checks.reviewScore) = $OVERALL_SCORE" ...
fi
```

### In Jeeves notification

```
🤖 Agent PR Ready — Reviewed ✅

Task: test-predictions-phase1
PR: #2
CI: ✅ Passed
Review: 7.5/10 (approve with suggestions)

Haiku: 8/10 — Clean, no issues
Sonnet: 7/10 — Good but missing edge case tests

2 suggestions (see PR comments)

Review: https://github.com/jeevesbot-io/sports-dashboard/pull/2
```

## Cost Estimates

**Per PR review:**
| Tier | Typical diff size | Cost |
|------|------------------|------|
| Haiku only | Any | ~$0.01 |
| Haiku + Sonnet | <500 lines | ~$0.15-0.30 |
| Haiku + Sonnet + Opus | <500 lines | ~$1.00-1.80 |
| All tiers, large PR | >1000 lines | ~$2.00-3.50 |

**Monthly (50 PRs, tiers 1+2):**
- Haiku: 50 × $0.01 = $0.50
- Sonnet: 50 × $0.22 = $11.00
- **Total: ~$11.50/month**

Adding Opus for complex PRs (10/month): +$12 = ~$23.50/month

## Implementation Plan

### Files to Create
1. `scripts/review-pr.sh` — Main review orchestrator
2. `scripts/lib/openrouter.sh` — OpenRouter API wrapper (reusable)
3. `prompts/review-tier1.txt` — Haiku review prompt template
4. `prompts/review-tier2.txt` — Sonnet review prompt template
5. `prompts/review-tier3.txt` — Opus review prompt template

### Files to Modify
1. `scripts/check-agents.sh` — Add review trigger after PR detection
2. `active-tasks.json` schema — Add review fields to task object
3. `JEEVES-INTEGRATION.md` — Add review workflow

### Testing
1. Test with existing PR #1 (README)
2. Test each tier independently
3. Test PR comment posting
4. Test with large diff (>500 lines)
5. Test with no OpenRouter key (graceful failure)
6. Verify cost tracking accuracy

### Estimated Effort
- review-pr.sh: 2-3 hours
- OpenRouter wrapper: 1 hour
- Prompt templates: 1 hour
- check-agents.sh integration: 1 hour
- Testing: 2 hours
- Documentation: 1 hour
- **Total: 8-10 hours**
