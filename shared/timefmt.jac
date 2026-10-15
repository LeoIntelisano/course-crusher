"""Parse what students type and format times the way the wireframe shows them."""

import from datetime { date, datetime, time, timedelta, tzinfo }
import from zoneinfo { ZoneInfo, ZoneInfoNotFoundError }

glob CLOCK_FORMAT_HINT: str = "Use 24-hour HH:MM, e.g. 17:30.";
glob DUE_PAST_DAYS: int = 365;
glob DUE_FUTURE_DAYS: int = 5 * 365;
glob STORED_YEAR_RANGE: tuple[int, int] = (1970, 2200);

"""A "HH:MM" wall-clock time, or a ValueError naming the field.

Times with a UTC offset are rejected: they can't be compared with the plain
times the planner uses, and a class at "17:00+05:00" isn't a local time anyway.
"""
def parse_clock(text: str, field: str) -> time {
    try {
        value = time.fromisoformat(text.strip());
    } except ValueError {
        raise ValueError(f"{field}: {CLOCK_FORMAT_HINT}") from None;
    }
    if value.tzinfo is not None {
        raise ValueError(f"{field}: {CLOCK_FORMAT_HINT}");
    }
    return value;
}

def clock_text(value: time) -> str {
    return value.strftime("%H:%M");
}

def parse_zone(name: str) -> ZoneInfo {
    try {
        return ZoneInfo(name.strip());
    } except (ZoneInfoNotFoundError, ValueError) {
        raise ValueError(f"Unknown time zone: {name}. Use an IANA name such as America/Detroit.") from None;
    }
}

"""A timezone-aware datetime from ISO text. Local "YYYY-MM-DDTHH:MM" is read in `zone`."""
def parse_moment(text: str, zone: tzinfo, field: str) -> datetime {
    try {
        value = datetime.fromisoformat(text.strip());
    } except ValueError {
        raise ValueError(f"{field}: use a date and time such as 2026-10-21T23:59.") from None;
    }
    if value.tzinfo is None {
        return value.replace(tzinfo=zone);
    }
    return value;
}

"""A due date within a year back and five years ahead of `now`.

Dates near the ends of the calendar overflow when shifted between zones, which
would break every view that shows the assignment.
"""
def parse_due(text: str, zone: tzinfo, now: datetime) -> datetime {
    due = parse_moment(text, zone, "Due date");
    if not now - timedelta(days=DUE_PAST_DAYS) <= due <= now + timedelta(days=DUE_FUTURE_DAYS) {
        raise ValueError("Due date: pick a date within the next five years.");
    }
    return due;
}

"""Read a stored ISO timestamp; empty or unreadable text means "not set"."""
def stored_moment(text: str) -> datetime | None {
    if not text {
        return None;
    }
    try {
        value = datetime.fromisoformat(text);
    } except ValueError {
        return None;
    }
    if value.tzinfo is None {
        return None;
    }
    (first, last) = STORED_YEAR_RANGE;
    return value if first <= value.year <= last else None;
}

"""12:35 PM. No leading zero, like the wireframe."""
def clock_label(moment: datetime) -> str {
    hour = moment.hour % 12 or 12;
    suffix = "AM" if moment.hour < 12 else "PM";
    return f"{hour}:{moment.minute:02d} {suffix}";
}

"""12:35 – 1:25 PM when both ends share AM/PM, else 11:30 AM – 12:20 PM."""
def range_label(start: datetime, end: datetime) -> str {
    same_half = (start.hour < 12) == (end.hour < 12);
    left = clock_label(start);
    if same_half {
        left = left.rsplit(" ", 1)[0];
    }
    return f"{left} – {clock_label(end)}";
}

"""11 AM, the hour column of the timeline."""
def hour_label(moment: datetime) -> str {
    hour = moment.hour % 12 or 12;
    suffix = "AM" if moment.hour < 12 else "PM";
    return f"{hour} {suffix}";
}

"""Today, Tomorrow, or a short weekday such as Wed."""
def day_label(day: date, today: date) -> str {
    offset = (day - today).days;
    if offset == 0 {
        return "Today";
    }
    if offset == 1 {
        return "Tomorrow";
    }
    return day.strftime("%a");
}

"""Mon, Sep 28."""
def date_label(day: date) -> str {
    return f"{day.strftime('%a')}, {day.strftime('%b')} {day.day}";
}

"""Wed 11:59 PM, or Oct 21 11:59 PM when more than a week out."""
def due_label(due: datetime, today: date) -> str {
    days = (due.date() - today).days;
    when = due.strftime("%a") if 0 <= days < 7 else f"{due.strftime('%b')} {due.day}";
    return f"{when} {clock_label(due)}";
}
