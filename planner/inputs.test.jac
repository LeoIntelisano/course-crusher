import from datetime { date, datetime, time, timedelta }
import from zoneinfo { ZoneInfo }
import from scheduling.planner { PlanRules }
import from connectors.google_events { CalendarEntry }
import from courses.matching { course_matcher }

glob DETROIT: ZoneInfo = ZoneInfo("America/Detroit");
glob MONDAY: date = date(2026, 10, 5);

def days(count: int) -> list[date] {
    return [MONDAY + timedelta(days=n) for n in range(count)];
}

test "meetings expand onto their weekdays only" {
    lecture = MeetingSpec(
        title="EECS 445 Lecture", detail="Chrysler 220", weekdays=[0, 2], start=time(11), end=time(12, 20)
    );

    events = expand_meetings([lecture], days(7), PlanRules(zone=DETROIT));

    assert [(e.start.date(), e.title, e.detail) for e in events] == [
        (date(2026, 10, 5), "EECS 445 Lecture", "Chrysler 220"),
        (date(2026, 10, 7), "EECS 445 Lecture", "Chrysler 220")
    ];
    assert events[0].start == datetime(2026, 10, 5, 11, tzinfo=DETROIT);
    assert events[0].end == datetime(2026, 10, 5, 12, 20, tzinfo=DETROIT);
}

test "a meeting that ends before it starts is ignored" {
    broken = MeetingSpec(title="Lab", detail="", weekdays=[0], start=time(16), end=time(14));
    assert expand_meetings([broken], days(1), PlanRules(zone=DETROIT)) == [];
}

test "meetings land at local wall-clock time across a DST change" {
    seminar = MeetingSpec(title="Seminar", detail="", weekdays=[6], start=time(10), end=time(11));
    sundays = [date(2026, 10, 25), date(2026, 11, 1), date(2026, 11, 8)];

    events = expand_meetings([seminar], sundays, PlanRules(zone=DETROIT));

    assert [e.start.hour for e in events] == [10, 10, 10];
    assert events[0].start.utcoffset() != events[-1].start.utcoffset();
}

test "the horizon window spans whole local days" {
    rules = PlanRules(zone=DETROIT, horizon_days=7);

    (start, end) = horizon_window(datetime(2026, 10, 6, 15, 45, tzinfo=DETROIT), rules);

    assert start == datetime(2026, 10, 6, 0, 0, tzinfo=DETROIT);
    assert end == datetime(2026, 10, 13, 0, 0, tzinfo=DETROIT);
}

def timed_entry(title: str, start_hour: int, end_hour: int, busy: bool = True) -> CalendarEntry {
    return CalendarEntry(
        title=title,
        location="Chrysler 220",
        start=datetime(2026, 10, 6, start_hour, tzinfo=DETROIT),
        end=datetime(2026, 10, 6, end_hour, tzinfo=DETROIT),
        busy=busy
    );
}

test "Google entries split into blocking, shown and all-day, matched to courses" {
    matchers = [course_matcher("EECS 445", "Machine Learning", ["ML"]), course_matcher("PHYS 240", "", [])];
    entries = [
        timed_entry("EECS 445 Lecture", 11, 12),
        timed_entry("Maybe: ML study group", 13, 14, busy=False),
        timed_entry("Dentist", 15, 16),
        CalendarEntry(title="PHYS 240 midterm week", start_date=date(2026, 10, 19), end_date=date(2026, 10, 24), busy=False)
    ];

    (blocking, shown, all_day) = google_events(entries, matchers, True);

    assert [(e.title, e.source, e.course_code, e.detail) for e in blocking] == [
        ("EECS 445 Lecture", "google", "EECS 445", "Chrysler 220"), ("Dentist", "google", "", "Chrysler 220")
    ];
    assert [(e.title, e.course_code) for e in shown] == [("Maybe: ML study group", "EECS 445")];
    assert [(e.title, e.course_code) for e in all_day] == [("PHYS 240 midterm week", "PHYS 240")];
}

test "busy-only reads stay anonymous" {
    matchers = [course_matcher("EECS 445", "", [])];

    (blocking, shown, all_day) = google_events([timed_entry("Busy", 11, 12)], matchers, False);

    assert [(e.source, e.course_code) for e in blocking] == [("busy", "")];
    assert shown == [] and all_day == [];
}

test "meetings carry their course code" {
    lab = MeetingSpec(title="PHYS 240 Lab", detail="Randall", weekdays=[1], start=time(14), end=time(16), course_code="PHYS 240");

    events = expand_meetings([lab], days(7), PlanRules(zone=DETROIT));

    assert [(e.source, e.course_code) for e in events] == [("class", "PHYS 240")];
}

test "dates_between covers each local day the window touches" {
    rules = PlanRules(zone=DETROIT);
    start = datetime(2026, 10, 5, 0, 0, tzinfo=DETROIT);

    assert dates_between(start, start + timedelta(days=7), rules) == days(7);
    assert dates_between(start, start + timedelta(hours=1), rules) == [MONDAY];
}
