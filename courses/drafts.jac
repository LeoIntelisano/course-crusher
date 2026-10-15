"""The Breakdown screen's editable subtask list. Pure, so it runs in the browser and in `jac test`.

Every edit returns a new list: React only re-renders when state is rebound.
"""

import from shared.format { format_minutes }

glob TITLE_FALLBACK_LENGTH: int = 60;
glob MAX_DRAFT_MINUTES: int = 480;

obj DraftRow {
    has title: str;
    has tier: str;
    has minutes: int;
    has included: bool = True;
}

"""The title to save: what the student typed, else the description's first line."""
def default_title(title: str, description: str) -> str {
    if title.strip() {
        return title.strip();
    }
    for line in description.split(chr(10)) {
        if line.strip() {
            first = line.strip();
            if len(first) <= TITLE_FALLBACK_LENGTH {
                return first;
            }
            return first[:TITLE_FALLBACK_LENGTH - 1].rstrip() + "…";
        }
    }
    return "Untitled assignment";
}

def included_rows(rows: list[DraftRow]) -> list[DraftRow] {
    return [row for row in rows if row.included];
}

"""The card heading, e.g. 5 subtasks, 3h 20m total, across every row checked or not."""
def summary(rows: list[DraftRow]) -> str {
    total = sum([row.minutes for row in rows]);
    noun = "subtask" if len(rows) == 1 else "subtasks";
    return f"{len(rows)} {noun}, {format_minutes(total)} total";
}

def with_row(rows: list[DraftRow], index: int, replacement: DraftRow) -> list[DraftRow] {
    return [replacement if position == index else row for (position, row) in enumerate(rows)];
}

def toggle_row(rows: list[DraftRow], index: int) -> list[DraftRow] {
    row = rows[index];
    return with_row(rows, index, DraftRow(title=row.title, tier=row.tier, minutes=row.minutes, included=not row.included));
}

def retitle_row(rows: list[DraftRow], index: int, title: str) -> list[DraftRow] {
    row = rows[index];
    return with_row(rows, index, DraftRow(title=title, tier=row.tier, minutes=row.minutes, included=row.included));
}

def retier_row(rows: list[DraftRow], index: int, tier: str) -> list[DraftRow] {
    row = rows[index];
    return with_row(rows, index, DraftRow(title=row.title, tier=tier, minutes=row.minutes, included=row.included));
}

"""Typed minutes, clamped to what the server accepts. Blank or junk keeps the old value."""
def retime_row(rows: list[DraftRow], index: int, text: str) -> list[DraftRow] {
    row = rows[index];
    cleaned = "".join([ch for ch in text if ch.isdigit()]);
    if not cleaned {
        return rows;
    }
    minutes = min(MAX_DRAFT_MINUTES, max(1, int(cleaned)));
    return with_row(rows, index, DraftRow(title=row.title, tier=row.tier, minutes=minutes, included=row.included));
}
