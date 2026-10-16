import json;
import from contextlib { redirect_stderr, redirect_stdout }
import from io { StringIO }

glob SAMPLE_DAY_FIXTURE: str = "fixtures/calendar/freebusy_sample_day.json";

def run_cli(argv: list[str]) -> tuple[int, str, str] {
    out = StringIO();
    err = StringIO();
    with redirect_stdout(out) {
        with redirect_stderr(err) {
            code = main(argv);
        }
    }
    return (code, out.getvalue(), err.getvalue());
}

test "greet still works" {
    (code, out, _) = run_cli(["greet", "Ada"]);
    assert code == 0;
    assert out.strip() == "Hello, Ada! This is course-crusher.";
}

test "free-slots prints the day's open windows as JSON" {
    (code, out, err) = run_cli([
        "free-slots", "--fixture", SAMPLE_DAY_FIXTURE,
        "--date", "2026-10-06", "--tz", "America/Detroit"
    ]);

    assert code == 0, err;
    assert json.loads(out) == [
        {"start_time": "2026-10-06T08:00:00-04:00", "end_time": "2026-10-06T09:00:00-04:00", "duration_minutes": 60},
        {"start_time": "2026-10-06T09:45:00-04:00", "end_time": "2026-10-06T11:00:00-04:00", "duration_minutes": 75},
        {"start_time": "2026-10-06T12:30:00-04:00", "end_time": "2026-10-06T14:00:00-04:00", "duration_minutes": 90},
        {"start_time": "2026-10-06T16:30:00-04:00", "end_time": "2026-10-06T22:00:00-04:00", "duration_minutes": 330}
    ];
}

test "free-slots honours day bounds and the minimum length" {
    (code, out, err) = run_cli([
        "free-slots", "--fixture", SAMPLE_DAY_FIXTURE,
        "--date", "2026-10-06", "--tz", "America/Detroit",
        "--day-start", "09:00", "--day-end", "16:00", "--min-minutes", "80"
    ]);

    assert code == 0, err;
    assert [slot["duration_minutes"] for slot in json.loads(out)] == [90];
}

test "free-slots reports a bad time zone without a traceback" {
    (code, out, err) = run_cli([
        "free-slots", "--fixture", SAMPLE_DAY_FIXTURE, "--tz", "Mars/Olympus_Mons"
    ]);

    assert code == 1;
    assert out == "";
    assert err.startswith("free-slots: ");
    assert "Traceback" not in err;
}

test "free-slots reports a missing fixture without a traceback" {
    (code, _, err) = run_cli(["free-slots", "--fixture", "fixtures/calendar/nope.json"]);

    assert code == 1;
    assert err.startswith("free-slots: ");
}

test "free-slots requires a source" {
    with testraises(SystemExit) {
        run_cli(["free-slots", "--date", "2026-10-06"]);
    }
}
