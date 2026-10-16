"""Google Calendar connector: busy periods from the freeBusy API.

freeBusy is used instead of events.list because it needs only the narrow
`calendar.freebusy` scope and already applies "show as free", declined
invitations and recurring-event expansion. docs/connectors/google-calendar.md
covers the trade-offs and the OAuth setup.
"""

import json;
import logging;
import os;
import from datetime { datetime }
import from pathlib { Path }
import from google.auth.exceptions { RefreshError }
import from google.auth.transport.requests { AuthorizedSession, Request }
import from google.oauth2.credentials { Credentials }
import from google_auth_oauthlib.flow { InstalledAppFlow }
import from scheduling.time_slots { BusyBlock, require_window }

glob FREEBUSY_URL: str = "https://www.googleapis.com/calendar/v3/freeBusy";
glob GOOGLE_SCOPES: list[str] = ["https://www.googleapis.com/auth/calendar.freebusy"];
glob MAX_CALENDARS_PER_QUERY: int = 50;
glob REQUEST_TIMEOUT_SECONDS: int = 10;
glob CLIENT_SECRETS_ENV: str = "GOOGLE_CLIENT_SECRETS_FILE";
glob TOKEN_FILE_ENV: str = "GOOGLE_TOKEN_FILE";
glob DEFAULT_TOKEN_FILE: str = "~/.config/course-crusher/google-token.json";
glob TOKEN_DIR_MODE: int = 0o700;
glob TOKEN_FILE_MODE: int = 0o600;

glob logger: logging.Logger = logging.getLogger("course_crusher.google_calendar");

"""Google answered, but not with usable busy data."""
obj CalendarError(Exception) {}

"""Credentials are missing or misconfigured; raised before any network call."""
obj CalendarAuthError(Exception) {}

def build_freebusy_request(
    calendar_ids: list[str], window_start: datetime, window_end: datetime
) -> dict[str, str | list[dict[str, str]]] {
    if not calendar_ids {
        raise ValueError("At least one calendar ID is required");
    }
    if len(calendar_ids) > MAX_CALENDARS_PER_QUERY {
        raise ValueError(
            f"freeBusy accepts at most {MAX_CALENDARS_PER_QUERY} calendars per query"
        );
    }
    require_window(window_start, window_end);
    return {
        "timeMin": window_start.isoformat(),
        "timeMax": window_end.isoformat(),
        "items": [{"id": calendar_id} for calendar_id in calendar_ids]
    };
}

def parse_timestamp(text: str) -> datetime {
    try {
        value = datetime.fromisoformat(text);
    } except ValueError as err {
        raise CalendarError(f"Unreadable timestamp from Google: {text!r}") from err;
    }
    if value.tzinfo is None {
        raise CalendarError(f"Timestamp from Google has no UTC offset: {text!r}");
    }
    return value;
}

"""Flatten every calendar's busy periods into one list.

Overlaps between calendars are left in place; find_free_slots merges them.
Any per-calendar error fails the whole read, because silently dropping a
calendar would report its classes as free time. `payload` is decoded JSON,
so its values are `any` until each field is read.
"""
def parse_freebusy_response(payload: dict[str, any]) -> list[BusyBlock] {
    calendars: dict[str, any] = payload.get("calendars", {});
    errors = [
        f"{calendar_id}: {err.get('reason', 'unknown')}"
        for (calendar_id, calendar) in calendars.items()
        for err in calendar.get("errors", [])
    ];
    if errors {
        raise CalendarError(f"Google Calendar could not read {', '.join(errors)}");
    }
    return [
        BusyBlock(start=parse_timestamp(period["start"]), end=parse_timestamp(period["end"]))
        for calendar in calendars.values()
        for period in calendar.get("busy", [])
    ];
}

"""Read a saved freeBusy response. Lets tests and demos run without credentials."""
def load_freebusy_fixture(path: str) -> list[BusyBlock] {
    with open(path, encoding="utf-8") as handle {
        payload = json.load(handle);
    }
    return parse_freebusy_response(payload);
}

# `session` is `any` because production passes google-auth's AuthorizedSession
# and tests pass a fake; both expose the requests.Session `post` signature.
def fetch_busy_blocks(
    session: any, calendar_ids: list[str], window_start: datetime, window_end: datetime
) -> list[BusyBlock] {
    response = session.post(
        FREEBUSY_URL,
        json=build_freebusy_request(calendar_ids, window_start, window_end),
        timeout=REQUEST_TIMEOUT_SECONDS
    );
    response.raise_for_status();
    return parse_freebusy_response(response.json());
}

def require_client_secrets -> str {
    secrets_path = os.environ.get(CLIENT_SECRETS_ENV, "");
    if not secrets_path {
        raise CalendarAuthError(
            f"{CLIENT_SECRETS_ENV} is not set. Point it at the OAuth client JSON "
            "downloaded from Google Cloud Console (see docs/connectors/google-calendar.md)."
        );
    }
    if not Path(secrets_path).expanduser().is_file() {
        raise CalendarAuthError(f"{CLIENT_SECRETS_ENV} points to {secrets_path}, which does not exist.");
    }
    return str(Path(secrets_path).expanduser());
}

def token_file_path -> Path {
    return Path(os.environ.get(TOKEN_FILE_ENV, DEFAULT_TOKEN_FILE)).expanduser();
}

def write_token(token_path: Path, token_json: str) {
    token_path.parent.mkdir(parents=True, exist_ok=True, mode=TOKEN_DIR_MODE);
    descriptor = os.open(str(token_path), os.O_WRONLY | os.O_CREAT | os.O_TRUNC, TOKEN_FILE_MODE);
    with os.fdopen(descriptor, "w", encoding="utf-8") as handle {
        handle.write(token_json);
    }
    # O_CREAT's mode only applies to new files; tighten one left by an older run.
    os.chmod(token_path, TOKEN_FILE_MODE);
}

"""The cached token, refreshed if needed, or None when the browser flow must run."""
def cached_credentials(token_path: Path) -> Credentials | None {
    if not token_path.is_file() {
        return None;
    }
    credentials = Credentials.from_authorized_user_file(str(token_path), GOOGLE_SCOPES) as Credentials;
    if credentials.valid {
        return credentials;
    }
    if not (credentials.expired and credentials.refresh_token) {
        return None;
    }
    try {
        credentials.refresh(Request());
    } except RefreshError as err {
        logger.warning("Google token refresh failed, re-running consent: %s", err);
        return None;
    }
    write_token(token_path, str(credentials.to_json()));
    return credentials;
}

"""OAuth credentials for the freeBusy scope, using the installed-app loopback flow.

The first run opens a browser for consent; the token is then cached outside the
repo and refreshed silently.
"""
def load_credentials -> Credentials {
    secrets_path = require_client_secrets();
    token_path = token_file_path();
    cached = cached_credentials(token_path);
    if cached is not None {
        return cached;
    }
    consent = InstalledAppFlow.from_client_secrets_file(secrets_path, GOOGLE_SCOPES);
    credentials = consent.run_local_server(port=0) as Credentials;
    write_token(token_path, str(credentials.to_json()));
    return credentials;
}

def authorized_session -> AuthorizedSession {
    return AuthorizedSession(load_credentials());
}
