import from datetime { date, datetime, time, timedelta }
import from zoneinfo { ZoneInfo }
import from breakdown { CognitiveTier }
import from connections.google_link { CalendarStatus }
import from planner.inputs { AllDayEvent, PlanningInputs, TaskInfo }
import from scheduling.planner { CalendarEvent, PlanRules, PlanTask, ProtectedHours }

glob DETROIT: ZoneInfo = ZoneInfo("America/Detroit");
glob MONDAY: date = date(2026, 10, 5);

def at(day_offset: int, hour: int, minute: int = 0) -> datetime {
    return datetime.combine(MONDAY + timedelta(days=day_offset), time(hour, minute), tzinfo=DETROIT);
}

def item(key: str, start: int, end: int) -> CalendarItem {
    return CalendarItem(key=key, kind="event", title=key, detail="", start_minute=start, end_minute=end);
}

def week_inputs(
    events: list[CalendarEvent],
    shown: list[CalendarEvent] | None = None,
    all_day: list[AllDayEvent] | None = None,
    tasks: list[PlanTask] | None = None,
    protected: list[ProtectedHours] | None = None,
    names: bool = True
) -> PlanningInputs {
    task_list = tasks or [];
    return PlanningInputs(
        rules=PlanRules(zone=DETROIT, buffer_minutes=0, horizon_days=7),
        display_name="",
        tasks=task_list,
        info={
            t.task_id: TaskInfo(
                task_id=t.task_id, title=t.title, tier=str(t.tier), minutes=t.minutes,
                course_code="EECS 445", assignment_id="p2", assignment_title="Project 2"
            )
            for t in task_list
        },
        events=events,
        protected=protected or [],
        groups=[],
        calendar=CalendarStatus(state="connected", detail="Connected", calendars=["primary"], names=names),
        course_count=1,
        shown=shown or [],
        all_day=all_day or []
    );
}

def day(view: CalendarView, iso: str) -> CalendarDay {
    return [d for d in view.days if d.iso_date == iso][0];
}

test "items that don't overlap each get a full column" {
    laid = assign_lanes([item("b", 600, 660), item("a", 480, 540)]);
    assert [(i.key, i.lane, i.lanes) for i in laid] == [("a", 0, 1), ("b", 0, 1)];
}

test "overlapping items share the column side by side" {
    laid = assign_lanes([item("lecture", 660, 740), item("oh", 690, 720), item("lunch", 720, 780)]);
    lanes = {i.key: (i.lane, i.lanes) for i in laid};
    assert lanes["lecture"] == (0, 2);
    assert lanes["oh"] == (1, 2);
    assert lanes["lunch"] == (1, 2);
}

test "a chain of overlaps forms one cluster" {
    laid = assign_lanes([item("a", 0, 60), item("b", 30, 90), item("c", 60, 120), item("d", 200, 260)]);
    lanes = {i.key: (i.lane, i.lanes) for i in laid};
    assert lanes["a"] == (0, 2) and lanes["b"] == (1, 2) and lanes["c"] == (0, 2);
    assert lanes["d"] == (0, 1);
}

test "the week runs Monday to Sunday with today marked" {
    view = calendar_view(week_inputs([]), at(1, 12, 30), 0);

    assert [d.weekday for d in view.days] == ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];
    assert [d.is_today for d in view.days] == [False, True, False, False, False, False, False];
    assert view.range_label == "Oct 5 – Oct 11";
    assert view.now_minute == 12 * 60 + 30;
    assert (view.start_minute, view.end_minute) == (8 * 60, 22 * 60);
}

test "other weeks have no now line and offsets are clamped" {
    next_week = calendar_view(week_inputs([]), at(1, 12), 1);
    far = calendar_view(week_inputs([]), at(1, 12), 99);

    assert next_week.range_label == "Oct 12 – Oct 18" and next_week.now_minute == -1;
    assert far.week_offset == 8;
}

test "named Google events keep their course; classes and busy blocks keep their kind" {
    events = [
        CalendarEvent(title="EECS 445 Lecture", start=at(1, 11), end=at(1, 12, 20), detail="Chrysler 220", source="class", course_code="EECS 445"),
        CalendarEvent(title="ML office hours", start=at(1, 14), end=at(1, 15), detail="BBB 3901", source="google", course_code="EECS 445"),
        CalendarEvent(title="Busy", start=at(2, 9), end=at(2, 10), source="busy")
    ];
    shown = [CalendarEvent(title="Maybe lunch", start=at(1, 12, 30), end=at(1, 13, 30), source="google")];

    view = calendar_view(week_inputs(events, shown=shown), at(0, 8), 0);

    tuesday = {i.title: i for i in day(view, "2026-10-06").items};
    assert (tuesday["EECS 445 Lecture"].kind, tuesday["EECS 445 Lecture"].start_minute) == ("class", 660);
    assert (tuesday["ML office hours"].kind, tuesday["ML office hours"].course_code) == ("event", "EECS 445");
    assert tuesday["ML office hours"].detail == "2:00 – 3:00 PM · BBB 3901";
    assert tuesday["Maybe lunch"].kind == "free";
    assert [i.kind for i in day(view, "2026-10-07").items] == ["busy"];
}

test "events spanning midnight appear on both days" {
    overnight = CalendarEvent(title="Hackathon", start=at(4, 20), end=at(5, 2), source="google");

    view = calendar_view(week_inputs([overnight]), at(0, 8), 0);

    friday = day(view, "2026-10-09").items[0];
    saturday = day(view, "2026-10-10").items[0];
    assert (friday.start_minute, friday.end_minute) == (20 * 60, 24 * 60);
    assert (saturday.start_minute, saturday.end_minute) == (0, 2 * 60);
    assert view.start_minute == 0 and view.end_minute == 24 * 60;
}

test "planned blocks and protected hours are drawn" {
    task = PlanTask(task_id="t1", title="Implement the loop", tier=CognitiveTier.DEEP_WORK, minutes=50, group_id="p2");
    dinner = ProtectedHours(label="Dinner & gym", start=time(17), end=time(19));

    view = calendar_view(week_inputs([], tasks=[task], protected=[dinner]), at(1, 9), 0);

    tuesday = day(view, "2026-10-06").items;
    planned = [i for i in tuesday if i.kind == "task"][0];
    assert (planned.title, planned.tier, planned.start_minute, planned.end_minute) == ("Implement the loop", "Deep Work", 540, 590);
    assert planned.course_code == "EECS 445";
    assert len([d for d in view.days if [i for i in d.items if i.kind == "protected"]]) == 7;
    assert [i for i in day(view, "2026-10-05").items if i.kind == "task"] == [];
}

test "all-day events show on each day they cover" {
    fall_break = AllDayEvent(title="Fall break", start_date=date(2026, 10, 8), end_date=date(2026, 10, 10), course_code="");

    view = calendar_view(week_inputs([], all_day=[fall_break]), at(0, 8), 0);

    assert [len(d.all_day) for d in view.days] == [0, 0, 0, 1, 1, 0, 0];
    assert day(view, "2026-10-08").all_day[0].title == "Fall break";
}

test "the view reports whether event names are available" {
    assert calendar_view(week_inputs([], names=True), at(0, 8), 0).names;
    assert not calendar_view(week_inputs([], names=False), at(0, 8), 0).names;
    assert calendar_view(week_inputs([]), at(0, 8), 0).connected;
}
