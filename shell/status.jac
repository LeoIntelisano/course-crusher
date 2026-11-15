"""Header pill wording. Pure, so it is tested without a browser."""

import from shared.format { format_minutes }

glob ENERGY_LEVELS: list[str] = ["High", "Medium", "Low"];

"""What each level does to the rest of today. Matches rule 5 in scheduling/planner.jac."""
glob ENERGY_HELP: dict[str, str] = {
    "High": "Any work. Long Deep Work blocks are planned as usual.",
    "Medium": "Up to 90 minutes of Deep Work for the rest of today. Lighter work fills the remaining time.",
    "Low": "No Deep Work for the rest of today unless it's due today. Shallow and Low Energy tasks move up."
};

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

def blocks(count: int) -> str {
    return "1 block" if count == 1 else f"{count} blocks";
}

"""What changed on today's plan after an energy change, from the task ids planned for today before and after."""
def energy_notice(level: str, before_ids: list[str], after_ids: list[str]) -> str {
    moved_off = len([task_id for task_id in before_ids if task_id not in after_ids]);
    moved_in = len([task_id for task_id in after_ids if task_id not in before_ids]);
    if moved_off and moved_in {
        return f"Energy set to {level}: moved {blocks(moved_off)} off today and {blocks(moved_in)} in.";
    }
    if moved_off {
        return f"Energy set to {level}: moved {blocks(moved_off)} off today.";
    }
    if moved_in {
        return f"Energy set to {level}: {blocks(moved_in)} moved into today.";
    }
    return f"Energy set to {level}. Today's plan didn't need to change.";
}
