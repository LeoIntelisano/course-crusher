"""OAuth for the web app: Google's web-server flow with PKCE.

The CLI keeps the installed-app loopback flow in `google_calendar.jac`. The
browser app can't use it, because consent has to come back to a page the app
serves. This module builds the consent URL, exchanges the returned code, and
rebuilds credentials from what the app stores per user.

Configuration (both read at call time, never stored):

- `GOOGLE_WEB_CLIENT_SECRETS_FILE`: OAuth client JSON of type "Web application",
  kept outside the repo.
- `GOOGLE_OAUTH_REDIRECT_URI`: must match an authorized redirect URI on that
  client. Defaults to the dev server's callback page.

Stored tokens omit the client ID and secret; those are re-read from the client
file, so a database leak doesn't also leak the OAuth client.
"""

import json;
import os;
import requests;
import from datetime { datetime }
import from pathlib { Path }
import from google.auth.transport.requests { Request }
import from google.oauth2.credentials { Credentials }
import from google_auth_oauthlib.flow { Flow }
import from connectors.google_calendar { CalendarAuthError }
import from connectors.google_events { EVENT_SCOPES }

glob WEB_CLIENT_SECRETS_ENV: str = "GOOGLE_WEB_CLIENT_SECRETS_FILE";
glob REDIRECT_URI_ENV: str = "GOOGLE_OAUTH_REDIRECT_URI";
glob DEFAULT_REDIRECT_URI: str = "http://localhost:8000/connections/google/callback";
glob STORED_TOKEN_FIELDS: list[str] = ["token", "refresh_token", "expiry", "scopes"];
glob REVOKE_URL: str = "https://oauth2.googleapis.com/revoke";
glob REVOKE_TIMEOUT_SECONDS: int = 10;
glob HTTP_OK: int = 200;

"""Everything the callback needs to finish consent: the URL to send the browser to, and the PKCE pair."""
obj ConsentRequest {
    has url: str;
    has state: str;
    has code_verifier: str;
}

def web_client_file -> str {
    path = os.environ.get(WEB_CLIENT_SECRETS_ENV, "");
    if not path {
        raise CalendarAuthError(
            f"{WEB_CLIENT_SECRETS_ENV} is not set. See docs/connectors/google-calendar.md."
        );
    }
    resolved = Path(path).expanduser();
    if not resolved.is_file() {
        raise CalendarAuthError(f"{WEB_CLIENT_SECRETS_ENV} points to a file that does not exist.");
    }
    return str(resolved);
}

def web_auth_configured -> bool {
    try {
        web_client_file();
    } except CalendarAuthError {
        return False;
    }
    return True;
}

def redirect_uri -> str {
    return os.environ.get(REDIRECT_URI_ENV, "") or DEFAULT_REDIRECT_URI;
}

def client_config -> dict[str, str] {
    with open(web_client_file(), encoding="utf-8") as handle {
        payload = json.load(handle);
    }
    section = payload.get("web") or payload.get("installed");
    if not section {
        raise CalendarAuthError("The OAuth client file has no 'web' section.");
    }
    return {
        "client_id": section["client_id"],
        "client_secret": section["client_secret"],
        "token_uri": section.get("token_uri", "https://oauth2.googleapis.com/token")
    };
}

def new_flow(state: str = "", code_verifier: str = "") -> Flow {
    return Flow.from_client_secrets_file(
        web_client_file(),
        scopes=EVENT_SCOPES,
        redirect_uri=redirect_uri(),
        state=state or None,
        code_verifier=code_verifier or None
    ) as Flow;
}

"""Step 1: the consent URL. `prompt=consent` makes Google return a refresh token every time."""
def start_consent -> ConsentRequest {
    oauth = new_flow();
    (url, state) = oauth.authorization_url(prompt="consent");
    return ConsentRequest(url=str(url), state=str(state), code_verifier=str(oauth.code_verifier));
}

"""Step 2: trade the code from the callback for tokens, returned as the JSON the app stores."""
def finish_consent(code: str, state: str, code_verifier: str) -> str {
    oauth = new_flow(state=state, code_verifier=code_verifier);
    oauth.fetch_token(code=code);
    return storable_token(oauth.credentials as Credentials);
}

"""The token fields worth keeping, without the client ID and secret."""
def storable_token(credentials: Credentials) -> str {
    payload = json.loads(str(credentials.to_json()));
    return json.dumps({key: payload[key] for key in STORED_TOKEN_FIELDS if key in payload});
}

def credentials_from_token(token_json: str) -> Credentials {
    stored = json.loads(token_json);
    config = client_config();
    expiry_text = stored.get("expiry");
    expiry: datetime | None = None;
    if expiry_text {
        # google-auth compares expiry against naive UTC
        expiry = datetime.fromisoformat(expiry_text.replace("Z", "+00:00")).replace(tzinfo=None);
    }
    return Credentials(
        token=stored.get("token"),
        refresh_token=stored.get("refresh_token"),
        token_uri=config["token_uri"],
        client_id=config["client_id"],
        client_secret=config["client_secret"],
        scopes=stored.get("scopes") or EVENT_SCOPES,
        expiry=expiry
    );
}

"""Usable credentials plus the token to store if a refresh changed it (else None)."""
def fresh_credentials(token_json: str) -> tuple[Credentials, str | None] {
    credentials = credentials_from_token(token_json);
    if credentials.valid {
        return (credentials, None);
    }
    if not credentials.refresh_token {
        raise CalendarAuthError("Google access has expired. Reconnect Google Calendar.");
    }
    credentials.refresh(Request());
    return (credentials, storable_token(credentials));
}

"""Ask Google to revoke a stored token. Revoking the refresh token ends the whole grant.

Returns whether Google accepted it; callers disconnect locally either way.
"""
def revoke_token(token_json: str) -> bool {
    stored = json.loads(token_json);
    token = stored.get("refresh_token") or stored.get("token");
    if not token {
        return False;
    }
    response = requests.post(
        REVOKE_URL,
        params={"token": token},
        headers={"Content-Type": "application/x-www-form-urlencoded"},
        timeout=REVOKE_TIMEOUT_SECONDS
    );
    return response.status_code == HTTP_OK;
}
