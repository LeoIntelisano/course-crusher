"""Fit subtasks into a student's free time over the coming days.

Pure functions over plain objects: no graph, no network, no clock. Callers pass
`now`, every calendar event and the protected hours, so a test can pin a day
exactly. `planner/service.jac` turns stored tasks into `PlanTask`s and the
resulting `Plan` into the Today, Plan and Breakdown views.

Rules, in the order they are applied:

1. Free time is each day's window minus calendar events (padded by
   `buffer_minutes` for travel) and protected hours. Gaps shorter than
   `min_slot_minutes` are dropped, as in `find_free_slots`.
2. Tasks are placed earliest deadline first. Tasks of one assignment keep their
   breakdown order and never start before the previous one ends.
3. Each task goes into the earliest gap it fits whole; tasks are never split.
4. Deep Work must end by `deep_work_cutoff`, so it stays off late nights.
5. Energy sets how much Deep Work fits in the rest of today: no cap at High,
   `MEDIUM_DEEP_WORK_MINUTES` at Medium, none at Low. Deep Work due today or
   overdue is never held back and doesn't count against the cap. Whatever
   doesn't fit today moves to a later day.
6. A task with an approved time (`fixed_start`) is placed there first and keeps
   it while that time is still free, not over, and allowed by rules 4 and 5. A
   block already under way keeps its start. Otherwise the task is placed like
   any other.
"""

import from datetime { date, datetime, time, timedelta, timezone, tzinfo }
import from breakdown { CognitiveTier }
import from scheduling.time_slots { BusyBlock, TimeSlot, day_window, find_free_slots, time_slot }

glob DEFAULT_DAY_START: time = time(8);
glob DEFAULT_DAY_END: time = time(22);
glob DEFAULT_DEEP_WORK_CUTOFF: time = time(21);
glob DEFAULT_BUFFER_MINUTES: int = 10;
glob DEFAULT_MIN_SLOT_MINUTES: int = 15;
glob DEFAULT_HORIZON_DAYS: int = 7;
glob MAX_HORIZON_DAYS: int = 28;
glob START_GRANULARITY_MINUTES: int = 5;
glob NO_DEADLINE: datetime = datetime.max.replace(tzinfo=timezone.utc);
glob MEDIUM_DEEP_WORK_MINUTES: int = 90;

"""How much focus the student says they have right now."""
enum Energy: str {
    HIGH = "High",
    MEDIUM = "Medium",
    LOW = "Low"
}

"""One unit of work to place. `group_id` is the assignment; `order` is its breakdown position."""
obj PlanTask {
    has task_id: str;
    has title: str;
    has tier: CognitiveTier;
    has minutes: int;
    has group_id: str = "";
    has order: int = 1;
    has due: datetime | None = None;
    has not_before: datetime | None = None;
    has fixed_start: datetime | None = None;
}

"""A fixed calendar commitment: a class time, a named Google event, or an anonymous busy block.

`source` is "class", "google" or "busy"; `course_code` is set when the event belongs to a course.
"""
obj CalendarEvent {
    has title: str;
    has start: datetime;
    has end: datetime;
    has detail: str = "";
    has source: str = "";
    has course_code: str = "";
}

"""Time the student keeps free every day, such as dinner and the gym."""
obj ProtectedHours {
    has label: str;
    has start: time;
    has end: time;
}

obj PlanRules {
    has zone: tzinfo;
    has day_start: time = DEFAULT_DAY_START;
    has day_end: time = DEFAULT_DAY_END;
    has deep_work_cutoff: time = DEFAULT_DEEP_WORK_CUTOFF;
    has buffer_minutes: int = DEFAULT_BUFFER_MINUTES;
    has min_slot_minutes: int = DEFAULT_MIN_SLOT_MINUTES;
    has horizon_days: int = DEFAULT_HORIZON_DAYS;
    has energy: Energy = Energy.HIGH;
}

"""Where a task landed. `fixed` means it kept the time the student approved."""
obj Placement {
    has task_id: str;
    has start: datetime;
    has end: datetime;
    has fixed: bool = False;
}

"""Where every task landed. `unplaced` found no gap in the horizon; `late` ends after its due time."""
obj Plan {
    has placements: list[Placement];
    has unplaced: list[str];
    has late: list[str];
    has free: list[TimeSlot];
}

enum CheckLevel: str {
    OK = "ok",
    WARN = "warn",
    ERROR = "error"
}

"""One line of the "Agent checks" card."""
obj PlanCheck {
    has level: CheckLevel;
    has message: str;
}

"""Display name and deadline for each assignment, used by the checks."""
obj PlanGroup {
    has group_id: str;
    has label: str;
    has due: datetime | None = None;
}

def validate_rules(rules: PlanRules) {
    if rules.day_end <= rules.day_start {
        raise ValueError("The day must end after it starts.");
    }
    if rules.buffer_minutes < 0 {
        raise ValueError("The buffer between events cannot be negative.");
    }
    if rules.min_slot_minutes < 1 {
        raise ValueError("The shortest useful slot must be at least 1 minute.");
    }
    if not 1 <= rules.horizon_days <= MAX_HORIZON_DAYS {
        raise ValueError(f"Plan between 1 and {MAX_HORIZON_DAYS} days ahead.");
    }
}

def validate_task(task: PlanTask) {
    if task.minutes <= 0 {
        raise ValueError(f"Task {task.task_id} needs a positive duration.");
    }
}

"""Round up to the next 5-minute mark so suggested start times read cleanly."""
def round_up(moment: datetime, minutes: int = START_GRANULARITY_MINUTES) -> datetime {
    floored = moment.replace(second=0, microsecond=0);
    overshoot = floored.minute % minutes;
    if overshoot == 0 and floored == moment {
        return floored;
    }
    return floored + timedelta(minutes=(minutes - overshoot));
}

def local_day(moment: datetime, zone: tzinfo) -> date {
    return moment.astimezone(zone).date();
}

def at_local(day: date, clock: time, zone: tzinfo) -> datetime {
    return datetime.combine(day, clock, tzinfo=zone);
}

def planning_days(now: datetime, rules: PlanRules) -> list[date] {
    first = local_day(now, rules.zone);
    return [first + timedelta(days=offset) for offset in range(rules.horizon_days)];
}

def protected_on(blocks: list[ProtectedHours], day: date, zone: tzinfo) -> list[BusyBlock] {
    return [
        BusyBlock(start=at_local(day, block.start, zone), end=at_local(day, block.end, zone))
        for block in blocks
        if block.end > block.start
    ];
}

"""Calendar events as busy time, padded so work never starts the minute a class ends."""
def padded_events(events: list[CalendarEvent], buffer_minutes: int) -> list[BusyBlock] {
    pad = timedelta(minutes=buffer_minutes);
    return [BusyBlock(start=event.start - pad, end=event.end + pad) for event in events];
}

"""Every free gap from `now` to the end of the horizon, in chronological order."""
def free_gaps(
    events: list[CalendarEvent],
    protected: list[ProtectedHours],
    rules: PlanRules,
    now: datetime
) -> list[TimeSlot] {
    validate_rules(rules);
    busy = padded_events(events, rules.buffer_minutes);
    earliest = round_up(now.astimezone(rules.zone));
    gaps: list[TimeSlot] = [];
    for day in planning_days(now, rules) {
        (window_start, window_end) = day_window(day, rules.zone, rules.day_start, rules.day_end);
        start = max(window_start, earliest);
        if start >= window_end {
            continue;
        }
        day_busy = busy + protected_on(protected, day, rules.zone);
        gaps = gaps + find_free_slots(day_busy, start, window_end, rules.min_slot_minutes);
    }
    return gaps;
}

def sort_key(task: PlanTask) -> tuple[datetime, str, int, str] {
    return (task.due or NO_DEADLINE, task.group_id, task.order, task.task_id);
}

"""Minutes of Deep Work that fit in the rest of today at `energy`; None means no cap."""
def deep_work_budget(energy: Energy) -> int | None {
    if energy == Energy.LOW {
        return 0;
    }
    if energy == Energy.MEDIUM {
        return MEDIUM_DEEP_WORK_MINUTES;
    }
    return None;
}

"""Today's Deep Work that the energy cap applies to: not due today and not overdue."""
def capped_today(task: PlanTask, gap_day: date, rules: PlanRules, today: date) -> bool {
    if task.tier != CognitiveTier.DEEP_WORK or gap_day != today {
        return False;
    }
    return task.due is None or local_day(task.due, rules.zone) > today;
}

"""Rule 5. `deep_used` is the capped Deep Work already placed today."""
def deep_work_allowed(task: PlanTask, gap_day: date, rules: PlanRules, today: date, deep_used: int = 0) -> bool {
    if not capped_today(task, gap_day, rules, today) {
        return True;
    }
    budget = deep_work_budget(rules.energy);
    return budget is None or deep_used + task.minutes <= budget;
}

"""What placing `task` at `start` adds to today's capped Deep Work."""
def budget_cost(task: PlanTask, start: datetime, rules: PlanRules, today: date) -> int {
    return task.minutes if capped_today(task, local_day(start, rules.zone), rules, today) else 0;
}

"""The earliest start for `task` inside `gap`, or None when it does not fit there."""
def fit_in_gap(
    task: PlanTask, gap: TimeSlot, earliest: datetime, rules: PlanRules, today: date, deep_used: int = 0
) -> datetime | None {
    start = round_up(max(gap.start_time, earliest).astimezone(rules.zone));
    end = start + timedelta(minutes=task.minutes);
    if end > gap.end_time {
        return None;
    }
    gap_day = local_day(start, rules.zone);
    if not deep_work_allowed(task, gap_day, rules, today, deep_used) {
        return None;
    }
    if task.tier == CognitiveTier.DEEP_WORK and end > at_local(gap_day, rules.deep_work_cutoff, rules.zone) {
        return None;
    }
    return start;
}

"""Remove [start, end) from the gap at `index`, keeping what is left on either side."""
def consume(gaps: list[TimeSlot], index: int, start: datetime, end: datetime) -> list[TimeSlot] {
    gap = gaps[index];
    remnants = [
        time_slot(s, e)
        for (s, e) in [(gap.start_time, start), (end, gap.end_time)]
        if e > s
    ];
    return gaps[:index] + remnants + gaps[index + 1:];
}

"""The gap holding [start, end) whole, or -1."""
def gap_holding(gaps: list[TimeSlot], start: datetime, end: datetime) -> int {
    for (index, gap) in enumerate(gaps) {
        if gap.start_time <= start and end <= gap.end_time {
            return index;
        }
    }
    return -1;
}

"""Whether an approved time still stands: not over, not before `not_before`, and allowed today."""
def fixed_time_allowed(
    task: PlanTask, start: datetime, end: datetime, rules: PlanRules, now: datetime, today: date, deep_used: int
) -> bool {
    if end <= now or (task.not_before is not None and start < task.not_before) {
        return False;
    }
    day = local_day(start, rules.zone);
    if not deep_work_allowed(task, day, rules, today, deep_used) {
        return False;
    }
    return not (task.tier == CognitiveTier.DEEP_WORK and end > at_local(day, rules.deep_work_cutoff, rules.zone));
}

"""Tasks with an approved time, earliest first."""
def approved_times(tasks: list[PlanTask]) -> list[tuple[datetime, PlanTask]] {
    pinned: list[tuple[datetime, PlanTask]] = [];
    for task in tasks {
        start = task.fixed_start;
        if start is not None {
            pinned = pinned + [(start, task)];
        }
    }
    return sorted(pinned, key=lambda (pair: tuple[datetime, PlanTask]) -> datetime { return pair[0]; });
}

"""Rule 6: keep each approved time that still stands, consuming its slot from the gaps.

Returns the kept placements, the gaps left, and the capped Deep Work they use today.
"""
def place_fixed(
    tasks: list[PlanTask], gaps: list[TimeSlot], rules: PlanRules, now: datetime, today: date
) -> tuple[list[Placement], list[TimeSlot], int] {
    placements: list[Placement] = [];
    deep_used = 0;
    earliest = round_up(now.astimezone(rules.zone));
    for (start, task) in approved_times(tasks) {
        end = start + timedelta(minutes=task.minutes);
        if not fixed_time_allowed(task, start, end, rules, now, today, deep_used) {
            continue;
        }
        # A block already under way only needs what's left of it to be free.
        held_from = max(start, earliest);
        index = gap_holding(gaps, held_from, end) if held_from < end else -1;
        if index < 0 {
            continue;
        }
        placements = placements + [Placement(task_id=task.task_id, start=start, end=end, fixed=True)];
        gaps = consume(gaps, index, held_from, end);
        deep_used = deep_used + budget_cost(task, start, rules, today);
    }
    return (placements, gaps, deep_used);
}

def earliest_start(task: PlanTask, now: datetime, ready: dict[str, datetime]) -> datetime {
    candidates = [now] + [moment for moment in [task.not_before, ready.get(task.group_id)] if moment is not None];
    return max(candidates);
}

"""Place every task; see the module docstring for the rules."""
def plan_tasks(
    tasks: list[PlanTask],
    events: list[CalendarEvent],
    protected: list[ProtectedHours],
    rules: PlanRules,
    now: datetime
) -> Plan {
    for task in tasks {
        validate_task(task);
    }
    today = local_day(now, rules.zone);
    (placements, gaps, deep_used) = place_fixed(tasks, free_gaps(events, protected, rules, now), rules, now, today);
    kept = {p.task_id: p for p in placements};
    unplaced: list[str] = [];
    ready: dict[str, datetime] = {};
    blocked: set[str] = set();
    for task in sorted(tasks, key=sort_key) {
        if task.task_id in kept {
            end = kept[task.task_id].end;
            if task.group_id {
                ready = {**ready, task.group_id: max(end, ready.get(task.group_id, end))};
            }
            continue;
        }
        if task.group_id and task.group_id in blocked {
            unplaced = unplaced + [task.task_id];
            continue;
        }
        earliest = earliest_start(task, now, ready);
        spot = first_fit(task, gaps, earliest, rules, today, deep_used);
        if spot is None {
            unplaced = unplaced + [task.task_id];
            if task.group_id {
                # later steps of this assignment cannot jump ahead of it
                blocked = blocked | {task.group_id};
            }
            continue;
        }
        (index, start) = spot;
        end = start + timedelta(minutes=task.minutes);
        placements = placements + [Placement(task_id=task.task_id, start=start, end=end)];
        gaps = consume(gaps, index, start, end);
        deep_used = deep_used + budget_cost(task, start, rules, today);
        if task.group_id {
            ready = {**ready, task.group_id: end};
        }
    }
    return Plan(
        placements=placements,
        unplaced=unplaced,
        late=late_tasks(tasks, placements),
        free=gaps
    );
}

def first_fit(
    task: PlanTask, gaps: list[TimeSlot], earliest: datetime, rules: PlanRules, today: date, deep_used: int = 0
) -> tuple[int, datetime] | None {
    for (index, gap) in enumerate(gaps) {
        if gap.end_time <= earliest {
            continue;
        }
        start = fit_in_gap(task, gap, earliest, rules, today, deep_used);
        if start is not None {
            return (index, start);
        }
    }
    return None;
}

def late_tasks(tasks: list[PlanTask], placements: list[Placement]) -> list[str] {
    due_by_id = {task.task_id: task.due for task in tasks};
    return [
        placement.task_id
        for placement in placements
        if due_by_id.get(placement.task_id) is not None
        and placement.end > due_by_id[placement.task_id]
    ];
}

def placement_for(plan: Plan, task_id: str) -> Placement | None {
    for placement in plan.placements {
        if placement.task_id == task_id {
            return placement;
        }
    }
    return None;
}

"""The next planned block that has not ended yet, or None when nothing is placed."""
def next_placement(plan: Plan, now: datetime) -> Placement | None {
    upcoming = [p for p in plan.placements if p.end > now];
    if not upcoming {
        return None;
    }
    return min(upcoming, key=lambda (p: Placement) -> datetime { return p.start; });
}

"""The free gap a placement sits in, measured before anything was placed into it."""
def surrounding_gap(
    placement: Placement,
    events: list[CalendarEvent],
    protected: list[ProtectedHours],
    rules: PlanRules,
    now: datetime
) -> TimeSlot | None {
    for gap in free_gaps(events, protected, rules, now) {
        if gap.start_time <= placement.start and placement.end <= gap.end_time {
            return gap;
        }
    }
    return None;
}

"""The first calendar event that starts at or after `moment`."""
def next_event_after(events: list[CalendarEvent], moment: datetime) -> CalendarEvent | None {
    later = [event for event in events if event.start >= moment];
    if not later {
        return None;
    }
    return min(later, key=lambda (e: CalendarEvent) -> datetime { return e.start; });
}

"""Minutes booked per tier for placements starting inside [start, end)."""
def tier_minutes(
    plan: Plan, tasks: list[PlanTask], start: datetime, end: datetime
) -> dict[str, int] {
    tier_by_id = {task.task_id: str(task.tier) for task in tasks};
    totals = {str(tier): 0 for tier in list(CognitiveTier)};
    for placement in plan.placements {
        if start <= placement.start < end {
            tier = tier_by_id[placement.task_id];
            totals = {**totals, tier: totals[tier] + minutes_between(placement.start, placement.end)};
        }
    }
    return totals;
}

def minutes_between(start: datetime, end: datetime) -> int {
    return int((end - start).total_seconds() // 60);
}

"""Assignments with a step that is late or found no time before its deadline."""
def groups_at_risk(plan: Plan, tasks: list[PlanTask]) -> list[str] {
    risky = set(plan.late) | set(plan.unplaced);
    groups = {task.group_id for task in tasks if task.task_id in risky and task.due is not None};
    return sorted(groups);
}

"""The "Agent checks" for one assignment's proposed or saved subtasks."""
def plan_checks(
    plan: Plan,
    tasks: list[PlanTask],
    events: list[CalendarEvent],
    groups: list[PlanGroup],
    focus_group: str,
    rules: PlanRules
) -> list[PlanCheck] {
    focus_ids = {task.task_id for task in tasks if task.group_id == focus_group};
    focus = [p for p in plan.placements if p.task_id in focus_ids];
    return (
        clash_checks(focus, events)
        + late_night_checks(focus, tasks, rules)
        + deadline_checks(plan, focus_ids)
        + same_day_checks(groups, focus_group, rules)
    );
}

def overlaps(placement: Placement, event: CalendarEvent) -> bool {
    return placement.start < event.end and event.start < placement.end;
}

def clash_checks(focus: list[Placement], events: list[CalendarEvent]) -> list[PlanCheck] {
    clashes = [p for p in focus for e in events if overlaps(p, e)];
    if clashes {
        return [PlanCheck(level=CheckLevel.ERROR, message=f"{len(clashes)} blocks clash with fixed events")];
    }
    noun = "event" if len(events) == 1 else "events";
    return [PlanCheck(level=CheckLevel.OK, message=f"No clash with {len(events)} fixed {noun}")];
}

def late_night_checks(
    focus: list[Placement], tasks: list[PlanTask], rules: PlanRules
) -> list[PlanCheck] {
    deep_ids = {task.task_id for task in tasks if task.tier == CognitiveTier.DEEP_WORK};
    deep = [p for p in focus if p.task_id in deep_ids];
    if not deep {
        return [];
    }
    late = [
        p for p in deep
        if p.end > at_local(local_day(p.start, rules.zone), rules.deep_work_cutoff, rules.zone)
    ];
    if late {
        return [PlanCheck(level=CheckLevel.WARN, message="Some Deep Work runs late at night")];
    }
    return [PlanCheck(level=CheckLevel.OK, message="Deep Work kept off late nights")];
}

def deadline_checks(plan: Plan, focus_ids: set[str]) -> list[PlanCheck] {
    missing = [task_id for task_id in plan.unplaced if task_id in focus_ids];
    late = [task_id for task_id in plan.late if task_id in focus_ids];
    checks: list[PlanCheck] = [];
    if missing {
        noun = "subtask doesn't" if len(missing) == 1 else "subtasks don't";
        checks = checks + [PlanCheck(level=CheckLevel.ERROR, message=f"{len(missing)} {noun} fit in the next week")];
    }
    if late {
        noun = "subtask lands" if len(late) == 1 else "subtasks land";
        checks = checks + [PlanCheck(level=CheckLevel.ERROR, message=f"{len(late)} {noun} after the deadline")];
    }
    return checks;
}

def same_day_checks(groups: list[PlanGroup], focus_group: str, rules: PlanRules) -> list[PlanCheck] {
    focus_due: datetime | None = None;
    for g in groups {
        if g.group_id == focus_group {
            focus_due = g.due;
        }
    }
    if focus_due is None {
        return [];
    }
    due_day = local_day(focus_due, rules.zone);
    weekday = focus_due.astimezone(rules.zone).strftime("%a");
    return [
        PlanCheck(level=CheckLevel.WARN, message=f"{g.label} also due {weekday}")
        for g in groups
        if g.group_id != focus_group and g.due is not None and local_day(g.due, rules.zone) == due_day
    ];
}
