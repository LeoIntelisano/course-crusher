"""Match calendar event names to courses.

An event belongs to a course when its name contains, as whole words:

- the course code, with or without its space ("EECS 445" or "EECS445"),
- the course name (four characters or longer), or
- one of the student's own tags for the course ("ML", "Hutchins 100").

An event name the student linked by hand skips all of that: `overrides` maps its
normalized name to a course code, or to "" for "not a class".

Matching ignores case and punctuation. When several courses match, the longest
matching phrase wins, so "EECS 445 Lab" picks EECS 445 over a course tagged "Lab".
Pure, so both the planner and the tests use it directly.
"""

glob MIN_NAME_LENGTH: int = 4;
glob KIND_KEYWORDS: list[tuple[str, list[str]]] = [
    ("Exam", ["exam", "midterm", "final", "quiz"]),
    ("Office hours", ["office hours", "oh"]),
    ("Lab", ["lab", "laboratory"]),
    ("Discussion", ["discussion", "dis", "recitation", "section"]),
    ("Lecture", ["lecture", "lec", "class"])
];

"""A course's matchable phrases, already normalized."""
obj CourseMatcher {
    has code: str;
    has phrases: list[str];
}

"""Lowercase, keep letters and digits, and collapse everything else to single spaces."""
def normalize(text: str) -> str {
    kept = "".join([ch.lower() if ch.isalnum() else " " for ch in text]);
    return " ".join(kept.split());
}

def contains_phrase(normalized_text: str, phrase: str) -> bool {
    return bool(phrase) and f" {phrase} " in f" {normalized_text} ";
}

def course_matcher(code: str, name: str, tags: list[str]) -> CourseMatcher {
    code_phrase = normalize(code);
    phrases = [code_phrase, code_phrase.replace(" ", "")];
    if len(normalize(name)) >= MIN_NAME_LENGTH {
        phrases = phrases + [normalize(name)];
    }
    phrases = phrases + [normalize(tag) for tag in tags];
    return CourseMatcher(code=code, phrases=list(dict.fromkeys([p for p in phrases if p])));
}

"""The code of the course an event name belongs to, or "" when none matches."""
def match_course(title: str, matchers: list[CourseMatcher], overrides: dict[str, str] | None = None) -> str {
    text = normalize(title);
    if overrides is not None and text in overrides {
        return overrides[text];
    }
    best_code = "";
    best_length = 0;
    for matcher in matchers {
        for phrase in matcher.phrases {
            if contains_phrase(text, phrase) and len(phrase) > best_length {
                best_code = matcher.code;
                best_length = len(phrase);
            }
        }
    }
    return best_code;
}

"""What kind of meeting an event name describes: Lecture, Lab, Discussion, Office hours, Exam, or ""."""
def event_kind(title: str) -> str {
    text = normalize(title);
    for (kind, words) in KIND_KEYWORDS {
        for word in words {
            if contains_phrase(text, word) {
                return kind;
            }
        }
    }
    return "";
}
