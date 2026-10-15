import json;
import os;
import stat;
import from datetime { datetime, timezone }
import from pathlib { Path }
import from tempfile { TemporaryDirectory }
import from unittest.mock { patch }
import from google.auth.exceptions { RefreshError }
import from google.oauth2.credentials { Credentials }
import from scheduling.time_slots { find_free_slots }

glob SAMPLE_DAY_FIXTURE: str = "fixtures/calendar/freebusy_sample_day.json";
glob WINDOW_START: datetime = datetime(2026, 10, 6, 12, 0, tzinfo=timezone.utc);
glob WINDOW_END: datetime = datetime(2026, 10, 7, 2, 0, tzinfo=timezone.utc);

def utc(hour: int, minute: int = 0) -> datetime {
    return datetime(2026, 10, 6, hour, minute, tzinfo=timezone.utc);
}

"""Stands in for requests.Response at the HTTP boundary."""
obj FakeResponse {
    has payload: dict[str, any];
    has status_error: Exception | None = None;

    def raise_for_status {
        if self.status_error {
            raise self.status_error;
        }
    }

    def json -> dict[str, any] {
        return self.payload;
    }
}

"""Stands in for google.auth.transport.requests.AuthorizedSession."""
obj FakeSession {
    has response: FakeResponse;
    has calls: list[dict[str, any]] = [];

    def post(url: str, json: dict[str, any], timeout: int) -> FakeResponse {
        self.calls.append({"url": url, "json": json, "timeout": timeout});
        return self.response;
    }
}

test "build_freebusy_request lists each calendar and the window" {
    body = build_freebusy_request(["primary", "classes@group"], WINDOW_START, WINDOW_END);

    assert body == {
        "timeMin": "2026-10-06T12:00:00+00:00",
        "timeMax": "2026-10-07T02:00:00+00:00",
        "items": [{"id": "primary"}, {"id": "classes@group"}]
    };
}

test "build_freebusy_request rejects bad input" {
    with testraises(ValueError, `match="At least one calendar") {
        build_freebusy_request([], WINDOW_START, WINDOW_END);
    }
    with testraises(ValueError, `match="at most 50") {
        build_freebusy_request([f"cal-{i}" for i in range(51)], WINDOW_START, WINDOW_END);
    }
    with testraises(ValueError, `match="timezone-aware") {
        build_freebusy_request(["primary"], datetime(2026, 10, 6, 8), WINDOW_END);
    }
    with testraises(ValueError, `match="window_end must be after window_start") {
        build_freebusy_request(["primary"], WINDOW_END, WINDOW_START);
    }
}

test "parse_freebusy_response collects busy blocks from every calendar" {
    blocks = load_freebusy_fixture(SAMPLE_DAY_FIXTURE);

    assert sorted([(b.start, b.end) for b in blocks]) == [
        (utc(13), utc(13, 45)),
        (utc(15), utc(16, 30)),
        (utc(18), utc(20)),
        (utc(19, 30), utc(20, 30))
    ];
}

test "parse_freebusy_response treats a calendar with no busy key as free" {
    assert parse_freebusy_response({"calendars": {"primary": {}}}) == [];
    assert parse_freebusy_response({}) == [];
}

test "parse_freebusy_response surfaces per-calendar errors" {
    payload = {
        "calendars": {
            "primary": {"busy": []},
            "missing@group": {
                "errors": [{"domain": "global", "reason": "notFound"}],
                "busy": []
            }
        }
    };

    with testraises(CalendarError, `match="missing@group: notFound") {
        parse_freebusy_response(payload);
    }
}

test "fixture busy blocks produce the free slots shown on the Today screen" {
    blocks = load_freebusy_fixture(SAMPLE_DAY_FIXTURE);

    slots = find_free_slots(blocks, WINDOW_START, WINDOW_END);

    assert [(s.start_time, s.end_time, s.duration_minutes) for s in slots] == [
        (utc(12), utc(13), 60),
        (utc(13, 45), utc(15), 75),
        (utc(16, 30), utc(18), 90),
        (utc(20, 30), WINDOW_END, 330)
    ];
}

test "fetch_busy_blocks posts the request and parses the reply" {
    reply = FakeResponse(payload={"calendars": {"primary": {"busy": [
        {"start": "2026-10-06T18:00:00Z", "end": "2026-10-06T20:00:00Z"}
    ]}}});
    session = FakeSession(response=reply);

    blocks = fetch_busy_blocks(session, ["primary"], WINDOW_START, WINDOW_END);

    assert [(b.start, b.end) for b in blocks] == [(utc(18), utc(20))];
    assert len(session.calls) == 1;
    assert session.calls[0]["url"] == FREEBUSY_URL;
    assert session.calls[0]["json"]["items"] == [{"id": "primary"}];
    assert session.calls[0]["timeout"] == REQUEST_TIMEOUT_SECONDS;
}

test "fetch_busy_blocks propagates HTTP errors" {
    session = FakeSession(
        response=FakeResponse(payload={}, status_error=RuntimeError("403 Forbidden"))
    );

    with testraises(RuntimeError, `match="403") {
        fetch_busy_blocks(session, ["primary"], WINDOW_START, WINDOW_END);
    }
}

test "load_credentials fails fast when the client secrets path is unset" {
    with patch.dict("os.environ", {}, clear=True) {
        with testraises(CalendarAuthError, `match=CLIENT_SECRETS_ENV) {
            load_credentials();
        }
    }
}

test "load_credentials fails fast when the client secrets file is missing" {
    with patch.dict("os.environ", {CLIENT_SECRETS_ENV: "/nonexistent/client_secret.json"}) {
        with testraises(CalendarAuthError, `match="does not exist") {
            load_credentials();
        }
    }
}

def write_json(path: Path, payload: dict[str, str]) {
    path.write_text(json.dumps(payload), encoding="utf-8");
}

def oauth_env(directory: Path) -> dict[str, str] {
    secrets = directory / "client_secret.json";
    secrets.write_text("{}", encoding="utf-8");
    return {
        CLIENT_SECRETS_ENV: str(secrets),
        TOKEN_FILE_ENV: str(directory / "token.json")
    };
}

def cached_token(expiry: str) -> dict[str, str] {
    return {
        "token": "cached-access-token",
        "refresh_token": "cached-refresh-token",
        "client_id": "client-id.apps.googleusercontent.com",
        "client_secret": "client-secret",
        "expiry": expiry
    };
}

test "load_credentials reuses a valid cached token without the browser flow" {
    with TemporaryDirectory() as tmp {
        env = oauth_env(Path(tmp));
        write_json(Path(env[TOKEN_FILE_ENV]), cached_token("2099-01-01T00:00:00Z"));

        with patch.dict("os.environ", env) {
            credentials = load_credentials();
        }

        assert credentials.token == "cached-access-token";
    }
}

test "cached_credentials falls back to consent when refresh is rejected" {
    with TemporaryDirectory() as tmp {
        token_path = Path(tmp) / "token.json";
        write_json(token_path, cached_token("2000-01-01T00:00:00Z"));
        rejected = RefreshError("invalid_grant: Token has been expired or revoked.");

        with patch.object(Credentials, "refresh", side_effect=rejected) {
            assert cached_credentials(token_path) is None;
        }
    }
}

test "cached_credentials returns None when no token has been saved" {
    with TemporaryDirectory() as tmp {
        assert cached_credentials(Path(tmp) / "missing.json") is None;
    }
}

test "write_token restricts the token file to its owner" {
    with TemporaryDirectory() as tmp {
        token_path = Path(tmp) / "nested" / "token.json";
        token_path.parent.mkdir();
        token_path.write_text("stale", encoding="utf-8");
        os.chmod(token_path, 0o644);

        write_token(token_path, "{\"token\": \"fresh\"}");

        assert token_path.read_text(encoding="utf-8") == "{\"token\": \"fresh\"}";
        assert stat.S_IMODE(token_path.stat().st_mode) == TOKEN_FILE_MODE;
    }
}

test "cached_credentials refreshes an expired token and saves it" {
    with TemporaryDirectory() as tmp {
        token_path = Path(tmp) / "token.json";
        write_json(token_path, cached_token("2000-01-01T00:00:00Z"));
        os.chmod(token_path, 0o644);

        with patch.object(Credentials, "refresh") as refresh {
            credentials = cached_credentials(token_path);
        }

        assert credentials is not None;
        assert refresh.call_count == 1;
        assert json.loads(token_path.read_text(encoding="utf-8"))["refresh_token"] == "cached-refresh-token";
        assert stat.S_IMODE(token_path.stat().st_mode) == TOKEN_FILE_MODE;
    }
}

test "parse_freebusy_response rejects malformed timestamps" {
    def payload_with(start: str) -> dict[str, any] {
        return {"calendars": {"primary": {"busy": [{"start": start, "end": "2026-10-06T20:00:00Z"}]}}};
    }

    with testraises(CalendarError, `match="Unreadable timestamp") {
        parse_freebusy_response(payload_with("next tuesday"));
    }
    with testraises(CalendarError, `match="no UTC offset") {
        parse_freebusy_response(payload_with("2026-10-06T18:00:00"));
    }
}
