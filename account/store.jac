"""Profile and protected-hours endpoints.

Validation failures come back as `ProfileResult(ok=False, error=...)` with a
message meant for the student, rather than as an exception whose envelope the
browser would have to unpick.
"""

import from account.schema { Profile, ProtectedBlock, ensure_profile, protected_blocks }
import from scheduling.planner { Energy, PlanRules, validate_rules }
import from shared.format { initials }
import from shared.timefmt { clock_text, parse_clock, parse_zone }

glob MAX_NAME_LENGTH: int = 80;
glob MAX_LABEL_LENGTH: int = 60;
glob MAX_BUFFER_MINUTES: int = 60;
glob MIN_SLOT_RANGE: tuple[int, int] = (5, 120);
glob MAX_PROTECTED_BLOCKS: int = 10;

obj ProtectedView {
    has id: str;
    has label: str;
    has start: str;
    has end: str;
}

obj ProfileView {
    has display_name: str;
    has initials: str;
    has timezone: str;
    has energy: str;
    has day_start: str;
    has day_end: str;
    has deep_work_cutoff: str;
    has buffer_minutes: int;
    has min_slot_minutes: int;
    has protected: list[ProtectedView];
}

obj ProfileResult {
    has ok: bool;
    has error: str = "";
    has profile: ProfileView | None = None;
}

def protected_view(block: ProtectedBlock) -> ProtectedView {
    return ProtectedView(id=jid(block), label=block.label, start=block.start, end=block.end);
}

def profile_view(profile: Profile) -> ProfileView {
    blocks = sorted(protected_blocks(), key=lambda (b: ProtectedBlock) -> str { return b.start; });
    return ProfileView(
        display_name=profile.display_name,
        initials=initials(profile.display_name),
        timezone=profile.timezone,
        energy=str(profile.energy),
        day_start=profile.day_start,
        day_end=profile.day_end,
        deep_work_cutoff=profile.deep_work_cutoff,
        buffer_minutes=profile.buffer_minutes,
        min_slot_minutes=profile.min_slot_minutes,
        protected=[protected_view(b) for b in blocks]
    );
}

def ok_result(profile: Profile) -> ProfileResult {
    return ProfileResult(ok=True, profile=profile_view(profile));
}

def failed(message: str) -> ProfileResult {
    return ProfileResult(ok=False, error=message);
}

def clean_name(display_name: str) -> str {
    name = " ".join(display_name.split());
    if len(name) > MAX_NAME_LENGTH {
        raise ValueError(f"Keep your name under {MAX_NAME_LENGTH} characters.");
    }
    return name;
}

def:protect get_profile -> ProfileView {
    return profile_view(ensure_profile());
}

"""First-run setup after signup: the name shown in the sidebar and the browser's time zone."""
def:protect setup_account(display_name: str, timezone: str) -> ProfileResult {
    try {
        name = clean_name(display_name);
        zone = parse_zone(timezone);
    } except ValueError as err {
        return failed(str(err));
    }
    profile = ensure_profile();
    profile.display_name = name;
    profile.timezone = str(zone);
    return ok_result(profile);
}

def:protect save_profile(
    display_name: str,
    timezone: str,
    day_start: str,
    day_end: str,
    deep_work_cutoff: str,
    buffer_minutes: int,
    min_slot_minutes: int
) -> ProfileResult {
    try {
        name = clean_name(display_name);
        zone = parse_zone(timezone);
        start = parse_clock(day_start, "Day start");
        end = parse_clock(day_end, "Day end");
        cutoff = parse_clock(deep_work_cutoff, "Deep Work cutoff");
        if not 0 <= buffer_minutes <= MAX_BUFFER_MINUTES {
            raise ValueError(f"Keep the buffer between 0 and {MAX_BUFFER_MINUTES} minutes.");
        }
        (low, high) = MIN_SLOT_RANGE;
        if not low <= min_slot_minutes <= high {
            raise ValueError(f"The shortest slot must be between {low} and {high} minutes.");
        }
        if not start < cutoff <= end {
            raise ValueError("The Deep Work cutoff must fall inside your day.");
        }
        validate_rules(
            PlanRules(
                zone=zone,
                day_start=start,
                day_end=end,
                deep_work_cutoff=cutoff,
                buffer_minutes=buffer_minutes,
                min_slot_minutes=min_slot_minutes
            )
        );
    } except ValueError as err {
        return failed(str(err));
    }
    profile = ensure_profile();
    profile.display_name = name;
    profile.timezone = str(zone);
    profile.day_start = clock_text(start);
    profile.day_end = clock_text(end);
    profile.deep_work_cutoff = clock_text(cutoff);
    profile.buffer_minutes = buffer_minutes;
    profile.min_slot_minutes = min_slot_minutes;
    return ok_result(profile);
}

def:protect set_energy(energy: str) -> ProfileResult {
    allowed = [str(level) for level in list(Energy)];
    if energy not in allowed {
        return failed(f"Energy must be one of {', '.join(allowed)}.");
    }
    profile = ensure_profile();
    profile.energy = Energy(energy);
    return ok_result(profile);
}

def:protect add_protected_hours(label: str, start: str, end: str) -> ProfileResult {
    name = " ".join(label.split());
    try {
        if not name {
            raise ValueError("Give the protected time a name, e.g. Dinner & gym.");
        }
        if len(name) > MAX_LABEL_LENGTH {
            raise ValueError(f"Keep the name under {MAX_LABEL_LENGTH} characters.");
        }
        opens = parse_clock(start, "Start");
        closes = parse_clock(end, "End");
        if closes <= opens {
            raise ValueError("Protected time must end after it starts.");
        }
        if len(protected_blocks()) >= MAX_PROTECTED_BLOCKS {
            raise ValueError(f"Keep up to {MAX_PROTECTED_BLOCKS} protected times.");
        }
    } except ValueError as err {
        return failed(str(err));
    }
    root ++> ProtectedBlock(label=name, start=clock_text(opens), end=clock_text(closes));
    return ok_result(ensure_profile());
}

def:protect remove_protected_hours(block_id: str) -> ProfileResult {
    matches = [b for b in protected_blocks() if jid(b) == block_id];
    if not matches {
        return failed("That protected time no longer exists.");
    }
    del matches[0];
    return ok_result(ensure_profile());
}
