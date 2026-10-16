import from datetime { date, datetime, time, timezone }
import from zoneinfo { ZoneInfo }

glob DETROIT: ZoneInfo = ZoneInfo("America/Detroit");

def at(hour: int, minute: int = 0) -> datetime {
    return datetime(2026, 10, 6, hour, minute, tzinfo=DETROIT);
}

test "parse_clock accepts HH:MM and names the field on failure" {
    assert parse_clock(" 17:30 ", "Start") == time(17, 30);
    with testraises(ValueError, `match="Start: Use 24-hour HH:MM") {
        parse_clock("5pm", "Start");
    }
}

test "clock_text round-trips a time" {
    assert clock_text(time(8, 5)) == "08:05";
}

test "parse_zone accepts IANA names and rejects others" {
    assert str(parse_zone("America/Detroit")) == "America/Detroit";
    with testraises(ValueError, `match="Unknown time zone") {
        parse_zone("Mars/Olympus_Mons");
    }
    with testraises(ValueError, `match="Unknown time zone") {
        parse_zone("../etc/passwd");
    }
}

test "parse_moment reads local input in the student's zone" {
    assert parse_moment("2026-10-07T23:59", DETROIT, "Due") == datetime(2026, 10, 7, 23, 59, tzinfo=DETROIT);
    utc = parse_moment("2026-10-07T12:00:00+00:00", DETROIT, "Due");
    assert utc == datetime(2026, 10, 7, 12, tzinfo=timezone.utc);
    with testraises(ValueError, `match="Due: use a date and time") {
        parse_moment("next friday", DETROIT, "Due");
    }
}

test "parse_clock rejects times with a UTC offset" {
    with testraises(ValueError, `match="Use 24-hour HH:MM") {
        parse_clock("17:00+05:00", "Start");
    }
}

test "parse_due keeps due dates within five years" {
    now = datetime(2026, 10, 6, 12, tzinfo=timezone.utc);
    assert parse_due("2026-10-21T23:59", DETROIT, now) == datetime(2026, 10, 21, 23, 59, tzinfo=DETROIT);
    with testraises(ValueError, `match="within the next five years") {
        parse_due("9999-12-31T23:59+00:00", DETROIT, now);
    }
    with testraises(ValueError, `match="within the next five years") {
        parse_due("1990-01-01T09:00", DETROIT, now);
    }
    with testraises(ValueError, `match="Due date: use a date and time") {
        parse_due("someday", DETROIT, now);
    }
}

test "stored_moment treats empty, unreadable and naive text as unset" {
    assert stored_moment("") is None;
    assert stored_moment("garbage") is None;
    assert stored_moment("2026-10-07T12:00:00") is None;
    assert stored_moment("2026-10-07T12:00:00+00:00") == datetime(2026, 10, 7, 12, tzinfo=timezone.utc);
    assert stored_moment("9999-12-31T23:59:00+00:00") is None;
}

test "clock and range labels match the wireframe" {
    assert clock_label(at(12, 35)) == "12:35 PM";
    assert clock_label(at(0, 5)) == "12:05 AM";
    assert range_label(at(12, 35), at(13, 25)) == "12:35 – 1:25 PM";
    assert range_label(at(11), at(12, 20)) == "11:00 AM – 12:20 PM";
    assert hour_label(at(14)) == "2 PM";
    assert hour_label(at(0)) == "12 AM";
}

test "day, date and due labels" {
    today = date(2026, 10, 6);
    assert day_label(today, today) == "Today";
    assert day_label(date(2026, 10, 7), today) == "Tomorrow";
    assert day_label(date(2026, 10, 8), today) == "Thu";
    assert date_label(date(2026, 9, 28)) == "Mon, Sep 28";
    assert due_label(datetime(2026, 10, 7, 23, 59, tzinfo=DETROIT), today) == "Wed 11:59 PM";
    assert due_label(datetime(2026, 10, 21, 23, 59, tzinfo=DETROIT), today) == "Oct 21 11:59 PM";
}
