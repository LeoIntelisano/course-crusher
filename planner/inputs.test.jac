import from datetime { date, datetime, time, timedelta }
import from zoneinfo { ZoneInfo }
import from scheduling.planner { PlanRules }

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
