---
name: clocket
description: Self-hosted, privacy-first calendar management for OpenClaw agents via Radicale CalDAV server. Use when an agent needs to create, read, update, or delete calendar events programmatically — editorial calendars, recurring schedules, guest coordination, reminders. No cloud accounts required. Data never leaves the machine. Syncs with any CalDAV client (Apple Calendar, Thunderbird, DAVx⁵). Use for (1) setting up a local calendar server, (2) managing events from agent workflows, (3) editorial/content calendars with guest tracking, (4) recurring event management, (5) any calendar task where privacy matters.
---

# Radicale Calendar Skill

Self-hosted calendar management for OpenClaw agents. Radicale is a lightweight CalDAV server that runs locally — no cloud, no accounts, no data leaving your machine.

## Quick Start

### Install

```bash
bash scripts/install.sh
```

This installs Radicale, creates config, sets up a LaunchAgent for persistence, and starts the server on `127.0.0.1:5232`.

### Create a Calendar

```bash
bash scripts/calendar.sh create "my-calendar" "My Calendar"
```

### Add an Event

```bash
bash scripts/calendar.sh add "my-calendar" \
  --title "Weekly Standup" \
  --start "2026-03-10T09:00" \
  --end "2026-03-10T09:30" \
  --recurring weekly
```

### List Events

```bash
bash scripts/calendar.sh list "my-calendar"
```

### Update an Event

```bash
bash scripts/calendar.sh update "my-calendar" "event-uid" \
  --title "New Title" \
  --description "Updated description"
```

### Delete an Event

```bash
bash scripts/calendar.sh delete "my-calendar" "event-uid"
```

## Architecture

```
Agent (OpenClaw) → scripts/calendar.sh → Radicale (localhost:5232) → Local filesystem
                                              ↕
                                        CalDAV Clients
                                   (Apple Calendar, etc.)
```

All data stored in `~/.openclaw/workspace/data/radicale/collections/`.

## Configuration

Default config lives at `~/.config/radicale/config`. The install script sets sensible defaults:
- Binds to `127.0.0.1:5232` (localhost only — never exposed)
- htpasswd auth (plaintext for localhost; use bcrypt if exposing via reverse proxy)
- Filesystem storage in the workspace

## CalDAV Client Sync

To view calendars on your devices, connect any CalDAV client to `http://127.0.0.1:5232`. See `references/client-sync.md` for setup instructions per platform.

## Editorial Calendar Workflow

For content calendars (podcast guests, X Spaces, blog posts):

```bash
# Create editorial calendar
bash scripts/calendar.sh create "spaces" "Weekly X Spaces"

# Add episode with guest
bash scripts/calendar.sh add "spaces" \
  --title "S01E05 - AI Privacy with Jane Doe" \
  --start "2026-04-03T09:30" \
  --end "2026-04-03T10:00" \
  --description "Guest: Jane Doe (@janedoe)\nTopic: Privacy in decentralized AI" \
  --recurring weekly

# List upcoming episodes
bash scripts/calendar.sh list "spaces" --upcoming 4
```

## Troubleshooting

- **Server won't start**: Check if port 5232 is in use: `lsof -i :5232`
- **Auth failing**: Verify `~/.config/radicale/users` has correct credentials
- **LaunchAgent not loading**: Run `launchctl load ~/Library/LaunchAgents/com.clocket.plist`
