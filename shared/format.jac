"""Display helpers with no imports, so both the server and the browser bundle use them."""

glob MINUTES_PER_HOUR: int = 60;
glob MINUTES_PER_DAY: int = 1440;
glob TIER_CLASSES: dict[str, str] = {
    "Deep Work": "deep",
    "Shallow Work": "shallow",
    "Low Energy": "low"
};

"""45 -> "45m", 60 -> "1h", 185 -> "3h 5m"."""
def format_minutes(total: int) -> str {
    hours = total // MINUTES_PER_HOUR;
    minutes = total % MINUTES_PER_HOUR;
    if hours == 0 {
        return f"{minutes}m";
    }
    if minutes == 0 {
        return f"{hours}h";
    }
    return f"{hours}h {minutes}m";
}

"""Long spans read in days: 4514 -> "3d 3h"; under a day it matches format_minutes."""
def format_span(total: int) -> str {
    if total < MINUTES_PER_DAY {
        return format_minutes(total);
    }
    days = total // MINUTES_PER_DAY;
    hours = (total % MINUTES_PER_DAY) // MINUTES_PER_HOUR;
    return f"{days}d {hours}h" if hours else f"{days}d";
}

"""The tier's short CSS key: "Deep Work" -> "deep". Unknown tiers fall back to "shallow"."""
def tier_key(tier: str) -> str {
    return TIER_CLASSES.get(tier, "shallow");
}

def pluralize(count: int, singular: str, plural: str) -> str {
    word = singular if count == 1 else plural;
    return f"{count} {word}";
}

"""Up to two initials from a display name: "Varshini Anbu" -> "VA"."""
def initials(name: str) -> str {
    parts = [part for part in name.split() if part];
    if not parts {
        return "?";
    }
    return "".join([part[0].upper() for part in parts[:2]]);
}

def two_digits(value: int) -> str {
    return str(value) if value >= 10 else "0" + str(value);
}

"""A countdown as mm:ss: 3017 -> "50:17"."""
def countdown_text(seconds: int) -> str {
    safe = max(0, seconds);
    return f"{two_digits(safe // 60)}:{two_digits(safe % 60)}";
}
