"""Each student's Google Calendar connection, and the busy time it contributes to the plan.

The link lives on the student's root. Its token never leaves the server: views
report only the connection state, the calendars read, and when they last synced.
"""

import logging;
import from datetime { datetime, timedelta, timezone }
import from google.auth.exceptions { GoogleAuthError, RefreshError }
import from google.auth.transport.requests { AuthorizedSession }
import from requests { RequestException }
import from connectors.google_calendar { CalendarAuthError, CalendarError, fetch_busy_blocks }
import from connectors.google_web_auth {
    finish_consent,
    fresh_credentials,
    revoke_token,
    start_consent,
    web_auth_configured
}
import from scheduling.planner { CalendarEvent }

glob logger: logging.Logger = logging.getLogger("course_crusher.connections");
glob MAX_CALENDARS: int = 10;
glob MAX_CALENDAR_ID_LENGTH: int = 200;
glob CONSENT_TTL: timedelta = timedelta(minutes=10);
glob SETUP_PROBLEM: str = "Google sign-in isn't set up correctly on this server.";
glob READ_PROBLEM: str = "Couldn't read Google Calendar. Showing your plan without it.";

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

obj CalendarStatus {
    has state: str;
    has detail: str;
    has calendars: list[str];
    has last_synced_at: str = "";
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
    return CalendarStatus(
        state=str(LinkState.CONNECTED),
        detail="Connected",
        calendars=link.calendar_ids,
        last_synced_at=link.last_synced_at
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
    return ConnectResult(ok=True, status=status_of(link));
}

"""Google busy time inside the window as calendar events, plus the resulting status.

A failed read is recorded on the link and surfaced in the status, and the plan
goes ahead without Google rather than failing the whole page.
"""
def google_busy_events(window_start: datetime, window_end: datetime) -> tuple[list[CalendarEvent], CalendarStatus] {
    link = ensure_link();
    if not link.token_json or not web_auth_configured() {
        return ([], status_of(link));
    }
    try {
        (credentials, refreshed) = fresh_credentials(link.token_json);
        if refreshed is not None {
            link.token_json = refreshed;
        }
        blocks = fetch_busy_blocks(
            AuthorizedSession(credentials), link.calendar_ids, window_start, window_end
        );
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
    events = [
        CalendarEvent(title="Busy", start=b.start, end=b.end, detail="Google Calendar")
        for b in blocks
    ];
    return (events, status_of(link));
}
