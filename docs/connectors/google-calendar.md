# Google Calendar connector

Finds the open windows in a student's day so the scheduler can place work into
them — the "auto-fitted day" on the Today screen, e.g. the 90-minute gap before
PHYS 240 Lab.

| Piece | File |
|---|---|
| `BusyBlock`, `TimeSlot`, gap detection | `scheduling/time_slots.jac` |
| freeBusy request/response, OAuth | `connectors/google_calendar.jac` |
| Sample freeBusy response | `fixtures/calendar/freebusy_sample_day.json` |
| CLI | `jac run main.jac -- free-slots ...` |

## API choice: `freeBusy.query`, not `events.list`

`POST https://www.googleapis.com/calendar/v3/freeBusy` takes a time window and
up to 50 calendar IDs and returns only `{start, end}` busy periods per calendar.

| | `freeBusy.query` | `events.list` |
|---|---|---|
| Narrowest scope | `calendar.freebusy` ("View your availability in your calendars") | `calendar.events.readonly` (full event details) |
| Event titles, locations, attendees | Not returned | Returned |
| "Show as free" events, declined invites | Already excluded | We would have to filter `transparency` and attendee `responseStatus` ourselves |
| Recurring events | Already expanded | Needs `singleEvents=true` |
| Calls per window | One for up to 50 calendars | One per calendar, paginated |

Gap-finding needs only *when* the student is busy, not *what* they are doing, so
freeBusy wins on both privacy and correctness. The cost is that the Today screen
cannot label a gap "before PHYS 240 Lab" from this data alone. If we want that
label, add an `events.list` call for the single next event behind its own scope
request rather than widening this connector.

Behaviour worth knowing:

- Busy periods are returned in UTC (or `timeZone` if set). `start` is inclusive,
  `end` exclusive.
- Each calendar can carry an `errors` list (`notFound`, `internalError`, …)
  instead of busy data. The connector treats any per-calendar error as a failed
  read: dropping the calendar silently would show its classes as free time.
- Busy periods from different calendars overlap freely; merging happens in
  `find_free_slots`.

## Authentication strategy

**CLI / local development: OAuth 2.0 installed-app (loopback) flow**, via
`google-auth-oauthlib`'s `InstalledAppFlow.run_local_server`.

1. In Google Cloud Console, enable the Google Calendar API, configure the OAuth
   consent screen, add yourself as a test user, and create an OAuth client of type
   **Desktop app**. Download its JSON.
2. Keep that JSON **outside the repo** (`client_secret*.json` is gitignored as a
   backstop) and point the connector at it:

   ```bash
   export GOOGLE_CLIENT_SECRETS_FILE="$HOME/.config/course-crusher/client_secret.json"
   ```

3. Run `jac run main.jac -- free-slots --google`. The first run opens a browser for
   consent and caches the token at `~/.config/course-crusher/google-token.json`
   (override with `GOOGLE_TOKEN_FILE`), created with mode `0600`. Later runs refresh
   it silently; if Google rejects the refresh, consent runs again.

The connector fails fast with `CalendarAuthError` before any network call if
`GOOGLE_CLIENT_SECRETS_FILE` is unset or points at a missing file.

While an external-user consent screen is in **Testing** status, Google expires
refresh tokens after 7 days, so expect to re-consent weekly until the app is published.

**Tests and demos: no credentials at all.** Instead of mock credentials, the HTTP
boundary is faked. `fetch_busy_blocks` takes any object with a `requests`-style
`post`, so tests pass a fake session. `--fixture` reads a saved freeBusy response
through the same parser the live path uses. Mock credentials would still need a
fake token endpoint and would test Google's library rather than our code.

**Later, the web app:** when CourseCrusher runs as a Jac server, switch to the
web-server OAuth flow with the token stored per user server-side. Only
`load_credentials` changes; `fetch_busy_blocks(session, …)` stays the same.

## `TimeSlot` contract

```jac
obj TimeSlot {
    has start_time: datetime;      # timezone-aware, in the caller's zone
    has end_time: datetime;
    has duration_minutes: int;     # whole minutes, rounded down
}
```

Serialized by `slot_to_dict` / the CLI as ISO 8601 with a UTC offset:

```json
{
  "start_time": "2026-10-06T12:30:00-04:00",
  "end_time": "2026-10-06T14:00:00-04:00",
  "duration_minutes": 90
}
```

`find_free_slots(busy, window_start, window_end, min_duration_minutes=15)`:

- requires timezone-aware datetimes everywhere (naive values raise `ValueError`);
- clips busy blocks to the window, then sorts and merges blocks that overlap or touch;
- returns slots in the window's time zone, in chronological order;
- drops gaps shorter than `min_duration_minutes`, which treats a 10-minute walk
  between buildings as busy rather than as a work slot.

## CLI

```bash
# Offline, against the sample day (no credentials needed)
jac run main.jac -- free-slots --fixture fixtures/calendar/freebusy_sample_day.json \
    --date 2026-10-06 --tz America/Detroit

# Live
jac run main.jac -- free-slots --google --calendar primary \
    --calendar umich-classes@group.calendar.google.com --tz America/Detroit
```

`--day-start` / `--day-end` (default `08:00`–`22:00`) bound the day and
`--min-minutes` sets the shortest useful slot. Output is a JSON array of
`TimeSlot`s on stdout. Errors go to stderr with exit code 1.

## Not yet handled

- **Protected hours** (dinner, gym) from Settings: pass them to
  `find_free_slots` as extra `BusyBlock`s once that setting exists.
- **Travel buffers** around classes in different buildings.
- **Multi-day windows**: call `day_window` per day; one window spanning the
  night would report sleep as free time.
