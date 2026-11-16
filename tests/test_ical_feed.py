"""Run with: python -m unittest discover -s tests -p 'test_ical_feed.py'."""
import unittest
from datetime import datetime, timezone
from unittest.mock import patch

from connectors.ical_feed import IcalFeedError, fetch_ical, parse_ical, validate_ical_url


class Response:
    status_code = 200

    def __init__(self, raw):
        self.raw = raw

    def __enter__(self):
        return self

    def __exit__(self, *args):
        return False

    def iter_content(self, chunk_size):
        yield self.raw


class IcalFeedTests(unittest.TestCase):
    def setUp(self):
        self.url = "https://calendar.google.com/calendar/ical/test%40gmail.com/private-token/basic.ics"
        self.start = datetime(2026, 11, 16, tzinfo=timezone.utc)
        self.end = datetime(2026, 11, 23, tzinfo=timezone.utc)

    def test_accepts_google_private_feed(self):
        self.assertEqual(validate_ical_url(self.url), self.url)

    def test_refuses_other_domains_or_ports(self):
        for url in (
            "http://calendar.google.com/calendar/ical/x/private-x/basic.ics",
            "https://evil.example/calendar/ical/x/private-x/basic.ics",
            "https://calendar.google.com.evil.example/calendar/ical/x/private-x/basic.ics",
            "https://calendar.google.com:444/calendar/ical/x/private-x/basic.ics",
            "https://calendar.google.com@evil.example/calendar/ical/x/private-x/basic.ics",
            "https://calendar.google.com/calendar/ical/x/private-x/basic.ics?redirect=evil",
            "https://127.0.0.1/calendar/ical/x/private-x/basic.ics",
        ):
            with self.subTest(url=url), self.assertRaises(IcalFeedError):
                validate_ical_url(url)

    def test_recurring_events_and_all_day(self):
        raw = ("BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//CourseCrusher test//EN\r\n"
               "BEGIN:VEVENT\r\nUID:meeting-1\r\nDTSTAMP:20261101T000000Z\r\n"
               "DTSTART:20261116T140000Z\r\nDTEND:20261116T150000Z\r\n"
               "RRULE:FREQ=DAILY;COUNT=3\r\nSUMMARY:Lecture\r\nEND:VEVENT\r\n"
               "BEGIN:VEVENT\r\nUID:holiday-1\r\nDTSTAMP:20261101T000000Z\r\n"
               "DTSTART;VALUE=DATE:20261120\r\nDTEND;VALUE=DATE:20261121\r\n"
               "SUMMARY:No class\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n").encode()
        events = parse_ical(raw, self.start, self.end)
        self.assertEqual(len([e for e in events if e["title"] == "Lecture"]), 3)
        self.assertEqual(len([e for e in events if e["title"] == "No class"]), 1)
        self.assertFalse(next(e for e in events if e["title"] == "No class")["busy"])

    @patch("connectors.ical_feed.requests.get")
    def test_fetch_disables_redirects_and_keeps_url_out_of_errors(self, get):
        get.return_value = Response(b"BEGIN:VCALENDAR\r\nVERSION:2.0\r\nEND:VCALENDAR\r\n")
        self.assertEqual(fetch_ical(self.url, self.start, self.end), [])
        self.assertFalse(get.call_args.kwargs["allow_redirects"])
        get.return_value.status_code = 404
        with self.assertRaises(IcalFeedError) as error:
            fetch_ical(self.url, self.start, self.end)
        self.assertNotIn("private-token", str(error.exception))


if __name__ == "__main__":
    unittest.main()
