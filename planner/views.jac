"""Today, Plan and "Where it fits" views, built from planner inputs.

Pure functions: given the same `PlanningInputs` and `now`, they return the same
view. Times are formatted here in the student's zone, so the browser shows
labels as they are and does no time-zone math of its own.
"""

import from datetime { date, datetime, timedelta }
import from breakdown { CognitiveTier }
import from connections.google_link { CalendarStatus }
import from planner.inputs { PlanningInputs, TaskInfo }
import from scheduling.planner {
    CalendarEvent,
    Energy,
    Placement,
    Plan,
    PlanRules,
    free_gaps,
    groups_at_risk,
    local_day,
    minutes_between,
    next_event_after,
    next_placement,
    plan_tasks,
    planning_days,
    round_up,
    surrounding_gap,
    tier_minutes
}
import from shared.format { format_minutes, initials }
import from shared.timefmt { clock_label, date_label, day_label, due_label, hour_label, range_label }

glob DAYS_PER_WEEK: int = 7;
glob GAP_IN_MINUTES_BELOW: int = 120;

obj PlanItem {
    has task_id: str;
    has title: str;
    has tier: str;
    has minutes: int;
    has course_code: str;
    has assignment_title: str;
    has start: str = "";
    has end: str = "";
    has day_label: str = "";
    has start_label: str = "";
    has range_label: str = "";
    has due_label: str = "";
    has days_left: int = -1;
    has late: bool = False;
}

obj UpNext {
    has item: PlanItem;
    has why: str;
}

obj TimelineBlock {
    has kind: str;
    has title: str;
    has detail: str;
    has hour_label: str;
    has start: str;
    has end: str;
    has tier: str = "";
    has course_code: str = "";
}

obj WeekLoad {
    has range_label: str;
    has deep_minutes: int;
    has shallow_minutes: int;
    has low_minutes: int;
    has at_risk: int;
}

obj TodayView {
    has date_label: str;
    has display_name: str;
    has initials: str;
    has energy: str;
    has free_state: str;
    has free_until_label: str;
    has free_minutes: int;
    has week: WeekLoad;
    has calendar: CalendarStatus;
    has up_next: UpNext | None = None;
    has queue: list[PlanItem] = [];
    has timeline: list[TimelineBlock] = [];
    has unplaced: list[PlanItem] = [];
    has open_tasks: int = 0;
    has course_count: int = 0;
}

obj DayPlan {
    has day_label: str;
    has date_label: str;
    has items: list[PlanItem];
    has events: list[TimelineBlock];
    has total_minutes: int;
}

obj WeekView {
    has days: list[DayPlan];
    has unplaced: list[PlanItem];
    has at_risk: int;
}

def by_start(p: Placement) -> datetime {
    return p.start;
}

def days_left(due: datetime | None, rules: PlanRules, today: date) -> int {
    if due is None {
        return -1;
    }
    return (local_day(due, rules.zone) - today).days;
}

def plan_item(info: TaskInfo, placement: Placement, rules: PlanRules, today: date, late: set[str]) -> PlanItem {
    start = placement.start.astimezone(rules.zone);
    end = placement.end.astimezone(rules.zone);
    return PlanItem(
        task_id=info.task_id,
        title=info.title,
        tier=info.tier,
        minutes=info.minutes,
        course_code=info.course_code,
        assignment_title=info.assignment_title,
        start=start.isoformat(),
        end=end.isoformat(),
        day_label=day_label(start.date(), today),
        start_label=clock_label(start),
        range_label=range_label(start, end),
        due_label=due_label(info.due.astimezone(rules.zone), today) if info.due is not None else "",
        days_left=days_left(info.due, rules, today),
        late=info.task_id in late
    );
}

def unplaced_item(info: TaskInfo, rules: PlanRules, today: date) -> PlanItem {
    return PlanItem(
        task_id=info.task_id,
        title=info.title,
        tier=info.tier,
        minutes=info.minutes,
        course_code=info.course_code,
        assignment_title=info.assignment_title,
        due_label=due_label(info.due.astimezone(rules.zone), today) if info.due is not None else "",
        days_left=days_left(info.due, rules, today)
    );
}

"""The gap with its article: a 90-minute gap, an 80-minute gap, a 2h 30m gap."""
def gap_phrase(minutes: int) -> str {
    size = f"{minutes}-minute" if minutes < GAP_IN_MINUTES_BELOW else format_minutes(minutes);
    spoken_vowel = size.startswith("8") or size.startswith("11") or size.startswith("18");
    article = "an" if spoken_vowel else "a";
    return f"{article} {size} gap";
}

def deadline_sentence(inputs: PlanningInputs, plan: Plan, chosen: Placement, today: date) -> str {
    info = inputs.info[chosen.task_id];
    if info.due is None {
        return "";
    }
    later = [
        inputs.info[p.task_id] for p in plan.placements
        if p.start > chosen.start and inputs.info[p.task_id].assignment_id == info.assignment_id
    ];
    deep = str(CognitiveTier.DEEP_WORK);
    if info.tier == deep and later and not [step for step in later if step.tier == deep] {
        return "This is the last Deep Work block before the deadline; the remaining steps are lighter.";
    }
    left = days_left(info.due, inputs.rules, today);
    if left < 0 {
        return "It's past due.";
    }
    if left == 0 {
        return "It's due today.";
    }
    if left == 1 {
        return "It's due tomorrow.";
    }
    return f"It's due {due_label(info.due.astimezone(inputs.rules.zone), today)}.";
}

"""The sentence after "Why now:" on the Up next card, built only from facts the planner used."""
def why_now(inputs: PlanningInputs, plan: Plan, chosen: Placement, now: datetime) -> str {
    rules = inputs.rules;
    today = local_day(now, rules.zone);
    deadline = deadline_sentence(inputs, plan, chosen, today);
    chosen_day = local_day(chosen.start, rules.zone);
    if chosen_day != today {
        when = clock_label(chosen.start.astimezone(rules.zone));
        label = day_label(chosen_day, today);
        day = "tomorrow" if label == "Tomorrow" else f"on {label}";
        lead = f"nothing else fits today, so this is first up {day} at {when}.";
        if rules.energy == Energy.LOW and inputs.info[chosen.task_id].tier == str(CognitiveTier.DEEP_WORK) {
            lead = f"your energy is Low, so Deep Work waits until {day} at {when}.";
        }
        return " ".join([part for part in [lead, deadline] if part]);
    }
    reasons: list[str] = [];
    gap = surrounding_gap(chosen, inputs.events, inputs.protected, rules, now);
    if gap is not None {
        phrase = f"you have {gap_phrase(minutes_between(gap.start_time, gap.end_time))}";
        following = next_event_after(inputs.events, gap.end_time);
        if following is not None and following.start - gap.end_time <= timedelta(minutes=rules.buffer_minutes) {
            phrase = f"{phrase} before {following.title}";
        }
        reasons = reasons + [phrase];
    }
    reasons = reasons + [f"you marked your energy {rules.energy}"];
    return " ".join([part for part in [" and ".join(reasons) + ".", deadline] if part]);
}

"""The time, where, and which course, skipping the course when the title already names it."""
def event_detail(event: CalendarEvent, span: str) -> str {
    parts = [span] + ([event.detail] if event.detail else []);
    if event.course_code and event.course_code.lower() not in event.title.lower() {
        parts = parts + [event.course_code];
    }
    return " · ".join(parts);
}

def event_block(event: CalendarEvent, rules: PlanRules) -> TimelineBlock {
    start = event.start.astimezone(rules.zone);
    end = event.end.astimezone(rules.zone);
    return TimelineBlock(
        kind="busy" if event.source == "busy" else "event",
        title=event.title,
        detail=event_detail(event, range_label(start, end)),
        hour_label=hour_label(start),
        start=start.isoformat(),
        end=end.isoformat(),
        course_code=event.course_code
    );
}

def task_block(info: TaskInfo, placement: Placement, rules: PlanRules) -> TimelineBlock {
    start = placement.start.astimezone(rules.zone);
    end = placement.end.astimezone(rules.zone);
    return TimelineBlock(
        kind="task",
        title=f"{info.tier} · {info.title}",
        detail=f"{range_label(start, end)} · {info.course_code}",
        hour_label=hour_label(start),
        start=start.isoformat(),
        end=end.isoformat(),
        tier=info.tier
    );
}

def day_blocks(inputs: PlanningInputs, placements: list[Placement], day: date) -> list[TimelineBlock] {
    rules = inputs.rules;
    events = [event_block(e, rules) for e in inputs.events if local_day(e.start, rules.zone) == day];
    protected = [
        TimelineBlock(
            kind="protected",
            title=f"Protected — {block.label}",
            detail=range_label(datetime.combine(day, block.start), datetime.combine(day, block.end)),
            hour_label=hour_label(datetime.combine(day, block.start, tzinfo=rules.zone)),
            start=datetime.combine(day, block.start, tzinfo=rules.zone).isoformat(),
            end=datetime.combine(day, block.end, tzinfo=rules.zone).isoformat()
        )
        for block in inputs.protected
    ];
    tasks = [task_block(inputs.info[p.task_id], p, rules) for p in placements];
    return sorted(events + protected + tasks, key=lambda (b: TimelineBlock) -> str { return b.start; });
}

"""free / busy / done, the next boundary as a label, and minutes until it."""
def free_status(inputs: PlanningInputs, now: datetime) -> tuple[str, str, int] {
    rules = inputs.rules;
    local_now = now.astimezone(rules.zone);
    today = local_now.date();
    gaps = [
        g for g in free_gaps(inputs.events, inputs.protected, rules, now)
        if local_day(g.start_time, rules.zone) == today
    ];
    if not gaps {
        return ("done", "", 0);
    }
    first = gaps[0];
    if first.start_time <= round_up(local_now) {
        return ("free", clock_label(first.end_time), minutes_between(local_now, first.end_time));
    }
    return ("busy", clock_label(first.start_time), minutes_between(local_now, first.start_time));
}

def week_load(plan: Plan, inputs: PlanningInputs, now: datetime) -> WeekLoad {
    rules = inputs.rules;
    today = local_day(now, rules.zone);
    monday = today - timedelta(days=today.weekday());
    sunday = monday + timedelta(days=DAYS_PER_WEEK - 1);
    totals = tier_minutes(
        plan,
        inputs.tasks,
        datetime.combine(monday, datetime.min.time(), tzinfo=rules.zone),
        datetime.combine(sunday + timedelta(days=1), datetime.min.time(), tzinfo=rules.zone)
    );
    return WeekLoad(
        range_label=f"{monday.strftime('%b')} {monday.day} – {sunday.strftime('%b')} {sunday.day}",
        deep_minutes=totals[str(CognitiveTier.DEEP_WORK)],
        shallow_minutes=totals[str(CognitiveTier.SHALLOW_WORK)],
        low_minutes=totals[str(CognitiveTier.LOW_ENERGY)],
        at_risk=len(groups_at_risk(plan, inputs.tasks))
    );
}

def today_view(inputs: PlanningInputs, now: datetime) -> TodayView {
    rules = inputs.rules;
    today = local_day(now, rules.zone);
    plan = plan_tasks(inputs.tasks, inputs.events, inputs.protected, rules, now);
    late = set(plan.late);
    todays = sorted(
        [p for p in plan.placements if local_day(p.start, rules.zone) == today], key=by_start
    );
    chosen = next_placement(plan, now);
    up_next: UpNext | None = None;
    queue: list[PlanItem] = [];
    if chosen is not None {
        up_next = UpNext(
            item=plan_item(inputs.info[chosen.task_id], chosen, rules, today, late),
            why=why_now(inputs, plan, chosen, now)
        );
        queue = [
            plan_item(inputs.info[p.task_id], p, rules, today, late)
            for p in todays
            if p.task_id != chosen.task_id and p.start >= chosen.start
        ];
    }
    (state, until, minutes) = free_status(inputs, now);
    return TodayView(
        date_label=date_label(today),
        display_name=inputs.display_name,
        initials=initials(inputs.display_name),
        energy=str(rules.energy),
        free_state=state,
        free_until_label=until,
        free_minutes=minutes,
        week=week_load(plan, inputs, now),
        calendar=inputs.calendar,
        up_next=up_next,
        queue=queue,
        timeline=day_blocks(inputs, todays, today),
        unplaced=[unplaced_item(inputs.info[t], rules, today) for t in plan.unplaced],
        open_tasks=len(inputs.tasks),
        course_count=inputs.course_count
    );
}

def week_view(inputs: PlanningInputs, now: datetime) -> WeekView {
    rules = inputs.rules;
    today = local_day(now, rules.zone);
    plan = plan_tasks(inputs.tasks, inputs.events, inputs.protected, rules, now);
    late = set(plan.late);
    days: list[DayPlan] = [];
    for day in planning_days(now, rules) {
        placed = sorted(
            [p for p in plan.placements if local_day(p.start, rules.zone) == day], key=by_start
        );
        days = days + [
            DayPlan(
                day_label=day_label(day, today),
                date_label=date_label(day),
                items=[plan_item(inputs.info[p.task_id], p, rules, today, late) for p in placed],
                events=[b for b in day_blocks(inputs, [], day) if b.kind != "protected"],
                total_minutes=sum([minutes_between(p.start, p.end) for p in placed])
            )
        ];
    }
    return WeekView(
        days=days,
        unplaced=[unplaced_item(inputs.info[t], rules, today) for t in plan.unplaced],
        at_risk=len(groups_at_risk(plan, inputs.tasks))
    );
}
