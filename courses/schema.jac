"""Courses, their weekly class meetings, assignments and the subtasks added to the plan.

    root --> Course -MeetsAt-> ClassMeeting
                    -Assigned-> Assignment -Step-> Task
    root --> EventLink (the student's own course choice for an event name)

Timestamps are ISO 8601 strings with a UTC offset. Lookups by ID only walk the
caller's own root, so an ID from another account simply isn't found.
"""

import from breakdown { CognitiveTier }
import from courses.colors { fill_colors }

"""`tags` are extra names the student uses for the course in calendar events, e.g. "ML".
`color` is a key from `courses.colors.PALETTE`."""
node Course {
    has code: str;
    has name: str = "";
    has tags: list[str] = [];
    has color: str = "";
}

"""The student's decision for one calendar event name, overriding automatic matching.

`key` is the normalized title; `course_id` is the course, or "" for "not a class".
"""
node EventLink {
    has title: str;
    has key: str;
    has course_id: str = "";
}

"""A weekly class meeting. `weekdays` uses Python's numbering: Monday is 0."""
node ClassMeeting {
    has kind: str = "Lecture";
    has weekdays: list[int] = [];
    has start: str = "09:00";
    has end: str = "10:00";
    has location: str = "";
}

node Assignment {
    has title: str;
    has description: str = "";
    has due_at: str = "";
    has created_at: str = "";
}

"""One subtask in the plan. `not_before` is set by Reschedule and Not today."""
node Task {
    has title: str;
    has tier: CognitiveTier;
    has estimated_duration: int;
    has order: int = 1;
    has done: bool = False;
    has completed_at: str = "";
    has not_before: str = "";
}

edge MeetsAt: Course --> ClassMeeting {}

edge Assigned: Course --> Assignment {}

edge Step: Assignment --> Task {}

def all_courses -> list[Course] {
    return sorted(
        [root-->[?:Course]], key=lambda (c: Course) -> str { return c.code.lower(); }
    );
}

"""Courses in the order they were added, which is the order colors are handed out in."""
def courses_in_creation_order -> list[Course] {
    return [root-->[?:Course]];
}

def event_links -> list[EventLink] {
    return [root-->[?:EventLink]];
}

"""Give courses added before colors existed one, in the order they were added."""
def ensure_colors {
    courses = courses_in_creation_order();
    for (course, color) in zip(courses, fill_colors([c.color for c in courses]), strict=True) {
        if course.color != color {
            course.color = color;
        }
    }
}

def meetings_of(course: Course) -> list[ClassMeeting] {
    return [course ->:MeetsAt:->];
}

def assignments_of(course: Course) -> list[Assignment] {
    return [course ->:Assigned:->];
}

def steps_of(assignment: Assignment) -> list[Task] {
    return sorted(
        [assignment ->:Step:->], key=lambda (t: Task) -> int { return t.order; }
    );
}

def find_course(course_id: str) -> Course | None {
    for course in [root-->[?:Course]] {
        if jid(course) == course_id {
            return course;
        }
    }
    return None;
}

"""An assignment together with the course that owns it."""
def find_assignment(assignment_id: str) -> tuple[Course, Assignment] | None {
    for course in [root-->[?:Course]] {
        for assignment in assignments_of(course) {
            if jid(assignment) == assignment_id {
                return (course, assignment);
            }
        }
    }
    return None;
}

def find_task(task_id: str) -> Task | None {
    for course in [root-->[?:Course]] {
        for assignment in assignments_of(course) {
            for task in [assignment ->:Step:->] {
                if jid(task) == task_id {
                    return task;
                }
            }
        }
    }
    return None;
}

def find_meeting(meeting_id: str) -> ClassMeeting | None {
    for course in [root-->[?:Course]] {
        for meeting in meetings_of(course) {
            if jid(meeting) == meeting_id {
                return meeting;
            }
        }
    }
    return None;
}
