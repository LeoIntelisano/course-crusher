import from datetime { date, datetime, time, timedelta }
import from zoneinfo { ZoneInfo }
import from breakdown { CognitiveTier }
import from connections.google_link { CalendarStatus }
import from planner.inputs { PlanningInputs, TaskInfo }
import from scheduling.planner {
    CalendarEvent,
    Energy,
    PlanGroup,
    PlanRules,
    PlanTask,
    ProtectedHours
}

glob DETROIT: ZoneInfo = ZoneInfo("America/Detroit");
glob TUESDAY: date = date(2026, 10, 6);

def at(hour: int, minute: int = 0, day_offset: int = 0) -> datetime {
    return datetime.combine(TUESDAY + timedelta(days=day_offset), time(hour, minute), tzinfo=DETROIT);
}

obj Step {
    has task_id: str;
    has title: str;
    has tier: CognitiveTier;
    has minutes: int;
    has group_id: str;
    has order: int;
}

def project2_steps -> list[Step] {
    return [
        Step(task_id="gd", title="Implement gradient descent loop", tier=CognitiveTier.DEEP_WORK, minutes=50, group_id="p2", order=1),
        Step(task_id="ab", title="Run learning-rate ablation", tier=CognitiveTier.SHALLOW_WORK, minutes=25, group_id="p2", order=2),
        Step(task_id="sub", title="Proofread and submit to Canvas", tier=CognitiveTier.LOW_ENERGY, minutes=30, group_id="p2", order=3),
        Step(task_id="ch7", title="Read Ch. 7 — Neural networks", tier=CognitiveTier.LOW_ENERGY, minutes=25, group_id="read", order=1)
    ];
}

def due_of(group_id: str) -> datetime {
    return at(23, 59, 1) if group_id == "p2" else at(23, 59, 2);
}

def course_of(_group_id: str) -> str {
    return "EECS 445";
}

"""The wireframe's Tuesday: lecture, lab, dinner, and Project 2 due Wednesday night."""
def wireframe_inputs(steps: list[Step], buffer_minutes: int = 0, energy: Energy | None = None) -> PlanningInputs {
    rules = PlanRules(
        zone=DETROIT, buffer_minutes=buffer_minutes, horizon_days=3, energy=energy or Energy.HIGH
    );
    tasks = [
        PlanTask(
            task_id=s.task_id, title=s.title, tier=s.tier, minutes=s.minutes,
            group_id=s.group_id, order=s.order, due=due_of(s.group_id)
        )
        for s in steps
    ];
    info = {
        s.task_id: TaskInfo(
            task_id=s.task_id, title=s.title, tier=str(s.tier), minutes=s.minutes,
            course_code=course_of(s.group_id), assignment_id=s.group_id,
            assignment_title="Project 2" if s.group_id == "p2" else "Reading", due=due_of(s.group_id)
        )
        for s in steps
    };
    return PlanningInputs(
        rules=rules,
        display_name="Varshini Anbu",
        tasks=tasks,
        info=info,
        events=[
            CalendarEvent(title="EECS 445 Lecture", start=at(11), end=at(12, 20), detail="Chrysler 220"),
            CalendarEvent(title="PHYS 240 Lab", start=at(14), end=at(16), detail="Randall")
        ],
        protected=[ProtectedHours(label="dinner & gym", start=time(17), end=time(19))],
        groups=[
            PlanGroup(group_id="p2", label="EECS 445 Project 2", due=due_of("p2")),
            PlanGroup(group_id="read", label="EECS 445 Reading", due=due_of("read"))
        ],
        calendar=CalendarStatus(state="disconnected", detail="Not connected", calendars=["primary"]),
        course_count=1
    );
}

test "up next is the Deep Work block in the gap before the lab" {
    view = today_view(wireframe_inputs(project2_steps()), at(12, 30));

    assert view.up_next is not None;
    item = view.up_next.item;
    assert (item.task_id, item.range_label, item.day_label) == ("gd", "12:30 – 1:20 PM", "Today");
    assert item.due_label == "Wed 11:59 PM" and item.days_left == 1;
}

test "why now names the gap, the energy and the deadline" {
    view = today_view(wireframe_inputs(project2_steps()), at(12, 30));

    assert view.up_next is not None;
    assert view.up_next.why == (
        "you have a 90-minute gap before PHYS 240 Lab and you marked your energy High. "
        + "This is the last Deep Work block before the deadline; the remaining steps are lighter."
    );
}

test "why now uses an before 80 and counts the travel buffer" {
    view = today_view(wireframe_inputs(project2_steps(), buffer_minutes=10), at(12, 30));

    assert view.up_next is not None;
    assert view.up_next.why.startswith("you have an 80-minute gap before PHYS 240 Lab");
}

test "the queue holds the rest of today's blocks in order" {
    view = today_view(wireframe_inputs(project2_steps()), at(12, 30));

    assert [(q.task_id, q.start_label) for q in view.queue] == [
        ("ab", "1:20 PM"), ("sub", "4:00 PM"), ("ch7", "4:30 PM")
    ];
}

test "the timeline interleaves classes, plan blocks and protected time" {
    view = today_view(wireframe_inputs(project2_steps()), at(12, 30));

    assert [(b.kind, b.hour_label) for b in view.timeline] == [
        ("event", "11 AM"), ("task", "12 PM"), ("task", "1 PM"), ("event", "2 PM"),
        ("task", "4 PM"), ("task", "4 PM"), ("protected", "5 PM")
    ];
    lecture = view.timeline[0];
    assert (lecture.title, lecture.detail) == ("EECS 445 Lecture", "11:00 AM – 12:20 PM · Chrysler 220");
    assert view.timeline[1].title == "Deep Work · Implement gradient descent loop";
    assert view.timeline[1].tier == "Deep Work";
    assert view.timeline[-1].title == "Protected — dinner & gym";
}

test "free status reports free until the lab, busy during it, and done at night" {
    inputs = wireframe_inputs(project2_steps());

    free = today_view(inputs, at(12, 30));
    busy = today_view(inputs, at(15));
    done = today_view(inputs, at(22, 30));

    assert (free.free_state, free.free_until_label, free.free_minutes) == ("free", "2:00 PM", 90);
    assert (busy.free_state, busy.free_until_label) == ("busy", "4:00 PM");
    assert done.free_state == "done";
}

test "week load totals this week's booked minutes by tier" {
    view = today_view(wireframe_inputs(project2_steps()), at(12, 30));

    assert view.week.range_label == "Oct 5 – Oct 11";
    assert (view.week.deep_minutes, view.week.shallow_minutes, view.week.low_minutes) == (50, 25, 55);
    assert view.week.at_risk == 0;
}

test "the header fields come from the profile and the plan" {
    view = today_view(wireframe_inputs(project2_steps()), at(12, 30));

    assert (view.date_label, view.display_name, view.initials, view.energy) == ("Tue, Oct 6", "Varshini Anbu", "VA", "High");
    assert (view.open_tasks, view.course_count) == (4, 1);
    assert view.calendar.state == "disconnected";
}

test "with nothing left today, up next is tomorrow's first block" {
    view = today_view(wireframe_inputs(project2_steps()[:1]), at(21, 30));

    assert view.up_next is not None;
    assert view.up_next.item.day_label == "Tomorrow";
    assert view.up_next.why.startswith("nothing else fits today, so this is first up tomorrow at 8:00 AM.");
    assert view.queue == [];
}

test "an empty plan has no up next" {
    view = today_view(wireframe_inputs([]), at(12, 30));

    assert view.up_next is None and view.queue == [] and view.unplaced == [];
    assert [b.kind for b in view.timeline] == ["event", "event", "protected"];
}

test "low energy moves Deep Work off today" {
    view = today_view(wireframe_inputs(project2_steps(), energy=Energy.LOW), at(12, 30));

    assert view.energy == "Low";
    assert view.up_next is not None;
    assert view.up_next.item.task_id != "gd";
}

test "with low energy and only Deep Work left, why now says it waits" {
    view = today_view(wireframe_inputs(project2_steps()[:1], energy=Energy.LOW), at(12, 30));

    assert view.up_next is not None;
    assert view.up_next.why.startswith("your energy is Low, so Deep Work waits until tomorrow at 8:00 AM.");
}

test "work that cannot fit before the deadline is listed and counted at risk" {
    giant = [Step(task_id="big", title="Write everything", tier=CognitiveTier.SHALLOW_WORK, minutes=600, group_id="p2", order=1)];

    view = today_view(wireframe_inputs(giant), at(12, 30));

    assert [u.task_id for u in view.unplaced] == ["big"];
    assert view.week.at_risk == 1;
}

test "the week view groups blocks and classes by day" {
    week = week_view(wireframe_inputs(project2_steps()), at(12, 30));

    assert [d.day_label for d in week.days] == ["Today", "Tomorrow", "Thu"];
    today = week.days[0];
    assert [i.task_id for i in today.items] == ["gd", "ab", "sub", "ch7"];
    assert [e.title for e in today.events] == ["EECS 445 Lecture", "PHYS 240 Lab"];
    assert today.total_minutes == 130;
    assert week.days[1].items == [] and week.unplaced == [] and week.at_risk == 0;
}

test "gap_phrase picks the article and the unit" {
    assert gap_phrase(90) == "a 90-minute gap";
    assert gap_phrase(80) == "an 80-minute gap";
    assert gap_phrase(11) == "an 11-minute gap";
    assert gap_phrase(150) == "a 2h 30m gap";
    assert gap_phrase(480) == "an 8h gap";
}
