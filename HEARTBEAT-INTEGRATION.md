# Swarm Monitoring — Heartbeat Integration

This file documents how to integrate swarm monitoring into Jeeves's heartbeat system.

## Overview

The swarm monitoring system (`monitor.sh`) runs periodically via cron and writes notifications to:
```
~/.openclaw/swarm/notifications/pending.json
```

Jeeves's heartbeat should check for this file and send any pending notifications.

## Integration Steps

Add this check to your `HEARTBEAT.md` (or implement directly in heartbeat logic):

### 1. Check for Pending Swarm Notifications

```markdown
## Swarm Notifications

Every heartbeat, check for pending swarm notifications:

1. Check if `~/.openclaw/swarm/notifications/pending.json` exists
2. If it does, read the file and parse the JSON
3. For each notification in the `notifications` array:
   - Send the `message` field to Nick via the message tool
4. After sending all notifications, move the file to `notifications/sent/<timestamp>.json`
```

### 2. Example Implementation (pseudo-code)

```javascript
// In heartbeat handler
const pendingPath = '~/.openclaw/swarm/notifications/pending.json';
if (fileExists(pendingPath)) {
  const data = readJSON(pendingPath);
  
  for (const notif of data.notifications) {
    await sendMessage(notif.message); // Send to Nick via message tool
  }
  
  // Move to sent folder
  const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
  const sentPath = `~/.openclaw/swarm/notifications/sent/notifications-${timestamp}.json`;
  moveFile(pendingPath, sentPath);
}
```

### 3. Notification Format

The pending.json file has this structure:

```json
{
  "timestamp": "2026-02-24T20:45:00Z",
  "notifications": [
    {
      "type": "pr_ready",
      "task_id": "test-predictions-phase1",
      "repo": "sports-dashboard",
      "pr": 2,
      "review_score": 8.3,
      "recommendation": "approve",
      "message": "🤖 PR #2 ready for review\n📊 Score: 8.3/10 (approve)\n🔗 https://github.com/jeevesbot-io/sports-dashboard/pull/2"
    },
    {
      "type": "agent_stuck",
      "task_id": "some-task",
      "message": "⚠️ Agent stuck: some-task (running >60min)"
    }
  ]
}
```

The `message` field contains a human-readable message ready to be sent directly to the user.

### 4. Notification Types

- **pr_ready**: A PR has been created and reviewed, ready for human review
- **agent_stuck**: An agent has been running for >60 minutes without creating a PR
- **agent_failed**: An agent has failed permanently (max retries exceeded)
- **agent_respawned**: An agent has been respawned after a failure

### 5. Frequency

- Heartbeat typically runs every 30-60 minutes
- Swarm monitor runs every 5-10 minutes
- This means notifications may batch up between heartbeat checks (which is fine)
- You could also run the swarm monitor more frequently than the heartbeat

## Testing

To test the integration:

1. Run `~/.openclaw/swarm/scripts/monitor.sh --dry-run` to generate test notifications
2. Check that `notifications/pending.json` was created
3. In your next heartbeat, verify it picks up and sends the notifications
4. Verify the file was moved to `notifications/sent/`

## Alternative: Direct Integration

If you prefer, you could call `monitor.sh` directly from the heartbeat instead of relying on cron:

```bash
# In heartbeat
~/.openclaw/swarm/scripts/monitor.sh
# Then check for pending.json as above
```

This gives you more control over timing and ensures monitoring happens even if cron isn't set up.
