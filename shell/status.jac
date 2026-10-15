"""Header pill wording. Pure, so it is tested without a browser."""

import from shared.format { format_minutes }

glob ENERGY_LEVELS: list[str] = ["High", "Medium", "Low"];

"""Desktop: "Free until 2:00 PM". Compact (mobile): "Free 1h 25m"."""
def free_text(state: str, until: str, minutes: int, compact: bool) -> str {
    if state == "free" {
        return f"Free {format_minutes(minutes)}" if compact else f"Free until {until}";
    }
    if state == "busy" {
        return f"Busy until {until}";
    }
    return "Day's done";
}
