"""Turn a student's stored courses, tasks and calendar into planner inputs.

`load_inputs` is the only function here that reads the graph or calls Google.
Everything it returns is plain data, so the views in `planner/views.jac` are
pure and tested without a server.
"""

import from datetime { date, datetime, time, timedelta }
import from account.schema { ensure_profile, protected_blocks, rules_for, to_protected_hours }
import from breakdown { CognitiveTier }
import from connections.google_link { CalendarStatus, google_busy_events }
import from courses.schema {
    Assignment,
    ClassMeeting,
    Course,
    Task,
    all_courses,
    assignments_of,
    meetings_of,
    steps_of
}
import from scheduling.planner {
    CalendarEvent,
    PlanGroup,
    PlanRules,
    PlanTask,
    ProtectedHours,
    at_local,
    planning_days
}
import from shared.timefmt { parse_clock, stored_moment }

"""What the views show about a task besides where it lands."""
obj TaskInfo {
    has task_id: str;
    has title: str;
    has tier: str;
    has minutes: int;
    has course_code: str;
    has assignment_id: str;
    has assignment_title: str;
    has due: datetime | None = None;
}

"""A weekly class meeting, ready to expand into dated events."""
obj MeetingSpec {
    has title: str;
    has detail: str;
    has weekdays: list[int];
    has start: time;
    has end: time;
}

obj PlanningInputs {
    has rules: PlanRules;
    has display_name: str;
    has tasks: list[PlanTask];
    has info: dict[str, TaskInfo];
    has events: list[CalendarEvent];
    has protected: list[ProtectedHours];
    has groups: list[PlanGroup];
    has calendar: CalendarStatus;
    has course_count: int;
}

"""One dated event per meeting per matching weekday."""
def expand_meetings(meetings: list[MeetingSpec], days: list[date], rules: PlanRules) -> list[CalendarEvent] {
    return [
        CalendarEvent(
            title=meeting.title,
            start=at_local(day, meeting.start, rules.zone),
            end=at_local(day, meeting.end, rules.zone),
            detail=meeting.detail
        )
        for day in days
        for meeting in meetings
        if day.weekday() in meeting.weekdays and meeting.end > meeting.start
    ];
}

"""From the start of the first planning day to the end of the last."""
def horizon_window(now: datetime, rules: PlanRules) -> tuple[datetime, datetime] {
    days = planning_days(now, rules);
    return (
        at_local(days[0], time(0), rules.zone),
        at_local(days[-1] + timedelta(days=1), time(0), rules.zone)
    );
}

"""Every open subtask with its assignment and course, in one pass over the graph."""
def open_steps(courses: list[Course]) -> list[tuple[Course, Assignment, Task]] {
    return [
        (course, assignment, task)
        for course in courses
        for assignment in assignments_of(course)
        for task in steps_of(assignment)
        if not task.done
    ];
}

def plan_task(assignment: Assignment, task: Task) -> PlanTask {
    return PlanTask(
        task_id=jid(task),
        title=task.title,
        tier=CognitiveTier(task.tier),
        minutes=task.estimated_duration,
        group_id=jid(assignment),
        order=task.order,
        due=stored_moment(assignment.due_at),
        not_before=stored_moment(task.not_before)
    );
}

def task_info(course: Course, assignment: Assignment, task: Task) -> TaskInfo {
    return TaskInfo(
        task_id=jid(task),
        title=task.title,
        tier=str(task.tier),
        minutes=task.estimated_duration,
        course_code=course.code,
        assignment_id=jid(assignment),
        assignment_title=assignment.title,
        due=stored_moment(assignment.due_at)
    );
}

def meeting_spec(course: Course, meeting: ClassMeeting) -> MeetingSpec {
    return MeetingSpec(
        title=f"{course.code} {meeting.kind}",
        detail=meeting.location,
        weekdays=meeting.weekdays,
        start=parse_clock(meeting.start, "Start"),
        end=parse_clock(meeting.end, "End")
    );
}

def load_inputs(now: datetime) -> PlanningInputs {
    profile = ensure_profile();
    rules = rules_for(profile);
    courses = all_courses();
    steps = open_steps(courses);
    meetings = [meeting_spec(course, m) for course in courses for m in meetings_of(course)];
    groups = [
        PlanGroup(group_id=jid(a), label=f"{c.code} {a.title}", due=stored_moment(a.due_at))
        for c in courses
        for a in assignments_of(c)
    ];
    (window_start, window_end) = horizon_window(now, rules);
    (busy, calendar) = google_busy_events(window_start, window_end);
    return PlanningInputs(
        rules=rules,
        display_name=profile.display_name,
        tasks=[plan_task(a, t) for (_, a, t) in steps],
        info={jid(t): task_info(c, a, t) for (c, a, t) in steps},
        events=expand_meetings(meetings, planning_days(now, rules), rules) + busy,
        protected=[to_protected_hours(b) for b in protected_blocks()],
        groups=groups,
        calendar=calendar,
        course_count=len(courses)
    );
}
