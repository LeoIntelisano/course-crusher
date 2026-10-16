"""Each student's Google Calendar connection, and the busy time it contributes to the plan.

The link lives on the student's root. Its token never leaves the server: views
report only the connection state, the calendars read, and when they last synced.
"""

import json;
import logging;
import time;
import from datetime { datetime, timedelta, timezone }
import from google.auth.exceptions { GoogleAuthError, RefreshError }
import from google.auth.transport.requests { AuthorizedSession }
import from requests { RequestException }
import from connectors.google_calendar { CalendarAuthError, CalendarError, fetch_busy_blocks }
import from connectors.google_events { CalendarEntry, fetch_events, has_event_access }
import from connectors.google_web_auth {
    finish_consent,
    fresh_credentials,
    revoke_token,
    start_consent,
    web_auth_configured
}

glob logger: logging.Logger = logging.getLogger("course_crusher.connections");
glob MAX_CALENDARS: int = 10;
glob MAX_CALENDAR_ID_LENGTH: int = 200;
glob CONSENT_TTL: timedelta = timedelta(minutes=10);
glob SETUP_PROBLEM: str = "Google sign-in isn't set up correctly on this server.";
glob READ_PROBLEM: str = "Couldn't read Google Calendar. Showing your plan without it.";
glob CACHE_SECONDS: float = 60.0;
glob BUSY_TITLE: str = "Busy";

glob DAYS_PER_WEEK: int = 7;

# Recent reads per link and window, so the Today page and the calendar don't each
# call Google on one page load. In memory only: event names are never stored.
glob entry_cache: dict[str, tuple[float, list[CalendarEntry]]] = {};

enum LinkState: str {
    NOT_CONFIGURED = "not_configured",
    DISCONNECTED = "disconnected",
    CONNECTED = "connected",
    ERROR = "error"
}

node GoogleLink {
    has token_json: str = "";
    has calendar_ids: list[str] = ["primary"];
    has pending_state: str = "";
    has pending_verifier: str = "";
    has pending_started_at: str = "";
    has connected_at: str = "";
    has last_synced_at: str = "";
    has last_error: str = "";
}

"""`names` is False for links granted before event names were read; they show busy time only."""
obj CalendarStatus {
    has state: str;
    has detail: str;
    has calendars: list[str];
    has last_synced_at: str = "";
    has names: bool = False;
}

obj ConnectStart {
    has ok: bool;
    has url: str = "";
    has error: str = "";
}

obj ConnectResult {
    has ok: bool;
    has status: CalendarStatus;
    has error: str = "";
}

def ensure_link -> GoogleLink {
    existing = [root-->[?:GoogleLink]];
    if existing {
        return existing[0];
    }
    return root ++> GoogleLink();
}

def now_text -> str {
    return datetime.now(timezone.utc).isoformat();
}

"""Whether a consent started at `started_at` is too old to finish (or was never started)."""
def consent_expired(started_at: str, now: datetime) -> bool {
    if not started_at {
        return True;
    }
    try {
        started = datetime.fromisoformat(started_at);
    } except ValueError {
        return True;
    }
    return now - started > CONSENT_TTL;
}

def clear_pending(link: GoogleLink) {
    link.pending_state = "";
    link.pending_verifier = "";
    link.pending_started_at = "";
}

def token_scopes(link: GoogleLink) -> list[str] {
    if not link.token_json {
        return [];
    }
    try {
        return list(json.loads(link.token_json).get("scopes") or []);
    } except (ValueError, AttributeError) {
        return [];
    }
}

def reads_names(link: GoogleLink) -> bool {
    return has_event_access(token_scopes(link));
}

def forget_cached(link: GoogleLink) {
    prefix = f"{jid(link)}|";
    entry_cache = {key: value for (key, value) in entry_cache.items() if not key.startswith(prefix)};
}

"""Widen a window to whole Monday-to-Monday weeks in its own zone.

Today and the calendar ask for overlapping but different windows; aligned, they
usually share one read and one cache entry.
"""
def aligned_window(window_start: datetime, window_end: datetime) -> tuple[datetime, datetime] {
    zone = window_start.tzinfo;
    first = window_start.date() - timedelta(days=window_start.weekday());
    last = (window_end - timedelta(microseconds=1)).astimezone(zone).date();
    after = last + timedelta(days=DAYS_PER_WEEK - last.weekday());
    return (
        datetime.combine(first, datetime.min.time(), tzinfo=zone),
        datetime.combine(after, datetime.min.time(), tzinfo=zone)
    );
}

def status_of(link: GoogleLink) -> CalendarStatus {
    if not web_auth_configured() {
        return CalendarStatus(
            state=str(LinkState.NOT_CONFIGURED),
            detail="Google sign-in isn't set up on this server yet.",
            calendars=[]
        );
    }
    if not link.token_json {
        return CalendarStatus(
            state=str(LinkState.DISCONNECTED), detail="Not connected", calendars=link.calendar_ids
        );
    }
    if link.last_error {
        return CalendarStatus(
            state=str(LinkState.ERROR),
            detail=link.last_error,
            calendars=link.calendar_ids,
            last_synced_at=link.last_synced_at
        );
    }
    names = reads_names(link);
    return CalendarStatus(
        state=str(LinkState.CONNECTED),
        detail="Connected" if names else "Connected for busy times only. Reconnect to show event names.",
        calendars=link.calendar_ids,
        last_synced_at=link.last_synced_at,
        names=names
    );
}

def:protect calendar_status -> CalendarStatus {
    return status_of(ensure_link());
}

"""Begin consent. The browser goes to `url`; Google sends it back to the callback page."""
def:protect start_google_connect -> ConnectStart {
    if not web_auth_configured() {
        return ConnectStart(ok=False, error="Google sign-in isn't set up on this server yet.");
    }
    try {
        consent = start_consent();
    } except (CalendarAuthError, ValueError, KeyError, TypeError, OSError) as err {
        logger.error("Could not start Google consent: %s", err);
        return ConnectStart(ok=False, error="Couldn't start Google sign-in. Check the server's OAuth client.");
    }
    link = ensure_link();
    link.pending_state = consent.state;
    link.pending_verifier = consent.code_verifier;
    link.pending_started_at = now_text();
    return ConnectStart(ok=True, url=consent.url);
}

def connect_failed(link: GoogleLink, message: str) -> ConnectResult {
    return ConnectResult(ok=False, error=message, status=status_of(link));
}

"""Finish consent with the `code` and `state` Google appended to the callback URL."""
def:protect finish_google_connect(code: str, state: str) -> ConnectResult {
    link = ensure_link();
    if not link.pending_state or state != link.pending_state {
        return connect_failed(link, "This sign-in link expired. Start again from Connections.");
    }
    if consent_expired(link.pending_started_at, datetime.now(timezone.utc)) {
        clear_pending(link);
        return connect_failed(link, "This sign-in link expired. Start again from Connections.");
    }
    if not code {
        return connect_failed(link, "Google didn't return an authorization code.");
    }
    verifier = link.pending_verifier;
    clear_pending(link);
    try {
        token = finish_consent(code, state, verifier);
    } except (CalendarAuthError, GoogleAuthError, RequestException, ValueError, KeyError, TypeError, OSError, Warning) as err {
        logger.error("Google token exchange failed: %s", err);
        return connect_failed(link, "Google sign-in didn't complete. Try connecting again.");
    }
    link.token_json = token;
    link.connected_at = now_text();
    link.last_error = "";
    forget_cached(link);
    return ConnectResult(ok=True, status=status_of(link));
}

"""Revoke the grant at Google (best effort), then forget the token."""
def:protect disconnect_google -> CalendarStatus {
    link = ensure_link();
    if link.token_json {
        try {
            if not revoke_token(link.token_json) {
                logger.warning("Google did not confirm token revocation");
            }
        } except (RequestException, ValueError) as err {
            logger.warning("Google token revocation failed: %s", err);
        }
    }
    link.token_json = "";
    forget_cached(link);
    clear_pending(link);
    link.last_error = "";
    link.last_synced_at = "";
    return status_of(link);
}

def:protect set_google_calendars(calendar_ids: list[str]) -> ConnectResult {
    link = ensure_link();
    cleaned = [cid.strip() for cid in calendar_ids if cid.strip()];
    if not cleaned {
        return connect_failed(link, "Keep at least one calendar, e.g. primary.");
    }
    if len(cleaned) > MAX_CALENDARS or [c for c in cleaned if len(c) > MAX_CALENDAR_ID_LENGTH] {
        return connect_failed(link, f"Read at most {MAX_CALENDARS} calendars.");
    }
    link.calendar_ids = list(dict.fromkeys(cleaned));
    forget_cached(link);
    return ConnectResult(ok=True, status=status_of(link));
}

"""Read the window from Google: named events when the grant allows it, else busy blocks titled "Busy"."""
def read_google(link: GoogleLink, window_start: datetime, window_end: datetime) -> list[CalendarEntry] {
    (credentials, refreshed) = fresh_credentials(link.token_json);
    if refreshed is not None {
        link.token_json = refreshed;
    }
    session = AuthorizedSession(credentials);
    if reads_names(link) {
        return fetch_events(session, link.calendar_ids, window_start, window_end);
    }
    return [
        CalendarEntry(title=BUSY_TITLE, start=b.start, end=b.end)
        for b in fetch_busy_blocks(session, link.calendar_ids, window_start, window_end)
    ];
}

"""The student's Google entries inside the window, plus the resulting status.

A failed read is recorded on the link and surfaced in the status, and the plan
goes ahead without Google rather than failing the whole page.
"""
def google_entries(window_start: datetime, window_end: datetime) -> tuple[list[CalendarEntry], CalendarStatus] {
    link = ensure_link();
    if not link.token_json or not web_auth_configured() {
        return ([], status_of(link));
    }
    (read_start, read_end) = aligned_window(window_start, window_end);
    cache_key = f"{jid(link)}|{read_start.isoformat()}|{read_end.isoformat()}";
    now = time.monotonic();
    cached = entry_cache.get(cache_key);
    if cached is not None and now - cached[0] < CACHE_SECONDS {
        return (cached[1], status_of(link));
    }
    try {
        entries = read_google(link, read_start, read_end);
    } except RefreshError as err {
        logger.warning("Google refresh rejected: %s", err);
        link.last_error = "Google access expired. Reconnect Google Calendar.";
        return ([], status_of(link));
    } except CalendarError as err {
        # our own message, e.g. which calendar Google couldn't read
        logger.warning("Google Calendar read failed: %s", err);
        link.last_error = str(err);
        return ([], status_of(link));
    } except (CalendarAuthError, ValueError, KeyError, TypeError, OSError) as err {
        logger.error("Google Calendar configuration problem: %s", err);
        link.last_error = SETUP_PROBLEM;
        return ([], status_of(link));
    } except (GoogleAuthError, RequestException) as err {
        logger.warning("Google Calendar request failed: %s", err);
        link.last_error = READ_PROBLEM;
        return ([], status_of(link));
    }
    link.last_synced_at = now_text();
    link.last_error = "";
    fresh = {key: value for (key, value) in entry_cache.items() if now - value[0] < CACHE_SECONDS};
    entry_cache = {**fresh, cache_key: (now, entries)};
    return (entries, status_of(link));
}
