import json;
import requests;
import from datetime { datetime, timedelta, timezone }
import from pathlib { Path }
import from tempfile { TemporaryDirectory }
import from unittest.mock { MagicMock, patch }
import from google.oauth2.credentials { Credentials }
import from google_auth_oauthlib.flow { Flow }

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

def issued_credentials(expiry: datetime) -> Credentials {
    return Credentials(
        token="access-token",
        refresh_token="refresh-token",
        token_uri="https://oauth2.googleapis.com/token",
        client_id="test-client.apps.googleusercontent.com",
        client_secret="test-client-secret",
        scopes=GOOGLE_SCOPES,
        expiry=expiry
    );
}

"""Stands in for google_auth_oauthlib's Flow at the library boundary."""
obj FakeFlow {
    has code_verifier: str = "verifier-123";
    has credentials: Credentials | None = None;
    has fetched_with: list[str] = [];

    def authorization_url(prompt: str) -> tuple[str, str] {
        return (f"https://accounts.google.com/o/oauth2/auth?prompt={prompt}", "state-abc");
    }

    def fetch_token(code: str) {
        self.fetched_with.append(code);
    }
}

test "web auth is unconfigured without a client file" {
    with patch.dict("os.environ", {WEB_CLIENT_SECRETS_ENV: ""}) {
        assert not web_auth_configured();
        with testraises(CalendarAuthError, `match=WEB_CLIENT_SECRETS_ENV) {
            web_client_file();
        }
    }
    with patch.dict("os.environ", {WEB_CLIENT_SECRETS_ENV: "/nonexistent/client.json"}) {
        assert not web_auth_configured();
    }
}

test "the redirect URI defaults to the dev callback page" {
    with patch.dict("os.environ", {REDIRECT_URI_ENV: ""}) {
        assert redirect_uri() == DEFAULT_REDIRECT_URI;
    }
    with patch.dict("os.environ", {REDIRECT_URI_ENV: "https://crush.example.edu/connections/google/callback"}) {
        assert redirect_uri() == "https://crush.example.edu/connections/google/callback";
    }
}

test "start_consent returns the URL, state and PKCE verifier" {
    with TemporaryDirectory() as tmp {
        fake = FakeFlow();
        with patch.dict("os.environ", client_env(tmp)) {
            with patch.object(Flow, "from_client_secrets_file", return_value=fake) as factory {
                consent = start_consent();
            }
        }
        assert consent.url.endswith("prompt=consent");
        assert (consent.state, consent.code_verifier) == ("state-abc", "verifier-123");
        assert factory.call_args.kwargs["redirect_uri"] == "http://localhost:8000/connections/google/callback";
        assert factory.call_args.kwargs["scopes"] == GOOGLE_SCOPES;
    }
}

test "finish_consent exchanges the code with the stored verifier and drops the client secret" {
    with TemporaryDirectory() as tmp {
        fake = FakeFlow(credentials=issued_credentials(datetime(2099, 1, 1)));
        with patch.dict("os.environ", client_env(tmp)) {
            with patch.object(Flow, "from_client_secrets_file", return_value=fake) as factory {
                token_json = finish_consent("auth-code", "state-abc", "verifier-123");
            }
        }
        stored = json.loads(token_json);
        assert fake.fetched_with == ["auth-code"];
        assert factory.call_args.kwargs["state"] == "state-abc";
        assert factory.call_args.kwargs["code_verifier"] == "verifier-123";
        assert stored["refresh_token"] == "refresh-token";
        assert "client_secret" not in stored and "client_id" not in stored;
    }
}

test "stored tokens rebuild full credentials from the client file" {
    with TemporaryDirectory() as tmp {
        token_json = storable_token(issued_credentials(datetime(2099, 1, 1)));
        with patch.dict("os.environ", client_env(tmp)) {
            credentials = credentials_from_token(token_json);
        }
        assert credentials.client_secret == "test-client-secret";
        assert credentials.refresh_token == "refresh-token";
        assert credentials.valid;
    }
}

test "fresh_credentials reuses a valid token without refreshing" {
    with TemporaryDirectory() as tmp {
        token_json = storable_token(issued_credentials(datetime(2099, 1, 1)));
        with patch.dict("os.environ", client_env(tmp)) {
            with patch.object(Credentials, "refresh") as refresh {
                (_, refreshed) = fresh_credentials(token_json);
            }
        }
        assert refreshed is None;
        assert refresh.call_count == 0;
    }
}

test "fresh_credentials refreshes an expired token and returns the new one to store" {
    with TemporaryDirectory() as tmp {
        token_json = storable_token(issued_credentials(datetime.now(timezone.utc).replace(tzinfo=None) - timedelta(hours=1)));
        with patch.dict("os.environ", client_env(tmp)) {
            with patch.object(Credentials, "refresh") as refresh {
                (_, refreshed) = fresh_credentials(token_json);
            }
        }
        assert refresh.call_count == 1;
        assert refreshed is not None and "client_secret" not in json.loads(refreshed);
    }
}

test "an expired token without a refresh token asks for reconnection" {
    with TemporaryDirectory() as tmp {
        expired = json.dumps({"token": "old", "expiry": "2000-01-01T00:00:00Z"});
        with patch.dict("os.environ", client_env(tmp)) {
            with testraises(CalendarAuthError, `match="Reconnect Google Calendar") {
                fresh_credentials(expired);
            }
        }
    }
}

test "a client file without a web section is rejected" {
    with TemporaryDirectory() as tmp {
        path = Path(tmp) / "bad.json";
        path.write_text(json.dumps({"other": {}}), encoding="utf-8");
        with patch.dict("os.environ", {WEB_CLIENT_SECRETS_ENV: str(path)}) {
            with testraises(CalendarAuthError, `match="no 'web' section") {
                client_config();
            }
        }
    }
}

test "revoke_token sends the refresh token to Google" {
    stored = json.dumps({"token": "access", "refresh_token": "refresh"});
    with patch.object(requests, "post", return_value=MagicMock(status_code=200)) as post {
        accepted = revoke_token(stored);
    }
    assert accepted;
    assert post.call_args.args[0] == REVOKE_URL;
    assert post.call_args.kwargs["params"] == {"token": "refresh"};
}

test "revoke_token reports a rejected or empty token" {
    with patch.object(requests, "post", return_value=MagicMock(status_code=400)) {
        assert not revoke_token(json.dumps({"token": "access"}));
    }
    assert not revoke_token(json.dumps({}));
}
