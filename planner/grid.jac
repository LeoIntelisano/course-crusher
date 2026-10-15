"""Geometry for the week calendar grid. No imports, so the browser and `jac test` share it."""

glob HOUR_PX: int = 44;
glob MINUTES_PER_HOUR: int = 60;
glob MIN_ITEM_PX: int = 18;
glob ITEM_GAP_PX: int = 2;

def minutes_to_px(minutes: int) -> int {
    return (minutes * HOUR_PX) // MINUTES_PER_HOUR;
}

"""Pixel height of a grid that runs from `start_minute` to `end_minute`."""
def grid_height(start_minute: int, end_minute: int) -> int {
    return minutes_to_px(max(0, end_minute - start_minute));
}

"""Every whole hour from the top of the grid to the bottom, inclusive of the top."""
def hour_marks(start_minute: int, end_minute: int) -> list[int] {
    first = start_minute // MINUTES_PER_HOUR;
    last = end_minute // MINUTES_PER_HOUR;
    return [hour for hour in range(first, last)];
}

"""13 -> "1 PM", 0 -> "12 AM"."""
def hour_text(hour: int) -> str {
    clock = hour % 12 or 12;
    suffix = "AM" if hour % 24 < 12 else "PM";
    return f"{clock} {suffix}";
}

"""CSS position for an item: top/height in px from the grid's top, left/width in % for its lane."""
def item_box(
    start_minute: int, end_minute: int, grid_start: int, lane: int, lanes: int
) -> dict[str, str] {
    lanes_safe = max(1, lanes);
    top = minutes_to_px(start_minute - grid_start);
    height = max(MIN_ITEM_PX, minutes_to_px(end_minute - start_minute) - ITEM_GAP_PX);
    width = 100 / lanes_safe;
    return {
        "top": f"{top}px",
        "height": f"{height}px",
        "left": f"{lane * width}%",
        "width": f"calc({width}% - 3px)"
    };
}

"""Top offset in px of the current-time line, or -1 when it's off the grid."""
def now_offset(now_minute: int, grid_start: int, grid_end: int) -> int {
    if now_minute < grid_start or now_minute > grid_end {
        return -1;
    }
    return minutes_to_px(now_minute - grid_start);
}
