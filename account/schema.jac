"""A student's planning preferences, stored on their own root.

Clock times are "HH:MM" strings so they read back the same in every client.
Every endpoint that touches these nodes is `:protect`, so `root` is always the
signed-in student's root and no lookup can reach another student's data.
"""

import from scheduling.planner { Energy, PlanRules, ProtectedHours }
import from shared.timefmt { parse_clock, parse_zone }

glob DEFAULT_TIMEZONE: str = "America/Detroit";

node Profile {
    has display_name: str = "";
    has timezone: str = DEFAULT_TIMEZONE;
    has energy: Energy = Energy.HIGH;
    has day_start: str = "08:00";
    has day_end: str = "22:00";
    has deep_work_cutoff: str = "21:00";
    has buffer_minutes: int = 10;
    has min_slot_minutes: int = 15;
}

"""Time kept free every day, e.g. "Dinner & gym" 17:00-19:00."""
node ProtectedBlock {
    has label: str;
    has start: str;
    has end: str;
}

"""The caller's profile, created with defaults on first use."""
def ensure_profile -> Profile {
    existing = [root-->[?:Profile]];
    if existing {
        return existing[0];
    }
    return root ++> Profile();
}

def protected_blocks -> list[ProtectedBlock] {
    return [root-->[?:ProtectedBlock]];
}

def to_protected_hours(block: ProtectedBlock) -> ProtectedHours {
    return ProtectedHours(
        label=block.label,
        start=parse_clock(block.start, "Protected start"),
        end=parse_clock(block.end, "Protected end")
    );
}

"""Planner rules from a stored profile."""
def rules_for(profile: Profile) -> PlanRules {
    return PlanRules(
        zone=parse_zone(profile.timezone),
        day_start=parse_clock(profile.day_start, "Day start"),
        day_end=parse_clock(profile.day_end, "Day end"),
        deep_work_cutoff=parse_clock(profile.deep_work_cutoff, "Deep Work cutoff"),
        buffer_minutes=profile.buffer_minutes,
        min_slot_minutes=profile.min_slot_minutes,
        energy=Energy(profile.energy)
    );
}
