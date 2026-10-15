import json;
import requests;
import from datetime { datetime, timedelta, timezone }
import from pathlib { Path }
import from tempfile { TemporaryDirectory }
import from unittest.mock { MagicMock, patch }
import from google.auth.transport.requests { AuthorizedSession }
import from google.oauth2.credentials { Credentials }
import from google_auth_oauthlib.flow { Flow }
import from jaclang.testing.testing { JacTestClient }
import from connectors.google_calendar { GOOGLE_SCOPES }
import from connectors.google_web_auth { REDIRECT_URI_ENV, WEB_CLIENT_SECRETS_ENV }
import from shared.api_testing { call, sign_up, signed_in_client }

glob CLIENT: dict[str, dict[str, str]] = {
    "web": {
        "client_id": "test-client.apps.googleusercontent.com",
        "client_secret": "test-client-secret",
        "auth_uri": "https://accounts.google.com/o/oauth2/auth",
        "token_uri": "https://oauth2.googleapis.com/token"
    }
};

def client_env(directory: str) -> dict[str, str] {
    path = Path(directory) / "client_secret_web.json";
    path.write_text(json.dumps(CLIENT), encoding="utf-8");
    return {WEB_CLIENT_SECRETS_ENV: str(path), REDIRECT_URI_ENV: "http://localhost:8000/connections/google/callback"};
}

"""Stands in for google_auth_oauthlib's Flow."""
obj FakeFlow {
    has credentials: Credentials | None = None;
    has code_verifier: str = "verifier-123";

    def authorization_url(prompt: str) -> tuple[str, str] {
        return ("https://accounts.google.com/o/oauth2/auth?state=state-abc", "state-abc");
    }

    def fetch_token(code: str) {}
}

"""Stands in for the freeBusy HTTP response."""
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

def issued_credentials -> Credentials {
    return Credentials(
        token="access-token",
        refresh_token="refresh-token",
        token_uri="https://oauth2.googleapis.com/token",
        client_id="test-client.apps.googleusercontent.com",
        client_secret="test-client-secret",
        scopes=GOOGLE_SCOPES,
        expiry=datetime(2099, 1, 1)
    );
}

def connect(client: JacTestClient) -> dict[str, any] {
    fake = FakeFlow(credentials=issued_credentials());
    with patch.object(Flow, "from_client_secrets_file", return_value=fake) {
        started = call(client, "start_google_connect");
        assert started["ok"], started["error"];
        return call(client, "finish_google_connect", {"code": "auth-code", "state": "state-abc"});
    }
}

def busy_tomorrow -> dict[str, any] {
    start = (datetime.now(timezone.utc) + timedelta(days=1)).replace(hour=15, minute=0, second=0, microsecond=0);
    return {"calendars": {"primary": {"busy": [
        {"start": start.isoformat(), "end": (start + timedelta(hours=1)).isoformat()}
    ]}}};
}

test "without a server OAuth client, Google is reported as not configured" {
    client = signed_in_client();
    try {
        with patch.dict("os.environ", {WEB_CLIENT_SECRETS_ENV: ""}) {
            status = call(client, "calendar_status");
            started = call(client, "start_google_connect");
        }
        assert status["state"] == "not_configured";
        assert not started["ok"] and "isn't set up" in started["error"];
    } finally {
        client.close();
    }
}

test "connecting stores a token the browser never sees" {
    with TemporaryDirectory() as tmp {
        with patch.dict("os.environ", client_env(tmp)) {
            client = signed_in_client();
            try {
                assert call(client, "calendar_status")["state"] == "disconnected";
                finished = connect(client);
                status = call(client, "calendar_status");
            } finally {
                client.close();
            }
        }
    }
    assert finished["ok"], finished["error"];
    assert status["state"] == "connected" and status["calendars"] == ["primary"];
    assert "token" not in json.dumps(status) and "refresh" not in json.dumps(finished);
}

test "finishing with the wrong state or no code is refused" {
    with TemporaryDirectory() as tmp {
        with patch.dict("os.environ", client_env(tmp)) {
            client = signed_in_client();
            try {
                never_started = call(client, "finish_google_connect", {"code": "c", "state": "state-abc"});
                with patch.object(Flow, "from_client_secrets_file", return_value=FakeFlow()) {
                    call(client, "start_google_connect");
                }
                forged = call(client, "finish_google_connect", {"code": "c", "state": "attacker-state"});
                status = call(client, "calendar_status");
            } finally {
                client.close();
            }
        }
    }
    assert not never_started["ok"] and "expired" in never_started["error"];
    assert not forged["ok"];
    assert status["state"] == "disconnected";
}

test "a state started by one student can't be finished by another" {
    with TemporaryDirectory() as tmp {
        with patch.dict("os.environ", client_env(tmp)) {
            client = signed_in_client("victim@example.com");
            try {
                with patch.object(Flow, "from_client_secrets_file", return_value=FakeFlow()) {
                    call(client, "start_google_connect");
                }
                sign_up(client, "attacker@example.com");
                hijack = call(client, "finish_google_connect", {"code": "c", "state": "state-abc"});
            } finally {
                client.close();
            }
        }
    }
    assert not hijack["ok"];
}

test "Google busy time is planned around" {
    with TemporaryDirectory() as tmp {
        with patch.dict("os.environ", client_env(tmp)) {
            client = signed_in_client();
            try {
                call(client, "setup_account", {"display_name": "S", "timezone": "UTC"});
                connect(client);
                with patch.object(AuthorizedSession, "post", return_value=FakeResponse(payload=busy_tomorrow())) as post {
                    week = call(client, "get_week");
                }
                status = call(client, "calendar_status");
            } finally {
                client.close();
            }
        }
    }
    busy = [e for d in week["days"] for e in d["events"] if e["kind"] == "busy"];
    assert [(e["title"], e["detail"]) for e in busy] == [("Busy", "3:00 – 4:00 PM")];
    assert post.call_count == 1;
    assert post.call_args.kwargs["json"]["items"] == [{"id": "primary"}];
    assert status["state"] == "connected" and status["last_synced_at"];
}

test "a failed Google read is reported and the plan still loads" {
    with TemporaryDirectory() as tmp {
        with patch.dict("os.environ", client_env(tmp)) {
            client = signed_in_client();
            try {
                connect(client);
                failing = FakeResponse(payload={"calendars": {"primary": {"errors": [{"reason": "notFound"}]}}});
                with patch.object(AuthorizedSession, "post", return_value=failing) {
                    today = call(client, "get_today");
                }
            } finally {
                client.close();
            }
        }
    }
    assert today["calendar"]["state"] == "error";
    assert "primary: notFound" in today["calendar"]["detail"];
}

test "calendars can be chosen and Google can be disconnected" {
    with TemporaryDirectory() as tmp {
        with patch.dict("os.environ", client_env(tmp)) {
            client = signed_in_client();
            try {
                connect(client);
                chosen = call(client, "set_google_calendars", {"calendar_ids": [" primary ", "classes@group", "primary", ""]});
                none_left = call(client, "set_google_calendars", {"calendar_ids": ["  "]});
                too_many = call(client, "set_google_calendars", {"calendar_ids": [f"c{n}" for n in range(11)]});
                disconnected = call(client, "disconnect_google");
            } finally {
                client.close();
            }
        }
    }
    assert chosen["ok"] and chosen["status"]["calendars"] == ["primary", "classes@group"];
    assert not none_left["ok"] and not too_many["ok"];
    assert disconnected["state"] == "disconnected";
}

test "consent older than ten minutes has expired" {
    now = datetime(2026, 10, 6, 12, 0, tzinfo=timezone.utc);

    assert not consent_expired("2026-10-06T11:55:00+00:00", now);
    assert consent_expired("2026-10-06T11:49:00+00:00", now);
    assert consent_expired("", now);
    assert consent_expired("not a time", now);
}

test "disconnecting revokes the grant at Google" {
    with TemporaryDirectory() as tmp {
        with patch.dict("os.environ", client_env(tmp)) {
            client = signed_in_client();
            try {
                connect(client);
                with patch.object(requests, "post", return_value=MagicMock(status_code=200)) as revoke {
                    status = call(client, "disconnect_google");
                }
            } finally {
                client.close();
            }
        }
    }
    assert status["state"] == "disconnected";
    assert revoke.call_count == 1;
    assert revoke.call_args.kwargs["params"] == {"token": "refresh-token"};
}

test "a failed revocation still disconnects locally" {
    with TemporaryDirectory() as tmp {
        with patch.dict("os.environ", client_env(tmp)) {
            client = signed_in_client();
            try {
                connect(client);
                with patch.object(requests, "post", side_effect=requests.ConnectionError("offline")) {
                    status = call(client, "disconnect_google");
                }
            } finally {
                client.close();
            }
        }
    }
    assert status["state"] == "disconnected";
}

test "a broken OAuth client file is reported without leaking its contents" {
    with TemporaryDirectory() as tmp {
        env = client_env(tmp);
        with patch.dict("os.environ", env) {
            client = signed_in_client();
            try {
                connect(client);
                Path(env[WEB_CLIENT_SECRETS_ENV]).write_text(json.dumps({"web": {"client_id": "x"}}), encoding="utf-8");
                today = call(client, "get_today");
            } finally {
                client.close();
            }
        }
    }
    assert today["calendar"]["state"] == "error";
    assert today["calendar"]["detail"] == "Google sign-in isn't set up correctly on this server.";
    assert "client_secret" not in json.dumps(today);
}
