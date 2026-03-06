# Clocket

**Your schedule. Your machine. Your clocket.me.**

A self-hosted CalDAV calendar skill for [OpenClaw](https://github.com/openclaw/openclaw) agents. Privacy-first, localhost-only, works with any CalDAV client.

## What It Does

- Creates and manages calendars on a local Radicale CalDAV server
- Add, list, and delete events via CLI
- Syncs with Apple Calendar, Thunderbird, GNOME Calendar, or any CalDAV client
- Runs on localhost — your data never leaves your machine

## Quick Start

```bash
# Install Radicale and configure
bash scripts/install.sh

# Create a calendar
bash scripts/calendar.sh create "Work"

# Add an event
bash scripts/calendar.sh add "Work" "Team standup" "2026-03-10T09:00" "2026-03-10T09:30"

# List events
bash scripts/calendar.sh list "Work"
```

## Structure

```
├── SKILL.md              # OpenClaw skill definition
├── scripts/
│   ├── install.sh        # Radicale installer + LaunchAgent setup
│   └── calendar.sh       # CLI for calendar operations
└── references/
    └── client-sync.md    # How to connect CalDAV clients
```

## Requirements

- macOS (LaunchAgent for persistence) or Linux (systemd)
- Python 3 + pip
- OpenClaw (optional — works standalone too)

## License

MIT
