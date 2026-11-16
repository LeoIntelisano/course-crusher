"""Read-only Google Calendar secret iCal subscriptions.

The URL is a credential. Never return it to the browser after connection, log
it, or follow redirects. Restrict the fetch destination to Google's iCal host.
"""
from __future__ import annotations

from datetime import date, datetime, time, timedelta, timezone
from urllib.parse import urlsplit

import requests
from icalendar import Calendar
import recurring_ical_events

MAX_FEED_BYTES = 2_000_000
MAX_EVENTS = 3000
TIMEOUT = (5, 15)


class IcalFeedError(ValueError):
    """A feed cannot be used. Error messages contain no private URL."""


def validate_ical_url(url: str) -> str:
    url = url.strip()
    if not url or len(url) > 2048:
        raise IcalFeedError("Paste your Google Calendar secret iCal address.")
    try:
        parts = urlsplit(url)
        port = parts.port
    except ValueError as exc:
        raise IcalFeedError("Invalid calendar URL.") from exc
    if (parts.scheme != "https" or parts.hostname != "calendar.google.com"
            or port not in (None, 443) or parts.username or parts.password
            or parts.query or parts.fragment or not parts.path.startswith("/calendar/ical/")
            or not parts.path.endswith("/basic.ics")):
        raise IcalFeedError("Use the HTTPS 'Secret address in iCal format' from Google Calendar settings.")
    return url


def parse_ical(data: bytes, window_start: datetime, window_end: datetime) -> list[dict]:
    """Expand recurring events and convert occurrences to simple Jac-friendly data."""
    try:
        calendar = Calendar.from_ical(data)
        occurrences = recurring_ical_events.of(calendar).between(window_start, window_end)
    except Exception as exc:
        raise IcalFeedError("This link didn't return a readable iCal calendar.") from exc
    result = []
    for event in occurrences:
        if len(result) >= MAX_EVENTS:
            raise IcalFeedError("This calendar contains too many events in the selected period.")
        if str(event.get("STATUS", "")).upper() == "CANCELLED":
            continue
        start_prop = event.get("DTSTART")
        if start_prop is None:
            continue
        start = start_prop.dt
        end_prop = event.get("DTEND")
        duration_prop = event.get("DURATION")
        end = end_prop.dt if end_prop is not None else (
            start + duration_prop.dt if duration_prop is not None else
            start + (timedelta(days=1) if isinstance(start, date) and not isinstance(start, datetime) else timedelta(0))
        )
        if end <= start:
            continue
        title = str(event.get("SUMMARY", "(No title)"))[:300]
        location = str(event.get("LOCATION", ""))[:300]
        busy = str(event.get("TRANSP", "OPAQUE")).upper() != "TRANSPARENT"
        if isinstance(start, datetime) and isinstance(end, datetime):
            if start.tzinfo is None:
                start = start.replace(tzinfo=window_start.tzinfo)
            if end.tzinfo is None:
                end = end.replace(tzinfo=window_start.tzinfo)
            result.append({"title": title, "location": location,
                           "start": start, "end": end, "busy": busy})
        elif isinstance(start, date) and isinstance(end, date):
            result.append({"title": title, "location": location,
                           "start_date": start, "end_date": end, "busy": False})
    return result


def fetch_ical(url: str, window_start: datetime, window_end: datetime) -> list[dict]:
    validate_ical_url(url)
    if window_start.tzinfo is None or window_end.tzinfo is None or window_end <= window_start:
        raise IcalFeedError("Invalid calendar time window.")
    try:
        # No redirects: URLs are credentials, and arbitrary redirect targets
        # would let a malicious calendar URL read internal network resources.
        with requests.get(url, timeout=TIMEOUT, stream=True, allow_redirects=False) as response:
            if response.status_code in (301, 302, 303, 307, 308):
                raise IcalFeedError("Google redirected this calendar link. Copy a fresh secret iCal address.")
            if response.status_code != 200:
                raise IcalFeedError("Google could not provide this calendar. Check the secret iCal link.")
            chunks = []
            total = 0
            for chunk in response.iter_content(chunk_size=65536):
                total += len(chunk)
                if total > MAX_FEED_BYTES:
                    raise IcalFeedError("Calendar feed is too large (2 MB limit).")
                chunks.append(chunk)
    except requests.RequestException as exc:
        raise IcalFeedError("Couldn't reach Google Calendar. Try again.") from exc
    return parse_ical(b"".join(chunks), window_start, window_end)
