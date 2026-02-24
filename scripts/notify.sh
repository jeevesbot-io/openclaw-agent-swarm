#!/bin/bash
# notify.sh — Notification sender for swarm monitoring
# Reads notifications/pending.json and moves to sent/ after processing
# Usage: notify.sh [--dry-run]

set -euo pipefail

# --- Configuration ---
SWARM_DIR="$HOME/.openclaw/swarm"
NOTIFICATIONS_DIR="$SWARM_DIR/notifications"
PENDING_FILE="$NOTIFICATIONS_DIR/pending.json"
SENT_DIR="$NOTIFICATIONS_DIR/sent"
LOG_FILE="$SWARM_DIR/logs/notify-$(date +%Y%m%d-%H%M%S).log"

# Dry-run mode
DRY_RUN=false
if [ "${1:-}" = "--dry-run" ]; then
  DRY_RUN=true
  echo "DRY RUN MODE - No actual actions will be taken"
fi

# --- Logging ---
mkdir -p "$(dirname "$LOG_FILE")" "$SENT_DIR"
exec 1> >(tee -a "$LOG_FILE")
exec 2>&1

log() { echo "[$(date +%H:%M:%S)] $*"; }

log "=== Notification Sender Started ==="

# --- Check for pending notifications ---
if [ ! -f "$PENDING_FILE" ]; then
  log "No pending notifications found at $PENDING_FILE"
  exit 0
fi

# --- Parse notifications ---
NOTIFICATION_COUNT=$(jq -r '.notifications | length' "$PENDING_FILE" 2>/dev/null || echo "0")

if [ "$NOTIFICATION_COUNT" = "0" ]; then
  log "Pending file exists but has no notifications"
  exit 0
fi

log "Found $NOTIFICATION_COUNT notification(s) to send"

# --- Send each notification ---
# Note: The actual sending is done by Jeeves's heartbeat reading the pending file
# This script just validates and moves the file to sent/

if [ "$DRY_RUN" = true ]; then
  log "[DRY-RUN] Would process notifications:"
  jq -r '.notifications[] | .message' "$PENDING_FILE" | while read -r line; do
    echo "  $line"
  done
  log "[DRY-RUN] Would move $PENDING_FILE to $SENT_DIR/"
else
  # Move to sent directory with timestamp
  TIMESTAMP=$(date +%Y%m%d-%H%M%S)
  SENT_FILE="$SENT_DIR/notifications-$TIMESTAMP.json"
  
  mv "$PENDING_FILE" "$SENT_FILE"
  log "Notifications moved to $SENT_FILE"
  log "Jeeves's heartbeat will pick these up and send them"
fi

log "=== Notification Sender Complete ==="
exit 0
