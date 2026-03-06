#!/usr/bin/env bash
set -euo pipefail

# Radicale Calendar Skill — Calendar Management
# Usage: calendar.sh <command> <calendar> [options]
#
# Commands:
#   create <calendar-id> <display-name>     Create a new calendar
#   add <calendar-id> [options]             Add an event
#   list <calendar-id> [--upcoming N]       List events
#   update <calendar-id> <uid> [options]    Update an event
#   delete <calendar-id> <uid>              Delete an event
#   calendars                               List all calendars

# Load credentials
ENV_FILE="${HOME}/.config/radicale/skill.env"
if [ -f "$ENV_FILE" ]; then
    source "$ENV_FILE"
else
    RADICALE_URL="${RADICALE_URL:-http://127.0.0.1:5232}"
    RADICALE_USER="${RADICALE_USER:-agent}"
    RADICALE_PASS="${RADICALE_PASS:-}"
fi

AUTH="${RADICALE_USER}:${RADICALE_PASS}"
BASE="${RADICALE_URL}/${RADICALE_USER}"

die() { echo "ERROR: $*" >&2; exit 1; }

# Generate a UID
gen_uid() {
    local prefix="${1:-event}"
    echo "${prefix}-$(date +%Y%m%d%H%M%S)-$(openssl rand -hex 4)"
}

# Create calendar
cmd_create() {
    local cal_id="${1:?Usage: calendar.sh create <calendar-id> <display-name>}"
    local display_name="${2:-$cal_id}"

    curl -sf -u "$AUTH" -X MKCOL \
        -H "Content-Type: application/xml" \
        --data-binary "<?xml version='1.0' encoding='UTF-8'?>
<mkcol xmlns='DAV:' xmlns:C='urn:ietf:params:xml:ns:caldav'>
  <set><prop>
    <resourcetype><collection/><C:calendar/></resourcetype>
    <displayname>${display_name}</displayname>
  </prop></set>
</mkcol>" \
        "${BASE}/${cal_id}/" >/dev/null

    echo "Created calendar: ${cal_id} (${display_name})"
}

# Add event
cmd_add() {
    local cal_id="${1:?Usage: calendar.sh add <calendar-id> --title ... --start ... --end ...}"
    shift

    local title="" start="" end="" description="" location="" recurring=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --title) title="$2"; shift 2 ;;
            --start) start="$2"; shift 2 ;;
            --end) end="$2"; shift 2 ;;
            --description) description="$2"; shift 2 ;;
            --location) location="$2"; shift 2 ;;
            --recurring) recurring="$2"; shift 2 ;;
            *) die "Unknown option: $1" ;;
        esac
    done

    [ -z "$title" ] && die "--title is required"
    [ -z "$start" ] && die "--start is required (format: YYYY-MM-DDTHH:MM)"
    [ -z "$end" ] && end=$(date -j -f "%Y-%m-%dT%H:%M" -v+1H "$start" "+%Y-%m-%dT%H:%M" 2>/dev/null || echo "$start")

    local uid=$(gen_uid "evt")
    local dtstart=$(echo "$start" | tr -d ':-')
    local dtend=$(echo "$end" | tr -d ':-')

    local rrule=""
    case "${recurring:-}" in
        daily)   rrule="RRULE:FREQ=DAILY" ;;
        weekly)  rrule="RRULE:FREQ=WEEKLY" ;;
        monthly) rrule="RRULE:FREQ=MONTHLY" ;;
        yearly)  rrule="RRULE:FREQ=YEARLY" ;;
        "")      rrule="" ;;
        *)       die "Unknown recurring type: $recurring (use daily|weekly|monthly|yearly)" ;;
    esac

    local ical="BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//Radicale Calendar Skill//EN
BEGIN:VEVENT
UID:${uid}@radicale-skill
DTSTART:${dtstart}
DTEND:${dtend}
SUMMARY:${title}"

    [ -n "$description" ] && ical="${ical}
DESCRIPTION:${description}"
    [ -n "$location" ] && ical="${ical}
LOCATION:${location}"
    [ -n "$rrule" ] && ical="${ical}
${rrule}"

    ical="${ical}
DTSTAMP:$(date -u +%Y%m%dT%H%M%SZ)
END:VEVENT
END:VCALENDAR"

    curl -sf -u "$AUTH" -X PUT \
        -H "Content-Type: text/calendar" \
        --data-binary "$ical" \
        "${BASE}/${cal_id}/${uid}.ics" >/dev/null

    echo "Added event: ${title}"
    echo "UID: ${uid}@radicale-skill"
}

# List events
cmd_list() {
    local cal_id="${1:?Usage: calendar.sh list <calendar-id>}"
    shift
    local upcoming=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --upcoming) upcoming="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    local response
    response=$(curl -sf -u "$AUTH" -X REPORT \
        -H "Content-Type: application/xml" \
        --data-binary '<?xml version="1.0" encoding="UTF-8"?>
<C:calendar-query xmlns:D="DAV:" xmlns:C="urn:ietf:params:xml:ns:caldav">
  <D:prop>
    <D:getetag/>
    <C:calendar-data/>
  </D:prop>
  <C:filter>
    <C:comp-filter name="VCALENDAR">
      <C:comp-filter name="VEVENT"/>
    </C:comp-filter>
  </C:filter>
</C:calendar-query>' \
        "${BASE}/${cal_id}/")

    # Extract and display events
    echo "$response" | grep -o 'SUMMARY:.*' | sed 's/SUMMARY:/• /' | while read -r line; do
        echo "$line"
    done

    if [ -z "$response" ] || ! echo "$response" | grep -q "SUMMARY"; then
        curl -sf -u "$AUTH" "${BASE}/${cal_id}/" | grep -o 'SUMMARY:.*' | sed 's/SUMMARY:/• /' || echo "(no events found)"
    fi
}

# Delete event
cmd_delete() {
    local cal_id="${1:?Usage: calendar.sh delete <calendar-id> <uid>}"
    local uid="${2:?Usage: calendar.sh delete <calendar-id> <uid>}"

    # Find the .ics file containing this UID
    local ics_name=$(echo "$uid" | sed 's/@radicale-skill//')
    curl -sf -u "$AUTH" -X DELETE "${BASE}/${cal_id}/${ics_name}.ics" >/dev/null 2>&1 && \
        echo "Deleted event: ${uid}" || \
        die "Event not found: ${uid}"
}

# List calendars
cmd_calendars() {
    local response
    response=$(curl -sf -u "$AUTH" -X PROPFIND \
        -H "Content-Type: application/xml" \
        -H "Depth: 1" \
        --data-binary '<?xml version="1.0" encoding="UTF-8"?>
<D:propfind xmlns:D="DAV:">
  <D:prop>
    <D:displayname/>
    <D:resourcetype/>
  </D:prop>
</D:propfind>' \
        "${BASE}/")

    echo "Calendars:"
    echo "$response" | grep -oE '<displayname>[^<]+</displayname>' | sed 's/<[^>]*>//g' | while read -r name; do
        [ -n "$name" ] && echo "  • $name"
    done
}

# Route commands
case "${1:-help}" in
    create)    shift; cmd_create "$@" ;;
    add)       shift; cmd_add "$@" ;;
    list)      shift; cmd_list "$@" ;;
    delete)    shift; cmd_delete "$@" ;;
    calendars) shift; cmd_calendars "$@" ;;
    help|*)
        echo "Usage: calendar.sh <command> [options]"
        echo ""
        echo "Commands:"
        echo "  create <calendar-id> <display-name>   Create a calendar"
        echo "  add <calendar-id> --title ... --start ...  Add an event"
        echo "  list <calendar-id>                    List events"
        echo "  delete <calendar-id> <uid>            Delete an event"
        echo "  calendars                             List all calendars"
        ;;
esac
