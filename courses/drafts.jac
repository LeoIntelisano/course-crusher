"""The Breakdown screen's editable subtask list. Pure, so it runs in the browser and in `jac test`.

Every edit returns a new list: React only re-renders when state is rebound.
"""

import from shared.format { format_minutes }

glob TITLE_FALLBACK_LENGTH: int = 60;
glob MAX_DRAFT_MINUTES: int = 480;
glob BLANK_ROW_TIER: str = "Shallow Work";
glob BLANK_ROW_MINUTES: int = 30;

obj DraftRow {
    has title: str;
    has tier: str;
    has minutes: int;
    has included: bool = True;
    has scheduled_date: str = "";
    has scheduled_time: str = "";
}

"""Everything on Breakdown that isn't saved yet, kept while the student visits other screens."""
obj BreakdownDraft {
    has course_id: str = "";
    has title: str = "";
    has due_at: str = "";
    has description: str = "";
    has source: str = "";
    has rows: list[DraftRow] = [];
}

"""Nothing typed and no breakdown yet. The course alone doesn't count: it's picked by default."""
def is_blank(draft: BreakdownDraft) -> bool {
    typed = draft.title.strip() + draft.due_at.strip() + draft.description.strip() + draft.source.strip();
    return not typed and len(draft.rows) == 0;
}

"""Keep the student's course while it still exists, else fall back to the first one."""
def course_to_select(course_ids: list[str], wanted: str) -> str {
    if wanted and wanted in course_ids {
        return wanted;
    }
    return course_ids[0] if len(course_ids) > 0 else "";
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
    return with_row(rows, index, DraftRow(title=row.title, tier=row.tier, minutes=row.minutes, included=not row.included, scheduled_date=row.scheduled_date, scheduled_time=row.scheduled_time));
}

def retitle_row(rows: list[DraftRow], index: int, title: str) -> list[DraftRow] {
    row = rows[index];
    return with_row(rows, index, DraftRow(title=title, tier=row.tier, minutes=row.minutes, included=row.included, scheduled_date=row.scheduled_date, scheduled_time=row.scheduled_time));
}

def retier_row(rows: list[DraftRow], index: int, tier: str) -> list[DraftRow] {
    row = rows[index];
    return with_row(rows, index, DraftRow(title=row.title, tier=tier, minutes=row.minutes, included=row.included, scheduled_date=row.scheduled_date, scheduled_time=row.scheduled_time));
}

"""Typed minutes, clamped to what the server accepts. Blank or junk keeps the old value."""
def retime_row(rows: list[DraftRow], index: int, text: str) -> list[DraftRow] {
    row = rows[index];
    cleaned = "";
    for ch in text {
        if ch.isdigit() {
            cleaned += ch;
        }
    }
    if not cleaned {
        return rows;
    }
    minutes = min(MAX_DRAFT_MINUTES, max(1, int(cleaned)));
    return with_row(rows, index, DraftRow(title=row.title, tier=row.tier, minutes=minutes, included=row.included, scheduled_date=row.scheduled_date, scheduled_time=row.scheduled_time));
}

"""A new, empty subtask at the end, for breaking an assignment down by hand."""
def add_blank_row(rows: list[DraftRow]) -> list[DraftRow] {
    return rows + [DraftRow(title="", tier=BLANK_ROW_TIER, minutes=BLANK_ROW_MINUTES)];
}

"""Keep the student's optional local date and time together with each editable row."""
def redate_row(rows: list[DraftRow], index: int, value: str) -> list[DraftRow] {
    row = rows[index];
    return with_row(rows, index, DraftRow(title=row.title, tier=row.tier, minutes=row.minutes, included=row.included, scheduled_date=value, scheduled_time=row.scheduled_time));
}

def reclock_row(rows: list[DraftRow], index: int, value: str) -> list[DraftRow] {
    row = rows[index];
    return with_row(rows, index, DraftRow(title=row.title, tier=row.tier, minutes=row.minutes, included=row.included, scheduled_date=row.scheduled_date, scheduled_time=value));
}

"""Local datetime strings, positionally matching included subtasks, or empty for automatic planning."""
def manual_starts(rows: list[DraftRow]) -> list[str] {
    return [f"{row.scheduled_date}T{row.scheduled_time}" if row.scheduled_date and row.scheduled_time else "" for row in included_rows(rows)];
}

"""Reject incomplete selections before previewing, rather than silently ignoring them."""
def invalid_schedule_row(rows: list[DraftRow]) -> int {
    for (index, row) in enumerate(rows) {
        if row.included and bool(row.scheduled_date) != bool(row.scheduled_time) {
            return index + 1;
        }
    }
    return 0;
}

"""Turning a planner suggestion into a manual start should preserve the other field."""
def set_date_from_suggestion(rows: list[DraftRow], index: int, value: str, suggested: str) -> list[DraftRow] {
    row = rows[index];
    if not value {
        return with_row(rows, index, DraftRow(title=row.title, tier=row.tier, minutes=row.minutes, included=row.included));
    }
    clock = row.scheduled_time or (suggested.split("T")[1][:5] if "T" in suggested else "");
    return with_row(rows, index, DraftRow(title=row.title, tier=row.tier, minutes=row.minutes, included=row.included, scheduled_date=value, scheduled_time=clock));
}

def set_time_from_suggestion(rows: list[DraftRow], index: int, value: str, suggested: str) -> list[DraftRow] {
    row = rows[index];
    if not value {
        return with_row(rows, index, DraftRow(title=row.title, tier=row.tier, minutes=row.minutes, included=row.included));
    }
    day = row.scheduled_date or (suggested.split("T")[0] if suggested else "");
    return with_row(rows, index, DraftRow(title=row.title, tier=row.tier, minutes=row.minutes, included=row.included, scheduled_date=day, scheduled_time=value));
}

def auto_schedule_row(rows: list[DraftRow], index: int) -> list[DraftRow] {
    row = rows[index];
    return with_row(rows, index, DraftRow(title=row.title, tier=row.tier, minutes=row.minutes, included=row.included));
}
