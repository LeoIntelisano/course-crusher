import from datetime { date, datetime, timezone }

glob WINDOW_START: datetime = datetime(2026, 10, 5, 4, 0, tzinfo=timezone.utc);
glob WINDOW_END: datetime = datetime(2026, 10, 12, 4, 0, tzinfo=timezone.utc);

def timed(summary: str, start: str, end: str, extra: dict[str, any] | None = None) -> dict[str, any] {
    return {"summary": summary, "start": {"dateTime": start}, "end": {"dateTime": end}, **(extra or {})};
}

"""Stands in for requests.Response at the HTTP boundary."""
obj FakeResponse {
    has payload: dict[str, any];
    has status_code: int = 200;

    def raise_for_status {
        if self.status_code >= 400 {
            raise RuntimeError(f"HTTP {self.status_code}");
        }
    }

    def json -> dict[str, any] {
        return self.payload;
    }
}

"""Stands in for AuthorizedSession; serves one queued response per GET."""
obj FakeSession {
    has responses: list[FakeResponse];
    has calls: list[dict[str, any]] = [];

    def get(url: str, params: dict[str, any], timeout: int) -> FakeResponse {
        self.calls.append({"url": url, "params": params, "timeout": timeout});
        return self.responses[len(self.calls) - 1];
    }
}

test "timed events keep their name, place and times" {
    lecture = parse_event(timed(
        "EECS 445 Lecture", "2026-10-06T11:00:00-04:00", "2026-10-06T12:20:00-04:00",
        {"location": "Chrysler 220"}
    ));

    assert lecture is not None;
    assert (lecture.title, lecture.location, lecture.busy) == ("EECS 445 Lecture", "Chrysler 220", True);
    assert lecture.start == datetime(2026, 10, 6, 15, 0, tzinfo=timezone.utc);
}

test "show-as-free events stay visible but don't block time" {
    lunch = parse_event(timed("Lunch?", "2026-10-06T12:00:00Z", "2026-10-06T13:00:00Z", {"transparency": "transparent"}));
    assert lunch is not None and not lunch.busy;
}

test "all-day events carry dates and never block time" {
    fall_break = parse_event({"summary": "Fall break", "start": {"date": "2026-10-19"}, "end": {"date": "2026-10-21"}});

    assert fall_break is not None;
    assert (fall_break.start_date, fall_break.end_date, fall_break.busy) == (date(2026, 10, 19), date(2026, 10, 21), False);
    assert fall_break.start is None;
}

test "cancelled, declined and malformed events are dropped" {
    cancelled = timed("Moved", "2026-10-06T12:00:00Z", "2026-10-06T13:00:00Z", {"status": "cancelled"});
    declined = timed("Optional sync", "2026-10-06T12:00:00Z", "2026-10-06T13:00:00Z", {
        "attendees": [{"email": "me@umich.edu", "self": True, "responseStatus": "declined"}]
    });
    backwards = timed("Oops", "2026-10-06T13:00:00Z", "2026-10-06T12:00:00Z");

    assert parse_event(cancelled) is None;
    assert parse_event(declined) is None;
    assert parse_event(backwards) is None;
    assert parse_event({"summary": "No times"}) is None;
}

test "events someone else declined still count" {
    meeting = timed("Group meeting", "2026-10-06T12:00:00Z", "2026-10-06T13:00:00Z", {
        "attendees": [{"email": "friend@umich.edu", "responseStatus": "declined"}, {"self": True, "responseStatus": "accepted"}]
    });
    assert parse_event(meeting) is not None;
}

test "untitled events get a placeholder name" {
    blank = parse_event(timed("   ", "2026-10-06T12:00:00Z", "2026-10-06T13:00:00Z"));
    assert blank is not None and blank.title == UNTITLED;
}

test "unreadable timestamps are reported" {
    with testraises(CalendarError, `match="Unreadable timestamp") {
        parse_event(timed("Bad", "tuesday noon", "2026-10-06T13:00:00Z"));
    }
    with testraises(CalendarError, `match="Unreadable date") {
        parse_event({"summary": "Bad", "start": {"date": "someday"}, "end": {"date": "2026-10-21"}});
    }
}

test "fetch_events follows page tokens and asks for single events" {
    first = FakeResponse(payload={"items": [timed("A", "2026-10-06T12:00:00Z", "2026-10-06T13:00:00Z")], "nextPageToken": "p2"});
    second = FakeResponse(payload={"items": [timed("B", "2026-10-07T12:00:00Z", "2026-10-07T13:00:00Z")]});
    session = FakeSession(responses=[first, second]);

    entries = fetch_events(session, ["umich-classes@group.calendar.google.com"], WINDOW_START, WINDOW_END);

    assert [e.title for e in entries] == ["A", "B"];
    assert session.calls[0]["url"] == "https://www.googleapis.com/calendar/v3/calendars/umich-classes%40group.calendar.google.com/events";
    assert session.calls[0]["params"]["singleEvents"] == "true";
    assert session.calls[0]["params"]["timeMin"] == "2026-10-05T04:00:00+00:00";
    assert "pageToken" not in session.calls[0]["params"];
    assert session.calls[1]["params"]["pageToken"] == "p2";
}

test "fetch_events reads every calendar" {
    session = FakeSession(responses=[
        FakeResponse(payload={"items": [timed("Mine", "2026-10-06T12:00:00Z", "2026-10-06T13:00:00Z")]}),
        FakeResponse(payload={"items": [timed("Classes", "2026-10-06T14:00:00Z", "2026-10-06T15:00:00Z")]})
    ]);

    entries = fetch_events(session, ["primary", "classes"], WINDOW_START, WINDOW_END);

    assert [e.title for e in entries] == ["Mine", "Classes"];
}

test "an unreadable calendar fails the read instead of looking free" {
    session = FakeSession(responses=[FakeResponse(payload={}, status_code=404)]);

    with testraises(CalendarError, `match="could not read missing@group: notFound") {
        fetch_events(session, ["missing@group"], WINDOW_START, WINDOW_END);
    }
}

test "fetch_events validates its arguments" {
    with testraises(ValueError, `match="At least one calendar") {
        fetch_events(FakeSession(responses=[]), [], WINDOW_START, WINDOW_END);
    }
    with testraises(ValueError, `match="window_end must be after window_start") {
        fetch_events(FakeSession(responses=[]), ["primary"], WINDOW_END, WINDOW_START);
    }
}

test "event access depends on the granted scopes" {
    assert has_event_access([READONLY_SCOPE]);
    assert has_event_access(["https://www.googleapis.com/auth/calendar"]);
    assert not has_event_access(["https://www.googleapis.com/auth/calendar.freebusy"]);
    assert not has_event_access([]);
}
