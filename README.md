# 🕐 Clocket

Self-hosted, privacy-first calendar for AI agents.

Clocket gives [OpenClaw](https://github.com/openclaw/openclaw) agents the ability to manage calendars programmatically — create events, track editorial schedules, coordinate guests, set reminders — without touching Google, Microsoft, or any cloud service. Everything stays on your machine.

Powered by [Radicale](https://radicale.org), a lightweight CalDAV server.

## Why

AI agents need to manage time. Most calendar solutions require cloud accounts and send your data to third parties. If you're running a privacy-first agent (especially in the Morpheus/decentralized AI ecosystem), you need something local.

Clocket is that something.

## Install

```bash
bash scripts/install.sh
```

This installs Radicale, creates config, starts the server on `localhost:5232`, and sets up a LaunchAgent so it survives reboots.

## Usage

```bash
# Create a calendar
bash scripts/clocket.sh create "work" "Work Calendar"

# Add an event
bash scripts/clocket.sh add "work" \
  --title "Team Sync" \
  --start "2026-03-10T09:00" \
  --tz "America/Los_Angeles"

# Add recurring event
bash scripts/clocket.sh add "work" \
  --title "Weekly Standup" \
  --start "2026-03-10T09:00" \
  --recurring weekly

# List events
bash scripts/clocket.sh list "work"

# Check server status
bash scripts/clocket.sh status
```

See [SKILL.md](SKILL.md) for full documentation.

## Sync with Your Devices

Clocket runs a standard CalDAV server. Connect any CalDAV client:

- **Apple Calendar** → Add CalDAV account → `http://127.0.0.1:5232`
- **Thunderbird** → New Calendar → Network → CalDAV
- **Android (DAVx⁵)** → Base URL → `http://127.0.0.1:5232`

See [references/client-sync.md](references/client-sync.md) for detailed setup.

## Architecture

```
Agent (OpenClaw)  →  clocket.sh  →  Radicale (localhost:5232)  →  Local filesystem
                                          ↕
                                    CalDAV Clients
                               (Apple Calendar, Thunderbird, DAVx⁵)
```

## Built with Fieldcraft

Clocket is a [Fieldcraft](https://clocket.me) project — built for real use first, packaged for others second. We run it in production managing editorial calendars for Morpheus X Spaces before shipping it as a skill.

## License

MIT
