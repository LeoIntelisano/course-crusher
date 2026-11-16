"""Per-student, read-only Google iCal subscriptions without OAuth callbacks.

The secret URL is stored only on the authenticated user's root. It is never
included in the status returned to the browser. No external calendar entries
are persisted; the server fetches them when building a plan.
"""
import time;
import from datetime { datetime, timedelta, timezone }
import from connectors.ical_feed { IcalFeedError, fetch_ical, validate_ical_url }
import from connectors.google_events { CalendarEntry }

# Avoid refetching the same week's subscription on every UI request.
glob ICAL_CACHE_SECONDS: float = 300.0;
glob ical_cache: dict[str, tuple[float, list[CalendarEntry]]] = {};

node IcalLink {
    has feed_url: str = "";
    has last_synced_at: str = "";
    has last_error: str = "";
}

obj IcalStatus {
    has state: str;
    has detail: str = "";
    has last_synced_at: str = "";
}

obj IcalResult {
    has ok: bool;
    has status: IcalStatus;
    has error: str = "";
}

def ensure_ical_link -> IcalLink {
    existing = [root-->[?:IcalLink]];
    if existing {
        return existing[0];
    }
    return root ++> IcalLink();
}

def ical_status_of(link: IcalLink) -> IcalStatus {
    if not link.feed_url {
        return IcalStatus(state="disconnected", detail="Not connected");
    }
    if link.last_error {
        return IcalStatus(state="error", detail=link.last_error, last_synced_at=link.last_synced_at);
    }
    return IcalStatus(state="connected", detail="iCal calendar connected", last_synced_at=link.last_synced_at);
}

def clear_ical_cache(link: IcalLink) {
    prefix = f"{jid(link)}|";
    ical_cache = {key: value for (key, value) in ical_cache.items() if not key.startswith(prefix)};
}

def convert_ical_entries(items: list[dict[str, any]]) -> list[CalendarEntry] {
    return [CalendarEntry(
        title=str(item.get("title") or "(No title)"),
        location=str(item.get("location") or ""),
        start=item.get("start"),
        end=item.get("end"),
        start_date=item.get("start_date"),
        end_date=item.get("end_date"),
        busy=bool(item.get("busy", True))
    ) for item in items];
}

def:protect ical_status -> IcalStatus {
    return ical_status_of(ensure_ical_link());
}

"""Test before saving; an invalid URL cannot replace a good connection."""
def:protect connect_ical(url: str) -> IcalResult {
    link = ensure_ical_link();
    try {
        cleaned = validate_ical_url(url);
        now = datetime.now(timezone.utc);
        fetch_ical(cleaned, now, now + timedelta(days=7));
    } except IcalFeedError as err {
        return IcalResult(ok=False, status=ical_status_of(link), error=str(err));
    }
    link.feed_url = cleaned;
    link.last_error = "";
    link.last_synced_at = datetime.now(timezone.utc).isoformat();
    clear_ical_cache(link);
    return IcalResult(ok=True, status=ical_status_of(link));
}

def:protect disconnect_ical -> IcalStatus {
    link = ensure_ical_link();
    link.feed_url = "";
    link.last_synced_at = "";
    link.last_error = "";
    clear_ical_cache(link);
    return ical_status_of(link);
}

"""Refresh from Google on the next plan load; never echo the secret URL."""
def:protect refresh_ical -> IcalStatus {
    link = ensure_ical_link();
    link.last_error = "";
    clear_ical_cache(link);
    return ical_status_of(link);
}

"""Read the requested time window and report connection health without exposing the URL."""
def ical_entries(window_start: datetime, window_end: datetime) -> tuple[list[CalendarEntry], IcalStatus] {
    link = ensure_ical_link();
    if not link.feed_url {
        return ([], ical_status_of(link));
    }
    key = f"{jid(link)}|{window_start.isoformat()}|{window_end.isoformat()}";
    now = time.monotonic();
    cached = ical_cache.get(key);
    if cached is not None and now - cached[0] < ICAL_CACHE_SECONDS {
        return (cached[1], ical_status_of(link));
    }
    try {
        entries = convert_ical_entries(fetch_ical(link.feed_url, window_start, window_end));
    } except IcalFeedError as err {
        link.last_error = str(err);
        return ([], ical_status_of(link));
    }
    link.last_error = "";
    link.last_synced_at = datetime.now(timezone.utc).isoformat();
    ical_cache[key] = (now, entries);
    return (entries, ical_status_of(link));
}
