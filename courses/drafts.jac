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
    return with_row(rows, index, DraftRow(title=row.title, tier=row.tier, minutes=minutes, included=row.included));
}

"""A new, empty subtask at the end, for breaking an assignment down by hand."""
def add_blank_row(rows: list[DraftRow]) -> list[DraftRow] {
    return rows + [DraftRow(title="", tier=BLANK_ROW_TIER, minutes=BLANK_ROW_MINUTES)];
}
