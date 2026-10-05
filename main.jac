"""course-crusher - a command-line Jac app.

Subcommands are declared with `argparse` and dispatched from the entry block.
Add one by registering a parser in `build_parser` and a branch in `main`.

    jac run main.jac -- greet Ada --shout
    jac run main.jac -- free-slots --tz America/Detroit --date 2026-10-06
        --fixture fixtures/calendar/freebusy_sample_day.json
"""

import argparse;
import json;
import sys;
import from datetime { date, datetime, time, tzinfo }
import from zoneinfo { ZoneInfo, ZoneInfoNotFoundError }
import from connectors.google_calendar {
    CalendarAuthError,
    CalendarError,
    authorized_session,
    fetch_busy_blocks,
    load_freebusy_fixture
}
import from scheduling.time_slots {
    BusyBlock,
    DEFAULT_MIN_SLOT_MINUTES,
    day_window,
    find_free_slots,
    slot_to_dict
}

glob DEFAULT_DAY_START: time = time(8);
glob DEFAULT_DAY_END: time = time(22);
glob DEFAULT_CALENDARS: list[str] = ["primary"];

def greet(name: str, shout: bool = False) -> str {
    message = f"Hello, {name}! This is course-crusher.";
    return message.upper() if shout else message;
}

def build_parser -> argparse.ArgumentParser {
    parser = argparse.ArgumentParser(
        prog="course-crusher", description="course-crusher command-line tool"
    );
    commands = parser.add_subparsers(dest="command", required=True);
    greet_cmd = commands.add_parser("greet", help="Print a greeting");
    greet_cmd.add_argument("name", nargs="?", `default="world", help="Who to greet");
    greet_cmd.add_argument("--shout", action="store_true", help="Greet loudly");

    slots_cmd = commands.add_parser("free-slots", help="List a day's open time windows as JSON");
    source = slots_cmd.add_mutually_exclusive_group(required=True);
    source.add_argument("--fixture", help="Saved freeBusy response; needs no credentials");
    source.add_argument("--google", action="store_true", help="Query Google Calendar over OAuth");
    slots_cmd.add_argument(
        "--calendar", action="append", dest="calendars",
        help="Google calendar ID; repeat for several (default: primary)"
    );
    slots_cmd.add_argument("--date", type=date.fromisoformat, help="YYYY-MM-DD (default: today)");
    slots_cmd.add_argument("--tz", help="IANA zone, e.g. America/Detroit (default: system zone)");
    slots_cmd.add_argument("--day-start", type=time.fromisoformat, `default=DEFAULT_DAY_START);
    slots_cmd.add_argument("--day-end", type=time.fromisoformat, `default=DEFAULT_DAY_END);
    slots_cmd.add_argument(
        "--min-minutes", type=int, `default=DEFAULT_MIN_SLOT_MINUTES,
        help="Drop gaps shorter than this"
    );
    return parser;
}

def resolve_zone(name: str | None) -> tzinfo {
    if name {
        return ZoneInfo(name);
    }
    local_zone = datetime.now().astimezone().tzinfo;
    if local_zone is None {
        raise ValueError("Could not detect the system time zone; pass --tz");
    }
    return local_zone;
}

def read_busy_blocks(
    args: argparse.Namespace, window_start: datetime, window_end: datetime
) -> list[BusyBlock] {
    if args.fixture {
        return load_freebusy_fixture(args.fixture);
    }
    calendars = args.calendars or DEFAULT_CALENDARS;
    return fetch_busy_blocks(authorized_session(), calendars, window_start, window_end);
}

def free_slots_command(args: argparse.Namespace) -> int {
    try {
        zone = resolve_zone(args.tz);
        day = args.date or datetime.now(zone).date();
        (window_start, window_end) = day_window(day, zone, args.day_start, args.day_end);
        busy = read_busy_blocks(args, window_start, window_end);
        slots = find_free_slots(busy, window_start, window_end, args.min_minutes);
    } except (CalendarError, CalendarAuthError, ValueError, ZoneInfoNotFoundError, OSError) as err {
        print(f"free-slots: {err}", file=sys.stderr);
        return 1;
    }
    print(json.dumps([slot_to_dict(slot) for slot in slots], indent=2));
    return 0;
}

def main(argv: list[str] | None = None) -> int {
    args = build_parser().parse_args(argv);
    if args.command == "greet" {
        print(greet(args.name, args.shout));
        return 0;
    }
    if args.command == "free-slots" {
        return free_slots_command(args);
    }
    return 2;
}

with entry:__main__ {
    sys.`exit(main());
}
