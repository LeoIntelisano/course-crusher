"""Course, class-meeting, assignment and task endpoints.

Every endpoint is `:protect`: it runs on the signed-in student's root, and the
`find_*` helpers only walk that root. Expected failures (bad input, a deleted
item) return a result with `ok=False` and a message for the student.
"""

import from datetime { datetime, timezone }
import from account.schema { ensure_profile }
import from breakdown { CognitiveTier }
import from courses.schema {
    Assigned,
    Assignment,
    ClassMeeting,
    Course,
    MeetsAt,
    Step,
    Task,
    all_courses,
    assignments_of,
    find_assignment,
    find_course,
    find_meeting,
    find_task,
    meetings_of,
    steps_of
}
import from shared.timefmt {
    clock_text,
    due_label,
    parse_clock,
    parse_due,
    parse_zone,
    range_label,
    stored_moment
}

glob MAX_CODE_LENGTH: int = 20;
glob MAX_NAME_LENGTH: int = 80;
glob MAX_KIND_LENGTH: int = 30;
glob MAX_TITLE_LENGTH: int = 160;
glob MAX_DESCRIPTION_LENGTH: int = 20000;
glob MAX_SUBTASKS: int = 25;
glob MAX_SUBTASK_MINUTES: int = 480;
glob MAX_COURSES: int = 20;
glob MAX_MEETINGS_PER_COURSE: int = 10;
glob MAX_OPEN_TASKS: int = 400;
glob WEEKDAY_NAMES: list[str] = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];

"""A subtask the student confirmed on the Breakdown screen, possibly edited."""
obj SubtaskDraft {
    has title: str;
    has tier: str;
    has estimated_duration: int;
}

obj MeetingView {
    has id: str;
    has kind: str;
    has weekdays: list[int];
    has start: str;
    has end: str;
    has location: str;
    has summary: str;
}

obj TaskView {
    has id: str;
    has title: str;
    has tier: str;
    has estimated_duration: int;
    has order: int;
    has done: bool;
}

obj AssignmentView {
    has id: str;
    has title: str;
    has description: str;
    has due_at: str;
    has due_label: str;
    has tasks: list[TaskView];
    has open_minutes: int;
    has done_count: int;
}

obj CourseView {
    has id: str;
    has code: str;
    has name: str;
    has meetings: list[MeetingView];
    has assignments: list[AssignmentView];
    has open_tasks: int;
    has open_minutes: int;
}

obj CourseResult {
    has ok: bool;
    has error: str = "";
    has courses: list[CourseView] = [];
}

def single_line(text: str) -> str {
    return " ".join(text.split());
}

def require_text(text: str, field: str, limit: int) -> str {
    value = single_line(text);
    if not value {
        raise ValueError(f"{field} is required.");
    }
    if len(value) > limit {
        raise ValueError(f"{field} must be under {limit} characters.");
    }
    return value;
}

def weekday_summary(weekdays: list[int]) -> str {
    return " ".join([WEEKDAY_NAMES[d] for d in sorted(weekdays)]);
}

def meeting_view(meeting: ClassMeeting) -> MeetingView {
    today = datetime.now(timezone.utc).date();
    start = datetime.combine(today, parse_clock(meeting.start, "Start"));
    end = datetime.combine(today, parse_clock(meeting.end, "End"));
    where = f" · {meeting.location}" if meeting.location else "";
    return MeetingView(
        id=jid(meeting),
        kind=meeting.kind,
        weekdays=sorted(meeting.weekdays),
        start=meeting.start,
        end=meeting.end,
        location=meeting.location,
        summary=f"{weekday_summary(meeting.weekdays)} {range_label(start, end)}{where}"
    );
}

def task_view(task: Task) -> TaskView {
    return TaskView(
        id=jid(task),
        title=task.title,
        tier=str(task.tier),
        estimated_duration=task.estimated_duration,
        order=task.order,
        done=task.done
    );
}

def assignment_view(assignment: Assignment) -> AssignmentView {
    tasks = steps_of(assignment);
    due = stored_moment(assignment.due_at);
    zone = parse_zone(ensure_profile().timezone);
    today = datetime.now(zone).date();
    return AssignmentView(
        id=jid(assignment),
        title=assignment.title,
        description=assignment.description,
        due_at=assignment.due_at,
        due_label=due_label(due.astimezone(zone), today) if due is not None else "",
        tasks=[task_view(t) for t in tasks],
        open_minutes=sum([t.estimated_duration for t in tasks if not t.done]),
        done_count=len([t for t in tasks if t.done])
    );
}

def course_view(course: Course) -> CourseView {
    assignments = sorted(
        [assignment_view(a) for a in assignments_of(course)],
        key=lambda (a: AssignmentView) -> str { return a.due_at or "9999"; }
    );
    open_steps = [t for a in assignments for t in a.tasks if not t.done];
    return CourseView(
        id=jid(course),
        code=course.code,
        name=course.name,
        meetings=[meeting_view(m) for m in meetings_of(course)],
        assignments=assignments,
        open_tasks=len(open_steps),
        open_minutes=sum([t.estimated_duration for t in open_steps])
    );
}

def course_list -> list[CourseView] {
    return [course_view(c) for c in all_courses()];
}

def ok_courses -> CourseResult {
    return CourseResult(ok=True, courses=course_list());
}

def failed(message: str) -> CourseResult {
    return CourseResult(ok=False, error=message, courses=course_list());
}

def:protect list_courses -> list[CourseView] {
    return course_list();
}

def:protect add_course(code: str, name: str) -> CourseResult {
    try {
        clean_code = require_text(code, "Course code", MAX_CODE_LENGTH).upper();
        clean_name = single_line(name)[:MAX_NAME_LENGTH];
    } except ValueError as err {
        return failed(str(err));
    }
    courses = all_courses();
    if [c for c in courses if c.code == clean_code] {
        return failed(f"You already have {clean_code}.");
    }
    if len(courses) >= MAX_COURSES {
        return failed(f"You can track up to {MAX_COURSES} courses. Remove one first.");
    }
    root ++> Course(code=clean_code, name=clean_name);
    return ok_courses();
}

"""Remove a course with its meetings, assignments and their subtasks."""
def:protect remove_course(course_id: str) -> CourseResult {
    course = find_course(course_id);
    if course is None {
        return failed("That course no longer exists.");
    }
    for assignment in assignments_of(course) {
        delete_assignment(assignment);
    }
    for meeting in meetings_of(course) {
        del meeting;
    }
    del course;
    return ok_courses();
}

def:protect add_meeting(
    course_id: str, kind: str, weekdays: list[int], start: str, end: str, location: str
) -> CourseResult {
    course = find_course(course_id);
    if course is None {
        return failed("Pick a course first.");
    }
    if len(meetings_of(course)) >= MAX_MEETINGS_PER_COURSE {
        return failed(f"A course can have up to {MAX_MEETINGS_PER_COURSE} class times.");
    }
    try {
        clean_kind = require_text(kind or "Lecture", "Meeting type", MAX_KIND_LENGTH);
        days = sorted(set(weekdays));
        if not days or [d for d in days if not 0 <= d <= 6] {
            raise ValueError("Choose at least one weekday.");
        }
        opens = parse_clock(start, "Start");
        closes = parse_clock(end, "End");
        if closes <= opens {
            raise ValueError("A class must end after it starts.");
        }
    } except ValueError as err {
        return failed(str(err));
    }
    course +>:MeetsAt():+> ClassMeeting(
        kind=clean_kind,
        weekdays=days,
        start=clock_text(opens),
        end=clock_text(closes),
        location=single_line(location)[:MAX_NAME_LENGTH]
    );
    return ok_courses();
}

def:protect remove_meeting(meeting_id: str) -> CourseResult {
    meeting = find_meeting(meeting_id);
    if meeting is None {
        return failed("That class time no longer exists.");
    }
    del meeting;
    return ok_courses();
}

def clean_drafts(subtasks: list[SubtaskDraft]) -> list[SubtaskDraft] {
    if not subtasks {
        raise ValueError("Select at least one subtask to add.");
    }
    if len(subtasks) > MAX_SUBTASKS {
        raise ValueError(f"Add at most {MAX_SUBTASKS} subtasks at once.");
    }
    allowed = [str(t) for t in list(CognitiveTier)];
    cleaned: list[SubtaskDraft] = [];
    for (position, draft) in enumerate(subtasks, start=1) {
        title = require_text(draft.title, f"Subtask {position} title", MAX_TITLE_LENGTH);
        if draft.tier not in allowed {
            raise ValueError(f"Subtask {position} has an unknown tier.");
        }
        if not 1 <= draft.estimated_duration <= MAX_SUBTASK_MINUTES {
            raise ValueError(f"Subtask {position} needs 1 to {MAX_SUBTASK_MINUTES} minutes.");
        }
        cleaned = cleaned + [
            SubtaskDraft(title=title, tier=draft.tier, estimated_duration=draft.estimated_duration)
        ];
    }
    return cleaned;
}

"""Save an assignment and the subtasks the student confirmed. Nothing is scheduled until this runs."""
def:protect add_assignment(
    course_id: str, title: str, description: str, due_at: str, subtasks: list[SubtaskDraft]
) -> CourseResult {
    course = find_course(course_id);
    if course is None {
        return failed("Pick the course this assignment belongs to.");
    }
    zone = parse_zone(ensure_profile().timezone);
    try {
        clean_title = require_text(title, "Assignment title", MAX_TITLE_LENGTH);
        if len(description) > MAX_DESCRIPTION_LENGTH {
            raise ValueError("The description is too long to save.");
        }
        due = parse_due(due_at, zone, datetime.now(timezone.utc)) if due_at.strip() else None;
        drafts = clean_drafts(subtasks);
    } except ValueError as err {
        return failed(str(err));
    }
    if open_task_count() + len(drafts) > MAX_OPEN_TASKS {
        return failed(f"Your plan is capped at {MAX_OPEN_TASKS} open subtasks. Finish or remove some first.");
    }
    assignment = course +>:Assigned():+> Assignment(
        title=clean_title,
        description=description.strip(),
        due_at=due.isoformat() if due is not None else "",
        created_at=datetime.now(timezone.utc).isoformat()
    );
    for (position, draft) in enumerate(drafts, start=1) {
        assignment +>:Step():+> Task(
            title=draft.title,
            tier=CognitiveTier(draft.tier),
            estimated_duration=draft.estimated_duration,
            order=position
        );
    }
    return ok_courses();
}

def open_task_count -> int {
    return len([
        task
        for course in all_courses()
        for assignment in assignments_of(course)
        for task in [assignment ->:Step:->]
        if not task.done
    ]);
}

def delete_assignment(assignment: Assignment) {
    for task in [assignment ->:Step:->] {
        del task;
    }
    del assignment;
}

def:protect remove_assignment(assignment_id: str) -> CourseResult {
    found = find_assignment(assignment_id);
    if found is None {
        return failed("That assignment no longer exists.");
    }
    (_, assignment) = found;
    delete_assignment(assignment);
    return ok_courses();
}

def:protect set_task_done(task_id: str, done: bool) -> CourseResult {
    task = find_task(task_id);
    if task is None {
        return failed("That subtask no longer exists.");
    }
    task.done = done;
    task.completed_at = datetime.now(timezone.utc).isoformat() if done else "";
    return ok_courses();
}
