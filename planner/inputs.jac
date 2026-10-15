"""Turn a student's stored courses, tasks and calendar into planner inputs.

`load_inputs` is the only function here that reads the graph or calls Google.
Everything it returns is plain data, so the views in `planner/views.jac` and
`planner/week_calendar.jac` are pure and tested without a server. Google event names
are matched to courses here, by code, name or the student's tags.
"""

import from datetime { date, datetime, time, timedelta }
import from account.schema { ensure_profile, protected_blocks, rules_for, to_protected_hours }
import from breakdown { CognitiveTier }
import from connections.google_link { CalendarStatus, google_entries }
import from connectors.google_events { CalendarEntry }
import from courses.matching { CourseMatcher, course_matcher, match_course }
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
    has course_code: str = "";
}

"""An all-day calendar entry; `end_date` is exclusive, as Google sends it. Never blocks time."""
obj AllDayEvent {
    has title: str;
    has start_date: date;
    has end_date: date;
    has course_code: str = "";
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
    has shown: list[CalendarEvent] = [];
    has all_day: list[AllDayEvent] = [];
}

"""One dated event per meeting per matching weekday."""
def expand_meetings(meetings: list[MeetingSpec], days: list[date], rules: PlanRules) -> list[CalendarEvent] {
    return [
        CalendarEvent(
            title=meeting.title,
            start=at_local(day, meeting.start, rules.zone),
            end=at_local(day, meeting.end, rules.zone),
            detail=meeting.detail,
            source="class",
            course_code=meeting.course_code
        )
        for day in days
        for meeting in meetings
        if day.weekday() in meeting.weekdays and meeting.end > meeting.start
    ];
}

"""Google entries split three ways: events that block time, timed events marked
"show as free" (shown, never planned around), and all-day events.
"""
def google_events(
    entries: list[CalendarEntry], matchers: list[CourseMatcher], named: bool
) -> tuple[list[CalendarEvent], list[CalendarEvent], list[AllDayEvent]] {
    source = "google" if named else "busy";
    timed = [
        (e, CalendarEvent(
            title=e.title,
            start=e.start,
            end=e.end,
            detail=e.location,
            source=source,
            course_code=match_course(e.title, matchers) if named else ""
        ))
        for e in entries
        if e.start is not None and e.end is not None
    ];
    all_day = [
        AllDayEvent(
            title=e.title,
            start_date=e.start_date,
            end_date=e.end_date,
            course_code=match_course(e.title, matchers)
        )
        for e in entries
        if e.start_date is not None and e.end_date is not None
    ];
    return (
        [event for (source_entry, event) in timed if source_entry.busy],
        [event for (source_entry, event) in timed if not source_entry.busy],
        all_day
    );
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
        end=parse_clock(meeting.end, "End"),
        course_code=course.code
    );
}

def with_horizon(rules: PlanRules, horizon_days: int) -> PlanRules {
    return PlanRules(
        zone=rules.zone,
        day_start=rules.day_start,
        day_end=rules.day_end,
        deep_work_cutoff=rules.deep_work_cutoff,
        buffer_minutes=rules.buffer_minutes,
        min_slot_minutes=rules.min_slot_minutes,
        horizon_days=horizon_days,
        energy=rules.energy
    );
}

"""Every local date touched by [start, end)."""
def dates_between(start: datetime, end: datetime, rules: PlanRules) -> list[date] {
    first = start.astimezone(rules.zone).date();
    last = (end - timedelta(microseconds=1)).astimezone(rules.zone).date();
    return [first + timedelta(days=n) for n in range((last - first).days + 1)];
}

"""Everything the planner and the views need, read once.

`show_from`/`show_until` widen what is read beyond the planning horizon, so the
calendar can show a whole week, past days included. `horizon_days` plans further
ahead than the student's default.
"""
def load_inputs(
    now: datetime,
    show_from: datetime | None = None,
    show_until: datetime | None = None,
    horizon_days: int | None = None
) -> PlanningInputs {
    profile = ensure_profile();
    base_rules = rules_for(profile);
    rules = with_horizon(base_rules, horizon_days) if horizon_days else base_rules;
    courses = all_courses();
    steps = open_steps(courses);
    meetings = [meeting_spec(course, m) for course in courses for m in meetings_of(course)];
    groups = [
        PlanGroup(group_id=jid(a), label=f"{c.code} {a.title}", due=stored_moment(a.due_at))
        for c in courses
        for a in assignments_of(c)
    ];
    (plan_start, plan_end) = horizon_window(now, rules);
    window_start = min([plan_start] + ([show_from] if show_from else []));
    window_end = max([plan_end] + ([show_until] if show_until else []));
    (entries, calendar) = google_entries(window_start, window_end);
    matchers = [course_matcher(c.code, c.name, c.tags) for c in courses];
    (blocking, shown, all_day) = google_events(entries, matchers, calendar.names);
    return PlanningInputs(
        rules=rules,
        display_name=profile.display_name,
        tasks=[plan_task(a, t) for (_, a, t) in steps],
        info={jid(t): task_info(c, a, t) for (c, a, t) in steps},
        events=expand_meetings(meetings, dates_between(window_start, window_end, rules), rules) + blocking,
        protected=[to_protected_hours(b) for b in protected_blocks()],
        groups=groups,
        calendar=calendar,
        course_count=len(courses),
        shown=shown,
        all_day=all_day
    );
}
