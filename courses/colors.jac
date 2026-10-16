"""Course colors: a fixed palette, so every color has a matching Tailwind style and enough contrast.

Pure, so the server (assignment, validation) and the browser (swatches) share it.
The styles for each key live in `shared/styles.jac`.
"""

glob PALETTE: list[str] = ["indigo", "teal", "amber", "rose", "sky", "violet", "emerald", "orange"];

def is_course_color(color: str) -> bool {
    return color in PALETTE;
}

"""The least-used palette color, earliest in the palette on ties."""
def next_color(used: list[str]) -> str {
    counts = [len([u for u in used if u == color]) for color in PALETTE];
    fewest = min(counts);
    return PALETTE[counts.index(fewest)];
}

"""Colors for courses in creation order: ones already set are kept, the rest filled least-used first."""
def fill_colors(current: list[str]) -> list[str] {
    taken = [c for c in current if is_course_color(c)];
    filled: list[str] = [];
    for color in current {
        if is_course_color(color) {
            filled = filled + [color];
            continue;
        }
        pick = next_color(taken);
        taken = taken + [pick];
        filled = filled + [pick];
    }
    return filled;
}
