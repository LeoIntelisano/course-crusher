"""Google Calendar events with their names, for the web app.

The CLI keeps freeBusy (`google_calendar.jac`), which needs only the narrow
free/busy scope. The web app asks for read-only calendar access instead, so the
plan and the calendar view can say what each block is and match it to a course.
Events are read on demand and never stored.
"""

import from datetime { date, datetime }
import from urllib.parse { quote }
import from connectors.google_calendar {
    CalendarError,
    MAX_CALENDARS_PER_QUERY,
    REQUEST_TIMEOUT_SECONDS,
    parse_timestamp
}
import from scheduling.time_slots { require_window }

glob EVENTS_URL: str = "https://www.googleapis.com/calendar/v3/calendars/{calendar}/events";
glob READONLY_SCOPE: str = "https://www.googleapis.com/auth/calendar.readonly";
glob EVENT_SCOPES: list[str] = [READONLY_SCOPE];
glob SCOPES_WITH_EVENTS: set[str] = {
    READONLY_SCOPE,
    "https://www.googleapis.com/auth/calendar.events.readonly",
    "https://www.googleapis.com/auth/calendar.events",
    "https://www.googleapis.com/auth/calendar"
};
glob PAGE_SIZE: int = 250;
glob MAX_PAGES: int = 8;
glob UNTITLED: str = "(No title)";
glob EVENT_FIELDS: str = "items(summary,location,status,transparency,start,end,attendees(self,responseStatus)),nextPageToken";
glob READ_ERRORS: dict[int, str] = {403: "forbidden", 404: "notFound"};

"""One calendar entry. Timed events set `start`/`end`; all-day events set the dates (end exclusive)."""
obj CalendarEntry {
    has title: str;
    has location: str = "";
    has start: datetime | None = None;
    has end: datetime | None = None;
    has start_date: date | None = None;
    has end_date: date | None = None;
    has busy: bool = True;
}

def has_event_access(scopes: list[str]) -> bool {
    return bool(set(scopes) & SCOPES_WITH_EVENTS);
}

def declined_by_me(item: dict[str, any]) -> bool {
    return `any([
        attendee.get("self", False) and attendee.get("responseStatus") == "declined"
        for attendee in item.get("attendees", [])
    ]);
}

def read_date(text: str) -> date {
    try {
        return date.fromisoformat(text);
    } except ValueError {
        raise CalendarError(f"Unreadable date from Google: {text!r}") from None;
    }
}

"""An entry the student should see, or None for cancelled, declined or malformed events.

"Show as free" events stay visible but don't block time; all-day events never do.
`item` is decoded JSON, so its values are `any` until each field is read.
"""
def parse_event(item: dict[str, any]) -> CalendarEntry | None {
    if item.get("status") == "cancelled" or declined_by_me(item) {
        return None;
    }
    starts: dict[str, any] = item.get("start", {});
    ends: dict[str, any] = item.get("end", {});
    title = str(item.get("summary") or "").strip() or UNTITLED;
    location = str(item.get("location") or "").strip();
    if "dateTime" in starts and "dateTime" in ends {
        start = parse_timestamp(starts["dateTime"]);
        end = parse_timestamp(ends["dateTime"]);
        if end <= start {
            return None;
        }
        return CalendarEntry(
            title=title,
            location=location,
            start=start,
            end=end,
            busy=item.get("transparency") != "transparent"
        );
    }
    if "date" in starts and "date" in ends {
        return CalendarEntry(
            title=title,
            location=location,
            start_date=read_date(starts["date"]),
            end_date=read_date(ends["date"]),
            busy=False
        );
    }
    return None;
}

"""One page of events.list: the entries worth keeping and the next page token ("" when done)."""
def parse_events_page(payload: dict[str, any]) -> tuple[list[CalendarEntry], str] {
    entries = [parse_event(item) for item in payload.get("items", [])];
    return ([e for e in entries if e is not None], str(payload.get("nextPageToken") or ""));
}

def events_url(calendar_id: str) -> str {
    return EVENTS_URL.format(calendar=quote(calendar_id, safe=""));
}

# `session` is `any` for the same reason as fetch_busy_blocks: production passes
# google-auth's AuthorizedSession and tests pass a fake with the same `get`.
def fetch_calendar_events(
    session: any, calendar_id: str, window_start: datetime, window_end: datetime
) -> list[CalendarEntry] {
    entries: list[CalendarEntry] = [];
    page_token = "";
    for _ in range(MAX_PAGES) {
        params = {
            "timeMin": window_start.isoformat(),
            "timeMax": window_end.isoformat(),
            "singleEvents": "true",
            "orderBy": "startTime",
            "maxResults": PAGE_SIZE,
            "fields": EVENT_FIELDS
        };
        if page_token {
            params = {**params, "pageToken": page_token};
        }
        response = session.get(events_url(calendar_id), params=params, timeout=REQUEST_TIMEOUT_SECONDS);
        if response.status_code in READ_ERRORS {
            # dropping this calendar would show its classes as free time
            raise CalendarError(f"Google Calendar could not read {calendar_id}: {READ_ERRORS[response.status_code]}");
        }
        response.raise_for_status();
        (page, page_token) = parse_events_page(response.json());
        entries = entries + page;
        if not page_token {
            break;
        }
    }
    return entries;
}

"""Every calendar's events in the window, ordered by start (all-day events first each day)."""
def fetch_events(
    session: any, calendar_ids: list[str], window_start: datetime, window_end: datetime
) -> list[CalendarEntry] {
    if not calendar_ids {
        raise ValueError("At least one calendar ID is required");
    }
    if len(calendar_ids) > MAX_CALENDARS_PER_QUERY {
        raise ValueError(f"Read at most {MAX_CALENDARS_PER_QUERY} calendars at once");
    }
    require_window(window_start, window_end);
    return [
        item
        for calendar_id in calendar_ids
        for item in fetch_calendar_events(session, calendar_id, window_start, window_end)
    ];
}
