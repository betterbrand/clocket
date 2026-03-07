#!/usr/bin/env bash
set -euo pipefail

# Clocket — Calendar Management for OpenClaw Agents
# https://github.com/BetterBrand/Clocket
#
# Usage: clocket.sh <command> <calendar> [options]
#
# Commands:
#   create <calendar-id> <display-name>     Create a new calendar
#   add <calendar-id> [options]             Add an event
#   list <calendar-id> [--upcoming N]       List events (sorted by date)
#   search <calendar-id> <query>            Search events by text
#   update <calendar-id> <uid> [options]    Update an event
#   delete <calendar-id> <uid>              Delete an event
#   calendars                               List all calendars
#   status                                  Server health check

# ── Config ───────────────────────────────────────────────────

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
DATA_DIR="${HOME}/.openclaw/workspace/data/radicale/collections/collection-root/${RADICALE_USER}"

# Global flags
JSON_OUTPUT=false

die() { echo "ERROR: $*" >&2; exit 1; }

gen_uid() {
    echo "evt-$(date +%Y%m%d%H%M%S)-$(openssl rand -hex 4)"
}

# ── Helpers ──────────────────────────────────────────────────

# Parse an .ics file and extract VEVENT fields
# Output: tab-separated line for sorting/filtering
parse_ics() {
    local f="$1"
    local vevent=$(sed -n '/^BEGIN:VEVENT/,/^END:VEVENT/p' "$f")
    [ -z "$vevent" ] && return

    local summary=$(echo "$vevent" | grep "^SUMMARY:" | head -1 | sed 's/^SUMMARY://')
    local dtstart=$(echo "$vevent" | grep "^DTSTART" | head -1 | sed 's/^DTSTART[^:]*://')
    local dtend=$(echo "$vevent" | grep "^DTEND" | head -1 | sed 's/^DTEND[^:]*://')
    local uid=$(echo "$vevent" | grep "^UID:" | head -1 | sed 's/^UID://')
    local rrule=$(echo "$vevent" | grep "^RRULE:" | head -1 | sed 's/^RRULE://')
    local location=$(echo "$vevent" | grep "^LOCATION:" | head -1 | sed 's/^LOCATION://')
    local description=$(echo "$vevent" | grep "^DESCRIPTION:" | head -1 | sed 's/^DESCRIPTION://')
    local status=$(echo "$vevent" | grep "^STATUS:" | head -1 | sed 's/^STATUS://')

    # Format datetime for display (20260305T093000 → 2026-03-05 09:30)
    local display_date=""
    if [ -n "$dtstart" ]; then
        display_date=$(echo "$dtstart" | sed 's/\([0-9]\{4\}\)\([0-9]\{2\}\)\([0-9]\{2\}\)T\([0-9]\{2\}\)\([0-9]\{2\}\).*/\1-\2-\3 \4:\5/')
    fi

    local display_end=""
    if [ -n "$dtend" ]; then
        display_end=$(echo "$dtend" | sed 's/\([0-9]\{4\}\)\([0-9]\{2\}\)\([0-9]\{2\}\)T\([0-9]\{2\}\)\([0-9]\{2\}\).*/\1-\2-\3 \4:\5/')
    fi

    # Human-readable recurrence
    local recur_human=""
    if [ -n "$rrule" ]; then
        case "$rrule" in
            *FREQ=DAILY*)   recur_human="daily" ;;
            *FREQ=WEEKLY*)
                local byday=$(echo "$rrule" | grep -o 'BYDAY=[A-Z,]*' | sed 's/BYDAY=//')
                if [ -n "$byday" ]; then
                    recur_human="weekly (${byday})"
                else
                    recur_human="weekly"
                fi
                ;;
            *FREQ=MONTHLY*) recur_human="monthly" ;;
            *FREQ=YEARLY*)  recur_human="yearly" ;;
            *)              recur_human="$rrule" ;;
        esac
    fi

    # Tab-separated for sorting: sortkey|date|end|title|uid|recur|location|description|status
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$dtstart" "$display_date" "$display_end" "$summary" "$uid" "$recur_human" "$location" "$description" "$status"
}

# ── Commands ─────────────────────────────────────────────────

# Build VTIMEZONE block
build_vtimezone() {
    local tz="$1"
    case "$tz" in
        America/Los_Angeles)
            cat <<'VTEOF'
BEGIN:VTIMEZONE
TZID:America/Los_Angeles
BEGIN:STANDARD
DTSTART:20071104T020000
RRULE:FREQ=YEARLY;BYDAY=1SU;BYMONTH=11
TZOFFSETFROM:-0700
TZOFFSETTO:-0800
TZNAME:PST
END:STANDARD
BEGIN:DAYLIGHT
DTSTART:20070311T020000
RRULE:FREQ=YEARLY;BYDAY=2SU;BYMONTH=3
TZOFFSETFROM:-0800
TZOFFSETTO:-0700
TZNAME:PDT
END:DAYLIGHT
END:VTIMEZONE
VTEOF
            ;;
        America/Denver)
            cat <<'VTEOF'
BEGIN:VTIMEZONE
TZID:America/Denver
BEGIN:STANDARD
DTSTART:20071104T020000
RRULE:FREQ=YEARLY;BYDAY=1SU;BYMONTH=11
TZOFFSETFROM:-0600
TZOFFSETTO:-0700
TZNAME:MST
END:STANDARD
BEGIN:DAYLIGHT
DTSTART:20070311T020000
RRULE:FREQ=YEARLY;BYDAY=2SU;BYMONTH=3
TZOFFSETFROM:-0700
TZOFFSETTO:-0600
TZNAME:MDT
END:DAYLIGHT
END:VTIMEZONE
VTEOF
            ;;
        America/Chicago)
            cat <<'VTEOF'
BEGIN:VTIMEZONE
TZID:America/Chicago
BEGIN:STANDARD
DTSTART:20071104T020000
RRULE:FREQ=YEARLY;BYDAY=1SU;BYMONTH=11
TZOFFSETFROM:-0500
TZOFFSETTO:-0600
TZNAME:CST
END:STANDARD
BEGIN:DAYLIGHT
DTSTART:20070311T020000
RRULE:FREQ=YEARLY;BYDAY=2SU;BYMONTH=3
TZOFFSETFROM:-0600
TZOFFSETTO:-0500
TZNAME:CDT
END:DAYLIGHT
END:VTIMEZONE
VTEOF
            ;;
        America/New_York)
            cat <<'VTEOF'
BEGIN:VTIMEZONE
TZID:America/New_York
BEGIN:STANDARD
DTSTART:20071104T020000
RRULE:FREQ=YEARLY;BYDAY=1SU;BYMONTH=11
TZOFFSETFROM:-0400
TZOFFSETTO:-0500
TZNAME:EST
END:STANDARD
BEGIN:DAYLIGHT
DTSTART:20070311T020000
RRULE:FREQ=YEARLY;BYDAY=2SU;BYMONTH=3
TZOFFSETFROM:-0500
TZOFFSETTO:-0400
TZNAME:EDT
END:DAYLIGHT
END:VTIMEZONE
VTEOF
            ;;
        UTC|Etc/UTC)
            echo ""
            ;;
        *)
            # Generic — agent can extend
            echo ""
            ;;
    esac
}

cmd_create() {
    local cal_id="${1:?Usage: clocket.sh create <calendar-id> <display-name>}"
    local display_name="${2:-$cal_id}"

    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" -u "$AUTH" -X MKCOL \
        -H "Content-Type: application/xml" \
        --data-binary "<?xml version='1.0' encoding='UTF-8'?>
<mkcol xmlns='DAV:' xmlns:C='urn:ietf:params:xml:ns:caldav'>
  <set><prop>
    <resourcetype><collection/><C:calendar/></resourcetype>
    <displayname>${display_name}</displayname>
  </prop></set>
</mkcol>" \
        "${BASE}/${cal_id}/")

    if [[ "$http_code" =~ ^2 ]]; then
        if $JSON_OUTPUT; then
            printf '{"ok":true,"calendar":"%s","name":"%s"}\n' "$cal_id" "$display_name"
        else
            echo "✓ Created calendar: ${cal_id} (${display_name})"
        fi
    else
        die "Failed to create calendar (HTTP ${http_code}). Already exists?"
    fi
}

cmd_add() {
    local cal_id="${1:?Usage: clocket.sh add <calendar-id> --title ... --start ...}"
    shift

    local title="" start="" end="" description="" location="" recurring="" tz=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --title) title="$2"; shift 2 ;;
            --start) start="$2"; shift 2 ;;
            --end) end="$2"; shift 2 ;;
            --description) description="$2"; shift 2 ;;
            --location) location="$2"; shift 2 ;;
            --recurring) recurring="$2"; shift 2 ;;
            --tz|--timezone) tz="$2"; shift 2 ;;
            *) die "Unknown option: $1" ;;
        esac
    done

    [ -z "$title" ] && die "--title is required"
    [ -z "$start" ] && die "--start is required (format: YYYY-MM-DDTHH:MM)"

    # Default end = start + 1 hour
    if [ -z "$end" ]; then
        if command -v gdate &>/dev/null; then
            end=$(gdate -d "${start} + 1 hour" "+%Y-%m-%dT%H:%M" 2>/dev/null || echo "$start")
        elif [[ "$(uname)" == "Darwin" ]]; then
            end=$(date -j -f "%Y-%m-%dT%H:%M" -v+1H "$start" "+%Y-%m-%dT%H:%M" 2>/dev/null || echo "$start")
        else
            end=$(date -d "${start} + 1 hour" "+%Y-%m-%dT%H:%M" 2>/dev/null || echo "$start")
        fi
    fi

    local uid=$(gen_uid)
    local dtstart=$(echo "$start" | tr -d ':-' | sed 's/\([0-9]\{8\}\)\([0-9]\{4\}\)/\1T\2/')
    local dtend=$(echo "$end" | tr -d ':-' | sed 's/\([0-9]\{8\}\)\([0-9]\{4\}\)/\1T\2/')

    local rrule=""
    case "${recurring:-}" in
        daily)   rrule="RRULE:FREQ=DAILY" ;;
        weekly)  rrule="RRULE:FREQ=WEEKLY" ;;
        monthly) rrule="RRULE:FREQ=MONTHLY" ;;
        yearly)  rrule="RRULE:FREQ=YEARLY" ;;
        "")      ;;
        *)       die "Unknown recurring type: $recurring (daily|weekly|monthly|yearly)" ;;
    esac

    # Build iCal
    local ical="BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//Clocket//EN"

    if [ -n "$tz" ]; then
        local tzblock=$(build_vtimezone "$tz")
        [ -n "$tzblock" ] && ical="${ical}
${tzblock}"
    fi

    ical="${ical}
BEGIN:VEVENT
UID:${uid}@clocket"

    if [ -n "$tz" ]; then
        ical="${ical}
DTSTART;TZID=${tz}:${dtstart}
DTEND;TZID=${tz}:${dtend}"
    else
        ical="${ical}
DTSTART:${dtstart}
DTEND:${dtend}"
    fi

    ical="${ical}
SUMMARY:${title}"
    [ -n "$description" ] && ical="${ical}
DESCRIPTION:${description}"
    [ -n "$location" ] && ical="${ical}
LOCATION:${location}"
    [ -n "$rrule" ] && ical="${ical}
${rrule}"
    ical="${ical}
DTSTAMP:$(date -u +%Y%m%dT%H%M%SZ)
STATUS:CONFIRMED
END:VEVENT
END:VCALENDAR"

    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" -u "$AUTH" -X PUT \
        -H "Content-Type: text/calendar" \
        --data-binary "$ical" \
        "${BASE}/${cal_id}/${uid}.ics")

    if [[ "$http_code" =~ ^2 ]]; then
        if $JSON_OUTPUT; then
            printf '{"ok":true,"uid":"%s@clocket","title":"%s","start":"%s","end":"%s"' "$uid" "$title" "$start" "$end"
            [ -n "$recurring" ] && printf ',"recurring":"%s"' "$recurring"
            [ -n "$tz" ] && printf ',"tz":"%s"' "$tz"
            printf '}\n'
        else
            echo "✓ Added: ${title}"
            echo "  UID: ${uid}@clocket"
            [ -n "$recurring" ] && echo "  Recurring: ${recurring}"
            [ -n "$tz" ] && echo "  Timezone: ${tz}"
        fi
    else
        die "Failed to add event (HTTP ${http_code})"
    fi
}

cmd_list() {
    local cal_id="${1:?Usage: clocket.sh list <calendar-id>}"
    shift || true
    local upcoming=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --upcoming) upcoming="${2:-5}"; shift 2 ;;
            *) shift ;;
        esac
    done

    local ics_dir="${DATA_DIR}/${cal_id}"
    [ -d "$ics_dir" ] || die "Calendar not found: ${cal_id}"

    local tmpfile=$(mktemp)
    trap "rm -f '$tmpfile'" EXIT

    for f in "$ics_dir"/*.ics; do
        [ -f "$f" ] || continue
        parse_ics "$f" >> "$tmpfile"
    done

    local total=$(wc -l < "$tmpfile" | tr -d ' ')

    if [ "$total" -eq 0 ]; then
        if $JSON_OUTPUT; then
            echo '{"events":[],"count":0}'
        else
            echo "(no events in ${cal_id})"
        fi
        return
    fi

    # Sort by dtstart, optionally limit
    local sorted
    if [ -n "$upcoming" ]; then
        # Filter to future events only (compare with today's date)
        local today=$(date +%Y%m%dT%H%M%S)
        sorted=$(sort -t$'\t' -k1 "$tmpfile" | awk -F'\t' -v today="$today" '$1 >= today || $6 != ""' | head -n "$upcoming")
    else
        sorted=$(sort -t$'\t' -k1 "$tmpfile")
    fi

    if $JSON_OUTPUT; then
        echo '{"events":['
        local first=true
        echo "$sorted" | while IFS=$'\t' read -r sortkey date end title uid recur location desc status; do
            [ -z "$title" ] && continue
            $first || printf ','
            first=false
            printf '{"date":"%s","end":"%s","title":"%s","uid":"%s"' "$date" "$end" "$title" "$uid"
            [ -n "$recur" ] && printf ',"recurring":"%s"' "$recur"
            [ -n "$location" ] && printf ',"location":"%s"' "$location"
            [ -n "$desc" ] && printf ',"description":"%s"' "$desc"
            printf '}\n'
        done
        local shown
        if [ -n "$upcoming" ]; then
            shown=$(echo "$sorted" | grep -c . || echo 0)
        else
            shown=$total
        fi
        printf '],"count":%d}\n' "$shown"
    else
        echo "$sorted" | while IFS=$'\t' read -r sortkey date end title uid recur location desc status; do
            [ -z "$title" ] && continue
            printf "  %s  %s\n" "$date" "$title"
            [ -n "$recur" ] && printf "             ↻ %s\n" "$recur"
            [ -n "$location" ] && printf "             📍 %s\n" "$location"
            [ -n "$desc" ] && printf "             📝 %s\n" "$desc"
            printf "             id: %s\n\n" "$uid"
        done
        if [ -n "$upcoming" ]; then
            local shown=$(echo "$sorted" | grep -c . || echo 0)
            echo "${shown} of ${total} event(s) shown (--upcoming ${upcoming})"
        else
            echo "${total} event(s)"
        fi
    fi
}

cmd_search() {
    local cal_id="${1:?Usage: clocket.sh search <calendar-id> <query>}"
    local query="${2:?Usage: clocket.sh search <calendar-id> <query>}"

    local ics_dir="${DATA_DIR}/${cal_id}"
    [ -d "$ics_dir" ] || die "Calendar not found: ${cal_id}"

    local query_lower=$(echo "$query" | tr '[:upper:]' '[:lower:]')
    local count=0

    if $JSON_OUTPUT; then
        echo '{"results":['
        local first=true
    fi

    for f in "$ics_dir"/*.ics; do
        [ -f "$f" ] || continue
        local content_lower=$(cat "$f" | tr '[:upper:]' '[:lower:]')
        if echo "$content_lower" | grep -q "$query_lower"; then
            local parsed=$(parse_ics "$f")
            [ -z "$parsed" ] && continue
            count=$((count + 1))

            if $JSON_OUTPUT; then
                echo "$parsed" | while IFS=$'\t' read -r sortkey date end title uid recur location desc status; do
                    $first || printf ','
                    first=false
                    printf '{"date":"%s","title":"%s","uid":"%s"' "$date" "$title" "$uid"
                    [ -n "$recur" ] && printf ',"recurring":"%s"' "$recur"
                    [ -n "$location" ] && printf ',"location":"%s"' "$location"
                    printf '}\n'
                done
            else
                echo "$parsed" | while IFS=$'\t' read -r sortkey date end title uid recur location desc status; do
                    printf "  %s  %s\n" "$date" "$title"
                    [ -n "$recur" ] && printf "             ↻ %s\n" "$recur"
                    printf "             id: %s\n\n" "$uid"
                done
            fi
        fi
    done

    if $JSON_OUTPUT; then
        printf '],"query":"%s","count":%d}\n' "$query" "$count"
    else
        echo "${count} result(s) for \"${query}\""
    fi
}

cmd_update() {
    local cal_id="${1:?Usage: clocket.sh update <calendar-id> <uid> --title ...}"
    local uid_input="${2:?Usage: clocket.sh update <calendar-id> <uid> --title ...}"
    shift 2

    local uid_base=$(echo "$uid_input" | sed 's/@clocket$//' | sed 's/@radicale-skill$//' | sed 's/@fieldcraft$//')
    local ics_file="${DATA_DIR}/${cal_id}/${uid_base}.ics"

    [ -f "$ics_file" ] || die "Event not found: ${uid_input}"

    local new_title="" new_desc="" new_location="" new_start="" new_end=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --title) new_title="$2"; shift 2 ;;
            --description) new_desc="$2"; shift 2 ;;
            --location) new_location="$2"; shift 2 ;;
            --start) new_start="$2"; shift 2 ;;
            --end) new_end="$2"; shift 2 ;;
            *) die "Unknown option: $1" ;;
        esac
    done

    local content=$(cat "$ics_file")

    [ -n "$new_title" ] && content=$(echo "$content" | sed "s/^SUMMARY:.*$/SUMMARY:${new_title}/")
    if [ -n "$new_desc" ]; then
        if echo "$content" | grep -q "^DESCRIPTION:"; then
            content=$(echo "$content" | sed "s/^DESCRIPTION:.*$/DESCRIPTION:${new_desc}/")
        else
            content=$(echo "$content" | sed "/^SUMMARY:/a\\
DESCRIPTION:${new_desc}")
        fi
    fi
    if [ -n "$new_location" ]; then
        if echo "$content" | grep -q "^LOCATION:"; then
            content=$(echo "$content" | sed "s/^LOCATION:.*$/LOCATION:${new_location}/")
        else
            content=$(echo "$content" | sed "/^SUMMARY:/a\\
LOCATION:${new_location}")
        fi
    fi

    # Update DTSTAMP
    content=$(echo "$content" | sed "s/^DTSTAMP:.*$/DTSTAMP:$(date -u +%Y%m%dT%H%M%SZ)/")

    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" -u "$AUTH" -X PUT \
        -H "Content-Type: text/calendar" \
        --data-binary "$content" \
        "${BASE}/${cal_id}/${uid_base}.ics")

    if [[ "$http_code" =~ ^2 ]]; then
        if $JSON_OUTPUT; then
            printf '{"ok":true,"uid":"%s","updated":true}\n' "$uid_input"
        else
            echo "✓ Updated: ${uid_input}"
        fi
    else
        die "Failed to update event (HTTP ${http_code})"
    fi
}

cmd_delete() {
    local cal_id="${1:?Usage: clocket.sh delete <calendar-id> <uid>}"
    local uid_input="${2:?Usage: clocket.sh delete <calendar-id> <uid>}"

    local uid_base=$(echo "$uid_input" | sed 's/@clocket$//' | sed 's/@radicale-skill$//' | sed 's/@fieldcraft$//')

    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" -u "$AUTH" -X DELETE \
        "${BASE}/${cal_id}/${uid_base}.ics")

    if [[ "$http_code" =~ ^2 ]]; then
        if $JSON_OUTPUT; then
            printf '{"ok":true,"uid":"%s","deleted":true}\n' "$uid_input"
        else
            echo "✓ Deleted: ${uid_input}"
        fi
    else
        die "Event not found or delete failed (HTTP ${http_code})"
    fi
}

cmd_calendars() {
    if [ ! -d "$DATA_DIR" ]; then
        if $JSON_OUTPUT; then
            echo '{"calendars":[]}'
        else
            echo "(no calendars)"
        fi
        return
    fi

    if $JSON_OUTPUT; then
        echo '{"calendars":['
        local first=true
        for d in "$DATA_DIR"/*/; do
            [ -d "$d" ] || continue
            local name=$(basename "$d")
            local count=$(find "$d" -maxdepth 1 -name "*.ics" 2>/dev/null | wc -l | tr -d ' ')
            local display_name=""
            if [ -f "$d/.Radicale.props" ]; then
                display_name=$(grep -o '"D:displayname": "[^"]*"' "$d/.Radicale.props" 2>/dev/null | cut -d'"' -f4 || echo "")
            fi
            $first || printf ','
            first=false
            printf '{"id":"%s","name":"%s","events":%d}\n' "$name" "${display_name:-$name}" "$count"
        done
        echo ']}'
    else
        echo "Calendars:"
        for d in "$DATA_DIR"/*/; do
            [ -d "$d" ] || continue
            local name=$(basename "$d")
            local count=$(find "$d" -maxdepth 1 -name "*.ics" 2>/dev/null | wc -l | tr -d ' ')
            local display_name=""
            if [ -f "$d/.Radicale.props" ]; then
                display_name=$(grep -o '"D:displayname": "[^"]*"' "$d/.Radicale.props" 2>/dev/null | cut -d'"' -f4 || echo "")
            fi
            if [ -n "$display_name" ]; then
                echo "  • ${display_name} (${name}) — ${count} event(s)"
            else
                echo "  • ${name} — ${count} event(s)"
            fi
        done
    fi
}

cmd_status() {
    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" -u "$AUTH" "${RADICALE_URL}/.well-known/caldav" 2>/dev/null || echo "000")

    if [[ "$http_code" =~ ^[23] ]]; then
        if $JSON_OUTPUT; then
            printf '{"ok":true,"url":"%s",' "$RADICALE_URL"
            cmd_calendars | tail -n +1
        else
            echo "✓ Radicale running on ${RADICALE_URL}"
            cmd_calendars
        fi
    else
        if $JSON_OUTPUT; then
            printf '{"ok":false,"url":"%s","http_code":"%s"}\n' "$RADICALE_URL" "$http_code"
        else
            echo "✗ Radicale not responding (HTTP ${http_code})"
            echo "  Try: launchctl load ~/Library/LaunchAgents/com.clocket.plist"
        fi
    fi
}

# ── Main ─────────────────────────────────────────────────────

# Check for global --json flag
ARGS=()
for arg in "$@"; do
    if [ "$arg" = "--json" ]; then
        JSON_OUTPUT=true
    else
        ARGS+=("$arg")
    fi
done
set -- "${ARGS[@]+"${ARGS[@]}"}"

case "${1:-help}" in
    create)    shift; cmd_create "$@" ;;
    add)       shift; cmd_add "$@" ;;
    list)      shift; cmd_list "$@" ;;
    search)    shift; cmd_search "$@" ;;
    update)    shift; cmd_update "$@" ;;
    delete)    shift; cmd_delete "$@" ;;
    calendars) cmd_calendars ;;
    status)    cmd_status ;;
    help|*)
        cat <<'EOF'
Clocket — Calendar for OpenClaw Agents

Usage: clocket.sh <command> [options]

Commands:
  create <id> <name>                     Create a calendar
  add <id> --title ... --start ...       Add an event
  list <id> [--upcoming N]               List events
  search <id> <query>                    Search events by text
  update <id> <uid> --title ...          Update an event
  delete <id> <uid>                      Delete an event
  calendars                              List all calendars
  status                                 Server health check

Options (add/update):
  --title <text>          Event title (required for add)
  --start <datetime>      Start time: YYYY-MM-DDTHH:MM (required for add)
  --end <datetime>        End time (default: start + 1h)
  --description <text>    Event description
  --location <text>       Event location
  --recurring <freq>      daily | weekly | monthly | yearly
  --tz <timezone>         Timezone (e.g. America/Los_Angeles)

Global:
  --json                  Output as JSON (for agent consumption)
EOF
        ;;
esac
