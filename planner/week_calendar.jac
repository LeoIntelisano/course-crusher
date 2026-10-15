"""The week calendar on the Today screen.

Shows class times, Google events (with names and the course each one matched),
protected hours and the planner's blocks, Monday to Sunday. Pure: it lays out
`PlanningInputs`, so the browser only has to draw rectangles.

Positions are minutes since local midnight. Overlapping items in a day share the
column side by side: each gets a `lane` out of `lanes`.
"""

import from datetime { date, datetime, time, timedelta }
import from courses.matching { normalize }
import from planner.inputs { AllDayEvent, CourseChoice, PlanningInputs }
import from scheduling.planner {
    CalendarEvent,
    PlanRules,
    ProtectedHours,
    at_local,
    local_day,
    plan_tasks
}
import from shared.timefmt { range_label }

glob DAYS_PER_WEEK: int = 7;
glob MINUTES_PER_HOUR: int = 60;
glob MINUTES_PER_DAY: int = 1440;
glob WEEK_OFFSET_LIMIT: int = 8;

obj CalendarItem {
    has key: str;
    has kind: str;
    has title: str;
    has detail: str;
    has start_minute: int;
    has end_minute: int;
    has course_code: str = "";
    has tier: str = "";
    has color: str = "";
    has linkable: bool = False;
    has linked: bool = False;
    has lane: int = 0;
    has lanes: int = 1;
}

obj AllDayItem {
    has title: str;
    has course_code: str = "";
    has color: str = "";
}

obj CalendarDay {
    has iso_date: str;
    has weekday: str;
    has date_label: str;
    has is_today: bool;
    has items: list[CalendarItem];
    has all_day: list[AllDayItem];
}

"""A week of days. `start_minute`/`end_minute` bound the grid; `now_minute` is -1 unless today is shown."""
obj CalendarView {
    has days: list[CalendarDay];
    has range_label: str;
    has week_offset: int;
    has start_minute: int;
    has end_minute: int;
    has now_minute: int;
    has connected: bool;
    has names: bool;
    has courses: list[CourseChoice] = [];
}

def clamp_offset(week_offset: int) -> int {
    return max(-WEEK_OFFSET_LIMIT, min(WEEK_OFFSET_LIMIT, week_offset));
}

"""Monday of the week `week_offset` weeks from this one, in the student's zone."""
def week_start(now: datetime, rules: PlanRules, week_offset: int) -> date {
    today = local_day(now, rules.zone);
    return today - timedelta(days=today.weekday()) + timedelta(weeks=clamp_offset(week_offset));
}

def minute_of_day(moment: datetime, day: date, rules: PlanRules) -> int {
    midnight = at_local(day, time(0), rules.zone);
    minutes = int((moment - midnight).total_seconds() // MINUTES_PER_HOUR);
    return max(0, min(MINUTES_PER_DAY, minutes));
}

def clock_minutes(value: time) -> int {
    return value.hour * MINUTES_PER_HOUR + value.minute;
}

def event_kind(event: CalendarEvent, blocking: bool) -> str {
    if event.source == "class" {
        return "class";
    }
    if event.source == "busy" {
        return "busy";
    }
    return "event" if blocking else "free";
}

def event_detail(event: CalendarEvent, start: datetime, end: datetime, rules: PlanRules) -> str {
    parts = [range_label(start.astimezone(rules.zone), end.astimezone(rules.zone))];
    if event.detail {
        parts = parts + [event.detail];
    }
    return " · ".join(parts);
}

"""The part of an event that falls on `day`, or None. Multi-day events become one piece per day.

Named Google events are `linkable`: the student can tie them to a course by hand.
"""
def event_piece(
    event: CalendarEvent,
    blocking: bool,
    day: date,
    inputs: PlanningInputs,
    index: int
) -> CalendarItem | None {
    rules = inputs.rules;
    day_start = at_local(day, time(0), rules.zone);
    day_end = at_local(day + timedelta(days=1), time(0), rules.zone);
    if event.end <= day_start or event.start >= day_end {
        return None;
    }
    start = max(event.start, day_start);
    end = min(event.end, day_end);
    return CalendarItem(
        key=f"{event.source}-{day.isoformat()}-{index}",
        kind=event_kind(event, blocking),
        title=event.title,
        detail=event_detail(event, event.start, event.end, rules),
        start_minute=minute_of_day(start, day, rules),
        end_minute=minute_of_day(end, day, rules),
        course_code=event.course_code,
        color=inputs.colors.get(event.course_code, ""),
        linkable=event.source == "google",
        linked=normalize(event.title) in inputs.links
    );
}

def protected_item(block: ProtectedHours, day: date, index: int) -> CalendarItem {
    return CalendarItem(
        key=f"protected-{day.isoformat()}-{index}",
        kind="protected",
        title=block.label,
        detail=f"{block.start.strftime('%H:%M')} – {block.end.strftime('%H:%M')} · protected",
        start_minute=clock_minutes(block.start),
        end_minute=clock_minutes(block.end)
    );
}

"""Give overlapping items side-by-side lanes. Returns new items; the input is untouched.

Items that overlap, directly or through a chain, form a cluster; each item takes
the first lane that is free when it starts, and the cluster's lane count becomes
every member's `lanes`.
"""
def assign_lanes(items: list[CalendarItem]) -> list[CalendarItem] {
    ordered = sorted(items, key=lambda (i: CalendarItem) -> tuple[int, int] { return (i.start_minute, -i.end_minute); });
    placed: list[CalendarItem] = [];
    cluster: list[tuple[CalendarItem, int]] = [];
    lane_ends: list[int] = [];
    cluster_end = -1;
    for item in ordered {
        if cluster and item.start_minute >= cluster_end {
            placed = placed + close_cluster(cluster, len(lane_ends));
            cluster = [];
            lane_ends = [];
            cluster_end = -1;
        }
        free = [n for (n, end) in enumerate(lane_ends) if end <= item.start_minute];
        lane = free[0] if free else len(lane_ends);
        if free {
            lane_ends = [item.end_minute if n == lane else end for (n, end) in enumerate(lane_ends)];
        } else {
            lane_ends = lane_ends + [item.end_minute];
        }
        cluster = cluster + [(item, lane)];
        cluster_end = max(cluster_end, item.end_minute);
    }
    if cluster {
        placed = placed + close_cluster(cluster, len(lane_ends));
    }
    return placed;
}

def close_cluster(cluster: list[tuple[CalendarItem, int]], lanes: int) -> list[CalendarItem] {
    return [
        CalendarItem(
            key=item.key,
            kind=item.kind,
            title=item.title,
            detail=item.detail,
            start_minute=item.start_minute,
            end_minute=item.end_minute,
            course_code=item.course_code,
            tier=item.tier,
            color=item.color,
            linkable=item.linkable,
            linked=item.linked,
            lane=lane,
            lanes=lanes
        )
        for (item, lane) in cluster
    ];
}

def all_day_on(events: list[AllDayEvent], day: date, colors: dict[str, str]) -> list[AllDayItem] {
    return [
        AllDayItem(title=e.title, course_code=e.course_code, color=colors.get(e.course_code, ""))
        for e in events
        if e.start_date <= day < e.end_date
    ];
}

def round_down_hour(minute: int) -> int {
    return (minute // MINUTES_PER_HOUR) * MINUTES_PER_HOUR;
}

def round_up_hour(minute: int) -> int {
    return min(MINUTES_PER_DAY, -(-minute // MINUTES_PER_HOUR) * MINUTES_PER_HOUR);
}

def calendar_view(inputs: PlanningInputs, now: datetime, week_offset: int) -> CalendarView {
    rules = inputs.rules;
    offset = clamp_offset(week_offset);
    first = week_start(now, rules, offset);
    today = local_day(now, rules.zone);
    plan = plan_tasks(inputs.tasks, inputs.events, inputs.protected, rules, now);
    days: list[CalendarDay] = [];
    for day in [first + timedelta(days=n) for n in range(DAYS_PER_WEEK)] {
        pieces = [
            piece
            for (index, (event, blocking)) in enumerate(
                [(e, True) for e in inputs.events] + [(e, False) for e in inputs.shown]
            )
            for piece in [event_piece(event, blocking, day, inputs, index)]
            if piece is not None
        ];
        protected = [protected_item(block, day, n) for (n, block) in enumerate(inputs.protected)];
        tasks = [
            CalendarItem(
                key=f"task-{p.task_id}",
                kind="task",
                title=inputs.info[p.task_id].title,
                detail=f"{range_label(p.start.astimezone(rules.zone), p.end.astimezone(rules.zone))} · {inputs.info[p.task_id].course_code}",
                start_minute=minute_of_day(p.start, day, rules),
                end_minute=minute_of_day(p.end, day, rules),
                course_code=inputs.info[p.task_id].course_code,
                tier=inputs.info[p.task_id].tier,
                color=inputs.colors.get(inputs.info[p.task_id].course_code, "")
            )
            for p in plan.placements
            if local_day(p.start, rules.zone) == day
        ];
        items = [i for i in pieces + protected + tasks if i.end_minute > i.start_minute];
        days = days + [
            CalendarDay(
                iso_date=day.isoformat(),
                weekday=day.strftime("%a"),
                date_label=f"{day.strftime('%b')} {day.day}",
                is_today=day == today,
                items=assign_lanes(items),
                all_day=all_day_on(inputs.all_day, day, inputs.colors)
            )
        ];
    }
    every = [i for d in days for i in d.items];
    top = min([clock_minutes(rules.day_start)] + [i.start_minute for i in every]);
    bottom = max([clock_minutes(rules.day_end)] + [i.end_minute for i in every]);
    last = first + timedelta(days=DAYS_PER_WEEK - 1);
    return CalendarView(
        days=days,
        range_label=f"{first.strftime('%b')} {first.day} – {last.strftime('%b')} {last.day}",
        week_offset=offset,
        start_minute=round_down_hour(top),
        end_minute=round_up_hour(bottom),
        now_minute=minute_of_day(now, today, rules) if first <= today <= last else -1,
        connected=inputs.calendar.state == "connected" or inputs.calendar.state == "error",
        names=inputs.calendar.names,
        courses=inputs.choices
    );
}
