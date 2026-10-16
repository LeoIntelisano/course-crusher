import from datetime { date, datetime, time, timedelta }
import from zoneinfo { ZoneInfo }
import from breakdown { CognitiveTier }
import from connections.google_link { CalendarStatus }
import from planner.inputs { PlanningInputs, TaskInfo }
import from scheduling.planner { CalendarEvent, PlanGroup, PlanRules, PlanTask }

glob DETROIT: ZoneInfo = ZoneInfo("America/Detroit");
glob MONDAY: date = date(2026, 9, 28);

def at(hour: int, minute: int = 0, day_offset: int = 0) -> datetime {
    return datetime.combine(MONDAY + timedelta(days=day_offset), time(hour, minute), tzinfo=DETROIT);
}

def empty_inputs(events: list[CalendarEvent], groups: list[PlanGroup]) -> PlanningInputs {
    return PlanningInputs(
        rules=PlanRules(zone=DETROIT, buffer_minutes=0, horizon_days=3),
        display_name="",
        tasks=[],
        info={},
        events=events,
        protected=[],
        groups=groups,
        calendar=CalendarStatus(state="disconnected", detail="", calendars=[]),
        course_count=0
    );
}

def proposed(steps: list[tuple[str, CognitiveTier, int]], due: datetime | None) -> list[PlanTask] {
    return [
        PlanTask(
            task_id=preview_id(n), title=title, tier=tier, minutes=minutes,
            group_id=PREVIEW_GROUP, order=n, due=due
        )
        for (n, (title, tier, minutes)) in enumerate(steps, start=1)
    ];
}

"""Monday is full until 12:35 and from 2:00; Tuesday and Wednesday are open."""
def busy_monday -> list[CalendarEvent] {
    return [
        CalendarEvent(title="Morning", start=at(8), end=at(12, 35)),
        CalendarEvent(title="PHYS 240 Lab", start=at(14), end=at(22))
    ];
}

test "subtasks land in order and each says when" {
    steps = proposed([
        ("Set up train.py skeleton", CognitiveTier.DEEP_WORK, 35),
        ("Implement gradient descent loop", CognitiveTier.DEEP_WORK, 50),
        ("Run learning-rate ablation", CognitiveTier.SHALLOW_WORK, 25)
    ], at(23, 59, 2));

    preview = fit_view(empty_inputs(busy_monday(), []), "Project 2", at(23, 59, 2), steps, at(12));

    assert [(b.position, b.placed, b.when_label) for b in preview.blocks] == [
        (1, True, "Today 12:35 PM"), (2, True, "Today 1:10 PM"), (3, True, "Tomorrow 8:00 AM")
    ];
}

test "where-it-fits rows summarize each day like the wireframe" {
    steps = proposed([
        ("Skeleton", CognitiveTier.DEEP_WORK, 35),
        ("Loop", CognitiveTier.DEEP_WORK, 50),
        ("Ablation", CognitiveTier.SHALLOW_WORK, 25)
    ], at(23, 59, 2));

    preview = fit_view(empty_inputs(busy_monday(), []), "Project 2", at(23, 59, 2), steps, at(12));

    assert [(d.day_label, d.title, d.detail, d.tier) for d in preview.days] == [
        ("Mon", "2 Deep Work blocks", "12:35 PM, 1:10 PM · 1h 25m", "Deep Work"),
        ("Tue", "Ablation", "8:00 AM · 25m", "Shallow Work")
    ];
    assert preview.range_label == "Mon – Tue";
}

test "same-tier blocks on one day are counted" {
    steps = proposed([("A", CognitiveTier.DEEP_WORK, 30), ("B", CognitiveTier.DEEP_WORK, 30)], None);

    preview = fit_view(empty_inputs([], []), "Essay", None, steps, at(9));

    assert [(d.title, d.detail) for d in preview.days] == [("2 Deep Work blocks", "9:00 AM, 9:30 AM · 1h")];
}

test "the buffer is the time between the last block and the deadline" {
    steps = proposed([("Submit", CognitiveTier.LOW_ENERGY, 30)], at(20));

    preview = fit_view(empty_inputs([], []), "Quiz", at(20), steps, at(16));

    assert preview.buffer_label == "3h 30m of buffer";
}

test "a long buffer reads in days" {
    steps = proposed([("Submit", CognitiveTier.LOW_ENERGY, 30)], at(20, 0, 2));

    preview = fit_view(empty_inputs([], []), "Quiz", at(20, 0, 2), steps, at(16));

    assert preview.buffer_label == "2d 3h of buffer";
}

test "no buffer is shown without a deadline or when a block is missing" {
    open_ended = fit_view(empty_inputs([], []), "Essay", None, proposed([("A", CognitiveTier.LOW_ENERGY, 30)], None), at(9));
    too_big = fit_view(empty_inputs([], []), "Essay", at(20, 0, 2), proposed([("A", CognitiveTier.LOW_ENERGY, 900)], at(20, 0, 2)), at(9));

    assert open_ended.buffer_label == "";
    assert too_big.buffer_label == "";
    assert [(b.placed, b.when_label) for b in too_big.blocks] == [(False, "No slot this week")];
}

test "checks cover clashes, late nights and other deadlines that day" {
    groups = [PlanGroup(group_id="quiz", label="EECS 376 quiz", due=at(23, 0, 2))];
    steps = proposed([("Draft report", CognitiveTier.DEEP_WORK, 60)], at(23, 59, 2));

    preview = fit_view(empty_inputs(busy_monday(), groups), "Project 2", at(23, 59, 2), steps, at(12));

    assert [(c.level, c.message) for c in preview.checks] == [
        ("ok", "No clash with 2 fixed events"),
        ("ok", "Deep Work kept off late nights"),
        ("warn", "EECS 376 quiz also due Wed")
    ];
}

test "proposed work is planned around what is already in the plan" {
    existing = PlanTask(task_id="t1", title="Existing", tier=CognitiveTier.SHALLOW_WORK, minutes=60, group_id="g", due=at(10, 0, 0));
    inputs = empty_inputs([], []);
    crowded = PlanningInputs(
        rules=inputs.rules, display_name="", tasks=[existing],
        info={"t1": TaskInfo(task_id="t1", title="Existing", tier="Shallow Work", minutes=60, course_code="X", assignment_id="g", assignment_title="G")},
        events=[], protected=[], groups=[], calendar=inputs.calendar, course_count=1
    );

    preview = fit_view(crowded, "New", None, proposed([("New step", CognitiveTier.SHALLOW_WORK, 30)], None), at(9));

    assert preview.blocks[0].when_label == "Today 10:00 AM";
}
