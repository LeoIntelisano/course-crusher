import from datetime { date, datetime, time, timedelta }
import from zoneinfo { ZoneInfo }
import from breakdown { CognitiveTier }

glob DETROIT: ZoneInfo = ZoneInfo("America/Detroit");
glob TUESDAY: date = date(2026, 10, 6);

def at(hour: int, minute: int = 0, day_offset: int = 0) -> datetime {
    return datetime.combine(TUESDAY + timedelta(days=day_offset), time(hour, minute), tzinfo=DETROIT);
}

def rules(energy: Energy | None = None, horizon_days: int = 3, buffer_minutes: int = 0) -> PlanRules {
    return PlanRules(
        zone=DETROIT,
        energy=energy or Energy.HIGH,
        horizon_days=horizon_days,
        buffer_minutes=buffer_minutes
    );
}

def task(
    task_id: str,
    minutes: int,
    tier: CognitiveTier = CognitiveTier.SHALLOW_WORK,
    group_id: str = "",
    order: int = 1,
    due: datetime | None = None,
    not_before: datetime | None = None
) -> PlanTask {
    return PlanTask(
        task_id=task_id, title=f"Task {task_id}", tier=tier, minutes=minutes,
        group_id=group_id, order=order, due=due, not_before=not_before
    );
}

def event(title: str, start: datetime, end: datetime) -> CalendarEvent {
    return CalendarEvent(title=title, start=start, end=end);
}

def spans(plan: Plan) -> dict[str, tuple[datetime, datetime]] {
    return {p.task_id: (p.start, p.end) for p in plan.placements};
}

"""The wireframe's Tuesday: lecture 11:00-12:20, lab 14:00-16:00."""
def tuesday_classes -> list[CalendarEvent] {
    return [
        event("EECS 445 Lecture", at(11), at(12, 20)),
        event("PHYS 240 Lab", at(14), at(16))
    ];
}

test "round_up snaps to the next 5-minute mark" {
    assert round_up(at(12, 20)) == at(12, 20);
    assert round_up(at(12, 21)) == at(12, 25);
    assert round_up(at(12, 20).replace(second=1)) == at(12, 25);
    assert round_up(at(12, 58)) == at(13);
}

test "free gaps skip classes, buffers and protected hours" {
    dinner = ProtectedHours(label="Dinner & gym", start=time(17), end=time(19));

    gaps = free_gaps(tuesday_classes(), [dinner], rules(buffer_minutes=15, horizon_days=1), at(8));

    assert [(g.start_time, g.end_time) for g in gaps] == [
        (at(8), at(10, 45)),
        (at(12, 35), at(13, 45)),
        (at(16, 15), at(17)),
        (at(19), at(22))
    ];
}

test "free gaps start at now, rounded up" {
    gaps = free_gaps([], [], rules(horizon_days=1), at(9, 2));
    assert gaps[0].start_time == at(9, 5);
}

test "a day that is already over contributes no gaps" {
    gaps = free_gaps([], [], rules(horizon_days=2), at(23));
    assert [g.start_time for g in gaps] == [at(8, 0, 1)];
}

test "the wireframe day fits Deep Work into the gap after lecture" {
    deep = task("gd", 50, CognitiveTier.DEEP_WORK, due=at(23, 59, 1));

    plan = plan_tasks([deep], tuesday_classes(), [], rules(buffer_minutes=15), at(12, 30));

    assert spans(plan)["gd"] == (at(12, 35), at(13, 25));
    assert plan.unplaced == [] and plan.late == [];
}

test "earliest deadline is placed first" {
    later = task("later", 60, due=at(20, 0, 2));
    sooner = task("sooner", 60, due=at(20, 0, 1));

    plan = plan_tasks([later, sooner], [], [], rules(), at(8));

    assert spans(plan)["sooner"][0] == at(8);
    assert spans(plan)["later"][0] == at(9);
}

test "tasks without a deadline go after dated ones" {
    plan = plan_tasks(
        [task("whenever", 30), task("dated", 30, due=at(22, 0, 2))], [], [], rules(), at(8)
    );
    assert spans(plan)["dated"][0] < spans(plan)["whenever"][0];
}

test "an assignment's steps keep their breakdown order" {
    steps = [
        task("s3", 30, group_id="p2", order=3, due=at(23, 0, 1)),
        task("s1", 30, group_id="p2", order=1, due=at(23, 0, 1)),
        task("s2", 30, group_id="p2", order=2, due=at(23, 0, 1))
    ];

    plan = plan_tasks(steps, [], [], rules(), at(8));

    assert [p.task_id for p in plan.placements] == ["s1", "s2", "s3"];
    assert spans(plan)["s2"][0] == spans(plan)["s1"][1];
}

test "a later step never jumps ahead into an earlier gap" {
    long_first = task("s1", 90, group_id="lab", order=1, due=at(23, 0, 1));
    short_second = task("s2", 20, group_id="lab", order=2, due=at(23, 0, 1));
    short_gap = [event("Lecture", at(8, 30), at(12))];

    plan = plan_tasks([long_first, short_second], short_gap, [], rules(), at(8));

    assert spans(plan)["s1"] == (at(12), at(13, 30));
    assert spans(plan)["s2"][0] >= at(13, 30);
}

test "tasks are never split across gaps" {
    plan = plan_tasks(
        [task("big", 60)], [event("Class", at(8, 45), at(9, 15))], [], rules(horizon_days=1), at(8)
    );
    assert spans(plan)["big"] == (at(9, 15), at(10, 15));
}

test "Deep Work ends by the late-night cutoff" {
    evening_only = [event("Busy", at(8), at(20, 30))];

    plan = plan_tasks(
        [task("deep", 45, CognitiveTier.DEEP_WORK), task("light", 45, CognitiveTier.LOW_ENERGY)],
        evening_only, [], rules(horizon_days=2), at(8)
    );

    assert spans(plan)["light"] == (at(20, 30), at(21, 15));
    assert spans(plan)["deep"][0] == at(8, 0, 1);
}

test "low energy pushes today's Deep Work to tomorrow" {
    deep = task("deep", 50, CognitiveTier.DEEP_WORK, due=at(23, 0, 2));
    shallow = task("shallow", 20, due=at(23, 0, 2));

    plan = plan_tasks([deep, shallow], [], [], rules(energy=Energy.LOW), at(9));

    assert spans(plan)["deep"][0] == at(8, 0, 1);
    assert spans(plan)["shallow"][0] == at(9);
}

test "low energy still places Deep Work that is due today" {
    deep = task("deep", 50, CognitiveTier.DEEP_WORK, due=at(18));

    plan = plan_tasks([deep], [], [], rules(energy=Energy.LOW), at(9));

    assert spans(plan)["deep"][0] == at(9);
}

test "low energy keeps overdue Deep Work on today" {
    overdue = task("late", 50, CognitiveTier.DEEP_WORK, due=at(18, 0, -1));

    plan = plan_tasks([overdue], [], [], rules(energy=Energy.LOW), at(9));

    assert spans(plan)["late"][0] == at(9);
    assert plan.late == ["late"];
}

test "not_before reschedules a task later" {
    plan = plan_tasks([task("t", 30, not_before=at(15))], [], [], rules(), at(9));
    assert spans(plan)["t"][0] == at(15);
}

test "a task with no room in the horizon is unplaced and blocks its later steps" {
    booked = [event("All day", at(8, 0, d), at(22, 0, d)) for d in range(3)];
    steps = [task("a", 30, group_id="g", order=1), task("b", 30, group_id="g", order=2)];

    plan = plan_tasks(steps, booked, [], rules(), at(8));

    assert plan.placements == [];
    assert plan.unplaced == ["a", "b"];
}

test "a step placed after its due time is reported late" {
    plan = plan_tasks(
        [task("t", 60, due=at(10, 30))], [event("Class", at(8), at(10))], [], rules(), at(8)
    );
    assert spans(plan)["t"] == (at(10), at(11));
    assert plan.late == ["t"];
}

test "placed time is removed from the remaining free gaps" {
    plan = plan_tasks([task("t", 60)], [], [], rules(horizon_days=1), at(8));
    assert [(g.start_time, g.end_time) for g in plan.free] == [(at(9), at(22))];
}

test "planning does not modify its inputs" {
    tasks = [task("t2", 30, order=2, group_id="g"), task("t1", 30, order=1, group_id="g")];
    events = tuesday_classes();
    before = ([(t.task_id, t.order) for t in tasks], [(e.start, e.end) for e in events]);

    _ = plan_tasks(tasks, events, [], rules(), at(8));

    assert ([(t.task_id, t.order) for t in tasks], [(e.start, e.end) for e in events]) == before;
}

test "consume keeps the remnants on both sides" {
    gaps = free_gaps([], [], rules(horizon_days=1), at(8));

    left = consume(gaps, 0, at(10), at(11));

    assert [(g.start_time, g.end_time) for g in left] == [(at(8), at(10)), (at(11), at(22))];
}

test "next_placement skips blocks that already ended" {
    plan = plan_tasks([task("a", 30), task("b", 30)], [], [], rules(), at(8));

    first = next_placement(plan, at(8, 10));
    second = next_placement(plan, at(8, 30));

    assert first is not None and first.task_id == "a";
    assert second is not None and second.task_id == "b";
    assert next_placement(plan, at(23)) is None;
}

test "surrounding_gap measures the gap before placement" {
    events = tuesday_classes();
    plan = plan_tasks([task("t", 50)], events, [], rules(buffer_minutes=10), at(12, 30));

    gap = surrounding_gap(plan.placements[0], events, [], rules(buffer_minutes=10), at(12, 30));

    assert gap is not None;
    assert (gap.start_time, gap.end_time) == (at(12, 30), at(13, 50));
    following = next_event_after(events, gap.end_time);
    assert following is not None and following.title == "PHYS 240 Lab";
}

test "tier_minutes totals placements inside the window" {
    tasks = [
        task("d", 50, CognitiveTier.DEEP_WORK),
        task("s", 20),
        task("l", 15, CognitiveTier.LOW_ENERGY)
    ];
    plan = plan_tasks(tasks, [], [], rules(), at(8));

    totals = tier_minutes(plan, tasks, at(0), at(0, 0, 1));

    assert totals == {"Deep Work": 50, "Shallow Work": 20, "Low Energy": 15};
    assert tier_minutes(plan, tasks, at(0, 0, 1), at(0, 0, 2))["Deep Work"] == 0;
}

test "groups_at_risk lists assignments with late or missing steps" {
    tasks = [task("ok", 30, group_id="fine", due=at(20)), task("late", 60, group_id="tight", due=at(8, 30))];
    plan = plan_tasks(tasks, [], [], rules(), at(8));

    assert groups_at_risk(plan, tasks) == ["tight"];
}

test "plan checks pass for a clean fit and name same-day deadlines" {
    tasks = [
        task("a", 50, CognitiveTier.DEEP_WORK, group_id="p2", due=at(23, 59, 1)),
        task("b", 30, CognitiveTier.LOW_ENERGY, group_id="p2", order=2, due=at(23, 59, 1))
    ];
    events = tuesday_classes();
    groups = [
        PlanGroup(group_id="p2", label="Project 2", due=at(23, 59, 1)),
        PlanGroup(group_id="quiz", label="EECS 376 quiz", due=at(10, 0, 1)),
        PlanGroup(group_id="other", label="Essay", due=at(10, 0, 2))
    ];
    plan = plan_tasks(tasks, events, [], rules(), at(8));

    checks = plan_checks(plan, tasks, events, groups, "p2", rules());

    assert [(c.level, c.message) for c in checks] == [
        (CheckLevel.OK, "No clash with 2 fixed events"),
        (CheckLevel.OK, "Deep Work kept off late nights"),
        (CheckLevel.WARN, "EECS 376 quiz also due Wed")
    ];
}

test "plan checks flag steps that miss the deadline" {
    tasks = [
        task("a", 60, group_id="g", due=at(8, 30)),
        task("b", 30, group_id="g", order=2, due=at(8, 30))
    ];
    booked = [event("All day", at(8, 0, d), at(22, 0, d)) for d in range(1, 3)];
    plan = plan_tasks(tasks, booked, [], rules(), at(8));

    messages = [c.message for c in plan_checks(plan, tasks, booked, [], "g", rules())];

    assert "2 subtasks land after the deadline" in messages;
}

test "plan checks count unplaced steps" {
    booked = [event("All day", at(8, 0, d), at(22, 0, d)) for d in range(3)];
    tasks = [task("a", 30, group_id="g")];
    plan = plan_tasks(tasks, booked, [], rules(), at(8));

    checks = plan_checks(plan, tasks, booked, [], "g", rules());

    assert (CheckLevel.ERROR, "1 subtask doesn't fit in the next week") in [(c.level, c.message) for c in checks];
}

test "invalid rules and tasks are rejected" {
    with testraises(ValueError, `match="end after it starts") {
        free_gaps([], [], PlanRules(zone=DETROIT, day_start=time(22), day_end=time(8)), at(8));
    }
    with testraises(ValueError, `match="cannot be negative") {
        free_gaps([], [], PlanRules(zone=DETROIT, buffer_minutes=-5), at(8));
    }
    with testraises(ValueError, `match="days ahead") {
        free_gaps([], [], PlanRules(zone=DETROIT, horizon_days=0), at(8));
    }
    with testraises(ValueError, `match="at least 1 minute") {
        free_gaps([], [], PlanRules(zone=DETROIT, min_slot_minutes=0), at(8));
    }
    with testraises(ValueError, `match="positive duration") {
        plan_tasks([task("zero", 0)], [], [], rules(), at(8));
    }
}
