"""Convert Canvas responses into reviewable assignment drafts. No network or model calls."""

import json;
import sys;
import from datetime { datetime, timezone }
import from html.parser { HTMLParser }
import from pathlib { Path }
import from urllib.parse { urlparse }

glob BLOCK_TAGS: set[str] = {"p", "div", "li", "ul", "ol", "br", "hr", "h1", "h2", "h3", "h4", "h5", "h6", "blockquote", "pre", "tr"};
glob HIDDEN_TAGS: set[str] = {"script", "style"};

obj AssignmentTextParser(HTMLParser) {
    has parts: list[str] = [];
    has hidden: list[str] = [];

    def postinit {
        super.__init__(convert_charrefs=True);
    }

    def handle_starttag(tag: str, _attrs: list[tuple[str, str | None]]) {
        if tag in HIDDEN_TAGS {
            self.hidden.append(tag);
        }
        if not self.hidden and tag in BLOCK_TAGS {
            self.parts.append("\n");
        }
        if not self.hidden and tag in {"td", "th"} {
            self.parts.append(" ");
        }
    }

    def handle_endtag(tag: str) {
        if self.hidden {
            if tag == self.hidden[-1] {
                self.hidden.pop();
            }
            return;
        }
        if tag in BLOCK_TAGS {
            self.parts.append("\n");
        }
    }

    def handle_data(data: str) {
        if not self.hidden {
            self.parts.append(data);
        }
    }
}

def assignment_text(html: str) -> str {
    parser = AssignmentTextParser();
    parser.feed(html);
    parser.close();
    lines = [" ".join(line.split()) for line in "".join(parser.parts).splitlines()];
    return "\n".join([line for line in lines if line]);
}

obj CanvasAssignmentDraft {
    has source_assignment_id: str;
    has source_course_id: str;
    has title: str;
    has description: str;
    has due_at: str;
    has source_url: str;
    has needs_description: bool;
}

def canvas_id(value: any, field: str) -> str {
    if isinstance(value, bool) or not isinstance(value, int) or value <= 0 {
        raise ValueError(f"{field} must be a positive integer.");
    }
    return str(value);
}

def nullable_text(raw: dict[str, any], field: str) -> str {
    value = raw.get(field);
    if value is None {
        return "";
    }
    if not isinstance(value, str) {
        raise ValueError(f"{field} must be a string or null.");
    }
    return value;
}

def canvas_due_at(value: str) -> str {
    if not value {
        return "";
    }
    try {
        due = datetime.fromisoformat(value);
    } except ValueError {
        raise ValueError("due_at must be an ISO 8601 date with a timezone.");
    }
    if due.tzinfo is None or due.utcoffset() is None {
        raise ValueError("due_at must include a timezone.");
    }
    return due.astimezone(timezone.utc).isoformat();
}

def convert_assignment(raw: dict[str, any]) -> CanvasAssignmentDraft {
    assignment_id = canvas_id(raw.get("id"), "id");
    course_id = canvas_id(raw.get("course_id"), "course_id");
    title = nullable_text(raw, "name").strip();
    if not title {
        raise ValueError("name cannot be empty.");
    }
    description = assignment_text(nullable_text(raw, "description"));
    source_url = nullable_text(raw, "html_url").strip();
    if source_url {
        parsed = urlparse(source_url);
        if parsed.scheme != "https" or not parsed.hostname or parsed.username or parsed.password {
            raise ValueError("html_url must be an HTTPS URL without credentials.");
        }
    }
    return CanvasAssignmentDraft(
        source_assignment_id=assignment_id,
        source_course_id=course_id,
        title=title,
        description=description,
        due_at=canvas_due_at(nullable_text(raw, "due_at")),
        source_url=source_url,
        needs_description=not bool(description)
    );
}

"""Convert one API response page; reject duplicates before anything is saved."""
def convert_assignments(raw: list[any]) -> list[CanvasAssignmentDraft] {
    drafts: list[CanvasAssignmentDraft] = [];
    seen: set[tuple[str, str]] = set();
    for item in raw {
        if not isinstance(item, dict) {
            raise ValueError("Each assignment must be an object.");
        }
        draft = convert_assignment(item as dict[str, any]);
        key = (draft.source_course_id, draft.source_assignment_id);
        if key in seen {
            raise ValueError(f"Duplicate Canvas assignment: {key}");
        }
        seen.add(key);
        drafts.append(draft);
    }
    return drafts;
}

def load_assignment_fixture(path: str) -> list[CanvasAssignmentDraft] {
    raw = json.loads(Path(path).read_text(encoding="utf-8"));
    if not isinstance(raw, list) {
        raise ValueError("Expected a JSON array of Canvas assignments.");
    }
    return convert_assignments(raw as list[any]);
}

def preview_json(drafts: list[CanvasAssignmentDraft]) -> str {
    return json.dumps([
        {
            "source_assignment_id": draft.source_assignment_id,
            "source_course_id": draft.source_course_id,
            "title": draft.title,
            "description": draft.description,
            "due_at": draft.due_at,
            "source_url": draft.source_url,
            "needs_description": draft.needs_description
        }
        for draft in drafts
    ], indent=2);
}

with entry:__main__ {
    if len(sys.argv) != 2 {
        print("Usage: jac run connectors/canvas_assignments.jac -- <fixture.json>", file=sys.stderr);
        sys.`exit(1);
    }
    try {
        print(preview_json(load_assignment_fixture(sys.argv[1])));
    } except (ValueError, OSError) as err {
        print(f"canvas-import: {err}", file=sys.stderr);
        sys.`exit(1);
    }
}
