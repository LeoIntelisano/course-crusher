import from datetime { date, datetime, time }
import from zoneinfo { ZoneInfo }

glob DETROIT: ZoneInfo = ZoneInfo("America/Detroit");
glob TUESDAY: date = date(2026, 10, 6);

def at(hour: int, minute: int = 0) -> datetime {
    return datetime.combine(TUESDAY, time(hour, minute), tzinfo=DETROIT);
}

def busy(start: datetime, end: datetime) -> BusyBlock {
    return BusyBlock(start=start, end=end);
}

def spans(slots: list[TimeSlot]) -> list[tuple[datetime, datetime, int]] {
    return [(s.start_time, s.end_time, s.duration_minutes) for s in slots];
}

test "empty calendar yields the whole window" {
    slots = find_free_slots([], at(8), at(22));
    assert spans(slots) == [(at(8), at(22), 840)];
}

test "finds the gap between a lecture and a lab" {
    lecture = busy(at(11), at(12, 30));
    lab = busy(at(14), at(16));

    slots = find_free_slots([lab, lecture], at(8), at(22));

    assert spans(slots) == [
        (at(8), at(11), 180),
        (at(12, 30), at(14), 90),
        (at(16), at(22), 360)
    ];
}

test "overlapping and adjacent blocks merge into one busy span" {
    lab = busy(at(14), at(16));
    study_group = busy(at(15, 30), at(16, 30));
    office_hours = busy(at(16, 30), at(17));

    slots = find_free_slots([lab, office_hours, study_group], at(12), at(20));

    assert spans(slots) == [(at(12), at(14), 120), (at(17), at(20), 180)];
}

test "a block that contains another does not shorten the busy span" {
    slots = find_free_slots(
        [busy(at(9), at(13)), busy(at(10), at(11))], at(8), at(14)
    );
    assert spans(slots) == [(at(8), at(9), 60), (at(13), at(14), 60)];
}

test "blocks outside the window are ignored and straddling blocks are clipped" {
    before = busy(at(6), at(7));
    straddles_start = busy(at(7, 30), at(9));
    straddles_end = busy(at(21), at(23));

    slots = find_free_slots([before, straddles_start, straddles_end], at(8), at(22));

    assert spans(slots) == [(at(9), at(21), 720)];
}

test "a fully booked window yields no slots" {
    assert find_free_slots([busy(at(7), at(23))], at(8), at(22)) == [];
}

test "gaps shorter than the minimum are dropped" {
    blocks = [busy(at(9), at(10)), busy(at(10, 10), at(11))];

    default_slots = find_free_slots(blocks, at(9), at(11));
    short_slots = find_free_slots(blocks, at(9), at(11), min_duration_minutes=10);

    assert default_slots == [];
    assert spans(short_slots) == [(at(10), at(10, 10), 10)];
}

test "busy blocks in UTC line up with a local window" {
    utc = ZoneInfo("UTC");
    lab_utc = busy(
        datetime(2026, 10, 6, 18, 0, tzinfo=utc), datetime(2026, 10, 6, 20, 0, tzinfo=utc)
    );

    slots = find_free_slots([lab_utc], at(12), at(18));

    assert spans(slots) == [(at(12), at(14), 120), (at(16), at(18), 120)];
}

test "slots are expressed in the window's time zone" {
    utc = ZoneInfo("UTC");
    lab_utc = busy(
        datetime(2026, 10, 6, 18, 0, tzinfo=utc), datetime(2026, 10, 6, 20, 0, tzinfo=utc)
    );

    slots = find_free_slots([lab_utc], at(12), at(18));

    assert [slot_to_dict(s)["end_time"] for s in slots] == [
        "2026-10-06T14:00:00-04:00", "2026-10-06T18:00:00-04:00"
    ];
    assert [slot_to_dict(s)["start_time"] for s in slots] == [
        "2026-10-06T12:00:00-04:00", "2026-10-06T16:00:00-04:00"
    ];
}

test "inputs are not modified" {
    blocks = [busy(at(14), at(16)), busy(at(11), at(12))];
    original = [(b.start, b.end) for b in blocks];

    _ = find_free_slots(blocks, at(8), at(22));

    assert [(b.start, b.end) for b in blocks] == original;
}

test "rejects naive datetimes" {
    naive = datetime(2026, 10, 6, 8, 0);
    with testraises(ValueError, `match="timezone-aware") {
        find_free_slots([], naive, at(22));
    }
    with testraises(ValueError, `match="timezone-aware") {
        find_free_slots([busy(naive, at(9))], at(8), at(22));
    }
}

test "rejects an empty or inverted window" {
    with testraises(ValueError, `match="window_end must be after window_start") {
        find_free_slots([], at(12), at(12));
    }
}

test "rejects a busy block that ends before it starts" {
    with testraises(ValueError, `match="ends before it starts") {
        find_free_slots([busy(at(12), at(11))], at(8), at(22));
    }
}

test "rejects a non-positive minimum duration" {
    with testraises(ValueError, `match="min_duration_minutes") {
        find_free_slots([], at(8), at(22), min_duration_minutes=0);
    }
}

test "time_slot computes whole minutes" {
    slot = time_slot(at(12, 30), datetime.combine(TUESDAY, time(13, 59, 59), tzinfo=DETROIT));
    assert slot.duration_minutes == 89;
}

test "slot_to_dict emits the ISO 8601 contract" {
    slot = time_slot(at(12, 30), at(14));

    assert slot_to_dict(slot) == {
        "start_time": "2026-10-06T12:30:00-04:00",
        "end_time": "2026-10-06T14:00:00-04:00",
        "duration_minutes": 90
    };
}

test "day_window builds local start and end bounds" {
    (start, end) = day_window(TUESDAY, DETROIT, time(8), time(22));
    assert (start, end) == (at(8), at(22));
}

test "day_window rejects an end at or before the start" {
    with testraises(ValueError, `match="day_end must be after day_start") {
        day_window(TUESDAY, DETROIT, time(22), time(8));
    }
}
