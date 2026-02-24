# Phase 4 - Implementation Checklist

## Requirements ✅

- [x] **queue.json** - Task queue with proper schema
- [x] **queue-task.sh** - Add tasks to queue with validation
  - [x] Generates task IDs (format: `<branch-suffix>-<timestamp>`)
  - [x] Validates repo exists
  - [x] Validates branch starts with `agent/`
  - [x] Handles inline prompts and prompt files
  - [x] Atomic locking (mkdir-based)
  - [x] Prints task ID and position
- [x] **dispatch.sh** - Queue dispatcher
  - [x] Reads maxParallelAgents from config (not hardcoded)
  - [x] Counts active agents (status = "running" or "spawned")
  - [x] Respects priority ordering (high > normal > low, then FIFO)
  - [x] RAM awareness (checks memory pressure)
  - [x] Atomic locking (queue + registry)
  - [x] --dry-run mode
  - [x] Spawns up to available slots
  - [x] Removes dispatched tasks from queue
- [x] **cancel-task.sh** - Cancel queued or active tasks
  - [x] Removes from queue if queued
  - [x] Kills tmux + cleanup if active
  - [x] Moves to history with "cancelled" status
  - [x] --force flag
- [x] **monitor.sh** - Updated with dispatch step
  - [x] Calls dispatch.sh after check-agents.sh
  - [x] Before PR reviews
  - [x] Handles dispatch failures gracefully
- [x] **swarm-status.sh** - Updated with queue display
  - [x] Shows Active: X/Y slots
  - [x] Shows Queued: N (X high, Y normal, Z low)
  - [x] Lists up to 5 queued tasks with priority badges
  - [x] Shows "Done: X today" instead of total
- [x] **list-queue.sh** - View queue
  - [x] Human-readable output
  - [x] --json flag
  - [x] Priority sorted display

## Implementation Standards ✅

- [x] All scripts use `set -euo pipefail`
- [x] All scripts have comprehensive logging
- [x] All scripts have error traps
- [x] Atomic locking (mkdir-based, 5s timeout)
- [x] Scripts under 200 lines each
- [x] All scripts are executable (chmod +x)

## Testing ✅

- [x] Test 1: List empty queue
- [x] Test 2: Add task with priority
- [x] Test 3: List queue with 1 task
- [x] Test 4: Add multiple tasks with different priorities
- [x] Test 5: Priority sorting (high > normal > low, FIFO within)
- [x] Test 6: swarm-status.sh shows queue
- [x] Test 7: dispatch.sh --dry-run (spawns up to maxParallelAgents)
- [x] Test 8: cancel-task.sh removes from queue
- [x] Test 9: List after cancellation
- [x] Test 10: JSON output works

## Files Created ✅

- [x] queue.json (initialized)
- [x] scripts/queue-task.sh (executable)
- [x] scripts/list-queue.sh (executable)
- [x] scripts/dispatch.sh (executable)
- [x] scripts/cancel-task.sh (executable)
- [x] PHASE4-SUMMARY.md (documentation)
- [x] PHASE4-CHECKLIST.md (this file)

## Files Modified ✅

- [x] scripts/monitor.sh (added dispatch step)
- [x] scripts/swarm-status.sh (added queue display)

## Line Counts

- queue-task.sh: 151 lines (< 200 ✓)
- list-queue.sh: 66 lines (< 200 ✓)
- dispatch.sh: 172 lines (< 200 ✓)
- cancel-task.sh: 147 lines (< 200 ✓)

**Total:** 536 lines of new shell code

## Status: ✅ COMPLETE

All requirements met. All tests passed. Ready for production use.
