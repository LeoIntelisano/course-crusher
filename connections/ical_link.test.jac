"""iCal subscriptions keep their secret URL off the client status."""
import from datetime { date, datetime, timezone }

test "iCal starts disconnected and never returns a URL" {
    link = IcalLink();
    status = ical_status_of(link);
    assert status.state == "disconnected";
    link.feed_url = "https://calendar.google.com/calendar/ical/user/private-secret/basic.ics";
    status = ical_status_of(link);
    assert status.state == "connected";
    assert not hasattr(status, "feed_url");
}

test "iCal entries retain busy and all-day information" {
    events = convert_ical_entries([
        {"title": "Lecture", "start": datetime(2026, 11, 18, 12, tzinfo=timezone.utc), "end": datetime(2026, 11, 18, 13, tzinfo=timezone.utc), "busy": True},
        {"title": "Break", "start_date": date(2026, 11, 19), "end_date": date(2026, 11, 20), "busy": False}
    ]);
    assert len(events) == 2;
    assert events[0].busy and events[0].title == "Lecture";
    assert events[1].start_date == date(2026, 11, 19) and not events[1].busy;
}
